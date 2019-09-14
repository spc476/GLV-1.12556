#########################################################################
#
# Copyright 2019 by Sean Conner.  All Rights Reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation; either version 3 of the License, or (at your
# option) any later version.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this library; if not, see <http://www.gnu.org/licenses/>.
#
# Comments, questions and criticisms can be sent to: sean@conman.org
#
########################################################################

CC      = gcc -std=c99
CFLAGS  = -g -Wall -Wextra -pedantic
LDFLAGS = -g -shared

override CFLAGS += -fPIC

INSTALL         = /usr/bin/install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA    = $(INSTALL) -m 644

prefix          = /usr/local
datarootdir     = $(prefix)/share
exec_prefix     = $(prefix)
bindir          = $(exec_prefix)/bin
libdir          = $(exec_prefix)/lib

LUA             ?= lua
LUA_VERSION     := $(shell $(LUA) -e "print(_VERSION:match '^Lua (.*)')")
LUADIR          ?= $(datarootdir)/lua/$(LUA_VERSION)
LIBDIR          ?= $(libdir)/lua/$(LUA_VERSION)
BINDIR          ?= $(exec_prefix)/bin

ifneq ($(LUA_INCDIR),)
  override CFLAGS += -I$(LUA_INCDIR)
endif

# ===================================================

%.so : %.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

# ===================================================

.PHONY: all luacheck clean install uninstall

all:	Lua/GLV-1/getuserdir.so

luacheck:
	luacheck $(shell find . -name '*.lua')

clean:
	$(RM) $(shell find . -name '*~')
	$(RM) $(shell find . -name '*.so')

install: Lua/GLV-1/getuser.so
	$(INSTALL) -d $(DESTDIR)$(LIBDIR)/GLV-1
	$(INSTALL) -d $(DESTDIR)$(LUADIR)/GLV-1
	$(INSTALL) -d $(DESTDIR)$(LUADIR)/GLV-1/handlers
	$(INSTALL) -d $(DESTDIR)$(BINDIR)
	$(INSTALL_DATA)    Lua/GLV-1/*.lua          $(DESTDIR)$(LUADIR)/GLV-1
	$(INSTALL_DATA)    Lua/GLV-1/handlers/*.lua $(DESTDIR)$(LUADIR)/GLV-1/handlers
	$(INSTALL_PROGRAM) Lua/GLV-1/*.so           $(DESTDIR)$(LIBDIR)/GLV-1
	$(INSTALL_PROGRAM) Lua/GLV-1.12556.lua      $(DESTDIR)$(BINDIR)/GLV-1.12556

uninstall:
	$(RM) -r $(DESTDIR)$(LUADIR)/GLV-1
	$(RM) -r $(DESTDIR)$(LIBDIR)/GLV-1
	$(RM) -r $(DESTDIR)$(BINDIR)/GLV-1.12556
