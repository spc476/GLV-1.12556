-- ************************************************************************
--
--    The file handler
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
-- luacheck: globals init handler
-- luacheck: ignore 611

local syslog = require "org.conman.syslog"
local errno  = require "org.conman.errno"
local fsys   = require "org.conman.fsys"
local magic  = require "org.conman.fsys.magic"
local lpeg   = require "lpeg"
local io     = require "io"

_ENV = {}

-- ************************************************************************

local extension do
  local char = lpeg.C(lpeg.S"^$()%.[]*+-?") / "%%%1"
             + lpeg.R" \255"
  extension  = lpeg.Cs(char^1 * lpeg.Cc"$")
end

-- ************************************************************************

function init(conf)
  if not conf.extension then
    conf.extension = '%.gemini$'
  else
    conf.extension = extension:match(conf.extension)
  end
  
  if not conf.file then
    return false,"missing file specification"
  else
    return true
  end
end

-- ************************************************************************

function handler(conf,_,_,_,ios)
  local function contents(mime)
    local f,err = io.open(conf.file,'rb')
    if not f then
      syslog('error',"%s: %s",conf.file,err)
      ios:write("51\r\n")
      return 51
    end
    
    ios:write("20 ",mime,"\r\n")
    
    repeat
      local data = f:read(1024)
      if data then ios:write(data) end
    until not data
    
    f:close()
    return 20
  end
  
  if fsys.access(conf.file,'x') then
    syslog('error',"%s: can only serve non-executable files",conf.file)
    ios:write("40\r\n")
    return 40
  end
  
  local okay,err = fsys.access(conf.file,'r')
  if not okay then
    syslog('error',"%s: %s",conf.file,errno[err])
    ios:write("51\r\n")
    return 51
  end
  
  if conf.file:match(conf.extension) then
    return contents("text/gemini")
  elseif conf.mime then
    return contents(conf.mime)
  else
    return contents(magic(conf.file))
  end
end

-- ************************************************************************

return _ENV
