-- #!/usr/bin/env lua
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

local signal = require "org.conman.signal"
local exit   = require "org.conman.const.exit"
local syslog = require "org.conman.syslog"
local fsys   = require "org.conman.fsys"
local nfl    = require "org.conman.nfl"
local tls    = require "org.conman.nfl.tls"
local ip     = require "org.conman.parsers.ip-text"
local lpeg   = require "lpeg"
local url    = require "org.conman.parsers.url" * lpeg.P(-1)

math.randomseed(require("org.conman.math").seed())
require("org.conman.fsys.magic"):flags('mime')

-- ************************************************************************

local parse_address do
  local C = lpeg.C
  local P = lpeg.P
  local R = lpeg.R
  
  local host    = ip.IPv4
                + P"[" * ip.IPv6 * P"]"
                + C(R("!9",";~")^1)
  local port    = P":" * (R"09"^1 / tonumber)
  parse_address = host * port
end

-- ************************************************************************

if #arg == 0 then
  io.stderr:write(string.format("usage: %s config\n",arg[0]))
  os.exit(exit.USAGE,true)
end

local CONF = {} do
  local conffile,err = loadfile(arg[1],"t",CONF)
  
  if not conffile then
    io.stderr:write(string.format("%s: %s\n",arg[1],err))
    os.exit(exit.CONFIG,true)
  end
  
  conffile()
  
  if not CONF.syslog then
    CONF.syslog = { ident = "gemini" , facility = "daemon" }
  else
    CONF.syslog.ident    = CONF.syslog.ident    or "gemini"
    CONF.syslog.facility = CONF.syslog.facility or "daemon"
  end
  
  syslog.open(CONF.syslog.ident,CONF.syslog.facility)
  
  if not CONF.address then
    CONF.address = "[::]:1965"
    CONF._host   = "[::]"
    CONF._port   = 1965
  else
    CONF._host,CONF._port = parse_address:match(CONF.address)
    if not CONF._host or not CONF._port then
      syslog('critical',"%s: syntax error with address",arg[1])
      io.stderr:write(string.format("%s: syntax error with address",arg[1]),"\n")
      os.exit(exit.CONFIG,true)
    end
  end
  
  if not CONF.hosts then
    syslog('critical',"%s: at least one host needs to be defined",arg[1])
    io.stderr:write(string.format("%s: at least one host needs to be defined",arg[1]),"\n")
    os.exit(exit.CONFIG,true)
  end
  
  CONF.language = CONF.language or "en"
  CONF.charset  = CONF.charset  or "utf-8"
  
  -- ----------------------------------------------------------------------
  -- This expression will canonicalize the address field.  If the host is
  -- missing, it will be replaced with the "all" address.  If the port is
  -- missing, it will be replaced with the default port 1965.  If the host
  -- is '@', it will be replaced by the name of the host.
  -- ----------------------------------------------------------------------
  
  local canon_address do
    local Carg = lpeg.Carg
    local Cc   = lpeg.Cc
    local Cs   = lpeg.Cs
    local P    = lpeg.P
    local R    = lpeg.R
    
    local host    = ip.IPv4
                  + P"[" * ip.IPv6 * P"]"
                  + P"@" / "" * Carg(1)
                  + R("!9",";~")^1
                  + Cc(CONF._host)
    local port    = P":" * R"09"^1
                  + Cc(":" .. CONF._port)
    canon_address = Cs(host * port)
  end
  
  CONF._interfaces = {}
  
  -- -------------------
  -- Process each host.
  -- -------------------
  
  for host,conf in pairs(CONF.hosts) do
    if not conf.certificate then
      syslog('error',"%s: host %q missing certifiate---can't configure host",arg[1],host)
      io.stderr:write(string.format("%s: host %q missing certifiate---can't configure host",arg[1],host),"\n")
    end
    
    if not conf.keyfile then
      syslog('error',"%s: host %q missing keyfile---can't configure host",arg[1],host)
      io.stderr:write(string.format("%s: host %q missing keyfile---can't configure host",arg[1],host),"\n")
    end
    
    local addr = conf.address and canon_address:match(conf.address,1,host)
                 or CONF.address
                 
    if conf.certificate and conf.keyfile then
      local info
      
      if not CONF._interfaces[addr] then
        info = {}
        CONF._interfaces[addr] = info
      else
        info = CONF._interfaces[addr]
      end
      
      table.insert(info,{
                cert     = conf.certificate ,
                key      = conf.keyfile ,
                hostinfo = conf ,
        })
    end
    
    conf.language = conf.language or CONF.language
    conf.charset  = conf.charset  or CONF.charset
    
    if not conf.authorization then
      conf.authorization = {}
    end
    
    -- --------------------------------------------
    -- Make sure the redirect tables amd rewrite table always exist.
    -- --------------------------------------------
    
    if not conf.redirect then
      conf.redirect = { temporary = {} , permanent = {} , gone = {} }
    else
      conf.redirect.temporary = conf.redirect.temporary or {}
      conf.redirect.permanent = conf.redirect.permanent or {}
      conf.redirect.gone      = conf.redirect.gone      or {}
    end
    
    if not conf.rewrite then
      conf.rewrite = {}
    end
    
    -- --------------------------------------------------------------------
    -- If we don't have any handlers, make sure they now exist.
    -- If we do have handlers, load them up and initialize them.
    -- --------------------------------------------------------------------
    
    if not conf.handlers or #conf.handlers == 0 then
      syslog('warning',"%s: host %q has no handlers",arg[1],host)
      io.stderr:write(string.format("%s: host %q has no handlers",arg[1],host),"\n")
      conf.handlers = {}
    else
      local function notfound(_,_,_,_,ios)
        ios:write("51 \r\n")
        return 51
      end
      
      local function loadmod(info)
        if not info.path then
          syslog('error',"%q: missing path field in handler",info.module or "")
          io.stderr:write(string.format("%q: missing path field in handler",info.module or ""),"\n")
          info.path = ""
          info.code = { handler = notfound }
          return
        end
        
        if not info.module then
          syslog('error',"%q: missing module field",info.path or "")
          io.stderr:write(string.format("%q: missing module field",info.path or ""),"\n")
          info.code = { handler = notfound }
          return
        end
        
        local okay,mod = pcall(require,info.module)
        if not okay then
          syslog('error',"%q: %s",info.module,mod)
          io.stderr:write(string.format("%q: %s",info.module,mod),"\n")
          info.code = { handler = notfound }
          return
        end
        
        if type(mod) ~= 'table' then
          syslog('error',"%q: module not supported",info.module)
          io.stderr:write(string.format("%q: module not supported",info.module),"\n")
          info.code = { handler = notfound }
          return
        end
        
        info.code = mod
        
        if not mod.handler then
          syslog('error',"%q: missing handler()",info.module)
          io.stderr:write(string.format("%q: missing handler()",info.module),"\n")
          mod.handler = notfound
          return
        end
        
        info.language = info.language or conf.language
        info.charset  = info.charset  or conf.charset or "utf-8"
        
        if mod.init then
          okay,err = mod.init(info,conf,CONF)
          if not okay then
            syslog('error',"%q: %s",info.module,err)
            io.stderr:write(string.format("%q: %s",info.module,err),"\n")
            mod.handler = notfound
            return
          end
        end
      end
      
      table.sort(conf.handlers,function(a,b)
        return #a.path == #b.path and a.path < b.path
            or #a.path >  #b.path
      end)
      
      for i,info in ipairs(conf.handlers) do
        if i < #conf.handlers and info.path == conf.handlers[i+1] then
          syslog('warning',"duplicate path %q found",info.path)
          io.stderr:write(string.format("duplicate path %q found",info.path),"\n")
        end
        loadmod(info)
      end
    end
    
    syslog('info',"host %q configured",host)
  end
  
  if not next(CONF._interfaces) then
    syslog('critical',"%s: at least one host needs to be configured",arg[1])
    io.stderr:write(string.format("%s: at least one host needs to be configured",arg[1]),"\n")
    os.exit(exit.CONFIG,true)
  end
  
  package.loaded.CONF = CONF
