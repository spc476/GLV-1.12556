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
-- luacheck: globals syslog address cgi scgi hosts
-- luacheck: globals mime index no_access extension
-- luacheck: globals language charset
-- luacheck: ignore 611

-- ************************************************************************
-- syslog() definition block, optional, global only, default values
-- ************************************************************************

syslog =
{
  ident    = 'gemini', -- ID of server
  facility = 'daemon', -- syslog facility to log under
}

-- ************************************************************************
-- address---optional, global or host, default value
--
-- This should work fine on all systems, creating a listening socket bound
-- to all active interfaces.  If you only have IPv4, use "0.0.0.0:1965" to
-- bind to all active interfaces.  This can be a specific address if you
-- don't want to bind all active interfaces.
--
-- You do need to specify both the address (and it can be a hostname) AND
-- the port number.  If either is missing, then an error will be raised and
-- the program will not run.  The values here, both address and port, will
-- become the default values if not specified in the hosts block.
--
-- WARNING:  beware of using a default address and binding to specific
-- addresses in some hosts---either use the default address only, or specify
-- an address for every host.  Trying to mix the two may lead to anger, and
-- anger leads to hate, and hate leads to suffering.  Don't be lead to
-- suffering.
--
-- You have been warned.
-- ************************************************************************

address = "[::]:1965"

-- ************************************************************************
-- CGI definition block, optional, global, host, or filesystem handler,
-- no default values
--
-- Any file found with the executable bit set is considered a CGI script and
-- will be executed as such.  This module implements the CGI standard as
-- defined in RFC-3875.  The script will be executed, and any output will be
-- sent to the Gemini client.  The following environment variables will be
-- defined:
--
-- GEMINI_DOCUMENT_ROOT   Top level directory of site
-- GEMINI_SCRIPT_FILENAME The full path of the script being run
-- GEMINI_URL_PATH        The path portion of the URL
-- GEMINI_URL             The full URL of the request
-- GATEWAY_INTERFACE      Will be set to "CGI/1.1"
-- PATH_INFO              May be set (see RFC-3875 for details)
-- PATH_TRANSLATED        May be set (see RFC-3875 for deatils)
-- QUERY_STRING           Will be set to the passed in query string, or ""
-- REMOTE_ADDR            IP address of the client
-- REMOTE_HOST            IP address of the client (allowed in RFC-3875)
-- REQUEST_METHOD         "", as there are no requests types
-- SCRIPT_NAME            Name of the script per the URL path
-- SERVER_NAME            Domain
-- SERVER_PORT            Server connection port number
-- SERVER_PROTOCOL        Will be set to "GEMINI"
-- SRVER_SOFTWARE         Will be set to "GLV-1.12556/1"
--
-- AUTH_TYPE              If client certificate, set to "Certificate"
-- REMOTE_USER            If client certificate, set to the subject CN
--
-- In addition, scripts written for a webserver can also be used.  If such
-- scripts are used, addtional headers will be set:
--
-- REQUEST_METHOD         Will be changed to "GET"
-- SERVER_PROTOCOL        Will be changed to "HTTP/1.0"
-- HTTP_ACCEPT            Will be set to "*/*"
-- HTTP_ACCEPT_LANGUAGE   Will be set to "*"
-- HTTP_CONNECTION        Will be set to "close"
-- HTTP_REFERER           Will be set to ""
-- HTTP_USER_AGENT        Will be set to ""
--
-- Also, if HTTP based CGI scripts expect Apache-specific headers to be set,
-- those too can be specified and the following will be set:
--
-- DOCUMENT_ROOT          Will be set to the top level directory being served
-- CONTEXT_DOCUMENT_ROOT  Will be set to the top level directory begin served
-- CONTENT_PREFIX         Will be set to ""
-- SCRIPT_FILENAME        The full path of the script being run
--
-- If a certificate is required to run the script, and if it is so desired,
-- the following environment variables can be set:
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
-- Settings can be overwritten per site and per script.
-- ************************************************************************

