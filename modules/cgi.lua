-- ************************************************************************
--
--    Bible module
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

local dump   = require "org.conman.table".dump_value
local syslog = require "org.conman.syslog"
local fsys   = require "org.conman.fsys"
local ios    = require "org.conman.net.ios"
local io     = require "io"
local table  = require "table"
local string = require "string"

local pairs    = pairs
local tostring = tostring

-- ************************************************************************

local function pipe_read(self)
end

-- ************************************************************************

local function pipe_write(self)
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
    
    GATEWAY_INTERFACE = "CGI/1.1",
    QUERY_STRING      = query_to_string(location.query),
    REMOTE_ADDR       = tostring(remote),
    REMOTE_HOST       = tostring(remote),
    REQUEST_METHOD    = "",
    SCRIPT_NAME       = touripath(location),
    SERVER_NAME       = location.host,
    SERVER_PORT       = tostring(location.port),
    SERVER_PROTOCOL   = "GEMINI/1.0",
    SERVER_SOFTWARE   = "GLV-1.12556/1",
  }
  
  if location.path._n < #location.path then
    env.PATH_INFO       = totranslate(location)
    env.PATH_TRANSLATED = fsys.getcwd() .. env.PATH_INFO
  end
  
  return 200,"text/plain",dump("env",env)
end