end

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
  local value  = R(" .","0\255")^0
  local record = Cg(P"/" * C(name) * P"=" * C(value))
  cert_parse   = Cf(Ct"" * record^1,function(acc,n,v) acc[n] = v return acc end)
               + Ct""
end

-- ************************************************************************

local function main(ios)
  local request
  local auth =
  {
    _remote = ios.__remote.addr,
    _port   = ios.__remote.port
  }
  
  local function handler()
    ios:_handshake()
    
    request = ios:read("*l")
    if not request then
      ios:write("59 \r\n")
      return 59
    end
    
    -- -----------------------------------------------------------------
    -- I know 58 isn't a defined Gemini status, but I'm tired of buggy
    -- clients, so maybe THIS will get their damn attention
    -- -----------------------------------------------------------------
    
    if #request == 0 then
      ios:write("58 Not a gopher server!\r\n")
      return 58
    end
    
    -- -------------------------------------------------
    -- Current Gemini spec lists URLS max limit as 1024.
    -- -------------------------------------------------
    
    if #request > 1024 then
      ios:write("59 \r\n")
      return 59
    end
    
    local loc = url:match(request)
    if not loc then
      ios:write("59 \r\n")
      return 59
    end
    
    if not loc.scheme then
      ios:write("59 \r\n")
      return 59
    end
    
    if not loc.host then
      ios:write("59 \r\n")
      return 59
    end
    
    if loc.scheme ~= 'gemini'
    or not CONF.hosts[loc.host]
    or loc.port   ~= CONF.hosts[loc.host].port then
      ios:write("53 \r\n")
      return 53
    end
    
    -- ---------------------------------------------------------------
    -- user portion of a URL is invalid.
    -- ---------------------------------------------------------------
    
    if loc.user then
      ios:write("59 \r\n")
      return 59
    end
    
    if loc.fragment then
      ios:write("59 \r\n")
      return 59
    end
    
    -- ---------------------------------------------------------------
    -- Relative path resolution is the domain of the client, not the
    -- server.  So reject any requests with relative path elements.
    -- Also check for multiple '//' in a path, which I'm treating
    -- as invalid.
    -- ---------------------------------------------------------------
    
    if loc.path:match "/%.%./" or loc.path:match "/%./" or loc.path:match "//+" then
      ios:write("59 \r\n")
      return 59
    end
    
    -- --------------------------------------------------------------
    -- Do our authorization checks.  This way, we can get consistent
    -- authorization checks across handlers.  We do this before anything else
    -- (even redirects) to prevent unintended leakage of data (resources that
    -- might be available under authorization)
    -- --------------------------------------------------------------
    
    for _,rule in ipairs(CONF.hosts[loc.host].authorization) do
      if loc.path:match(rule.path) then
        if not ios.__ctx:peer_cert_provided() then
          ios:write("60 ",rule.message or "","\r\n")
          return 60
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
          ios:write("62 \r\n")
          return 62
        end
        
        if auth.now > auth.notafter then
          ios:write("62 \r\n")
          return 62
        end
        
        local okay,allowed = pcall(rule.check,auth.issuer,auth.subject,loc)
        if not okay then
          syslog('error',"%s: %s",rule.path,allowed)
          ios:write("40 \r\n")
          return 40
        end
        
        if not allowed then
          ios:write("61 \r\n")
          return 61
        end
        
        break
      end
    end
    
    -- -------------------------------------------------------------
    -- We handle the various redirections here, the temporary ones,
    -- the permanent ones, and those that are gone gone gone ...
    -- I'm still unsure of the order I want these in ...
    -- -------------------------------------------------------------
    
    for _,rule in ipairs(CONF.hosts[loc.host].redirect.temporary) do
      local match = table.pack(loc.path:match(rule[1]))
      if #match > 0 then
        local new = redirect_subst:match(rule[2],1,match)
        ios:write("30 ",new,"\r\n")
        return 30
      end
    end
    
    for _,rule in ipairs(CONF.hosts[loc.host].redirect.permanent) do
      local match = table.pack(loc.path:match(rule[1]))
      if #match > 0 then
        local new = redirect_subst:match(rule[2],1,match)
        ios:write("31 ",new,"\r\n")
        return 31
      end
    end
    
    for _,pattern in ipairs(CONF.hosts[loc.host].redirect.gone) do
      if loc.path:match(pattern) then
        ios:write("52 \r\n")
        return 52
      end
    end
    
    -- ------------------------------
    -- Handle the rewrite rules.
    -- ------------------------------
    
    for _,rule in ipairs(CONF.hosts[loc.host].rewrite) do
      local match = table.pack(loc.path:match(rule[1]))
      if #match > 0 then
        loc._pathorig = loc.path
        loc.path      = redirect_subst:match(rule[2],1,match)
        break
      end
    end
    
    -- -------------------------------------
    -- Run through our installed handlers
    -- -------------------------------------
    
    local found = false
    local okay
    local status
    
    for _,info in ipairs(CONF.hosts[loc.host].handlers) do
      if loc.path:sub(1,#info.path) == info.path then
        found       = true
        okay,status = pcall(
                info.code.handler,
                info,
                auth,
                loc,
                loc.path:sub(#info.path + 1,-1),
                ios
        )
        
        if not okay then
          syslog('error',"request=%q error=%q",request,status)
          status = 41
        end
        
        break
      end
    end
    
    if not found then
      syslog('error',"no handlers for %q found---possible configuration error?",request)
      ios:write("40 \r\n")
      status = 40
    end
    
    return status
  end
  
  local status = handler()
  
  syslog(
          'info',
          "remote=%s status=%d request=%q bytes=%d subject=%q issuer=%q",
          ios.__remote.addr,
          status,
          request,
          ios.__wbytes,
          auth and auth.S or "",
          auth and auth.I or ""
  )
  ios:close()
end

-- ************************************************************************

local function init_interface(interface,info)
  local addr,port = parse_address:match(interface)
  
  local okay,err = tls.listen(addr,port,main,function(conf)
    conf:verify_client_optional()
    conf:insecure_no_verify_cert()
    
    info[1].hostinfo.port = port
    if not conf:keypair_file(info[1].cert,info[1].key) then return false end
    
    for i = 2 , #info do
      info[i].hostinfo.port = port
      if not conf:add_keypair_file(info[i].cert,info[i].key) then
        return false
      end
    end
    
    return conf:protocols "tlsv1.2,tlsv1.3"
  end)
  
  if not okay then
    syslog('critical',"%s: %s\n",arg[1],err)
    io.stderr:write(string.format("%s: %s\n",arg[1],err))
    os.exit(exit.OSERR,true)
  end
end

-- ************************************************************************

for interface,info in pairs(CONF._interfaces) do
  init_interface(interface,info)
end

signal.catch('int')
signal.catch('term')
syslog('info',"entering service @%s",fsys.getcwd())
nfl.server_eventloop(function() return signal.caught() end)

for host,conf in pairs(CONF.hosts) do
  for _,info in ipairs(conf.handlers) do
    if info.code and info.code.fini then
      local ok,status = pcall(info.code.fini,info)
      if not ok then
        syslog('error',"%s %s: %s",host,info.module,status)
      end
    end
  end
end

os.exit(exit.OK,true)
