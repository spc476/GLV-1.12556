#!/usr/bin/env lua
-- ************************************************************************
--
--    Client program
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

local nfl    = require "org.conman.nfl"
local tls    = require "org.conman.nfl.tls"
local url    = require "url"
local uurl   = require "url-util"
local getopt = require "org.conman.getopt".getopt
local lpeg   = require "lpeg"

local CERT
local KEY
local NOVER
local SURL

-- ************************************************************************

local statparse do
  local Cc = lpeg.Cc
  local C  = lpeg.C
  local P  = lpeg.P
  local R  = lpeg.R
  
  local DD       = R"09" * R"09"
  local status   = P"200"    * Cc'okay'     * Cc'content'
                 + P"301"    * Cc'redirect' * Cc'permanent'
                 + P"401"    * Cc'client'   * Cc'unauthorized'
                 + P"403"    * Cc'client'   * Cc'forbidden'
                 + P"404"    * Cc'client'   * Cc'not-found'
                 + P"410"    * Cc'client'   * Cc'gone'
                 + P"429"    * Cc'client'   * Cc'slow-down'
                 + P"460"    * Cc'client'   * Cc'need-certificate'
                 + P"461"    * Cc'client'   * Cc'future-certificate'
                 + P"462"    * Cc'client'   * Cc'expired-certificate'
                 + P"463"    * Cc'client'   * Cc'rejected-certificate'
                 
                 -- ----------------
                 -- Catch-all path
                 -- ----------------
                 
                 + P"2" * DD * Cc'okay'     * Cc'content'
                 + P"3" * DD * Cc'redirect' * Cc'see-other'
                 + P"4" * DD * Cc'client'   * Cc'error'
                 + P"5" * DD * Cc'server'   * Cc'error'
                 
                 -- ----------------------------------------------------
                 -- Proposed 2-digit codes---The main categories aren't
                 -- quite right, bit they're the closest to the current
                 -- categories I'm using now.
                 -- ----------------------------------------------------
                 
                 + P"10" * Cc'search'   * Cc'need-info'
                 + P"20" * Cc'okay'     * Cc'content'
                 + P"30" * Cc'redirect' * Cc'temporary'
                 + P"31" * Cc'redirect' * Cc'permanent'
                 + P"40" * Cc'server'   * Cc'error'
                 + P"41" * Cc'server'   * Cc'overload'
                 + P"42" * Cc'server'   * Cc'CGI-error'
                 + P"43" * Cc'client'   * Cc'slow-down'
                 + P"50" * Cc'server'   * Cc'error'
                 + P"51" * Cc'client'   * Cc'not-found'
                 + P"53" * Cc'client'   * Cc'gone'
                 + P"59" * Cc'client'   * Cc'bad-request'
                 + P"60" * Cc'client'   * Cc'need-certificate'
                 + P"61" * Cc'client'   * Cc'need-certificate'
                 + P"62" * Cc'client'   * Cc'need-certificate'
                 + P"63" * Cc'client'   * Cc'rejected-certificate'
                 + P"64" * Cc'client'   * Cc'future-certificate'
                 + P"65" * Cc'client'   * Cc'expired-certificate'
                 
                 -- -----------------------------
                 -- The proposed catch-all path
                 -- -----------------------------
                 
                 + P"1" * R"09" * Cc'search'   * Cc'need-info'
                 + P"2" * R"09" * Cc'okay'     * Cc'content'
                 + P"3" * R"09" * Cc'redirect' * Cc'temporary'
                 + P"4" * R"09" * Cc'server'   * Cc'error'
                 + P"5" * R"09" * Cc'client'   * Cc'error'
                 + P"6" * R"09" * Cc'server'   * Cc'need-certificate'
                 
                 -- -----------------------------------
                 -- The "Official Spec" return codes.
                 -- -----------------------------------
                 
                 + P"2"      * Cc'okay'     * Cc'content'
                 + P"3"      * Cc'redirect' * Cc'permanent'
                 + P"4"      * Cc'client'   * Cc'error'
                 + P"5"      * Cc'server'   * Cc'error'
                 + P"9"      * Cc'client'   * Cc'slow-down'
                 
                 -- ---------------------------------------------------
                 -- The proposed 1-dight status codes---Most of these
                 -- match the existing structure and only add to them.
                 -- ---------------------------------------------------
                 
                 + P"1"      * Cc'search' * Cc'need-info'
                 + P"6"      * Cc'client' * Cc'gone'
                 + P"7"      * Cc'client' * Cc'slow-down'
                 + P"A"      * Cc'client' * Cc'need-certificate'
                 + P"B"      * Cc'client' * Cc'need-certificate'
                 + P"C"      * Cc'client' * Cc'rejected-certificate'
                 + P"D"      * Cc'cilent' * Cc'expired-certificate'
                 
  local infotype = P"\t" * C(R" \255"^0)
                 + Cc"type/text; charset=utf-8"
                 
  statparse      = status * infotype
end

-- ************************************************************************

local function main(location,usecert)
  local loc = url:match(location)
  local ios = tls.connect(loc.host,loc.port,nil,function(conf)
    if usecert then
      if not conf:cert_file(CERT)
      or not conf:key_file(KEY) then
        return false
      end
    end
    
    if NOVER then
      conf:insecure_no_verify_name()
      conf:insecure_no_verify_time()
      conf:insecure_no_verify_cert()
    end

    return conf:protocols "all"
  end)
  
  if not ios then
    io.stderr:write("cannot connect to ",loc.host,"\n")
    return
  end
  
  local request do
    if SURL then
      request = location
    else
      request = uurl.esc_path:match(loc.path)
      if loc.query then
        request = request .. "?" .. loc.query
      end
    end
  end
  
  ios:write(request,"\r\n")
  
  local statline = ios:read("*l")
  if not statline then
    io.stderr:write("bad request\n")
    ios:close()
    return
  end
  
  local system,status,info = statparse:match(statline)
  if not system then
    io.stderr:write("bad reply: ",statline,"\n")
    ios:close()
    return
  end
  
  io.stderr:write(string.format("system=%s status=%s info=%s\n",
        system,
        status,
        info
  ))
  
  if system == 'client' then
    if status == 'need-certificate' and CERT and KEY then
      return main(location,true)
    end
  end
  
  if system == 'okay' then
    io.stdout:write(ios:read("*a"))
  end
  
  ios:close()
end

-- ************************************************************************

CERT = os.getenv("GEMINI_CERT")
KEY  = os.getenv("GEMINI_KEY")

local URL do
  local usage = [[
usage: %s [options] url
        -c | --cert certificate
        -k | --key  keyfile
        -n | --noverify
        -h | --help this text
]]

  local opts =
  {
    { "c" , "cert"     , true    , function(c) CERT  = c    end },
    { "k" , "key"      , true    , function(k) KEY   = k    end },
    { "n" , "noverify" , false   , function()  NOVER = true end },
    { "u" , "url"      , false   , function()  SURL  = true end },
    { 'h' , "help"     , false   , function()
        io.stderr:write(string.format(usage,arg[0]))
        os.exit(false,true)
      end
    },
  }
  
  if #arg == 0 then
    io.stderr:write(string.format(usage,arg[0]))
    os.exit(false,true)
  end
  
  URL = arg[getopt(arg,opts)]
end

nfl.spawn(main,URL)
nfl.client_eventloop()
