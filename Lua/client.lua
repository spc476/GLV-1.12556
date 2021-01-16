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
local url    = require "org.conman.parsers.iri"
local idn    = require "org.conman.idn"
local uurl   = require "GLV-1.url-util"
local getopt = require "org.conman.getopt".getopt
local lpeg   = require "lpeg"

local CERT = os.getenv("GEMINI_CERT")
local KEY  = os.getenv("GEMINI_KEY")
local NOVER

-- ************************************************************************

local statparse do
  local Cc = lpeg.Cc
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  local S  = lpeg.S
  
  local status   = P"1" * R"09" * Cc'input'    * Cc'required'  * Cc(true)
                 + P"2" * R"09" * Cc'okay'     * Cc'content'   * Cc(true)
                 + P"3" * R"09" * Cc'redirect' * Cc'temporary' * Cc(true)
                 + P"4" * R"09" * Cc'error'    * Cc'temporary' * Cc(true)
                 + P"5" * R"09" * Cc'error'    * Cc'permanent' * Cc(true)
                 + P"6" * R"09" * Cc'auth'     * Cc'required'  * Cc(true)
  local infotype = S" \t"^1 * C(R" \255"^0)
                 + Cc"type/text; charset=utf-8"
  statparse      = status * infotype
end

-- ************************************************************************

local function main(location,usecert,rcount)
  rcount = rcount or 1
  local loc = url:match(location)
  
  if not loc then
    io.stderr:write("Parse error with given URL\n")
    os.exit(1)
  end
  
  if loc.scheme ~= 'gemini' then
    io.stderr:write(string.format("%s: scheme %q not supported\n",location,loc.scheme))
    os.exit(1)
  end
  
  io.stderr:write(string.format("loc=%q encoded=%q\n",loc.host,idn.encode(loc.host)))
  
  local ios = tls.connect(idn.encode(loc.host),loc.port,nil,function(conf)
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
  
  local okay,err = ios:write(location,"\r\n")
  if not okay then
    io.stderr:write("ios:write() = ",err,"\n")
    ios:close()
    return
  end
  
  local statline = ios:read("*l")
  if not statline then
    io.stderr:write("bad request\n")
    ios:close()
    return
  end
  
  io.stderr:write("<<< ",statline,"\n")
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
      ios:close()
      return main(location,true)
    end
    
  elseif system == 'redirect' then
    if rcount == 5 then
      io.stderr:write(string.format("too man redirects\n"))
    else
      local where  = url:match(info)
      local new    = uurl.merge(loc,where)
      local newloc = uurl.toa(new)
      
      io.stderr:write("--- ",newloc,"\n")
      ios:close()
      return main(newloc,usecert,rcount + 1)
    end
    
  elseif system == 'okay' then
    io.stderr:write(string.format("cipher=%q version=%s strength=%d\n",ios.__ctx:conn_cipher(),ios.__ctx:conn_version(),ios.__ctx:conn_cipher_strength()))
    io.stderr:write(string.format("servername=%q alpn=%q\n",ios.__ctx:conn_servername(),ios.__ctx:conn_alpn_selected()))
    repeat
      local data = ios:read(8192)
      if data then io.stdout:write(data) end
    until not data
    ios:close()
  else
    ios:close()
  end
end

-- ************************************************************************

local URL
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
nfl.spawn(main,URL)
nfl.client_eventloop()
