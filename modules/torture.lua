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

local abnf   = require "org.conman.parsers.abnf"
local lpeg   = require "lpeg"
local io     = require "io"
local table  = require "table"

local tonumber = tonumber

local CONF = {}
_ENV       = {}

-- ************************************************************************

local parse_headers,parse_body do
  local Cf = lpeg.Cf
  local Cg = lpeg.Cg
  local Cp = lpeg.Cp
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
  local number       = R"09"^1 / tonumber
  local status       = H"Status"       * P":" * LWSP * number     * abnf.CRLF
  local content_type = H"Content-Type" * P":" * LWSP * Cs(text^1) * abnf.CRLF
  local location     = H"Location"     * P":" * LWSP * Cs(text^1) * abnf.CRLF
  local reason       = H"Reason"       * P":" * LWSP * Cs(text^1) * abnf.CRLF
  local generic      = C(token)        * P":" * LWSP * C(text^0)  * abnf.CRLF
  local headers      = status + content_type + location + reason + generic
  parse_headers      = Cf(Ct"" * Cg(headers)^1,function(acc,name,value)
                         acc[name] = value
                         return acc
                       end)
                     * abnf.CRLF * Cp()
                     
  local line         = C(R("\9\9"," \255")^0) * abnf.CRLF
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
    match[1] = "0000"
  end
  
  local f = io.open(CONF.dir .. "/" .. match[1],"r")
  if not f then
    return 51,"Not found",""
  end
    
  local d = f:read("*a")
  local headers,pos = parse_headers:match(d)
  local reply       = parse_body:match(d,pos)
  f:close()  
  return headers['Status'],headers['Content-Type'],table.concat(reply,"\r\n") .. "\r\n"
end

-- ************************************************************************

return _ENV
