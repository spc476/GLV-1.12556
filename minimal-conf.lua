-- ************************************************************************
--
--    Mininal configuration file.
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
--
-- This configuration provides the minimum needed to run the Gemini server.
-- There is no redirects, no CGI, no authorization and the one required
-- handler to serve up files.
--
-- ************************************************************************
-- luacheck: globals hosts
-- luacheck: ignore 611

hosts =
{
  ["example.com"] =
  {
    certificate = "cert.pem",
    keyfile     = "key.pem",
    handlers    =
    {
      {
        path      = ".*",
        module    = "GLV-1.handlers.filesystem",
        directory = "share" -- change as needed
      }
    }
  }
}
