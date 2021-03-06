-- ************************************************************************
--
--    Standardize status messages
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

return {
  [40] = "Intertempa eraro", -- "Temporary Error",
  [41] = "Servilo neatingebla", -- "Server Unavailable",
  [42] = "Ofta Eraro de Interŝanĝa Enirejo", -- "CGI Error",
  [43] = "Prokura Eraro", -- "Proxy Error",
  [44] = "Malrapidiĝu", -- "Slow Down",
  [50] = "Permanenta eraro", -- "Permanent Error",
  [51] = "Ne trovita", -- "Not Found",
  [52] = "Malaperis", -- "Gone",
  [53] = "Proxy-peto rifuzis", -- "Proxy Request Refused",
  [59] = "Malbona peto", -- "Bad Request",
  [60] = "Klienta Atestilo Bezonata", -- "Client Certificate Required",
  [61] = "Atestilo ne rajtigita", -- "Certificate Not Authorized",
  [62] = "Atestilo ne validas", --Certificate Not Valid",
}
