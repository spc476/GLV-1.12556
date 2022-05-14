/***************************************************************************
*
* Get user home directory from the system.
* Copyright 2019 by Sean Conner.
*
* This library is free software; you can redistribute it and/or modify it
* under the terms of the GNU Lesser General Public License as published by
* the Free Software Foundation; either version 3 of the License, or (at your
* option) any later version.
*
* This library is distributed in the hope that it will be useful, but
* WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
* or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
* License for more details.
*
* You should have received a copy of the GNU Lesser General Public License
* along with this library; if not, see <http://www.gnu.org/licenses/>.
*
* Comments, questions and criticisms can be sent to: sean@conman.org
*
*************************************************************************/

#include <sys/types.h>
#include <pwd.h>

#include <lua.h>
#include <lauxlib.h>

static int getuserdir(lua_State *L)
{
  struct passwd *ent = getpwnam(luaL_checkstring(L,1));
  if (ent != NULL)
    lua_pushstring(L,ent->pw_dir);
  else
    lua_pushnil(L);
  return 1;
}

int luaopen_1_getuserdir(lua_State *L)
{
  lua_pushcfunction(L,getuserdir);
  return 1;
}
