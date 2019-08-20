#!/usr/bin/env lua
-- ************************************************************************
--
--    Server program
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

local signal    = require "org.conman.signal"
local exit      = require "org.conman.const.exit"
local syslog    = require "org.conman.syslog"
local fsys      = require "org.conman.fsys"
local magic     = require "org.conman.fsys.magic"
local errno     = require "org.conman.errno"
local net       = require "org.conman.net"
local nfl       = require "org.conman.nfl"
local tls       = require "org.conman.nfl.tls"
local lpeg      = require "lpeg"

local CONF = {}
local MSG  =
{
  [40] = "Temporary Error",
  [41] = "Server Unavailable",
  [42] = "CGI Error",
  [43] = "Proxy Error",
  [44] = "Slow Down",
  [50] = "Permanent Error",
  [51] = "Not Found",
  [52] = "Gone",
  [53] = "Proxy Request Refused",
  [59] = "Bad Request",
  [60] = "Client Certificate Required",
  [61] = "Transient Certificate Required",
  [62] = "Authorized Certicate Required",
  [63] = "Certificate Not Accepted",
  [64] = "Future Certificate Rejected",
  [65] = "Expired Certificate Rejected",
}

-- ************************************************************************

if #arg == 0 then
  io.stderr:write(string.format("usage: %s confifile\n",arg[0]))
  os.exit(exit.USAGE,true)
end

do
  local conf,err = loadfile(arg[1],"t",CONF)
  if not conf then
    io.stderr:write(string.format("%s: %s\n",arg[1],err))
    os.exit(exit.CONFIG,true)
  end
  
  conf()
  
  if CONF.modules then
    package.path  = CONF.modules  .. ";" .. package.path
  end
  
  if CONF.cmodules then
    package.cpath = CONF.cmodules .. ";" .. package.cpath
  end
  
  if not CONF.no_access then
    CONF.no_access = {}
  end
  
  -- --------------------------------------------
  -- Make sure the redirect tables always exist.
  -- --------------------------------------------
  
  if not CONF.redirect then
    CONF.redirect = { temporary = {} , permanent = {} , gone = {} }
  else
    CONF.redirect.temporary = CONF.redirect.temporary or {}
    CONF.redirect.permanent = CONF.redirect.permanent or {}
    CONF.redirect.gone      = CONF.redirect.gone      or {}
  end
  
  -- --------------------------------------------------------------------
  -- If we don't have any handlers, make sure they now exist.
  -- If we do have handlers, load them up and initialize them.
  -- --------------------------------------------------------------------
  
  if not CONF.handlers then
    CONF.handlers = {}
  else
    local function notfound()
      return 404,"Not found",""
    end
    
    local function loadmod(info)
      local okay,mod = pcall(require,info.module)
      if not okay then
        syslog('error',"%s: %s",info.module,mod)
        info.code = { handler = notfound }
        return
      end
      
      if type(mod) ~= 'table' then
        syslog('error',"%s: module not supported",info.module)
        info.code = { handler = notfound }
        return
      end
      
      if not mod.handler then
        syslog('error',"%s: missing handler()",info.module)
        mod.handler = notfound
        return
      end
      
      if mod.init then
        okay,err = mod.init(info)
        if not okay then
          syslog('error',"%s: %s",info.module,err)
          mod.handler = notfound
          return
        end
      end
      
      info.code = mod
    end
    
    for _,info in pairs(CONF.handlers) do
      loadmod(info)
    end
  end
end

local url  = require "url"      -- XXX hack
local uurl = require "url-util" -- XXX hack
local cgi  = require "cgi"      -- XXX hack

magic:flags('mime')
syslog.open(CONF.log.ident,CONF.log.facility)

CONF._internal      = {}
CONF._internal.addr = net.address2(CONF.network.addr,'any','tcp',CONF.network.port)[1]

-- ************************************************************************

local redirect_subst do
  local replace  = lpeg.C(lpeg.P"$" * lpeg.R"09") * lpeg.Carg(1)
                 / function(c,t)
                     c = tonumber(c:sub(2,-1))
                     return t[c]
                   end
  local char     = replace + lpeg.P(1)
  redirect_subst = lpeg.Cs(char^1)
