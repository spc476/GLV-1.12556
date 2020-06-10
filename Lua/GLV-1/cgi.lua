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
local lpeg      = require "lpeg"
local io        = require "io"
local string    = require "string"
local coroutine = require "coroutine"
local uurl      = require "GLV-1.url-util"
local MSG       = require "GLV-1.MSG"
local gi        = require "GLV-1.gateway"

local tonumber  = tonumber

local DEVNULI = io.open("/dev/null","r")
local DEVNULO = io.open("/dev/null","w")

-- ************************************************************************
-- Handle script command line arguments per RFC-3875 section 4.4
-- ************************************************************************

local parse_cgi_args do
  local xdigit   = lpeg.locale().xdigit
  local char     = lpeg.P"%" * lpeg.C(xdigit * xdigit)
                 / function(c)
                     return string.char(tonumber(c,16))
                   end
                 + (lpeg.R"!~" - lpeg.S' #%<>[\\]^{|}"=&+')
  local args     = lpeg.Cs(char^1) * lpeg.P"+"^-1
  parse_cgi_args = lpeg.Ct(args^1) * lpeg.P(-1)
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

return function(auth,program,directory,base,location)
  local gconf = require "CONF".cgi
  local hconf = require "CONF".hosts[location.host].cgi
  local dconf = directory.cgi
  
  -- ------------------------------------------------------------------------
  -- If the cgi block is not defined for the server, nor for a host, and we
  -- get here, then there's been a misconfiguration.  Report the error.  The
  -- other case is when the host has explicitely set 'cgi = false', in which
  -- case, that host is opting out of CGI support entirely, so report the
  -- error in that case too.
  -- ------------------------------------------------------------------------
  
  if not gconf and not hconf and not dconf then
    syslog('error',"CGI script called, but CGI not configured!")
    return 40,MSG[40],""
  end
  
  if dconf == false
  or hconf == false and dconf == nil then
    syslog('error',"CGI script called, but CGI not configured!")
    return 40,MSG[40],""
  end
  
  local pipe,err1 = fsys.pipe()
  if not pipe then
    syslog('error',"CGI pipe: %s",errno[err1])
    return 40,MSG[40],""
  end
  
  pipe.read:setvbuf('no') -- buffering kills the event loop
  
  local child,err = process.fork()
  
  if not child then
    syslog('error',"process.fork() = %s",errno[err])
    return 40,MSG[40],""
  end
  
  -- =========================================================
  -- The child runs off to do its own thang ...
  -- =========================================================
  
  if child == 0 then
    fsys.redirect(DEVNULI,io.stdin)
    fsys.redirect(pipe.write,io.stdout)
    fsys.redirect(DEVNULO,io.stderr)
    
    -- -----------------------------------------------------------------
    -- Close file descriptors that aren't stdin, stdout or stderr.  Most
    -- Unix systems have dirfd(), right?  Right?  And /proc/self/fd,
    -- right?  Um ... erm ...
    -- -----------------------------------------------------------------
    
    local dir = fsys.opendir("/proc/self/fd")
    if dir and dir._tofd then
      local dirfh = dir:_tofd()
      
      for file in dir.next,dir do
        local fh = tonumber(file)
        if fh > 2 and fh ~= dirfh then
          fsys._close(fh)
        end
      end
      
    -- ----------------------------------------------------------
    -- if all else fails, at least close these to make this work
    -- ----------------------------------------------------------
    
    else
      DEVNULI:close()
      DEVNULO:close()
      pipe.write:close()
      pipe.read:close()
    end
    
    local args = parse_cgi_args:match(location.query or "") or {}
    local env  = gi.setup_env(auth,program,base,location,directory,'cgi',hconf,gconf)
    local prog do
      if program:match "^/" then
        prog = uurl.rm_dot_segs:match(program)
      else
        prog = uurl.rm_dot_segs:match(fsys.getcwd() .. "/" .. program)
      end
    end
    
    local okay,err2 = fsys.chdir(directory.directory)
    if not okay then
      syslog('error',"CGI cwd(%q) = %s",directory.directory,errno[err2])
      process.exit(exit.CONFIG)
    end
    
    process.exec(prog,args,env)
    process.exit(exit.OSERR)
  end
  
  -- =========================================================
  -- Meanwhile, back at the parent's place ...
  -- =========================================================
  
  pipe.write:close()
  local inp  = fdtoios(pipe.read)
  local hdrs = inp:read("h")
  local data = inp:read("a")
  inp:close()
  
  local info,err2 = process.wait(child)
  
  if not info then
    syslog('error',"process.wait() = %s",errno[err2])
    return 40,MSG[40],""
  end
  
  if info.status == 'normal' then
    if info.rc == 0 then
      return gi.handle_output(program,hdrs,data)
    else
      syslog('warning',"program=%q status=%d",program,info.rc)
      return 40,MSG[40],""
    end
  else
    syslog('error',"program=%q status=%s description=%s",program,info.status,info.description)
    return 40,MSG[40],""
  end
end
