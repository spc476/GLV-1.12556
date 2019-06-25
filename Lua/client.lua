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
local url    = require "org.conman.parsers.url"
local getopt = require "org.conman.getopt".getopt
local lpeg   = require "lpeg"

-- ************************************************************************
-- Because we're sending a URL, we need to properly escape the path in case
-- it contains characters from the 'reserved' set of characters for URLs.
-- ************************************************************************

local safe_segment do
  local Cs = lpeg.Cs
  local P  = lpeg.P
  local S  = lpeg.S
  
  local char   = S":/?#[]@|"
               / function(c)
                   return string.format("%%%02X",string.byte(c))
                 end
               + P(1)
  safe_segment = Cs(char^1)
end

-- ************************************************************************

local function normalize_directory(path)
  local new = {}
  for _,segment in ipairs(path) do
    if segment == ".." then
      table.remove(new)
    elseif segment ~= "." then
      table.insert(new,safe_segment:match(segment))
    end
  end
  
  return "/" .. table.concat(new,"/")
end

-- ************************************************************************

local function main(cert,key,nover,skip,location)
  local loc = url:match(location)
  local ios = tls.connect(loc.host,loc.port,nil,function(conf)
    if cert  then conf:cert_file(cert)           end
    if key   then conf:key_file(key)             end
    if nover then conf:insecure_no_verify_cert() end
    return conf:protocols "all"
  end)
  
  if not ios then
    io.stderr:write("cannot connect to ",loc.host,"\n")
    return
  end
  ios:write(normalize_directory(loc.path),"\r\n")
  if skip then ios:read("*l") end
  io.stdout:write(ios:read("*a"))
  ios:close()
end

-- ************************************************************************

local CERT , KEY , NOVER , SKIP , URL do
  local usage = [[
usage: %s [options] url
        -c | --cert certificate
        -k | --key  keyfile
        -n | --noverify
        -s | --skipheader
        -h | --help this text
]]

  local opts =
  {
    { "c" , "cert"     , true    , function(c) CERT  = c    end },
    { "k" , "key"      , true    , function(k) KEY   = k    end },
    { "n" , "noverify" , false   , function()  NOVER = true end },
    { "s" , "skipheader" , false , function()  SKIP  = true end },
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

nfl.spawn(main,CERT,KEY,NOVER,SKIP,URL)
nfl.client_eventloop()
