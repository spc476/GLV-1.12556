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
  [40] = "Temporary Error",
  [41] = "Server Unavailable",
  [42] = "CGI Error",
  [43] = "Proxy Error",
  [44] = "Slow Down",
  [50] = "Permanent Error",
  [51] = "Not Found",
  [52] = "Gone",
  [53] = "Proxy Request Refused",
  [59] = "Bad Request",
  [60] = "Client Certificate Required",
  [61] = "Certificate Not Authorized",
  [62] = "Certificate Not Valid",
}
