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
-- luacheck: globals parse_headers get_instance isset merge_env
-- luacheck: globals breakdown handle_output
-- luacheck: ignore 611
-- RFC-3875

local syslog = require "org.conman.syslog"
local abnf   = require "org.conman.parsers.abnf"
local lpeg   = require "lpeg"
local MSG    = require "GLV-1.MSG"

local pairs    = pairs
local tonumber = tonumber

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

function isset(hci,hc,sci,sc)
  if hci ~= nil then return hci end
  if hc  ~= nil then return hc  end
  if sci ~= nil then return sci end
  return sc
end

-- ************************************************************************

function merge_env(accenv,menv)
  if menv then
    for var,val in pairs(menv) do
      accenv[var] = val
    end
  end
end

-- ************************************************************************

function breakdown(env,base,fields)
  for name,value in pairs(fields) do
    env[base .. name] = value
  end
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