cgi =
{
  -- -----------------------------------------------------------------
  -- The following variables apply to ALL CGI scripts.  They are all
  -- optional, and do not need to be defined.
  -- -----------------------------------------------------------------
  
  http   = false,  -- (default value) use HTTP specific variables
  apache = false,  -- (default value) use Aapche specific variables
  envtls = false,  -- (default value) include details from TLS certificate
  
  -- ------------------------------------------------------------------
  -- Additional environment variables can be set.  The following list
  -- is probably what would be nice to have (no default values).
  -- ------------------------------------------------------------------
  
  env =
  {
    PATH    = "/usr/local/bin:/usr/bin:/bin",
    LANG    = "en_US.UTF-8",
    SETTING = "global",
  },
  
  -- -----------------------------------------------------------------
  -- The instance block allow you to define values per CGI script
  -- (no default values).
  -- -----------------------------------------------------------------
  
  instance =
  {
    ['^/private/index.gemini$'] =
    {
      envtls = true,        -- we WANT TLS env vars for this
    },
    
    ['^/sampleCGI/.*'] =
    {
      http   = true,
      apache = true,
      env    = -- this is in addition to the ALL CGI env block
      {
        SAMPLE_CONFIG = "sample.conf",
        SETTING       = "global-instance",
      }
    },
  }
}

-- ************************************************************************
-- SCGI definition block, optional, global, host, or filesystem handler,
-- no default values
--
-- Any symbolic link found in the form of 'scgi://hostname:port' or in the
-- form of 'scgi:/path/to/unixsocket' will be treated as a SCGI program,
-- with the server connecting to the hostname on the given port.  This
-- module implements the SCGI standard as defined in
--
-- https://web.archive.org/web/20020403050958/http://python.ca/nas/scgi/protocol.txt
--
-- There's not much there, but I have simplemented the following headers
-- that are sent to the SCGI program:
--
-- CONTENT_LENGTH         Will be set to "0"
-- SCGI                   Will be set to "1"
-- GEMINI_DOCUMENT_ROOT   Top level directory of site
-- GEMINI_SCRIPT_FILENAME The full path of the script being run
-- GEMINI_URL_PATH        The path portion of the URL
-- GEMINI_URL             The full URL of the request
-- PATH_INFO              May be set (see RFC-3875 for details)
-- PATH_TRANSLATED        May be set (see RFC-3875 for deatils)
-- QUERY_STRING           Will be set to the passed in query string, or ""
-- REMOTE_ADDR            IP address of the client
-- REMOTE_HOST            IP address of the client (allowed in RFC-3875)
-- REQUEST_METHOD         "", as there are no requests types
-- SCRIPT_NAME            Name of the script per the URL path
-- SERVER_NAME            Domain
-- SERVER_PORT            Server connection port number
-- SERVER_PROTOCOL        Will be set to "GEMINI"
-- SRVER_SOFTWARE         Will be set to "GLV-1.12556/1"
--
-- AUTH_TYPE              If client certificate, set to "Certificate"
-- REMOTE_USER            If client certificate, set to the subject CN
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
-- If a certificate is required to run the script, and it is so desired, the
-- following environment variables will be set:
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
-- Settings can be overwritten per site and per script.
-- ************************************************************************

scgi =
{
  -- -----------------------------------------------------------------
  -- The following variables will apply to ALL SCGI interfaces.  All are
  -- optional and do not need to be defined.
  -- -----------------------------------------------------------------
  
  http   = false, -- (default value) use HTTP specific variables
  envtls = false, -- (default value) include details from TLS certificate
  
  env =
  {
    SETTING = "global"
  },
  
  instance =
  {
    ['^/private/bar/?.*'] =
    {
      env = { SETTING = "global-instance" },
    }
  }
}

-- ************************************************************************
-- MIME types per extension, optional, global, host, or filesystem handler,
-- no default value.
--
-- Using this will override any MIME types returned by
-- org.conman.fsys.magic.  The host and instance blocks will be mered.
-- ************************************************************************

mime =
{
  json = "application/json",
}

-- ************************************************************************
-- index, no_access, extension, optional, global, host or filesystem
-- handler, default values
--
-- NOTE: The index and extension should be consistent; undefined behavior
--       otherwise.
-- ************************************************************************

index     = "index.gemini"
no_access = { "^%." }
extension = ".gemini"

