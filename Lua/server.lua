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
local url       = require "org.conman.parsers.url"
local lpeg      = require "lpeg"

local CONF = {}

-- ************************************************************************

if #arg == 0 then
  io.stderr:write(string.format("usage: %s confifile\n",arg[0]))
  os.exit(exit.USAGE,true)
end

do
  local conf,err = loadfile(arg[1],"t",CONF)
  if not conf then
    io.stderr:write(string.format("%s: %s\n",arg[1],errno[err]))
    os.exit(exit.CONFIG,true)
  end
  
  conf()
  
  if CONF.modules then
    package.path = CONF.modules .. ";" .. package.path
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
  -- If we don't have any handlers, make sure we have the table exists.
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

local function normalize_directory(path)
  local new = {}
  for _,segment in ipairs(path) do
    if segment == ".." then
      table.remove(new)
    elseif segment ~= "." then
      table.insert(new,segment)
    end
  end
  
  if new[#new] == "" then table.remove(new) end
  
  return new
end

-- ************************************************************************

local function descend_path(path)
  local function iter(state,var)
    state._n = state._n + 1
    if state._n <= #state then
      return var .. "/" .. state[state._n]
    end
  end
  
  path._n = 0
  return iter,path,"."
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

local function authorized(ios,dir)
  local pfname   = dir .. "/.private"
  local okay,err = fsys.access(pfname,'r')
  
  -- --------------------------------------------------------------
  -- If .private doesn't exist, we're okay to go.  Any other error
  -- and we deny access just to be safe
  -- --------------------------------------------------------------
  
  if not okay and err == errno.ENOENT then return true end
  if not okay then
    syslog('error',"%s: %s",pfname,errno[err])
    return false,401,"Unauthorized"
  end
  
  if not ios.__ctx:peer_cert_provided() then
    return false,460,"Need certificate"
  end
  
  local I         = ios.__ctx:peer_cert_issuer()
  local S         = ios.__ctx:peer_cert_subject()
  local issuer    = cert_parse:match(I)
  local subject   = cert_parse:match(S)
  local notbefore = ios.__ctx:peer_cert_notbefore()
  local notafter  = ios.__ctx:peer_cert_notafter()
  local now       = os.time()
  
  if now < notbefore then
    return false,461,"Future Certificate",S,I
  end
  
  if now > notafter then
    return false,462,"Expired Certificate",S,I
  end
  
  local check = loadfile(pfname,"t",{})
  if not check then
    return false,500,"Lungs bleeding, ribs cracked ... "
  end
  
  local ok,auth = pcall(check,issuer,subject)
  if not ok then
    syslog('error',"%s: %s",pfname,auth)
    return false,500,"Must not black out ... "
  end
  
  return auth,463,"Rejected certificate",S,I
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

local function makelink(dir,file)
  return dir:sub(2,-1) .. "/" .. file
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
    log(ios,400,"",reply(ios,"400\tBad Request\r\n"))
    ios:close()
    return
  end
  
  local loc = url:match(request)
  if not loc then
    log(ios,400,request,reply(ios,"400\tBad reqeust\r\n"))
    ios:close()
    return
  end
  
  -- ---------------------------------------------------------------------
  -- I actually accept URLs as the request---this way, if we support more
  -- than one host, we can switch among them on the server.  We don't
  -- support that here, since I haven't learned how to generate a server
  -- certificate for more than one host.  But it *could* be a possiblity.
  -- ---------------------------------------------------------------------
  
  if loc.scheme and loc.scheme ~= 'gemini'
  or loc.host   and loc.host   ~= CONF.network.host
  or loc.port   and loc.port   ~= CONF.network.port then
    log(ios,400,request,reply(ios,"400\tBad Request\r\n"))
    ios:close()
    return
  end
  
  -- -------------------------------------------------------------
  -- We handle the various redirections here, the temporary ones,
  -- the permanent ones, and those that are gone gone gone ...
  -- -------------------------------------------------------------
  
  local selector = "/" .. table.concat(loc.path,"/")
  
  for pattern,replace in pairs(CONF.redirect.temporary) do
    local match = table.pack(selector:match(pattern))
    if #match > 0 then
      local new = redirect_subst:match(replace,1,match)
      log(ios,302,request,reply(ios,"302\t",new,"\r\n"))
      ios:close()
      return
    end
  end
  
  for pattern,replace in pairs(CONF.redirect.permanent) do
    local match = table.pack(selector:match(pattern))
    if #match > 0 then
      local new = redirect_subst:match(replace,1,match)
      log(ios,301,request,reply(ios,"301\t",new,"\r\n"))
      ios:close()
      return
    end
  end
  
  for _,pattern in ipairs(CONF.redirect.gone) do
    if selector:match(pattern) then
      log(ios,410,request,reply(ios,"410\tNo Longer here\r\n"))
      ios:close()
      return
    end
  end
  
  -- -------------------------------------
  -- Run through our installed handlers
  -- -------------------------------------
  
  for pattern,info in pairs(CONF.handlers) do
    local match = table.pack(selector:match(pattern))
    if #match > 0 then
      local okay,status,mime,data = pcall(info.code.handler,ios,request,loc,match)
      if not okay then
        log(ios,500,request,reply(ios,"500\tInternal Error\r\n"))
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
  
  local path    = normalize_directory(loc.path)
  local final   = "."
  local subject
  local issuer
  
  for dir in descend_path(path) do
    -- ----------------------------------------------
    -- We resume our regularly scheduled programming
    -- ----------------------------------------------
    
    local info = fsys.stat(dir)
    
    if not info then
      log(ios,404,request,reply(ios,"404\tNot Found\r\n"))
      ios:close()
      return
    end
    
    if info.mode.type == 'dir' then
      if dir:match ".*/%." then
        log(ios,404,request,reply(ios,"404\tNot Found\r\n"),subject,issuer)
        ios:close()
        return
      end
      
      -- -------------------------------------------
      -- Do we have an issue with Unix permissions?
      -- -------------------------------------------
      
      if not fsys.access(dir,"x") then
        log(ios,500,request,reply(ios,"500\tHow did this happen?\r\n"),subject,issuer)
        ios:close()
        return
      end
      
      -- ---------------------------------------------------
      -- Does this directory have certificate requirements?
      -- ---------------------------------------------------
      
      local auth,status,msg,s,i = authorized(ios,dir)
      if not auth then
        log(ios,status,request,reply(ios,string.format("%d\t%s\r\n",status,msg)),s,i)
        ios:close()
        return
      end
      
      final = dir
      if s and not subject then subject = s end
      if i and not issuer  then issuer  = i end
      
    elseif info.mode.type == 'file' then
      -- ------------------------------------
      -- Do the Unix permissions allow this?
      -- ------------------------------------
      
      if not fsys.access(dir,"r") then
        log(ios,500,request,reply(ios,"500\tWTC?\r\n"),subject,issuer)
        ios:close()
        return
      end
      
      if dir:match ".*/%." then
        log(ios,404,request,reply(ios,"404\tNot Found\r\n"),subject,issuer)
        ios:close()
        return
      elseif dir:match "~$" then
        log(ios,404,request,reply(ios,"404\tNot found\r\n"),subject,issuer)
        ios:close()
        return
      elseif dir:match ".*%.gemini$" then
        local bytes = reply(ios,"200\ttext/gemini\r\n")
                    + copy_file(ios,dir)
        log(ios,200,request,bytes,subject,issuer)
        ios:close()
        return
      else
        if fsys.access(dir,"x") then
          cgi = require "cgi"
          loc.path._n = path._n
          local status,mime,data = cgi(ios.__remote,dir,loc)
          log(ios,status,request,reply(ios,status,"\t",mime,"\r\n",data))
        else
          local bytes = reply(ios,"200\t",magic(dir),"\r\n")
                      + copy_file(ios,dir)
          log(ios,200,request,bytes,subject,issuer)
        end
        ios:close()
        return
      end
      
    else
      log(ios,404,request,reply(ios,"404\tNot Found\r\n"),subject,issuer)
      ios:close()
      return
    end
  end
  
  if not final then
    syslog('critical',"This should not happen")
    log(ios,500,request,reply(ios,"500\tOops, internal error\r\n"),subject,issuer)
    ios:close()
    return
  end
  
  local indexf = final .. "/index.gemini"
  if fsys.access(indexf,"r") then
    local bytes = reply(ios,"200\ttext/gemini\r\n")
                + copy_file(ios,indexf)
    log(ios,200,request,bytes,subject,issuer)
    ios:close()
    return
  end
  
  local bytes = reply(ios,
        "200\ttext/gemini\r\n",
        "Index of ",final:sub(2,-1),"\r\n",
        "---------------------------\r\n",
        "\r\n"
  )
  
  local function access_okay(dir,entry)
    if entry:match "^%." then return false end
    if entry:match "~$"  then return false end
    if not fsys.access(dir .. "/" .. entry,"r") then return false end
    return true
  end
  
  for entry in fsys.dir(final) do
    if access_okay(final,entry) then
      bytes = bytes + reply(ios,"=> ",makelink(final,entry)," ",entry,"\r\n")
    end
  end
  
  bytes = bytes + reply(ios,
        "\r\n",
        "---------------------------\r\n",
        "GLV/1.12556\r\n"
  )
  log(ios,200,request,bytes,subject,issuer)
  ios:close()
end

-- ************************************************************************

local okay,err = tls.listena(CONF._internal.addr,main,function(conf)
  conf:verify_client_optional()
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
