-- ************************************************************************
--
--    Handle user directories
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
-- luacheck: globals init handler
-- luacheck: ignore 611

local fsys       = require "org.conman.fsys"
local filesystem = require "GLV-1.handlers.filesystem"
local getuserdir = require "GLV-1.getuserdir"
local MSG        = require "GLV-1.MSG"

_ENV = {}

-- ************************************************************************

function init(conf)
  if not conf.directory then
    conf.directory = "public_gemini"
  end
  
  filesystem.init(conf)
  return true
end

-- ************************************************************************

function handler(conf,auth,loc,match)
  local userdir = getuserdir(match[1])
  if not userdir then
    return 51,MSG[51],""
  end
  
  userdir = userdir .. "/" .. conf.directory
  
  if not fsys.access(userdir,"rx") then
    return 51,MSG[51],""
  end
  
  local fsconf =
  {
    path      = conf.path,
    module    = "GLV-1.handlers.filesystem",
    directory = userdir,
    index     = conf.index,
    extension = conf.extension,
    no_access = conf.no_access,
  }
  
  return filesystem.handler(fsconf,auth,loc,{ match[2] })
end

-- ************************************************************************

return _ENV
