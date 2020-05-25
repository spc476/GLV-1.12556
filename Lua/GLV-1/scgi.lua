-- ************************************************************************
--
--    SCGI interace.
--    Copyright 2020 by Sean Conner.  All Rights Reserved.
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

local syslog = require "org.conman.syslog"
local fsys   = require "org.conman.fsys"
local errno  = require "org.conman.errno"
local url    = require "org.conman.parsers.url"
local tcp    = require "org.conman.nfl.tcp"
local math   = require "math"
local os     = require "os"
local uurl   = require "GLV-1.url-util"
local MSG    = require "GLV-1.MSG"
local gi     = require "GLV-1.gateway"

local pairs    = pairs
local tostring = tostring

-- ************************************************************************

return function(auth,program,directory,location)
  local sconf = require "CONF".scgi
  local hconf = require "CONF".hosts[location.host].scgi
  
  if not sconf and not hconf then
    syslog('error',"SCGI called, but SCGI not configured!")
    return 40,MSG[40],""
  end
  
  if hconf == false then
    syslog('error',"SCGI called, but SCGI not configured!")
    return 40,MSG[40],""
  end
  
  sconf = sconf or {}
  hconf = hconf or {}
  
  local sconfi = gi.get_instance(location,sconf.instance)
  local hconfi = gi.get_instance(location,hconf.instance)
  local env    = {}
  
  gi.merge_env(env,sconf.env)
  gi.merge_env(env,sconfi.env)
  gi.merge_env(env,hconf.env)
  gi.merge_env(env,hconfi.env)
  
  env.GEMINI_DOCUMENT_ROOT = directory
  env.GEMINI_URL_PATH      = location.path
  env.GEMINI_URL           = uurl.toa(location)
  env.QUERY_STRING         = location.query or ""
  env.REMOTE_ADDR          = auth._remote
  env.REMOTE_HOST          = auth._remote
  env.SCRIPT_NAME          = program
  env.SERVER_NAME          = location.host
  env.SERVER_PORT          = tostring(location.port)
  env.SERVER_SOFTWARE      = "GLV-1.12556/1"
  
  if gi.isset(hconfi.http,hconf.http,sconfi.http,sconf.http) then
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
  
  local _,e      = location.path:find(fsys.basename(program),1,true)
  local pathinfo = e and location.path:sub(e+1,-1) or location.path
  
  if pathinfo ~= "" then
    env.PATH_INFO       = pathinfo
    env.PATH_TRANSLATED = directory .. pathinfo
  end
  
  if  auth._provided
  and gi.isset(hconfi.envtls,hconf.envtls,sconfi.envtls,sconf.envtls) then
    local remain = tostring(math.floor(os.difftime(auth.notafter,auth.now) / 86400))
    
    env.AUTH_TYPE   = "Certificate"
    env.REMOTE_USER = auth.subject.CN
    
    if not gi.isset(hconfi.apache,hconf.apache,sconfi.apache,sconf.apache) then
      env.TLS_CIPHER            = auth._ctx:conn_cipher()
      env.TLS_VERSION           = auth._ctx:conn_version()
      env.TLS_CLIENT_HASH       = auth._ctx:peer_cert_hash()
      env.TLS_CLIENT_ISSUER     = auth.I
      env.TLS_CLIENT_SUBJECT    = auth.S
      env.TLS_CLIENT_NOT_BEFORE = os.date("%Y-%m-%dT%H:%M:%SZ",auth.notbefore)
      env.TLS_CLIENT_NOT_AFTER  = os.date("%Y-%m-%dT%H:%M:%SZ",auth.notafter)
      env.TLS_CLIENT_REMAIN     = remain
      
      gi.breakdown(env,"TLS_CLIENT_ISSUER_", auth.issuer)
      gi.breakdown(env,"TLS_CLIENT_SUBJECT_",auth.subject)
    else
      env.SSL_CIPHER          = auth._ctx:conn_cipher()
      env.SSL_PROTOCOL        = auth._ctx:conn_version()
      env.SSL_CLIENT_I_DN     = auth.I
      env.SSL_CLIENT_S_DN     = auth.S
      env.SSL_CLIENT_V_START  = os.date("%b %d %H:%M:%S %Y GMT",auth.notbefore)
      env.SSL_CLIENT_V_END    = os.date("%b %d %H:%M:%S %Y GMT",auth.notafter)
      env.SSL_CLIENT_V_REMAIN = remain
      env.SSL_TLS_SNI         = location.host
      
      gi.breakdown(env,"SSL_CLIENT_I_DN_",auth.issuer)
      gi.breakdown(env,"SSL_CLIENT_S_DN_",auth.subject)
    end
  end
  
  local tenv = "CONTENT_LENGTH" .. '\0' .. "0" .. '\0'
            .. "SCGI"           .. '\0' .. "1" .. '\0'
  
  for name,val in pairs(env) do
    tenv = tenv .. name .. '\0' .. val .. '\0'
  end
  
  local scgiurl,err = fsys.readlink(program)
  if not scgiurl then
    syslog('error',"SCGI: readlink() = %s",errno[err])
    return 40,MSG[40],""
  end
  
  local scgiloc = url:match(scgiurl)
  if not scgiloc then
    syslog('error',"SCGI: bad link %q",scgiloc)
    return 40,MSG[40],""
  end
  
  if not scgiloc.host then
    syslog('error',"SCGI: %q missing host",program)
    return 40,MSG[40],""
  end
  
  if not scgiloc.port then
    syslog('error',"SCGI: %q missing port",program)
    return 40,MSG[40],""
  end
  
  local ios = tcp.connect(scgiloc.host,scgiloc.port,5)
  if not ios then
    return 40,MSG[40],""
  end
  
  ios:write(tostring(#tenv),":",tenv,",0:,")
  local hdrs = ios:read("h")
  local data = ios:read("a")
  ios:close()
  
  return gi.handle_output(program,hdrs,data)
end
