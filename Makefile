
.PHONY: luacheck clean

luacheck:
	luacheck Lua/*.lua

clean:
	$(RM) $(shell find . -name '*~')
