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

local CONF
local QUOTES
local INDEX
local NEXT
local MAX

_ENV = {}

-- ************************************************************************

function init(conf)
  CONF   = conf
  QUOTES = io.open(conf.quotes,"r")
  
  if not QUOTES then
    return false,"No quotes file"
  end
  
  local f = io.open(conf.index,"rb")
  if not f then
    return false,"No index file"
  end
  
  INDEX    = {}
  NEXT,MAX = string.unpack("<I4I4",f:read(8))
  NEXT     = NEXT + 1 -- adjust for 0 based index
  
  for _ = 1 , MAX do
    local s = f:read(4)
    local i = string.unpack("<I4",s)
    table.insert(INDEX,i)
  end
  
  table.insert(INDEX,f:seek('cur'))
  f:close()
  
  local state = io.open(conf.state,"r")
  if state then
    NEXT = state:read("*n")
    state:close()
  end
  
  QUOTES:seek('set',INDEX[NEXT])
  return true
end

-- ************************************************************************

function fini()
  QUOTES:close()
  local f = io.open(CONF.state,"w")
  if f then
    f:write(NEXT,"\n")
    f:close()
  end
end

-- ************************************************************************

function handler()
  local amount = INDEX[NEXT + 1] - INDEX[NEXT]
  local quote  = QUOTES:read(amount)
  
  NEXT = NEXT + 1
  if NEXT > MAX then
    NEXT = 1
    QUOTES:seek('set',0)
  end
  
  return 200,"text/plain",quote
end

-- ************************************************************************

return _ENV
