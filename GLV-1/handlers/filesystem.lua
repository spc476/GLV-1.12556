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
local uurl   = require "GLV-1.url-util"
local cgi    = require "GLV-1.cgi"
local scgi   = require "GLV-1.scgi"
local io     = require "io"
local string = require "string"
local table  = require "table"

local ipairs = ipairs
local pairs  = pairs

_ENV = {}

-- ************************************************************************

function init(iconf,hconf,gconf)
  iconf.index     = iconf.index
                 or hconf.index
                 or gconf.index
                 or "index.gemini"
  iconf.no_access = iconf.no_access
                 or hconf.no_access
                 or gconf.no_access
                 or { "^%." }
  iconf.extension = iconf.extension
                 or hconf.extension
                 or gconf.extension
                 or ".gemini"
                 
  local gmime = gconf.mime or {}
  local hmime = hconf.mime or {}
  
  for ext,mimetype in pairs(gmime) do
    if hmime[ext] == nil then
      hmime[ext] = mimetype
    end
  end
  
  if not iconf.mime then
    iconf.mime = hmime
  else
    for ext,mimetype in pairs(hmime) do
      if iconf.mime[ext] == nil then
        iconf.mime[ext] = mimetype
      end
    end
  end
  
  if not iconf.path then
    return false,"missing path"
  end
  
  if iconf.path:match "/$" then
    iconf.path = iconf.path:sub(1,-2)
  end
  
  do
    local ext = iconf.extension:sub(2,-1)
    if iconf.mime[ext] then
      if iconf.mime[ext] ~= 'text/gemini' then
        syslog('warning',"overriding existing MIME type for .%s",ext)
        iconf.mime[ext] = 'text/gemini'
      end
    else
      iconf.mime[ext] = 'text/gemini'
    end
  end
  
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

function handler(conf,auth,loc,pathinfo,ios)
  local function read_file(file,base)
    local function contents(mime)
      if mime == "" then
        syslog('warning',"%s: missing MIME type",file)
        mime = 'text/plain'
      end
      
      local f,err = io.open(file,"rb")
      if not f then
        syslog('error',"%s: %s",file,err)
        ios:write("51 \r\n")
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
    
    if fsys.access(file,"rx") then
      return cgi(auth,file,conf,base,loc,ios)
    end
    
    if not fsys.access(file,"r") then
      ios:write("51 \r\n")
      return 51
    end
    
    return contents(conf.mime[fsys.extension(file)] or magic(file))
  end
  
  if pathinfo == "" then
    loc.path = loc.path .. "/"
    ios:write("31 ",uurl.toa(loc),"\r\n")
    return 31
  end
  
  -- -----------------------------------------------------------------------
  -- pathinfo should start with a leading '/'.  If it doesn't then someone
  -- is playing games here.
  -- -----------------------------------------------------------------------
  
  if not pathinfo:match "^/" then
    ios:write("51 \r\n")
    return 51
  end
  
  pathinfo = pathinfo:sub(2,-1)
  
  for dir,segment in descend_path(pathinfo) do
    -- ----------------------------------------------------
    -- Skip the following files that match these patterns
    -- ----------------------------------------------------
    
    for _,pattern in ipairs(conf.no_access) do
      if segment:match(pattern) then
        ios:write("51 \r\n")
        return 51
      end
    end
    
    local name     = conf.directory .. "/" .. dir
    local info,err = fsys.lstat(name)
    
    if not info then
      syslog('error',"fsys.stat(%q) = %s",name,errno[err])
      ios:write("51 \r\n")
      return 51
    end
    
    if info.mode.type == 'dir' then
      -- -------------------------------------------
      -- Do we have an issue with Unix permissions?
      -- -------------------------------------------
      if not fsys.access(name,"x") then
        syslog('error',"access(%q) failed",dir)
        ios:write("51 \r\n")
        return 51
      end
    elseif info.mode.type == 'file' then
      local _,e  = loc.path:find(segment,1,true)
      local base = loc.path:sub(1,e)
      return read_file(name,base)
    elseif info.mode.type == 'link' then
      local _,e  = loc.path:find(segment,1,true)
      local base = loc.path:sub(1,e)
      return scgi(auth,name,conf,base,loc,ios)
    else
      ios:write("51 \r\n")
      return 51
    end
  end
  
  -- ----------------------------------------------------------------------
  -- Because I'm that pedantic---if we get here, we're at a directory.  If
  -- the passed in request did NOT end in a '/', do a permanent redirect to
  -- a request WITH a final '/'.  This is to ensure any mistakes with
  -- covering a directory in the authorization block doesn't fail because
  -- the user included a trailing '/' in the pattern ...
  -- ----------------------------------------------------------------------
  
  if not loc.path:match "/$" then
    ios:write("31 ",uurl.esc_path:match(loc.path .. "/"),"\r\n")
    return 31
  end
  
  -- ------------------------
  -- Check for an index file
  -- ------------------------
  
  local final = conf.directory .. "/" .. pathinfo
  if fsys.access(final .. "/" .. conf.index,"r") then
    return read_file(final .. "/" .. conf.index)
  end
  
  -- --------------------------------------------
  -- Nope, one doesn't exist, so let's build one
  -- --------------------------------------------
  
  local res =
  {
    string.format("Index of %s",pathinfo),
    "---------------------------",
    ""
  }
  
  local function access_okay(dir,entry)
    for _,pattern in ipairs(conf.no_access) do
      if entry:match(pattern) then return false end
    end
    
    local fname = dir .. "/" .. entry
    local info  = fsys.lstat(fname)
    if not info then
      return false
    elseif info.mode.type == 'file' then
      if fsys.access(fname,'rx') then
        return true,'file','CGI script'
      else
        return fsys.access(fname,"r"),'file',string.format("%d bytes",info.size)
      end
    elseif info.mode.type == 'dir' then
      return fsys.access(fname,"x"),'dir'
    elseif info.mode.type == 'link' then
      return true,'file','SCGI script'
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
    local okay,type,meta = access_okay(final,entry)
    if okay then
      table.insert(lists[type],{ name = entry , meta = meta })
    end
  end
  
  table.sort(lists.dir, function(a,b) return a.name < b.name end)
  table.sort(lists.file,function(a,b) return a.name < b.name end)
  
  for _,entry in ipairs(lists.dir) do
    table.insert(res,string.format("=> %s/\t%s/",uurl.esc_path:match(entry.name),entry.name))
  end
  
  if #lists.dir > 0 then
    table.insert(res,"")
  end
  
  for _,entry in ipairs(lists.file) do
    table.insert(res,string.format("=> %s\t%s (%s)",uurl.esc_path:match(entry.name),entry.name,entry.meta))
  end
  
  table.insert(res,"")
  table.insert(res,"---------------------------")
  table.insert(res,"GLV-1.12556")
  
  ios:write(
        "20 text/gemini\r\n",
        table.concat(res,"\r\n"),
        "\r\n"
  )
  return 20
end

-- ************************************************************************

return _ENV
