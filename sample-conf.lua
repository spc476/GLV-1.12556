-- ************************************************************************
--
--    Sample config file
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
-- luacheck: globals certificate network log redirect no_access
-- luacheck: globals cgi modules cmodules handlers
-- luacheck: ignore 611

-- ************************************************************************
-- Certificate definition block, required.
-- ************************************************************************

certificate =
{
  cert = "cert.pem", -- certificate
  key  = "key.pem",  -- certificate key
}

-- ************************************************************************
-- Network definition block, required
-- ************************************************************************

network =
{
  host = "example.com", -- hostname of the server
  addr = "0.0.0.0",             -- interface to listen on, IPv6 supported
  port = 1965,                  -- port to listen on.
}

-- ************************************************************************
-- syslog() definition block, required
-- ************************************************************************

log =
{
  ident    = 'gemini', -- ID of server
  facility = 'daemon', -- syslog facility to log under
}

-- ************************************************************************
-- File filter definition block, optional
--
-- Lua patterns matched against file segments (the stuff between '/' in the
-- path) and if matched, said file isn't served up or listed.  If not given,
-- then any file found under the serving area will be listed.
-- ************************************************************************

no_access =
{
  "^%.",  -- no to any dot files
  "%~$",  -- no to any backup files
}

-- ************************************************************************
-- Redirect definition block, optional
--
-- Before any handlers or files are checked, requests are filtered through
-- these redirection blocks.  The temporary block is for temporary
-- redirects, and the permanent block is for permanent redirects.  The keys
-- for these are Lua patterns that are tried against the request, and if a
-- match is found, the value is served up as the location to redirect to.
--
-- Pattern captures can be referenced in the value, "$1" will be replaced
-- with the first such capture, "$2" with the second capture, and so on.
--
-- The gone block is for requests that once existed, but no more.  This is
-- just a list of patterns to be matched against, any match will serve up a
-- resource gone status.
-- ************************************************************************

