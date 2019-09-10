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
  
  if not CONF.network.port then
    CONF.network.port = 1965
  end
  
  if not CONF.syslog then
    CONF.syslog = { ident = "gemini" , facility = "daemon" }
  else
    CONF.syslog.ident    = CONF.syslog.ident    or "gemini"
    CONF.syslog.facility = CONF.syslog.facility or "daemon"
  end
  
  if not CONF.authorization then
    CONF.authorization = {}
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
    
    for _,info in ipairs(CONF.handlers) do
      loadmod(info)
    end
  end
  
  package.loaded.CONF = CONF
end

local uurl = require "url-util" -- XXX hack
local MSG  = require "MSG"      -- XXX hack

magic:flags('mime')
syslog.open(CONF.syslog.ident,CONF.syslog.facility)

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

local function log(ios,status,request,bytes,auth)
  syslog(
        'info',
        "remote=%s status=%d request=%q bytes=%d subject=%q issuer=%q",
        ios.__remote.addr,
        status,
        request,
        bytes,
        auth and auth.S or "",
        auth and auth.I or ""
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
  -- I'm still unsure of the order I want these in ...
  -- -------------------------------------------------------------
  
  for _,rule in ipairs(CONF.redirect.temporary) do
    local match = table.pack(loc.path:match(rule[1]))
    if #match > 0 then
      local new = redirect_subst:match(rule[2],1,match)
      log(ios,30,request,reply(ios,"30\t",new,"\r\n"))
      ios:close()
      return
    end
  end
  
  for _,rule in ipairs(CONF.redirect.permanent) do
    local match = table.pack(loc.path:match(rule[1]))
    if #match > 0 then
      local new = redirect_subst:match(rule[2],1,match)
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
  
  -- --------------------------------------------------------------
  -- Do our authorization checks.  This way, we can get consistent
  -- authorization checks across handlers
  -- --------------------------------------------------------------
  
  local auth = { _remote = ios.__remote.addr }
  
  for _,rule in ipairs(CONF.authorization) do
    if loc.path:match(rule.path) then
      if not ios.__ctx:peer_cert_provided() then
        local ret = rule.status or 60
        log(ios,ret,request,reply(ios,ret,"\t",MSG[ret],"\r\n"))
        ios:close()
        return
      end
      
      auth._provided = true
      auth._ctx      = ios.__ctx
      auth.I         = ios.__ctx:peer_cert_issuer()
      auth.S         = ios.__ctx:peer_cert_subject()
      auth.issuer    = cert_parse:match(auth.I)
      auth.subject   = cert_parse:match(auth.S)
      auth.notbefore = ios.__ctx:peer_cert_notbefore()
      auth.notafter  = ios.__ctx:peer_cert_notafter()
      auth.now       = os.time()
      
      if auth.now < auth.notbefore then
        log(ios,64,request,reply(ios,"64\t",MSG[64],"\r\n"),auth)
        ios:close()
        return
      end
      
      if auth.now > auth.notafter then
        log(ios,65,request,reply(ios,"65\t",MSG[65],"\r\n"),auth)
        ios:close()
        return
      end
      
      local okay,err = pcall(rule.check,auth.issuer,auth.subject,loc)
      if not okay then
        syslog('error',"%s: %s",rule.path,err)
        log(ios,40,request,reply(ios,"40\t",MSG[40],"\r\n"),auth)
        ios:close()
        return
      end
      
      if not auth then
        log(ios,63,request,reply(ios,"63\t",MSG[63],"\r\n"),auth)
        ios:close()
        return
      end
      
      break
    end
  end
  
  -- -------------------------------------
  -- Run through our installed handlers
  -- -------------------------------------

  for _,info in ipairs(CONF.handlers) do
    local match = table.pack(loc.path:match(info.path))
    if #match > 0 then
      local okay,status,mime,data = pcall(info.code.handler,info,auth,loc,match)
      if not okay then
        log(ios,40,request,reply(ios,"40\t",MSG[40],"\r\n"),auth)
        syslog('error',"request=%s error=%s",request,status)
      else
        log(ios,status,request,reply(ios,status,"\t",mime,"\r\n",data),auth)
      end
      ios:close()
      return
    end
  end
  
  syslog('error',"no handlers for %q found---possible configuration error?",request)
  log(ios,41,request,reply(ios,"41\t",MSG[41],"\r\n"),auth)
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

signal.catch('int')
signal.catch('term')
syslog('info',"entering service @%s",fsys.getcwd())
nfl.server_eventloop(function() return signal.caught() end)

for _,info in ipairs(CONF.handlers) do
  if info.code and info.code.fini then
    local ok,status = pcall(info.code.fini,info)
    if not ok then
      syslog('error',"%s: %s",info.module,status)
    end
  end
end

os.exit(true,true)
