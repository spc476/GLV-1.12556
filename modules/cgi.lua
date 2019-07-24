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
-- luacheck: ignore 611
-- RFC-3875

local syslog    = require "org.conman.syslog"
local errno     = require "org.conman.errno"
local fsys      = require "org.conman.fsys"
local process   = require "org.conman.process"
local exit      = require "org.conman.const.exit"
local ios       = require "org.conman.net.ios"
local nfl       = require "org.conman.nfl"
local abnf      = require "org.conman.parsers.abnf"
local lpeg      = require "lpeg"
local io        = require "io"
local table     = require "table"
local string    = require "string"
local coroutine = require "coroutine"

local pairs        = pairs
local tostring     = tostring

-- ************************************************************************

local parse_headers do
  local Cf = lpeg.Cf
  local Cg = lpeg.Cg
  local Cs = lpeg.Cs
  local Ct = lpeg.Ct
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  local S  = lpeg.S
  
  local LWSP         = (abnf.WSP + abnf.CRLF * abnf.WSP)
  local text         = LWSP^1 / " "
                     + abnf.VCHAR
  local ignore       = LWSP + abnf.VCHAR
  local number       = R"09"^1 / tonumber
  local separator    = S'()<>@,;:\\"/[]?={}\t '
  local token        = (abnf.VCHAR - separator)^1

  local status       = C"Status"       * P":" * LWSP * number * ignore^0 * abnf.CRLF
  local content_type = C"Content-Type" * P":" * LWSP * Cs(text^1)        * abnf.CRLF
  local location     = C"Location"     * P":" * LWSP * C(abnf.VCHAR^1)   * abnf.CRLF
  local generic      = C(token)        * P":" * LWSP * C(text^0)         * abnf.CRLF
  local headers      = status + content_type + location + generic
  parse_headers      = Cf(Ct"" * Cg(headers)^1,function(acc,name,value)
                         acc[name] = value
                         return acc
                       end)
                     * abnf.CRLF
end

-- ************************************************************************

local function fdtoios(fd)
  local newfd   = ios()
  newfd.__fd    = fd
  newfd.__co    = coroutine.running()
  
  newfd.close = function(self)
    nfl.SOCKETS:remove(fd)
    self.__fd:close()
    return true
  end
  
  newfd._refill = function()
    return coroutine.yield()
  end
  
  nfl.SOCKETS:insert(fd,'r',function(event)
    if event.read then
      local data,err = fd:read(8192)
      if data then
        if #data == 0 then
          nfl.SOCKETS:remove(fd)
          newfd._eof = true
        end
        nfl.schedule(newfd.__co,data)
      else
        if err ~= errno.EAGAIN then
          syslog('error',"fd:read() = %s",errno[err])
        end
      end
    else
      newfd._eof = true
      nfl.SOCKETS:remove(fd)
      nfl.schedule(newfd.__co)
    end
  end)
  
  return newfd
end

-- ************************************************************************

local function makepipe()
  local fd = fsys.pipe()
  fd.read:setvbuf('no')
  return fd
end

-- ************************************************************************

local function touripath(location)
  local res = ""
  for i = 1 , location.path._n do
    res = res .. "/" .. location.path[i]
  end
  
  return res
end

-- ************************************************************************

local function totranslate(location)
  local res = ""
  for i = location.path._n + 1, #location.path do
    res = res .. "/" .. location.path[i]
  end
  
  return res
end

-- ************************************************************************

local function query_to_string(query)
  if not query then
    return ""
  end
  
  local res = {}
  
  for name,val in pairs(query) do
    if val == true then
      table.insert(res,name)
    else
      table.insert(res,string.format("%s=%s",name,val))
    end
  end
  
  return table.concat(res,"&")
end

-- ************************************************************************

return function(remote,program,location)
  local env =
  {
    PATH              = "/usr/local/bin:/usr/bin:/bin",
    DEBUG             = "true",
    
    GATEWAY_INTERFACE = "CGI/1.1",
    QUERY_STRING      = query_to_string(location.query),
    REMOTE_ADDR       = remote.addr,
    REMOTE_HOST       = remote.addr,
    REQUEST_METHOD    = "",
    SCRIPT_NAME       = touripath(location),
    SERVER_NAME       = location.host,
    SERVER_PORT       = tostring(location.port),
    SERVER_PROTOCOL   = "GEMINI",
    SERVER_SOFTWARE   = "GLV-1.12556/1",
  }
  
  -- -------------------------------------------------------------------
  -- XXX-a total hack.  I need to think on how to pass this info across
  -- -------------------------------------------------------------------
  
  if location.path._n < #location.path then
    env.PATH_INFO       = totranslate(location)
    env.PATH_TRANSLATED = fsys.getcwd() .. env.PATH_INFO
  end
  
  local devnulo = io.open("/dev/null","w")
  local devnuli = io.open("/dev/null","r")
  
  local pipe = makepipe()
  if not pipe then
    devnuli:close()
    devnulo:close()
    return 500,"Internal Error",""
  end
  
  local child,err = process.fork()
  
  if not child then
    syslog('error',"process.fork() = %s",errno[err])
    return 500,"Internal Error",""
  end
  
  if child == 0 then
    fsys.redirect(devnuli,io.stdin)
    
    local _,err2 = fsys.redirect(pipe.write,io.stdout)
    if err2 ~= 0 then
      syslog('error',"fsys.redirect(stdout) = %s",errno[err2])
      return 500,"Internal Error",""
    end
    
    fsys.redirect(devnulo,io.stderr)
    
    devnuli:close()
    devnulo:close()
    pipe.write:close()
    pipe.read:close()
    
    process.exec(program,{},env)
    process._exit(exit.OSERR)
  end
  
  devnuli:close()
  devnulo:close()
  pipe.write:close()
  
  local inp  = fdtoios(pipe.read)
  local hdrs = inp:read("h")
  local data = inp:read("a")
  inp:close()
  
  local info,err1 = process.wait(child)

  if not info then
    syslog('error',"process.wait() = %s",errno[err1])
    return 500,"Internal Error",""
  end
  
  if info.status == 'normal' then
    if info.rc == 0 then
      local headers = parse_headers:match(hdrs)
      
      if headers['Location'] then
        local status = headers['Status'] or 301
        return status,headers['Location'],""
      end
      
      local status  = headers['Status'] or 200
      local mime    = headers['Content-Type'] or "text/plain"
      return status,mime,data
    else
      syslog('warning',"program=%q status=%d",program,info.rc)
      return 500,"Internal Error",""
    end
  else
    syslog('error',"program=%q status=%s description=%s",program,info.status,info.description)
    return 500,"Internal Error",""
  end
end
