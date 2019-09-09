-- ************************************************************************
--
--    The file system handler
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

local syslog = require "org.conman.syslog"
local errno  = require "org.conman.errno"
local fsys   = require "org.conman.fsys"
local magic  = require "org.conman.fsys.magic"
local uurl   = require "url-util"
local MSG    = require "MSG"
local cgi    = require "cgi"
local io     = require "io"
local string = require "string"
local table  = require "table"

local ipairs = ipairs

_ENV = {}

-- ************************************************************************

function init(conf)
  if not conf.index then
    conf.index = "index.gemini"
  end
  
  magic:flags 'mime'
  return true
end

-- ************************************************************************

local function descend_path(path)
  local function iter(state,var)
    local n = state()
    if n then
      return var .. "/" .. n,n
    end
  end
  
  return iter,path:gmatch("[^/]+"),"."
end

-- ************************************************************************

function handler(conf,auth,loc,match)
  local function read_file(file)
    local function contents(mime)
      local f = io.open(file)
      if not f then
        return 40,MSG[40],""
      end
      
      local data = f:read("*a")
      f:close()
      return 20,mime,data
    end
    
    if fsys.access(file,"rx") then
      return cgi(auth,file,loc)
    end
    
    if not fsys.access(file,"r") then
      return 40,MSG[40],""
    end
    
    if file:match "%.gemini$" then
      return contents("text/gemini")
    else
      return contents(magic(file))
    end
  end
  
  for dir,segment in descend_path(match[1]) do
    -- ----------------------------------------------------
    -- Skip the following files that match these patterns
    -- ----------------------------------------------------
    
    for _,pattern in ipairs(conf.no_access) do
      if segment:match(pattern) then
        return 51,MSG[51],""
      end
    end
    
    local name = conf.directory .. "/" .. dir
    local info,err = fsys.stat(name)
    
    if not info then
      syslog('error',"fsys.stat(%q) = %s",name,errno[err])
      return 51,MSG[51],""
    end
    
    if info.mode.type == 'dir' then
      -- -------------------------------------------
      -- Do we have an issue with Unix permissions?
      -- -------------------------------------------
      if not fsys.access(name,"x") then
        syslog('error',"access(%q) failed",dir)
        return 40,MSG[40],""
      end
    elseif info.mode.type == 'file' then
      return read_file(name)
    else
      return 51,MSG[51],""
    end
  end
  
  local final = conf.directory .. "/" .. match[1]
  if fsys.access(final .. "/" .. conf.index,"r") then
    return read_file(final .. "/" .. conf.index)
  end
  
  local res =
  {
    string.format("Index of %s",match[1]),
    "---------------------------",
    ""
  }
  
  local function access_okay(dir,entry)
    for _,pattern in ipairs(conf.no_access) do
      if entry:match(pattern) then return false end
    end
    
    local fname = dir .. "/" .. entry
    local info  = fsys.stat(fname)
    if not info then
      return false
    elseif info.mode.type == 'file' then
      return fsys.access(fname,"r"),'file'
    elseif info.mode.type == 'dir' then
      return fsys.access(fname,"x"),'dir'
    else
      return false
    end
  end
  
  local lists =
  {
    dir  = {},
    file = {},
  }
  
  for entry in fsys.dir(final) do
    local okay,type = access_okay(final,entry)
    if okay then
      table.insert(lists[type],entry)
    end
  end
  
  table.sort(lists.dir)
  table.sort(lists.file)
  
  for _,entry in ipairs(lists.dir) do
    local filename
    
    if match[1]:match "/$" then
      filename = match[1] .. entry .. "/"
    else
      filename = match[1] .. "/" .. entry .. "/"
    end
    
    filename = uurl.rm_dot_segs:match(filename)
    filename = uurl.esc_path:match(filename)
    table.insert(res,string.format("=> %s\t%s",filename,entry))
  end
  
  if #lists.dir > 0 then
    table.insert(res,"")
  end
  
  for _,entry in ipairs(lists.file) do
    local filename
    
    if match[1]:match "/$" then
      filename = match[1] .. entry
    else
      filename = match[1] .. "/" .. entry
    end
    
    filename = uurl.rm_dot_segs:match(filename)
    filename = uurl.esc_path:match(filename)
    table.insert(res,string.format("=> %s\t%s",filename,entry))
  end
  
  table.insert(res,"")
  table.insert(res,"---------------------------")
  table.insert(res,"GLV-1.12556")
  
  return 20,"text/gemini",table.concat(res,"\r\n") .. "\r\n"
end

-- ************************************************************************

return _ENV
