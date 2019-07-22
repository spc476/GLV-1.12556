-- ************************************************************************
--
--    Bible module
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

local soundex   = require "org.conman.parsers.soundex"
local metaphone = require "org.conman.string".metaphone
local wrapt     = require "org.conman.string".wrapt
local lpeg      = require "lpeg"
local io        = require "io"
local math      = require "math"
local string    = require "string"
local table     = require "table"

local tonumber = tonumber

local CONF
local ABBR      = {}
local BOOKS     = {}
local SOUNDEX   = {}
local METAPHONE = {}

_ENV = {}

-- ************************************************************************

local bible_parse do
  local Cb = lpeg.Cb
  local Cc = lpeg.Cc
  local Cg = lpeg.Cg
  local Ct = lpeg.Ct
  local P  = lpeg.P
  local R  = lpeg.R
  
  -- G                  G.1:1-999:999
  -- G.a                G.a:1-a:999
  -- G.a:b              G.a:b-a:b
  -- G.a:b-x            G.a:b-a:x
  -- G.a-c              G.a:1-c:999
  -- G.a-c:d            G.a:1-c:d
  -- G.a:b-c:d          G.a:b-c:d
  
  local num   = R"09"^1 / tonumber
  
  local book  = Cg(R("AZ","az","09")^1,'book')
              * Cg(Cc(  1),'cb') * Cg(Cc(  1),'vb') -- starting chapter/book
              * Cg(Cc(999),'ce') * Cg(Cc(999),'ve') -- ending chapter/book
              
  local start = P"." * Cg(num,'cb')
              * Cg(Cc(true),'fcb')
              * Cg(Cb'cb','ce')
              * (
                  P":" * Cg(num,'vb') * Cg(Cc(true),'fvb')
                  * (
                      (#(P"-" * R"09"^1 * P(-1)) * P"-" * Cg(num,'ve'))
                      + Cg(Cb'vb','ve')
                    )
                )^-1
                
  local stop  =  P"-" * Cg(num,'ce') * Cg(Cc(true),'fce')
              * (P":" * Cg(num,'ve') * Cg(Cc(true),'fve'))^-1
              
  bible_parse = Ct(book * (start * stop^-1)^-1)
end

-- ************************************************************************

function init(conf)
  local entry = lpeg.C(lpeg.R("AZ","az","09")^1)
              * lpeg.S" \t"^0 * lpeg.P"," * lpeg.S" \t"^0
              * lpeg.C(lpeg.R("AZ","az","09")^1)
  
  for line in io.lines(conf.books) do
    local abbr,book = entry:match(line)
    local s         = soundex:match(book)
    local m         = metaphone(book)
    ABBR[abbr]      = book
    BOOKS[book]     = true
    SOUNDEX[s]      = book
    METAPHONE[m]    = book
  end
  
  CONF = conf
  return true
end

-- ************************************************************************

local function bible_request(query)
  local r = bible_parse:match(query)
  if not r then return end
  
  if ABBR[r.book] then
    r.book = ABBR[r.book]
    return r,true
  end
  
  if not BOOKS[r.book] then
    local s = soundex:match(r.book)
    if SOUNDEX[s] then
      r.book = SOUNDEX[s]
      return r,true
    end
    
    local m = metaphone(r.book)
    if METAPHONE[m] then
      r.book = METAPHONE[m]
      return r,true
    end
  else
    return r,false
  end
end

-- ************************************************************************

function handler(_,_,loc,match)
  local function redirect_here(path,book)
    local selector = { book.book }
    
    if book.fcb then
      table.insert(selector,string.format(".%d",book.cb))
    end
    if book.fvb then
      table.insert(selector,string.format(":%d",book.vb))
    end
    if book.fce then
      table.insert(selector,string.format("-%d",book.ce))
    end
    if book.fve then
      table.insert(selector,string.format(":%d",book.ve))
    end
    
    path[#path] = table.concat(selector)
    return string.format("/%s",table.concat(path,"/"))
  end
  
  -- ================================================
  
  local r,redirect = bible_request(match[1])
  local buffer     = {}
  
  if not r then
    return 404,"Not Found",""
  end
  
  if redirect then
    local here = redirect_here(loc.path,r)
    return 301,here,""
  end
  
  -- ================================================
  
  local function write(fmt,...)
    local s = string.format(fmt,...)
    table.insert(buffer,s)
  end
  
  -- ================================================
  
  local function readint(file)
    local c = file:read(1) -- trigger EOF
    if c then
      return c:byte()
           + file:read(1):byte() * 2^8
           + file:read(1):byte() * 2^16
           + file:read(1):byte() * 2^24
    end
  end
  
  -- ================================================
  
  local function show_chapter(chapter,low,high)
    local index = io.open(string.format("%s/%s/%d.index",CONF.verses,r.book,chapter),"rb")
    if not index then return end
    local verse = io.open(string.format("%s/%s/%d",CONF.verses,r.book,chapter),"r")
    local max   = math.min(high,readint(index))
    
    high = math.min(high,max)
    
    index:seek('set',low * 4)
    local start = readint(index)
    verse:seek('set',start)
    
    local hdr = string.format("Chapter %d",chapter)
    write("\n%s%s\n\n",string.rep(" ",40 - #hdr // 2),hdr)
    
    for v = low , high do
      local stop = readint(index)
      local len  = stop - start
      local text = verse:read(len)
      local wt   = wrapt(text,60)
      start      = stop
      write("%3d. %s\n",v,table.concat(wt,"\n     "))
    end
    
    index:close()
    verse:close()
  end
  
  -- ================================================
  
  write("%s%s\n",string.rep(" ",40 - #r.book // 2),r.book)
  
  for chapter = r.cb , r.ce do
    local vb
    local ve
    
    if chapter == r.cb then
      vb = r.vb
    else
      vb = 1
    end
    
    if chapter == r.ce then
      ve = r.ve
    else
      ve = 999
    end
    
    show_chapter(chapter,vb,ve)
  end
  
  return 200,"text/plain",table.concat(buffer)
end

-- ************************************************************************

return _ENV
