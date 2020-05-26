-- ************************************************************************
--
--    SCGI interace.
--    Copyright 2020 by Sean Conner.  All Rights Reserved.
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

local syslog = require "org.conman.syslog"
local fsys   = require "org.conman.fsys"
local errno  = require "org.conman.errno"
local url    = require "org.conman.parsers.url"
local tcp    = require "org.conman.nfl.tcp"
local MSG    = require "GLV-1.MSG"
local gi     = require "GLV-1.gateway"

local pairs    = pairs
local tostring = tostring

-- ************************************************************************

return function(auth,program,directory,location)
  local sconf = require "CONF".scgi
  local hconf = require "CONF".hosts[location.host].scgi
  
  if not sconf and not hconf then
    syslog('error',"SCGI called, but SCGI not configured!")
    return 40,MSG[40],""
  end
  
  if hconf == false then
    syslog('error',"SCGI called, but SCGI not configured!")
    return 40,MSG[40],""
  end
  
  local env  = gi.setup_env(auth,program,directory,location,sconf,hconf)
  local tenv = "CONTENT_LENGTH" .. '\0' .. "0" .. '\0'
            .. "SCGI"           .. '\0' .. "1" .. '\0'
  
  for name,val in pairs(env) do
    tenv = tenv .. name .. '\0' .. val .. '\0'
  end
  
  local scgiurl,err = fsys.readlink(program)
  if not scgiurl then
    syslog('error',"SCGI: readlink() = %s",errno[err])
    return 40,MSG[40],""
  end
  
  local scgiloc = url:match(scgiurl)
  if not scgiloc then
    syslog('error',"SCGI: bad link %q",scgiloc)
    return 40,MSG[40],""
  end
  
  if not scgiloc.host then
    syslog('error',"SCGI: %q missing host",program)
    return 40,MSG[40],""
  end
  
  if not scgiloc.port then
    syslog('error',"SCGI: %q missing port",program)
    return 40,MSG[40],""
  end
  
  local ios = tcp.connect(scgiloc.host,scgiloc.port,5)
  if not ios then
    return 40,MSG[40],""
  end
  
  ios:write(tostring(#tenv),":",tenv,",0:,")
  local hdrs = ios:read("h")
  local data = ios:read("a")
  ios:close()
  
  return gi.handle_output(program,hdrs,data)
end
