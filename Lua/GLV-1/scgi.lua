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
local net    = require "org.conman.net"
local tcp    = require "org.conman.nfl.tcp"
local gi     = require "GLV-1.gateway"

local pairs    = pairs
local tostring = tostring

-- ************************************************************************

return function(auth,program,directory,base,location,ios)
  local gconf = require "CONF".scgi
  local hconf = require "CONF".hosts[location.host].scgi
  local dconf = directory.scgi
  
  if not gconf and not hconf and not dconf then
    syslog('error',"SCGI called, but SCGI not configured!")
    ios:write("40\r\n")
    return 40
  end
  
  if dconf == false
  or hconf == false and dconf == nil then
    syslog('error',"SCGI called, but SCGI not configured!")
    ios:write("40\r\n")
    return 40
  end
  
  local env  = gi.setup_env(auth,program,base,location,directory,'scgi',hconf,gconf)
  local tenv = "CONTENT_LENGTH" .. '\0' .. "0" .. '\0'
            .. "SCGI"           .. '\0' .. "1" .. '\0'
  
  for name,val in pairs(env) do
    tenv = tenv .. name .. '\0' .. val .. '\0'
  end
  
  local scgiurl,err = fsys.readlink(program)
  if not scgiurl then
    syslog('error',"SCGI: readlink() = %s",errno[err])
    ios:write("40\r\n")
    return 40
  end
  
  local scgiloc = url:match(scgiurl)
  if not scgiloc then
    syslog('error',"SCGI: bad link %q",scgiurl)
    ios:write("40\r\n")
    return 40
  end
  
  if scgiloc.scheme ~= 'scgi' then
    syslog('error',"SCGI: bad scheme %q",scgiurl)
    ios:write("40\r\n")
    return 40
  end
  
  local addr
  
  if scgiloc.host then
    if not scgiloc.port then
      syslog('error',"SCGI: %q missing port",scgiurl)
      ios:write("40\r\n")
      return 40
    end
    
    addr = net.address2(scgiloc.host,'any','tcp',scgiloc.port)[1]
  else
    if scgiloc.path == "" then
      syslog('error',"SCGI: %q missing path",scgiurl)
      ios:write("40\r\n")
      return 40
    end
    
    addr = net.address(scgiloc.path,'tcp')
  end
  
  local inp = tcp.connecta(addr,5)
  if not inp then
    ios:write("40\r\n")
    return 40
  end
  
  inp:write(tostring(#tenv),":",tenv,",0:,")
  local status = gi.handle_output(ios,inp,program)
  inp:close()
  return status
end