end

-- ************************************************************************

local function descend_path(path)
  local function iter(state,var)
    local n = state()
    if n then
      assert(n ~= "..")
      assert(n ~= ".")
      return var .. "/" .. n,n
    end
  end
  
  return iter,path:gmatch("[^/]+"),"."
end

-- ************************************************************************

local cert_parse do
  local Cf = lpeg.Cf
  local Cg = lpeg.Cg
  local Ct = lpeg.Ct
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  
  local name   = R("AZ","az")^1
  local value  = R(" .","0\255")^1
  local record = Cg(P"/" * C(name) * P"=" * C(value))
  cert_parse   = Cf(Ct"" * record^1,function(acc,n,v) acc[n] = v return acc end)
end

-- ************************************************************************

local function authorized(tag,ios,checkf,loc)
  if not ios.__ctx:peer_cert_provided() then
    local ok,auth,status = pcall(checkf)
    if not ok then
      syslog('error',"%s: %s",tag,auth)
      return false,40
    else
      return false,status or 60
    end
  end
  
  local I         = ios.__ctx:peer_cert_issuer()
  local S         = ios.__ctx:peer_cert_subject()
  local issuer    = cert_parse:match(I)
  local subject   = cert_parse:match(S)
  local notbefore = ios.__ctx:peer_cert_notbefore()
  local notafter  = ios.__ctx:peer_cert_notafter()
  local now       = os.time()
  
  if now < notbefore then
    return false,64,S,I
  end
  
  if now > notafter then
    return false,65,S,I
  end
  
  local ok,auth = pcall(checkf,issuer,subject,loc)
  if not ok then
    syslog('error',"%s: %s",tag,auth)
    return false,40
  end
  
  return auth,63,S,I
end

-- ************************************************************************

local function authorized_dir(ios,dir,loc)
  local pfname   = dir .. "/.private"
  local okay,err = fsys.access(pfname,'r')
  
  -- --------------------------------------------------------------
  -- If .private doesn't exist, we're okay to go.  Any other error
  -- and we deny access just to be safe
  -- --------------------------------------------------------------
  
  if not okay and err == errno.ENOENT then return true end
  if not okay then
    syslog('error',"%s: %s",pfname,errno[err])
    return false,60
  end
  
  local check,err1 = loadfile(pfname,"t",{})
  if not check then
    syslog('error',"%s: %s",pfname,err1)
    return false,40
  end
  
  return authorized(pfname,ios,check,loc)
end

-- ************************************************************************

local function copy_file(ios,name)
  local f = io.open(name,"rb")
  local s = 0
  repeat
    local data = f:read(8192)
    if data then
      local okay,err = ios:write(data)
      if not okay then
        syslog('error',"ios:write() = %s",err)
        f:close()
        return s
      end
      s = s + #data
    end
  until not data
  f:close()
  return s
end

-- ************************************************************************

local function reply(ios,...)
  local bytes = 0
  
  for i = 1 , select('#',...) do
    local item = select(i,...)
    bytes = bytes + #tostring(item)
  end
  
  ios:write(...)
  return bytes
end

-- ************************************************************************

local function log(ios,status,request,bytes,subject,issuer)
  syslog(
        'info',
        "remote=%s status=%d request=%q bytes=%d subject=%q issuer=%q",
        ios.__remote.addr,
        status,
        request,
        bytes,
        subject or "",
        issuer  or ""
  )
end

-- ************************************************************************

