-- ************************************************************************
--
--    Gateway Interface utility routines.
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
-- luacheck: globals parse_headers get_instance isset merge
-- luacheck: globals breakdown setup_env handle_output
-- luacheck: ignore 611
-- RFC-3875

local syslog = require "org.conman.syslog"
local abnf   = require "org.conman.parsers.abnf"
local fsys   = require "org.conman.fsys"
local lpeg   = require "lpeg"
local math   = require "math"
local os     = require "os"
local MSG    = require "GLV-1.MSG"
local uurl   = require "GLV-1.url-util"

local pairs    = pairs
local select   = select
local tonumber = tonumber
local tostring = tostring

_ENV = {}

-- ************************************************************************

do
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

function get_instance(location,list)
  if list then
    for name,info in pairs(list) do
      if location.path:match(name) then
        return info
      end
    end
  end
  return {}
end

-- ************************************************************************

function isset(...)
  for i = 1 , select('#',...) do
    local v = select(i,...)
    if v ~= nil then return v end
  end
end

-- ************************************************************************

function merge(...)
  local accenv = {}
  for i = 1 , select('#',...) do
    local env = select(i,...)
    if env then
      for var,val in pairs(env) do
        accenv[var] = val
      end
    end
  end
  return accenv
end

-- ************************************************************************

function breakdown(env,base,fields)
  for name,value in pairs(fields) do
    env[base .. name] = value
  end
end

-- ************************************************************************

function setup_env(auth,program,base,location,directory,di,hconf,gconf)
  gconf       = gconf         or {} -- server wide config
  hconf       = hconf         or {} -- host config
  local dconf = directory[di] or {} -- directory config
  
  local gconfi = get_instance(location,gconf.instance)
  local hconfi = get_instance(location,hconf.instance)
  local dconfi = get_instance(location,dconf.instance)
  local env    = merge(
                        gconf.env,
                        gconfi.env,
                        hconf.env,
                        hconfi.env,
                        dconf.env,
                        dconfi.env
                      )
                      
  env.GEMINI_DOCUMENT_ROOT = directory.directory
  env.GEMINI_URL_PATH      = location.path
  env.GEMINI_URL           = uurl.toa(location)
  env.GATEWAY_INTERFACE    = "CGI/1.1"
  env.QUERY_STRING         = location.query or ""
  env.REMOTE_ADDR          = auth._remote
  env.REMOTE_HOST          = auth._remote
  env.SCRIPT_NAME          = base
  env.SERVER_NAME          = location.host
  env.SERVER_PORT          = tostring(location.port)
  env.SERVER_SOFTWARE      = "GLV-1.12556/1"
  
  local _,e      = location.path:find(fsys.basename(program),1,true)
  local pathinfo = e and location.path:sub(e+1,-1) or location.path
  
  if pathinfo ~= "" then
    env.PATH_INFO       = pathinfo
    env.PATH_TRANSLATED = directory.directory .. pathinfo
  end
  
  local http   = isset(dconfi.http,  dconf.http,  hconfi.http,  hconf.http,  gconfi.http,  gconf.http)
  local apache = isset(dconfi.apache,dconf.apache,hconfi.apache,hconf.apache,gconfi.apache,gconf.apache)
  local envtls = isset(dconfi.envtls,dconf.envtls,hconfi.envtls,hconf.envtls,gconfi.envtls,gconf.envtls)
  
  if http then
    env.REQUEST_METHOD       = "GET"
    env.SERVER_PROTOCOL      = "HTTP/1.0"
    env.HTTP_ACCEPT          = "*/*"
    env.HTTP_ACCEPT_LANGUAGE = "*"
    env.HTTP_CONNECTION      = "close"
    env.HTTP_REFERER         = ""
    env.HTTP_USER_AGENT      = ""
  else
    env.REQUEST_METHOD       = ""
    env.SERVER_PROTOCOL      = "GEMINI"
  end
  
  if auth._provided then
    env.AUTH_TYPE   = "Certificate"
    env.REMOTE_USER = auth.subject.CN or ""
  
    if envtls then
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
        
        breakdown(env,"TLS_CLIENT_ISSUER_", auth.issuer)
        breakdown(env,"TLS_CLIENT_SUBJECT_",auth.subject)
      else
        env.SSL_CIPHER          = auth._ctx:conn_cipher()
        env.SSL_PROTOCOL        = auth._ctx:conn_version()
        env.SSL_CLIENT_I_DN     = auth.I
        env.SSL_CLIENT_S_DN     = auth.S
        env.SSL_CLIENT_V_START  = os.date("%b %d %H:%M:%S %Y GMT",auth.notbefore)
        env.SSL_CLIENT_V_END    = os.date("%b %d %H:%M:%S %Y GMT",auth.notafter)
        env.SSL_CLIENT_V_REMAIN = remain
        env.SSL_TLS_SNI         = location.host
        
        breakdown(env,"SSL_CLIENT_I_DN_",auth.issuer)
        breakdown(env,"SSL_CLIENT_S_DN_",auth.subject)
      end
    end
  end
  
  if apache then
    local prog do
      if program:match "^/" then
        prog = uurl.rm_dot_segs:match(program)
      else
        prog = uurl.rm_dot_segs:match(fsys.getcwd() .. "/" .. program)
      end
    end
    
    env.DOCUMENT_ROOT         = directory.directory
    env.CONTEXT_DOCUMENT_ROOT = directory.directory
    env.CONTENT_PREFIX        = ""
    env.SCRIPT_FILENAME       = prog
  end
  
  return env
end

-- ************************************************************************

function handle_output(program,hdrs,data)
  local headers = parse_headers:match(hdrs)
  
  if not headers then
    syslog('error',"%s: is this a *GatewayInterface program?",program)
    return 40,MSG[40],""
  end
  
  if headers['Location'] then
    local status = headers['Status'] or 31
    return status,headers['Location'],""
  end
  
  local status  = headers['Status'] or 20
  local mime    = headers['Content-Type'] or "text/plain"
  return status,mime,data
end

-- ************************************************************************

return _ENV
