#!/usr/bin/env lua
-- ************************************************************************
--
--    Client program
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
-- luacheck: ignore 611

local nfl    = require "org.conman.nfl"
local tls    = require "org.conman.nfl.tls"
local url    = require "org.conman.parsers.url"
local getopt = require "org.conman.getopt".getopt
local lpeg   = require "lpeg"

local CERT
local KEY
local NOVER

-- ************************************************************************
-- Because we're sending a URL, we need to properly escape the path in case
-- it contains characters from the 'reserved' set of characters for URLs.
-- ************************************************************************

local safe_segment do
  local Cs = lpeg.Cs
  local P  = lpeg.P
  local S  = lpeg.S
  
  local char   = S":/?#[]@|"
               / function(c)
                   return string.format("%%%02X",string.byte(c))
                 end
               + P(1)
  safe_segment = Cs(char^1)
end

-- ************************************************************************

local function normalize_directory(path)
  local new = {}
  for _,segment in ipairs(path) do
    if segment == ".." then
      table.remove(new)
    elseif segment ~= "." then
      table.insert(new,safe_segment:match(segment))
    end
  end
  
  return "/" .. table.concat(new,"/")
end

-- ************************************************************************

local statparse do
  local Cc = lpeg.Cc
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  
  local DD       = R"09" * R"09"
  local status   = P"200"    * Cc'okay'     * Cc'content'
                 + P"301"    * Cc'redirect' * Cc'permanent'
                 + P"401"    * Cc'client'   * Cc'unauthorized''
                 + P"403"    * Cc'client'   * Cc'forbidden'
                 + P"404"    * Cc'client'   * Cc'not-found'
                 + P"405"    * Cc'client'   * Cc'unauthorized'
                 + P"410"    * Cc'client'   * Cc'gone'
                 + P"429"    * Cc'client'   * Cc'slow-down'
                 + P"460"    * Cc'client'   * Cc'need-certificate'
                 + P"461"    * Cc'client'   * Cc'future-certificate'
                 + P"462"    * Cc'client'   * Cc'expired-certificate'
                 + P"463"    * Cc'client'   * Cc'rejected-certificate'
                 
                 -- ----------------
                 -- Catch-all path
                 -- ----------------
                 
                 + P"2" * DD * Cc'okay'     * Cc'content'
                 + P"3" * DD * Cc'redirect' * Cc'see-other'
                 + P"4" * DD * Cc'client'   * Cc'error'
                 + P"5" * DD * Cc'server'   * Cc'error'
                 
                 -- -----------------------------------
                 -- The "Official Spec" return codes.
                 -- -----------------------------------
                 
                 + P"2"      * Cc'okay'     * Cc'content'
                 + P"3"      * Cc'redirect' * Cc'permanent'
                 + P"4"      * Cc'client'   * Cc'error'
                 + P"5"      * Cc'server'   * Cc'error'
                 + P"9"      * Cc'client'   * Cc'slow-down'
                 
  local infotype = P"\t" * C(R" \255"^0)
                 + Cc"type/text; charset=utf-8"
                 
  statparse      = status * infotype
end

-- ************************************************************************

local function main(location,usecert)
  local loc = url:match(location)
  local ios = tls.connect(loc.host,loc.port,nil,function(conf)
    if usecert then
      if not conf:cert_file(CERT)
      or not conf:key_file(KEY) then
        return false
      end
    end
    if nover then conf:insecure_no_verify_cert() end
    return conf:protocols "all"
  end)
  
  if not ios then
    io.stderr:write("cannot connect to ",loc.host,"\n")
    return
  end
  ios:write(normalize_directory(loc.path),"\r\n")
  
  local statline = ios:read("*l")
  if not statline then
    io.stderr:write("bad request\n")
    ios:close()
    return
  end
  
  local system,status,info = statparse:match(statline)
  if not system then
    io.stderr:write("bad reply: ",statline,"\n")
    ios:close()
    return
  end
  
  io.stderr:write(string.format("system=%s status=%s info=%s\n",
        system,
        status,
        info
  ))
  
  if system == 'client' then
    if status == 'need-certificate' then
      return main(location,true)
    end
  end
  
  if system == 'okay' then
    io.stdout:write(ios:read("*a"))
  end
  
  ios:close()
end

-- ************************************************************************

CERT = os.getenv("GEMINI_CERT")
KEY  = os.getenv("GEMINI_KEY")

local URL do
  local usage = [[
usage: %s [options] url
        -c | --cert certificate
        -k | --key  keyfile
        -n | --noverify
        -h | --help this text
]]

  local opts =
  {
    { "c" , "cert"     , true    , function(c) CERT  = c    end },
    { "k" , "key"      , true    , function(k) KEY   = k    end },
    { "n" , "noverify" , false   , function()  NOVER = true end },
    { 'h' , "help"     , false   , function()
        io.stderr:write(string.format(usage,arg[0]))
        os.exit(false,true)
      end
    },
  }
  
  if #arg == 0 then
    io.stderr:write(string.format(usage,arg[0]))
    os.exit(false,true)
  end
  
  URL = arg[getopt(arg,opts)]
end

nfl.spawn(main,URL)
nfl.client_eventloop()