--[[
redirect =
{
  temporary =
  {
    ['^/example1/(.*)'] = "/new-location/$1",
  },
  
  permanent =
  {
    ['^/example2/(contents)/(.*)' = "gemini://example.net/$1/$2",
  },
  
  gone =
  {
    '^/example3(.*)'
  }
}
--]]

-- ************************************************************************
-- Additional paths to load Lua modules, optional.  If you aren't using
-- CGI, or any handlers, then you won't need to define these.
-- ************************************************************************

--[[
modules  = "/var/gemini/modules/?.lua"
cmodules = "/var/gemini/modules/?.so"
--]]

-- ************************************************************************
-- Handler extensions, optional
--
-- These represent virtual resources, or virtual CGI scripts.  This is
-- checked after the redirections, but before the file system is handled.
-- The configuration options are entirely dependant upon the handler---the
-- only required configuration option per handler is the 'module' field,
-- which defines the codebase for the handler.
-- ************************************************************************

--[[
handlers =
{

  ['^/bible/(.*)'] =
  {
    module = "bible",
    books  = "thebooks",
    verses = "theverses",
  },
  
  ['^/qotd$'] =
  {
    module = "qotd",
    quotes = "quotes.txt",
    index  = "quotes.index",
    state  = "quotes.state",
  },
  
  ['^/gRFC/(.*)'] =
  {
    module = "gRFC",
    dir    = "gRFC",
    path   = "/gRFC",
  },
  
  ['^/test/torture/(.*)'] =
  {
    module = "torture",
    dir    = "torture",
  }
}
--]]

-- ************************************************************************
-- CGI definition block, optional
--
-- Any file found with the executable bit set is considered a CGI script and
-- will be executed as such.  This module implements the CGI standard as
-- defined in RFC-3875.  The script will be executed, and any output will be
-- sent to the Gemini client.  The following environment variables will be
-- defined:
--
-- GATEWAY_INTERFACE    Will be set to "CGI/1.1"
-- PATH_INFO            May be set (see RFC-3875 for details)
-- PATH_TRANSLATED      May be set (see RFC-3875 for deatils)
-- QUERY_STRING         Will be set to the passed in query string, or ""
-- REMOTE_ADDR          IP address of the client
-- REMOTE_HOST          IP address of the client (allowed in RFC-3875)
-- REQUEST_METHOD       Will be empty, as there are no requests types
-- SCRIPT_NAME          Name of the script per the URL path
-- SERVER_NAME          Per network.host
-- SERVER_PORT          Per network.port
-- SERVER_PROTOCOL      Will be set to "GEMINI"
-- SRVER_SOFTWARE       Will be set to "GLV-1.12556/1"
--
-- In addition, scripts written for a webserver can also be used.  If such
-- scripts are used, addtional headers will be set:
--
-- REQUEST_METHOD       Will be changed to "GET"
-- SERVER_PROTOCOL      Will be changed to "HTTP/1.0"
-- HTTP_ACCEPT          Will be set to "*/*"
-- HTTP_ACCEPT_LANGUAGE Will be set to "*"
-- HTTP_CONNECTION      Will be set to "close"
-- HTTP_REFERER         Will be set to ""
-- HTTP_USER_AGENT      Will be set to ""
--
-- Also, if HTTP based CGI scripts expect Apache-specific headers to be set,
-- those too can be specified and the following will be set:
--
-- DOCUMENT_ROOT        Will be set to the top level directory being served
-- SCRIPT_FILENAME      The full path of the script being run
--
-- If a certificate is required to run the script, and it is so desired, the
-- following environment variables can be set:
--
-- TLS_CIPHER                   Cipher being used
-- TLS_VERSION                  Version of TLS being used
-- TLS_CLIENT_HASH              Hash of the certificate
-- TLS_CLIENT_ISSUER            The x509 Issuer of the certificate
-- TLS_CLIENT_ISSUER_*          The x509 Issuer subfields
-- TLS_CLIENT_SUBJECT           The x509 Distinguished Name
-- TLS_CLIENT_SUBJECT_*         Various Distinguished Name subfields
-- TLS_CLIENT_NOT_BEFORE        Starting date of certificate
-- TLS_CLIENT_NOT_AFTER         Ending date of certificate
-- TLS_CLIENT_REMAIN            Number of days left for certificate
--
-- If the script is expecting Apache style environment variables, those
-- can be set instead:
--
-- SSL_CIPHER                   aka TLS_CIPHER
-- SSL_PROTOCOL                 aka TLS_VERSION
-- SSL_CLIENT_I_DN              ala TLS_CLIENT_ISSUER
-- SSL_CLIENT_I_DN_*            aka TLS_CLIENT_ISSUER_*
-- SSL_CLIENT_S_DN              aka TLS_CLIENT_SUBJECT
-- SSL_CLIENT_S_DN_*            aka TLS_CLIENT_SUBJECT_*
-- SSL_CLIENT_V_START           aka TLS_CLIENT_NOT_BEFORE
-- SSL_CLIENT_V_END             aka TLS_CLIENT_NOT_AFTER
-- SSL_CLIENT_V_REMAIN          aka TLS_CLIENT_REMAIN
-- SSL_TLS_SNI                  aka SERVER_NAME
--
-- ************************************************************************

--[[
cgi =
{
  -- -----------------------------------------------------------------
  -- The following variables apply to ALL CGI scripts.  They are all
  -- optional, and do not need to be defined.
  -- -----------------------------------------------------------------
  
  -- ------------------------------------------------------------
  -- All scripts will use this as the current working directory.
  -- ------------------------------------------------------------
  
  cwd = "/tmp",
  
  -- ------------------------------------------------------------------
  -- Additional environment variables can be set.  The following list
  -- is probably what would be nice to have.
  -- ------------------------------------------------------------------
  
  env =
  {
    PATH           = "/usr/local/bin:/usr/bin:/bin",
    LANG           = "en_US.UTF-8",
  },
  
  -- http   = true, -- only define if all CGI scripts are web based
  -- apache = true, -- if you want Apache style environment variables
  -- envtls = true, -- only define if you want all scripts to have TLS vars
  
  -- -----------------------------------------------------------------
  -- The following blocks allow you to define values per CGI script.
  -- -----------------------------------------------------------------
  
  instance =
  {
    ['^/private/raw.*'] =
    {
      cwd = '/var/tmp' -- different cwd
    },
    
    ['^/private/index.gemini$'] =
    {
      cwd = '/var/private' -- again, different cwd
      envtls = true,       -- we WANT TLS env vars for this
    },
    
    ['^/sampleCGI/.*'] =
    {
      http   = true,
      apache = true,
      env    = -- this is in addition to the ALL CGI env block
      {
        SAMPLE_CONFIG = "sample.conf",
      }
    },
  }
}
--]]
