/***************************************************************************
*
*   POSIX pipe() interface (to avoid C stdlib)
*   Copyright (C) 2019 by Sean Conner.
*
*   This program is free software: you can redistribute it and/or modify
*   it under the terms of the GNU General Public License as published by
*   the Free Software Foundation, either version 3 of the License, or
*   (at your option) any later version.
*
*   This program is distributed in the hope that it will be useful,
*   but WITHOUT ANY WARRANTY; without even the implied warranty of
*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*   GNU General Public License for more details.
*
*   You should have received a copy of the GNU General Public License
*   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*
*   Comments, questions and criticisms can be sent to: sean@conman.org
*
****************************************************************************/

#define _GNU_SOURCE

#include <stdio.h>
#include <errno.h>

#include <unistd.h>
#include <fcntl.h>

#include <lua.h>
#include <lauxlib.h>

#define TYPE_FD	"org.conman.application.gemini:FD"

/**************************************************************************/

static int fd___gc(lua_State *L)
{
  close(*(int *)lua_touserdata(L,1));  
  return 0;
}

/**************************************************************************/

static int fd___tostring(lua_State *L)
{
  lua_pushfstring(L,"fd%d",*(int *)lua_touserdata(L,1));
  return 1;
}

/**************************************************************************/

static int fd__tofd(lua_State *L)
{
  lua_pushinteger(L,*(int *)luaL_checkudata(L,1,TYPE_FD));
  return 1;
}

/**************************************************************************/

static int fd_read(lua_State *L)
{
  luaL_Buffer  buf;
  char        *buffer;
  ssize_t      size;
  
  lua_settop(L,1);
  buffer = luaL_buffinitsize(L,&buf,BUFSIZ);
  size   = read(*(int *)luaL_checkudata(L,1,TYPE_FD),buffer,BUFSIZ);
  if (size < 1) size = 0;
  luaL_pushresultsize(&buf,size);
  return 1;
}

/**************************************************************************/

static int makepipe(lua_State *L)
{
  int fd[2];
  int *fdread;
  int *fdwrite;
  
  lua_createtable(L,0,2);
  fdread  = lua_newuserdata(L,sizeof(int));
  *fdread = -1;
  luaL_getmetatable(L,TYPE_FD);
  lua_setmetatable(L,-2);
  lua_setfield(L,-2,"read");
  
  fdwrite  = lua_newuserdata(L,sizeof(int));
  *fdwrite = -1;
  luaL_getmetatable(L,TYPE_FD);
  lua_setmetatable(L,-2);
  lua_setfield(L,-2,"write");
  
  if (pipe(fd) == -1)
  {
    lua_pushnil(L);
    lua_pushinteger(L,errno);
    return 2;
  }
  
  if (
       (fcntl(fd[0],F_SETFL,O_NONBLOCK) == -1) ||
       (fcntl(fd[1],F_SETFL,O_NONBLOCK) == -1)
     )
  {
    lua_pushnil(L);
    lua_pushinteger(L,errno);
    close(fd[0]);
    close(fd[1]);
    return 2;
  }    
  
  *fdread  = fd[0];
  *fdwrite = fd[1];
  
  return 1;
}

/**************************************************************************/

static luaL_Reg const m_fdmeta[] =
{
  { "__gc"       , fd___gc       } ,
  { "__tostring" , fd___tostring } ,
  { "_tofd"      , fd__tofd      } ,
  { NULL         , NULL          }
};

static luaL_Reg const m_fdmetashadow[] =
{
  { "close" , fd___gc  } ,
  { "read"  , fd_read  } ,
  { NULL    , NULL     }
};

int luaopen_makepipe(lua_State *L)
{
  luaL_newmetatable(L,TYPE_FD);
  luaL_setfuncs(L,m_fdmeta,0);
  luaL_newlib(L,m_fdmetashadow);
  lua_setfield(L,-2,"__index");
  
  lua_pushcfunction(L,makepipe);
  return 1;
}