-- ************************************************************************
-- MIME text/* parameters langauge and charset
-- optional, global, host, cgi, scgi, handler
--
-- The values given here are the assumed defaults if not given and are
-- listed here for documentation purposes only.
--
-- XXX - cascade into cgi and scgi blocks.
-- ************************************************************************

charset  = "utf-8" -- default value
language = "en"    -- default value

-- ************************************************************************
-- Virtual hosts, mandatory, at least one host defined.
-- ************************************************************************

hosts =
{
  ['example.com'] =
  {
    -- -----------------------------------------------------------------
    -- You can specify the address in a few ways:
    --
    -- Nothing, in which case a default address and port are used.
    --
    -- address = 'example.com'
    --                  A hostname can be specified.  The default port
    --                  will be 1965 (although see the above section
    --                  about the default address)
    --
    -- address = 'example.com:21965'
    --                  Set both the host and the port number.
    --
    -- address = ':21965'
    --                  This will use the default address, but change the
    --                  port number.
    --
    -- address = '@'
    --                  This will set the host to the host currently
    --                  being defined.  This is a shortcut to cut down
    --                  on typing (and possibly making a mistake).
    --
    -- address = '@:21965'
    --                  Use the host currently being defined, but specify
    --                  the port number.
    --
    -- address = '192.168.1.10'
    --                  You can specify IP addresses.
    --
    -- address = '192.168.1.10:21965'
    --                  IP address and port number.
    --
    -- address = '[fc00::3]'
    --                  Also IPv6 addresses.
    --
    -- address = '[fc00::3]:21965'
    --                  IPv6 address and port number.
    --
    -- NOTE:    The use of '@' will involve a DNS request to resovle the
    --          address.
    -- -----------------------------------------------------------------
    
    address     = '@',
    certificate = "cert-example.com.pem",  -- mandatory
    keyfile     = "key-example.com.pem",   -- mandatory
    
    -- ********************************************************************
    -- MIME types.  The global setting is merged in with this.
    -- ********************************************************************
    
    mime =
    {
      gmi = 'text/gemini',
    },
    
    -- ********************************************************************
    -- Authorization, optional, no default values
    --
    -- Apply authorization to various paths.  The path patterns are applied
    -- in order, and first match wins.
    -- ********************************************************************
    
    authorization =
    {
      {
        -- -----------------------------------------------------------------
        -- If the pattern matches the query path, apply the authrentication
        -- -----------------------------------------------------------------
        
        path   = "^/private",
        
        -- -----------------------------------------------------------------
        -- Additional information about the type of certificate, or how to
        -- request a certificate, to access this material.  This is returned
        -- when Gemini returns a '60' status code.  This is an optional
        -- field with no default.
        -- -----------------------------------------------------------------
        
        message = "Please contact the admin for a certificate for access",
        
        -- ------------------------------------------------------------------
        -- Function to check the certificate.  It's given the issuer
        -- information, the subject information and the broken down request.
        -- ------------------------------------------------------------------
        
        check  = function(issuer,subject,location)
          return location.query
             and issuer.CN == "Conman Laboratories CA"
             and subject.CN
        end,
      },
    },
    
    -- ********************************************************************
    -- Redirect definition block, optional, no default values
    --
    -- Before any handlers or files are checked, requests are filtered
    -- through these redirection blocks.  The temporary block is for
    -- temporary redirects, and the permanent block is for permanent
    -- redirects.  The first element of each entry is the pattern that is
    -- tried against the request, and if matched, the value is served up as
    -- the redirected location.
    --
    -- Pattern captures can be referenced in the value, "$1" will be
    -- replaced with the first such capture, "$2" with the second capture,
    -- and so on.
    --
    -- The gone block is for requests that once existed, but no more.  This
    -- is just a list of patterns to be matched against, any match will
    -- serve up a resource gone status.
    -- ********************************************************************
    
    redirect =
    {
      temporary =
      {
        { '^/example1/(.*)' , "/new-location/$1" } ,
      },
      
      permanent =
      {
        { '^/example2/(contents)/(.*)' , "gemini://example.net/$1/$2" } ,
      },
      
      gone =
      {
        '^/example3(.*)'
      }
    },
    
    -- ********************************************************************
    -- Rewrite block
    --
    -- This will allow you to rewrite URIs internally to the program.  The
    -- pattern and replacement work the same as the redirection block, but
    -- the result is used immedately.  The first match will stop the process.
    --
    -- The example below will rewrite URLs of the form:
    --
    --		http://example.com/~fred/somepath.gemini
    --
    -- to the following:
    --
    --		http://exampoe.com/users/fred/somepath.gemini
    --
    -- This is useful in case a redirection isn't wanted, or some tricky
    -- URI usage is required for a custom module.
    -- ********************************************************************
    
    rewrite =
    {
      { "^/~([^/]+)(/?.*)" , "/users/$1$2" },
    },
    
    -- ********************************************************************
    -- Handlers, mandatory, at least one handler defined
    --
    -- These handle all requests, and are used after all redirections are
    -- checked.  The configuration options are entirely dependant upon the
    -- handler---the only required configuration options per handler are the
    -- 'path' field and the 'module' field, which defines the codebase for
    -- the handler.  The handlers can be defined in any order.  At runtime,
    -- the longest match wins.
    -- ********************************************************************
    
    handlers =
    {
      -- ----------------------
      -- Sample handler code.  Only here to show the skeleton
      -- of a handler.  Can be safely removed.
      -- ----------------------
      
      {
        path   = '/sample',
        module = "GLV-1.handlers.sample",
      },
      
      -- --------------------------------------
      -- A handler to serve up content when a file is just too much overhead
      -- ------------------------------------
      
      {
        path    = "/favicon.txt",
        module  = "GLV-1.handlers.content",
        mime    = "text/plain; charset=utf-8", -- optional, default value
        content = "👽",                         -- mandatory
      },
      
      -- ------------------------------------
      -- A handler to serve up a single file
      -- ------------------------------------
      
      {
        path      = '/motd',
        module    = "GLV-1.handlers.file",
        file      = "/etc/motd", -- mandatory
        extension = ".gemini",   -- optional, default value
        mime      = "text/plain" -- optional, if GNU magic can't determine type
      },
      
      -- ----------------------------------------------------------------
      -- Handles public user directories
      -- NOTE:  The prefix is used when a redirection is required.  The
      --	text supplied is used instead of the path.
      -- ----------------------------------------------------------------
      
      {
        path      = '/users',
        module    = "GLV-1.handlers.userdir",
        directory = "public_gemini", -- optional, default value
        index     = "index.gemini",  -- optional, default value
        extension = ".gemini",       -- optional, default value
        prefix    = "/~",            -- optional, defaults to path
        no_access = -- optional, see below
        {
          "^%.",  -- no to any dot files
        },
      },
      
      -- --------------------------------------
      -- Handles requests from a directory.
      -- --------------------------------------
      
      {
        path      = "/",
        module    = "GLV-1.handlers.filesystem",
        directory = "/var/example.com/share",
        index     = "index.gemini", -- optional, default value
        extension = '.gemini',      -- optional, default value
        mime      =
        {
          gmi  = 'text/plain',
          rss  = false,
          atom = 'application/atom+xml',
        },
        
        -- -----------------------------------------------------------------
        -- Optional, filter out filenames with the following patterns.  If
        -- not given, then by default, filter out files starting with a '.'
        -- -----------------------------------------------------------------
        
        no_access = -- optional
        {
          "^%.",  -- no to any dot files
        },
      },
    },
    
    -- ********************************************************************
    -- We can override the CGI settings per host.  If you don't want a host
    -- to use CGI, just set this field to false.
    -- ********************************************************************
    
    cgi =
    {
      -- ------------------------------------------------------------
      -- We can add some additional environment variables or overwrite
      -- some previously set variables.
      -- -------------------------------------------------------------
      
      env =
      {
        TZ      = "America/New York",     -- set one
        PATH    = "/var/example.com/bin", -- override
        SETTING = "host",
      },
      
      instance =
      {
        ['^/private/foo2/?.*'] =
        {
          env =
          {
            LD_PRELOAD = "/var/example.com/lib/debug.so",
            SETTING    = "host-instance",
          },
        },
        
        ['.*'] =
        {
          http   = true,
          apache = true,
        },
      },
    },
  },
  
  -- ********************************************************************
  -- We can override SCGI settings per host.  If you don't want a host to
  -- use SCGI, just set this field to false.
  -- ********************************************************************
  
  scgi =
  {
    env = { SETTING = 'host' },
    instance =
    {
      ['^/private/bar2/?.*'] =
      {
        env    = { SETTING = 'host-instance' },
        envtls = true,
      }
    }
  },
  
  -- ********************************************************************
  -- An example of a second host that does NOT support CGI.
  -- ********************************************************************
  
  ['example.org'] =
  {
    address     = '@',
    certificate = "cert-example.org.pem",
    keyfile     = "key-example.org.pem",
    
    cgi      = false,
    scgi     = false,
    handlers =
    {
      {
        path      = "/",
        module    = "GLV-1.handlers.filesystem",
        directory = "/var/exmple.org/share",
        language  = "en-US",
        charset   = "us-ascii",
      }
    }
  }
}
