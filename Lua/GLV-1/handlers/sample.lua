-- ************************************************************************
--
--    The sample handler
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
-- luacheck: globals init handler fini
-- luacheck: ignore 611

local syslog = require "org.conman.syslog"
local string = require "string"

_ENV = {}

-- ************************************************************************
-- Usage:	okay[,err] = sample.init(iconf,hconf,gconf)
-- Desc:	Do any initialization of the module
-- Input:	iconf (table) instance configuration block
--              hconf (table) host configuation block
--              gconf (table) global configuration block
-- Return:	okay (boolean) true if okay, false if any error
--		err (string) error message
--
-- NOTE:	This function is optional.
--		Also, any information local to an instance can be stored
--		in the passed in configuration block.
--		Not all modules will use the hconf or gconf block.
-- ************************************************************************

function init(iconf)
  syslog('debug',"init(%s) path pattern=%q",iconf.module,iconf.path)
  return true
end

-- ************************************************************************
-- Usage:	status,mime,data = sample.handler(conf,auth,loc,match)
-- Desc:	Handle the request
-- Input:	conf (table) configuration block from configuration file
--		auth (table) authentication information
-- 		loc (table) Broken down URL from the request
--		match (table) matched data from the path pattern
-- Return:	status (integer) Gemini status code
--		mime (string) MIME type for content, message for other
--		data (string) content if any
-- ************************************************************************

function handler(conf,auth,loc,match)
  return 20,'text/plain',string.format([[
conf.path=%q
conf.module=%q
auth.issuer=%q
auth.subject=%q
loc.host=%s
loc.port=%d
loc.path=%q
loc.query=%q
match[1]=%q
]],
	conf.path,
	conf.module,
	auth.issuer  or "",
	auth.subject or "",
	loc.host,
	loc.port,
	loc.path,
	loc.query or "",
	match[1]  or ""
  )
end

-- ************************************************************************
-- Usage:	okay,err = sample.fini(conf)
-- Desc;	Cleanup resources for module
-- Input:	conf (table) configuration block from configuration file
-- Return:	okay (boolean) true if okay, false if any error
--		err (string) error message
--
-- NOTE:	This function is optional.
-- ************************************************************************

function fini(conf)
  syslog('debug',"fini(%s) path pattern=%q",conf.module,conf.path)
  return true
end

-- ************************************************************************

return _ENV
