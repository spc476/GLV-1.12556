-- ************************************************************************
--
--    QOTD module
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
-- luacheck: globals init fini handler
-- luacheck: ignore 611

local io     = require "io"
local string = require "string"
local table  = require "table"

_ENV = {}

-- ************************************************************************

function init(conf)
  conf.QUOTES = io.open(conf.quotes,"r")
  
  if not conf.QUOTES then
    return false,"No quotes file"
  end
  
  local f = io.open(conf.index,"rb")
  if not f then
    return false,"No index file"
  end
  
  conf.INDEX         = {}
  conf.NEXT,conf.MAX = string.unpack("<I4I4",f:read(8))
  conf.NEXT          = conf.NEXT + 1 -- adjust for 0 based index
  
  for _ = 1 , conf.MAX do
    local s = f:read(4)
    local i = string.unpack("<I4",s)
    table.insert(conf.INDEX,i)
  end
  
  table.insert(conf.INDEX,f:seek('cur'))
  f:close()
  
  local state = io.open(conf.state,"r")
  if state then
    conf.NEXT = state:read("*n")
    state:close()
  end
  
  conf.QUOTES:seek('set',conf.INDEX[conf.NEXT])
  return true
end

-- ************************************************************************

function fini(conf)
  conf.QUOTES:close()
  local f = io.open(conf.state,"w")
  if f then
    f:write(conf.NEXT,"\n")
    f:close()
  end
end

-- ************************************************************************

function handler(conf)
  local amount = conf.INDEX[conf.NEXT + 1] - conf.INDEX[conf.NEXT]
  local quote  = conf.QUOTES:read(amount)
  
  conf.NEXT = conf.NEXT + 1
  if conf.NEXT > conf.MAX then
    conf.NEXT = 1
    conf.QUOTES:seek('set',0)
  end
  
  return 20,"text/plain",quote
end

-- ************************************************************************

return _ENV
