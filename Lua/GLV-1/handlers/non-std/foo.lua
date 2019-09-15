-- ************************************************************************
--
--    A Foo module to make a pedantic point.
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

local string = require "string"

_ENV = {}

-- ************************************************************************

function handler(_,_,_,match)
  if (match[2] == "") then
    return 20,"text/plain",string.format([[
This is a resource that *looks* like a directory, but isn't.  It's fooling
you and you don't like it!
]])
  else
    return 20,"text/gemini",string.format([[

Guess what?  There *is* an index file here, but there's no file that really
has a name of "%s%s".  Too bad.

=> /	Top Level
=> %s	What might be here?
=> %s%s	This page.

]],match[1],match[2],
	   match[1],
	   match[1],match[2])
  end
end

-- ************************************************************************

return _ENV
