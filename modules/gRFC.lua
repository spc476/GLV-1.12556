-- ************************************************************************
--
--    CGI interface.
--    Copyright 2019 by Sean Conner.  All Rights Reserved.
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--    Comments, questions and criticisms can be sent to: sean@conman.org
--
-- ************************************************************************
-- luacheck: globals init fini handler
-- luacheck: ignore 611
-- RFC-3875

-- ************************************************************************

local abnf     = require "org.conman.parsers.abnf"
local strftime = require "org.conman.parsers.strftime"
local fsys     = require "org.conman.fsys"
local lpeg     = require "lpeg"
local io       = require "io"
local os       = require "os"
local string   = require "string"
local table    = require "table"

local CONF = {}
_ENV = {}

-- ************************************************************************

local parse_headers, parse_body do
  local Cf = lpeg.Cf
  local Cg = lpeg.Cg
  local Cs = lpeg.Cs
  local Ct = lpeg.Ct
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  local S  = lpeg.S
  
  local H do
    local text = R("AZ","az") / function(c) return P(c:lower()) + P(c:upper()) end
               + P(1)         / function(c) return P(c) end
               
    H = function(s)
      local pattern = Cf(text^1,function(acc,pat) return acc * pat end)
      return pattern:match(s) / s
    end
  end
  
  local LWSP         = (abnf.WSP + abnf.CRLF * abnf.WSP)
  local text         = LWSP^1 / " "
                     + abnf.VCHAR
  local separator    = S'()<>@,;:\\"/[]?={}\t '
  local token        = (abnf.VCHAR - separator)^1
  local subject      = H"Subject"      * P":" * LWSP * Cs(text^1)                     * abnf.CRLF
  local from         = H"From"         * P":" * LWSP * Cs(text^1)                     * abnf.CRLF
  local date         = H"Date"         * P":" * LWSP * strftime:match("%a, %e %b %Y") * abnf.CRLF
  local content_type = H"Content-Type" * P":" * LWSP * Cs(text^1)                     * abnf.CRLF
  local status       = H"Status"       * P":" * LWSP * Cs(text^1)                     * abnf.CRLF
  local generic      = C(token)        * P":" * LWSP * C(text^0)                      * abnf.CRLF
  local headers      = subject + from + date + status + content_type + generic
  parse_headers      = Cf(Ct"" * Cg(headers)^1,function(acc,name,value)
                         acc[name] = value
                         return acc
                       end)
                     * abnf.CRLF
                     
  local line         = C(R("\9\9"," ~")^0) * abnf.CRLF
  parse_body         = Ct(line^1)
end

-- ************************************************************************

function init(conf)
  CONF = conf
  return true
end

-- ************************************************************************

function handler(_,_,_,match)
  if match[1] == "" then
    local reply = {}
    
    table.insert(reply,"Gemini Request For Comments")
    table.insert(reply,"---------------------------")
    table.insert(reply,"")
    
    for file in fsys.gexpand(CONF.dir .. "/[0-9][0-9][0-9][0-9]") do
      local f       = io.open(file,"r")
      local headers = parse_headers:match(f:read("*a"))
      f:close()
      
      local name = fsys.basename(file)
      local when = os.date("%Y-%m-%d",os.time(headers['Date']))
      
      table.insert(
        reply,
        string.format([[=> %s/%s %s %s %-8s %s]],
                CONF.path, name,
                name,
                when,
                headers['Status'],
                headers['Subject']
        )
      )
    end
    
    table.insert(reply,"")
    table.insert(reply,"---------------------------")
    table.insert(reply,"GLV-1.12556")
    
    return 200,"text/gemini",table.concat(reply,"\r\n") .. "\r\n"
    
  else
    local f = io.open(CONF.dir .. "/" .. match[1],"r")
    if not f then
      return 404,"Not found",""
    end
    
    local d       = f:read("*a")
    local headers = parse_headers:match(d)
    local reply   = parse_body:match(d)
    f:close()
    return 200,headers['Content-Type'],table.concat(reply,"\r\n") .. "\r\n"
  end
end

-- ************************************************************************

return _ENV
