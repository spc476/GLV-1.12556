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
-- luacheck: globals handler
-- luacheck: ignore 611

                 require "org.conman.math".randomseed()
local uurl     = require "GLV-1.url-util"
local math     = require "math"
local string   = require "string"
local tonumber = tonumber

_ENV = {}

-- ************************************************************************

function handler(_,_,loc,match)
  if match[2] == "" then
    return 20,"text/gemini","\r\n"
        .. "I'm thinking of a number between 1 and 100.  Click the\r\n"
        .. "link below to guess my number!\r\n"
        .. "\r\n"
        .. string.format("=> %s%d Hazzard a guess\r\n",match[1],math.random(100) + 1000)
  end
  
  if not loc.query then
    return 10,"Guess a number",""
  end
  
  local guess = uurl.esc_query:match(loc.query)
  
  if guess:match "^[%+%-][%d]" then
    return 10,"Guess anumber (just digits, no plus or minus sign)",""
  end
  
  if guess:match "^[%D]" then
    return 20,"text/gemini","\r\n"
           .. "Sigh.  I think your client is buggy and is assuming\r\n"
           .. "that the query string needs to start with the name,\r\n"
           .. "which it does not.  It just needs to be\r\n"
           .. "a number.  You might want to try again.  Sorry.\r\n"
           .. "\r\n"
           .. string.format("=> %s Try again\r\n",match[1])
           .. string.format("=> / Top level menu\r\n")
  end
  
  if guess:match "%?" then
    return 20,"text/gemini","\r\n"
           .. "Sign.  I think your client is buggy and has appended a\r\n"
           .. "second query string to one that already exists.  The query\r\n"
           .. 'your client sent, "' .. loc.query .. '" is not proper.  It\r\n'
           .. "should be just a number. You might want to try again.  Sorry.\r\n"
           .. "\r\n"
           .. string.format("=> %s Try again\r\n",match[1])
           .. string.format("=> / Top level menu\r\n")
  end
  
  guess = tonumber(guess)
  
  if not guess then
    return 10,"Guess a number",""
  end
  
  local num = tonumber(match[2])
  if not num then
    return 10,"Guess a number",""
  end
  
  num = num % 97
  
  if guess < num then
    return 10,"Higher",""
  elseif guess > num then
    return 10,"Lower",""
  else
    return 20,"text/gemini","\r\n"
        .. "Congratulations!  You guessed the number!\r\n"
        .. "\r\n"
        .. string.format("=> %s%d Try again?\r\n",match[1],math.random(100) + 1000)
        .. "=> / Nah, take me back home\r\n"
  end
end

-- ************************************************************************

return _ENV