local function main(ios)
  ios:_handshake()
  
  local request = ios:read("*l")
  if not request then
    log(ios,59,"",reply(ios,"59\t",MSG[59],"\r\n"))
    ios:close()
    return
  end
  
  local loc = url:match(request)
  if not loc then
    log(ios,59,"",reply(ios,"59\t",MSG[59],"\r\n"))
    ios:close()
    return
  end
  
  if not loc.host then
    log(ios,59,"",reply(ios,"59\t",MSG[59],"\r\n"))
    ios:close()
    return
  end
  
  loc.scheme = loc.scheme or "gemini"
  
  if loc.scheme ~= 'gemini'
  or loc.host   ~= CONF.network.host
  or loc.port   ~= CONF.network.port then
    log(ios,59,"",reply(ios,"59\t",MSG[59],"\r\n"))
    ios:close()
    return
  end
  
  loc.path   = uurl.rm_dot_segs:match(loc.path)
  
  -- -------------------------------------------------------------
  -- We handle the various redirections here, the temporary ones,
  -- the permanent ones, and those that are gone gone gone ...
  -- -------------------------------------------------------------
  
  for pattern,replace in pairs(CONF.redirect.temporary) do
    local match = table.pack(loc.path:match(pattern))
    if #match > 0 then
      local new = redirect_subst:match(replace,1,match)
      log(ios,30,request,reply(ios,"30\t",new,"\r\n"))
      ios:close()
      return
    end
  end
  
  for pattern,replace in pairs(CONF.redirect.permanent) do
    local match = table.pack(loc.path:match(pattern))
    if #match > 0 then
      local new = redirect_subst:match(replace,1,match)
      log(ios,31,request,reply(ios,"31\t",new,"\r\n"))
      ios:close()
      return
    end
  end
  
  for _,pattern in ipairs(CONF.redirect.gone) do
    if loc.path:match(pattern) then
      log(ios,52,request,reply(ios,"52\t",MSG[52],"\r\n"))
      ios:close()
      return
    end
  end
  
  -- -------------------------------------
  -- Run through our installed handlers
  -- -------------------------------------
  
  for pattern,info in pairs(CONF.handlers) do
    local match = table.pack(loc.path:match(pattern))
    if #match > 0 then
      local okay,status,mime,data = pcall(info.code.handler,ios,request,loc,match)
      if not okay then
        log(ios,40,request,reply(ios,"40\t",MSG[40],"\r\n"))
        syslog('error',"request=%s error=%s",request,status)
      else
        log(ios,status,request,reply(ios,status,"\t",mime,"\r\n",data))
      end
      ios:close()
      return
    end
  end
  
  -- -------------------------------------
  -- Regular file processing starts now
  -- -------------------------------------
  
  local subject
  local issuer
  
  -- =====================================================================
  
  local function write_file(file)
    if fsys.access(file,"x") then
      local status,mime,data = cgi(ios.__ctx,ios.__remote,file,loc,CONF.cgi)
      log(ios,status,request,reply(ios,status,"\t",mime,"\r\n",data),subject,issuer)
      return true
    end
    
    if not fsys.access(file,"r") then
      return false
    end
    
    if file:match "%.gemini$" then
      local bytes = reply(ios,"20\ttext/gemini\r\n")
                  + copy_file(ios,file)
      log(ios,20,request,bytes,subject,issuer)
    else
      local bytes = reply(ios,"20\t",magic(file),"\r\n")
                  + copy_file(ios,file)
      log(ios,20,request,bytes,subject,issuer)
    end
    
    return true
  end
  
  -- =====================================================================
  
  for dir,segment in descend_path(loc.path) do
    -- ----------------------------------------------------
    -- Skip the following files that match these patterns
    -- ----------------------------------------------------
    
    for _,pattern in ipairs(CONF.no_access) do
      if segment:match(pattern) then
        log(ios,51,request,reply(ios,"51\t",MSG[51],"\r\n"),subject,issuer)
        ios:close()
        return
      end
    end
    
    local info = fsys.stat(dir)
    
    if not info then
      log(ios,51,request,reply(ios,"51\t",MSG[51],"\r\n"),subject,issuer)
      ios:close()
      return
    end
    
    if info.mode.type == 'dir' then
    
      -- -------------------------------------------
      -- Do we have an issue with Unix permissions?
      -- -------------------------------------------
      
      if not fsys.access(dir,"x") then
        syslog('error',"access(%q) failed",dir)
        log(ios,40,request,reply(ios,"40\t",MSG[40],"\r\n"),subject,issuer)
        ios:close()
        return
      end
      
      -- ---------------------------------------------------
      -- Does this directory have certificate requirements?
      -- ---------------------------------------------------
      
      local auth,status,s,i = authorized_dir(ios,dir,loc)
      if not auth then
        log(ios,status,request,reply(ios,string.format("%d\t%s\r\n",status,MSG[status])),s,i)
        ios:close()
        return
      end
      
      if s and not subject then subject = s end
      if i and not issuer  then issuer  = i end
      
    elseif info.mode.type == 'file' then
      if not write_file(dir) then
        syslog('error',"type(%q) = %s",dir,info.mode.type)
        log(ios,40,request,reply(ios,"40\t",MSG[40],"\r\n"),subject,issuer)
        ios:close()
      end
      ios:close()
      return
      
    else
      log(ios,51,request,reply(ios,"51\t",MSG[51],"\r\n"),subject,issuer)
      ios:close()
      return
    end
  end
  
  -- ---------------------------------------------------------------------
  -- We're at the end of the request path, and we haven't hit a file yet.
  -- So serve up an index.  If "index.gemini" exists, serve that up,
  -- otherwise, make one up on the fly.
  -- ---------------------------------------------------------------------
  
  local final  = "."   .. loc.path
  
  if write_file(final .. "/index.gemini") then
    ios:close()
    return
  end
  
  local bytes = reply(ios,
        "20\ttext/gemini\r\n",
        "Index of ",loc.path,"\r\n",
        "---------------------------\r\n",
        "\r\n"
  )
  
  local function access_okay(dir,entry)
    for _,pattern in ipairs(CONF.no_access) do
      if entry:match(pattern) then return false end
    end
    
    local fname = dir .. "/" .. entry
    local info  = fsys.stat(fname)
    
    if not info then
      return false
    elseif info.mode.type == 'file' then
      return fsys.access(fname,'r'),'file'
    elseif info.mode.type == 'dir' then
      return fsys.access(fname,'x'),'dir'
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
    
    if loc.path:match "/$" then
      filename = loc.path .. entry .. "/"
    else
      filename = loc.path .. "/" .. entry .. "/"
    end
    
    filename = uurl.rm_dot_segs:match(filename)
    filename = uurl.esc_path:match(filename)
    bytes    = bytes + reply(ios,"=> ",filename,"\t",entry,"/\r\n")
  end
  
  if #lists.dir > 0 then
    bytes = bytes + reply(ios,"\r\n")
  end
  
  for _,entry in ipairs(lists.file) do
    local filename
    
    if loc.path:match "/$" then
      filename = loc.path .. entry
    else
      filename = loc.path .. "/" .. entry
    end
    
    filename = uurl.rm_dot_segs:match(filename)
    filename = uurl.esc_path:match(filename)
    bytes    = bytes + reply(ios,"=> ",filename,"\t",entry,"\r\n")
  end
  
  bytes = bytes + reply(ios,
        "\r\n",
        "---------------------------\r\n",
        "GLV-1.12556\r\n"
  )
  log(ios,20,request,bytes,subject,issuer)
  ios:close()
end

-- ************************************************************************

local okay,err = tls.listena(CONF._internal.addr,main,function(conf)
  conf:verify_client_optional()
  conf:insecure_no_verify_cert()
  return conf:cert_file(CONF.certificate.cert)
     and conf:key_file (CONF.certificate.key)
     and conf:protocols("all")
end)

if not okay then
  io.stderr:write(string.format("%s: %s\n",arg[1],err))
  os.exit(exit.OSERR,true)
end

okay,err = fsys.chdir(CONF.network.host)
if not okay then
  io.stderr:write(string.format("%s: %s\n",tostring(CONF.network.host),errno[err]))
  os.exit(exit.CONFIG,true)
end

signal.catch('int')
signal.catch('term')
syslog('info',"entering service @%s",fsys.getcwd())
nfl.server_eventloop(function() return signal.caught() end)

for _,info in pairs(CONF.handlers) do
  if info.code and info.code.fini then
    local ok,status = pcall(info.code.fini)
    if not ok then
      syslog('error',"%s: %s",info.module,status)
    end
  end
end

os.exit(true,true)
