-- ************************************************************************
--
--    CGI interface.
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

local syslog    = require "org.conman.syslog"
local errno     = require "org.conman.errno"
local fsys      = require "org.conman.fsys"
local process   = require "org.conman.process"
local exit      = require "org.conman.const.exit"
local ios       = require "org.conman.net.ios"
local nfl       = require "org.conman.nfl"
local abnf      = require "org.conman.parsers.abnf"
local lpeg      = require "lpeg"
local io        = require "io"
local os        = require "os"
local string    = require "string"
local coroutine = require "coroutine"
local math      = require "math"
local uurl      = require "GLV-1.url-util"
local MSG       = require "GLV-1.MSG"

local pairs     = pairs
local tostring  = tostring
local tonumber  = tonumber

local DEVNULI = io.open("/dev/null","r")
local DEVNULO = io.open("/dev/null","w")

-- ************************************************************************

local parse_headers do
  local Cc = lpeg.Cc
  local Cf = lpeg.Cf
  local Cg = lpeg.Cg
  local Cs = lpeg.Cs
  local Ct = lpeg.Ct
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  local S  = lpeg.S
  
  local H do
    local text = R("AZ","az") / function(c) return P(c:lower()) + P(c:upper()) end
               + P(1)         / function(c) return P(c) end
               
    H = function(s)
      local pattern = Cf(text^1,function(acc,pat) return acc * pat end)
      return pattern:match(s) / s
    end
  end
  
  local LWSP         = (abnf.WSP + abnf.CRLF * abnf.WSP)
  local text         = LWSP^1 / " "
                     + abnf.VCHAR
  local ignore       = LWSP + abnf.VCHAR
  local code         = (R"16" * R"09" * #(P(1) - R"09")) / tonumber
                     + (R"09" * R"09" * #(P(1) - R"09")) * Cc(50)
                     -- ------------------------------------------
                     -- Most common web status codes, translated
                     -- ------------------------------------------
                     
                     + P"200" * Cc(20)
                     + P"301" * Cc(31)
                     + P"302" * Cc(30)
                     + P"400" * Cc(59)
                     + P"403" * Cc(60)
                     + P"404" * Cc(51)
                     + P"405" * Cc(59)
                     + P"500" * Cc(40)
                     + P"501" * Cc(40)
                     
                     -- ----------------
                     -- Web catch all
                     -- ----------------
                     
                     + P"2" * R"09" * R"09" * Cc(20)
                     + P"3" * R"09" * R"09" * Cc(30)
                     + P"4" * R"09" * R"09" * Cc(50)
                     + P"5" * R"09" * R"09" * Cc(40)
                     + R"09" * R"09" * R"09" * Cc(50)
  local separator    = S'()<>@,;:\\"/[]?={}\t '
  local token        = (abnf.VCHAR - separator)^1
  local status       = H"Status"       * P":" * LWSP * code * ignore^0 * abnf.CRLF
  local content_type = H"Content-Type" * P":" * LWSP * Cs(text^1)        * abnf.CRLF
  local location     = H"Location"     * P":" * LWSP * C(abnf.VCHAR^1)   * abnf.CRLF
  local generic      = C(token)        * P":" * LWSP * C(text^0)         * abnf.CRLF
  local headers      = status + content_type + location + generic
  parse_headers      = Cf(Ct"" * Cg(headers)^1,function(acc,name,value)
                         acc[name] = value
                         return acc
                       end)
                     * abnf.CRLF
end

-- ************************************************************************
-- Handle script command line arguments per RFC-3875 section 4.4
-- ************************************************************************

local parse_cgi_args do
  local xdigit   = lpeg.locale().xdigit
  local char     = lpeg.P"%" * lpeg.C(xdigit * xdigit)
                 / function(c)
                     return string.char(tonumber(c,16))
                   end
                 + (lpeg.R"!~" - lpeg.S' #%<>[\\]^{|}"=&+')
  local args     = lpeg.Cs(char^1) * lpeg.P"+"^-1
  parse_cgi_args = lpeg.Ct(args^1) * lpeg.P(-1)
end

-- ************************************************************************

local function fdtoios(fd)
  local newfd   = ios()
  newfd.__fd    = fd
  newfd.__co    = coroutine.running()
  
  newfd.close = function(self)
    nfl.SOCKETS:remove(fd)
    self.__fd:close()
    return true
  end
  
  newfd._refill = function()
    return coroutine.yield()
  end
  
  nfl.SOCKETS:insert(fd,'r',function(event)
    if event.read then
      local data,err = fd:read(8192)
      if data then
        if #data == 0 then
          nfl.SOCKETS:remove(fd)
          newfd._eof = true
        end
        nfl.schedule(newfd.__co,data)
      else
        if err ~= errno.EAGAIN then
          syslog('error',"fd:read() = %s",errno[err])
        end
      end
    else
      newfd._eof = true
      nfl.SOCKETS:remove(fd)
      nfl.schedule(newfd.__co)
    end
  end)
  
  return newfd
end

-- ************************************************************************

return function(auth,program,directory,location)
  local sconf = require "CONF".cgi or {}
  local hconf = require "CONF".hosts[location.host].cgi or {}
  
  -- ------------------------------------------------------------------------
  -- If the cgi block is not defined for the server, nor for a host, and we
  -- get here, then there's been a misconfiguration.  Report the error.  The
  -- other case is when the host has explicitely set 'cgi = false', in which
  -- case, that host is opting out of CGI support entirely, so report the
  -- error in that case too.
  -- ------------------------------------------------------------------------
  
  if not sconf and not hconf then
    syslog('error',"CGI script called, but CGI not configured!")
    return 40,MSG[40],""
  end
  
  if hconf == false then
    syslog('error',"CGI script called, but CGI not configured!")
    return 40,MSG[40],""
  end
  
  local pipe,err1 = fsys.pipe()
  if not pipe then
    syslog('error',"CGI pipe: %s",errno[err1])
    return 40,MSG[40],""
  end
  
  pipe.read:setvbuf('no') -- buffering kills the event loop
  
  local child,err = process.fork()
  
  if not child then
    syslog('error',"process.fork() = %s",errno[err])
    return 40,MSG[40],""
  end
  
  -- =========================================================
  -- The child runs off to do its own thang ...
  -- =========================================================
  
  if child == 0 then
    fsys.redirect(DEVNULI,io.stdin)
    fsys.redirect(pipe.write,io.stdout)
    fsys.redirect(DEVNULO,io.stderr)
    
    -- -----------------------------------------------------------------
    -- Close file descriptors that aren't stdin, stdout or stderr.  Most
    -- Unix systems have dirfd(), right?  Right?  And /proc/self/fd,
    -- right?  Um ... erm ...
    -- -----------------------------------------------------------------
    
    local dir = fsys.opendir("/proc/self/fd")
    if dir and dir._tofd then
      local dirfh = dir:_tofd()
      
      for file in dir.next,dir do
        local fh = tonumber(file)
        if fh > 2 and fh ~= dirfh then
          fsys._close(fh)
        end
      end
      
    -- ----------------------------------------------------------
    -- if all else fails, at least close these to make this work
    -- ----------------------------------------------------------
    
    else
      DEVNULI:close()
      DEVNULO:close()
      pipe.write:close()
      pipe.read:close()
    end
    
    local args = parse_cgi_args:match(location.query or "") or {}
    local env  = {}
    local prog
    
    if program:match "^/" then
      prog = uurl.rm_dot_segs:match(program)
    else
      prog = uurl.rm_dot_segs:match(fsys.getcwd() .. "/" .. program)
    end
    
    local function merge_env(accenv,menv)
      if menv then
        for var,val in pairs(menv) do
          accenv[var] = val
        end
      end
    end
    
    merge_env(env,sconf.env)
    merge_env(env,hconf.env)
    
    -- ===================================================
    
    local function add_http()
      env.REQUEST_METHOD       = "GET"
      env.SERVER_PROTOCOL      = "HTTP/1.0"
      env.HTTP_ACCEPT          = "*/*"
      env.HTTP_ACCEPT_LANGUAGE = "*"
      env.HTTP_CONNECTION      = "close"
      env.HTTP_HOST            = location.host
      env.HTTP_REFERER         = ""
      env.HTTP_USER_AGENT      = ""
    end
    
    -- ===================================================
    
    local function add_apache()
      env.DOCUMENT_ROOT         = directory
      env.CONTEXT_DOCUMENT_ROOT = env.DOCUMENT_ROOT
      env.CONTEXT_PREFIX        = ""
      env.SCRIPT_FILENAME       = prog
    end
    
    -- ===================================================
    
    local function add_tlsenv(apache)
      local function breakdown(base,fields)
        for name,value in pairs(fields) do
          env[base .. name] = value
        end
      end
      
      if not auth._provided then return end
      
      local remain = tostring(math.floor(os.difftime(auth.notafter,auth.now) / 86400))
      
      if not apache then
        env.TLS_CIPHER            = auth._ctx:conn_cipher()
        env.TLS_VERSION           = auth._ctx:conn_version()
        env.TLS_CLIENT_HASH       = auth._ctx:peer_cert_hash()
        env.TLS_CLIENT_ISSUER     = auth.I
        env.TLS_CLIENT_SUBJECT    = auth.S
        env.TLS_CLIENT_NOT_BEFORE = os.date("%Y-%m-%dT%H:%M:%SZ",auth.notbefore)
        env.TLS_CLIENT_NOT_AFTER  = os.date("%Y-%m-%dT%H:%M:%SZ",auth.notafter)
        env.TLS_CLIENT_REMAIN     = remain
        
        breakdown("TLS_CLIENT_ISSUER_", auth.issuer)
        breakdown("TLS_CLIENT_SUBJECT_",auth.subject)
        
        env.AUTH_TYPE   = 'Certificate'
        env.REMOTE_USER = env.TLS_CLIENT_SUBJECT_CN
      else
        env.SSL_CIPHER          = auth._ctx:conn_cipher()
        env.SSL_PROTOCOL        = auth._ctx:conn_version()
        env.SSL_CLIENT_I_DN     = auth.I
        env.SSL_CLIENT_S_DN     = auth.S
        env.SSL_CLIENT_V_START  = os.date("%b %d %H:%M:%S %Y GMT",auth.notbefore)
        env.SSL_CLIENT_V_END    = os.date("%b %d %H:%M:%S %Y GMT",auth.notafter)
        env.SSL_CLIENT_V_REMAIN = remain
        env.SSL_TLS_SNI         = location.host
        
        breakdown("SSL_CLIENT_I_DN_",auth.issuer)
        breakdown("SSL_CLIENT_S_DN_",auth.subject)
        
        env.AUTH_TYPE   = 'Certificate'
        env.REMOTE_USER = env.SSL_CLIENT_S_DN_CN
      end
    end
    
    -- ===================================================
    
    local function get_instance(list)
      if list then
        for name,info in pairs(list) do
          if location.path:match(name) then
            return info
          end
        end
      end
      return {}
    end
    
    local function include_field(hci,hc,sci,sc)
      if hci ~= nil then return hci end
      if hc  ~= nil then return hc  end
      if sci ~= nil then return sci end
      return sc
    end
    
    local sconfi = get_instance(sconf.instance)
    local hconfi = get_instance(hconf.instance)
    local cwd    = hconfi.cwd or hconf.cwd or sconfi.cwd or sconf.cwd or directory
    
    if (include_field(hconfi.http,hconf.http,sconfi.http,sconf.http))         then add_http()   end
    if (include_field(hconfi.apache,hconf.apache,sconfi.apache,sconf.apache)) then add_apache() end
    if (include_field(hconfi.envtls,hconf.envtls,sconfi.envtls,sconf.envtls)) then
      add_tlsenv(hconfi.apache or hconf.apache or sconfi.apache,sconf.apache)
    end
    
    merge_env(env,sconf.env)
    merge_env(env,sconfi.env)
    merge_env(env,hconf.env)
    merge_env(env,hconfi,env)
    
    env.GEMINI_DOCUMENT_ROOT   = cwd
    env.GEMINI_SCRIPT_FILENAME = program
    env.GEMINI_URL_PATH        = location.path
    env.GEMINI_URL             = uurl.toa(location)
    env.GATEWAY_INTERFACE      = "CGI/1.1"
    env.QUERY_STRING           = location.query or ""
    env.REMOTE_ADDR            = auth._remote
    env.REMOTE_HOST            = auth._remote
    env.REQUEST_METHOD         = ""
    env.SCRIPT_NAME            = program:sub(2,-1)
    env.SERVER_NAME            = location.host
    env.SERVER_PORT            = tostring(location.port)
    env.SERVER_PROTOCOL        = "GEMINI"
    env.SERVER_SOFTWARE        = "GLV-1.12556/1"
    
    -- -----------------------------------------------------------------------
    -- The passed in dir is a relative path starting with "./".  So when
    -- searching for dir in location.path, start just past the leading period.
    -- -----------------------------------------------------------------------
    
    local _,e      = location.path:find(fsys.basename(program),1,true)
    local pathinfo = e and location.path:sub(e+1,-1) or location.path
    
    if pathinfo ~= "" then
      env.PATH_INFO       = pathinfo
      env.PATH_TRANSLATED = fsys.getcwd() .. env.PATH_INFO
    end
    
    local okay,err2 = fsys.chdir(cwd)
    if not okay then
      syslog('error',"CGI cwd(%q) = %s",cwd,errno[err2])
      process.exit(exit.CONFIG)
    end
    
    process.exec(prog,args,env)
    process.exit(exit.OSERR)
  end
  
  -- =========================================================
  -- Meanwhile, back at the parent's place ...
  -- =========================================================
  
  pipe.write:close()
  local inp  = fdtoios(pipe.read)
  local hdrs = inp:read("h")
  local data = inp:read("a")
  inp:close()
  
  local info,err2 = process.wait(child)
  
  if not info then
    syslog('error',"process.wait() = %s",errno[err2])
    return 40,MSG[40],""
  end
  
  if info.status == 'normal' then
    if info.rc == 0 then
      local headers = parse_headers:match(hdrs)
      
      if not headers then
        syslog('error',"%s: is this a CGI program?",program)
        return 40,MSG[40],""
      end
      
      if headers['Location'] then
        local status = headers['Status'] or 31
        return status,headers['Location'],""
      end
      
      local status  = headers['Status'] or 20
      local mime    = headers['Content-Type'] or "text/plain"
      return status,mime,data
    else
      syslog('warning',"program=%q status=%d",program,info.rc)
      return 40,MSG[40],""
    end
  else
    syslog('error',"program=%q status=%s description=%s",program,info.status,info.description)
    return 40,MSG[40],""
  end
end
