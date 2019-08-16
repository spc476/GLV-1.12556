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
local url    = require "url"
local uurl   = require "url-util"
local getopt = require "org.conman.getopt".getopt
local lpeg   = require "lpeg"

local CERT
local KEY
local NOVER
local SURL

-- ************************************************************************

local statparse do
  local Cc = lpeg.Cc
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  
  local status   = P"1" * R"09" * Cc'input'    * Cc'required'  * Cc(true)
                 + P"2" * R"09" * Cc'okay'     * Cc'content'   * Cc(true)
                 + P"3" * R"09" * Cc'redirect' * Cc'temporary' * Cc(true)
                 + P"4" * R"09" * Cc'error'    * Cc'temporary' * Cc(true)
                 + P"5" * R"09" * Cc'error'    * Cc'permanent' * Cc(true)
                 + P"6" * R"09" * Cc'auth'     * Cc'required'  * Cc(true)
                 + P"2"         * Cc'okay'     * Cc'content'   * Cc(false)
                 + P"3"         * Cc'redirect' * Cc'permanent' * Cc(false)
                 + P"4"         * Cc'error'    * Cc'permanent' * Cc(false)
                 + P"5"         * Cc'error'    * Cc'temporary' * Cc(false)
                 + P"9"         * Cc'error'    * Cc'slow-down' * Cc(false)
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
    
    if NOVER then
      conf:insecure_no_verify_name()
      conf:insecure_no_verify_time()
      conf:insecure_no_verify_cert()
    end

    return conf:protocols "all"
  end)
  
  if not ios then
    io.stderr:write("cannot connect to ",loc.host,"\n")
    return
  end
  
  local request do
    if SURL then
      request = location
    else
      request = uurl.esc_path:match(loc.path)
      if loc.query then
        request = request .. "?" .. loc.query
      end
    end
  end
  
  io.stderr:write(string.format(">>> %q\n",request))
  ios:write(request,"\r\n")
  
  local statline = ios:read("*l")
  if not statline then
    io.stderr:write("bad request\n")
    ios:close()
    return
  end
  
  io.stderr:write("<<< ",statline)
  local system,status,std,info = statparse:match(statline)
  if not system then
    io.stderr:write("bad reply: ",statline,"\n")
    ios:close()
    return
  end
  
  io.stderr:write(string.format("system=%s status=%s info=%s%s\n",
        system,
        status,
        info,
        std and "" or "OUTDATED"
  ))
  
  if system == 'auth' then
    if status == 'required' and CERT and KEY then
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
        -u | --url  send URL
        -h | --help this text
]]

  local opts =
  {
    { "c" , "cert"     , true    , function(c) CERT  = c    end },
    { "k" , "key"      , true    , function(k) KEY   = k    end },
    { "n" , "noverify" , false   , function()  NOVER = true end },
    { "u" , "url"      , false   , function()  SURL  = true end },
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
