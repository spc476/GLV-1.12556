
.PHONY: luacheck clean

luacheck:
	luacheck $(shell find . -name '*.lua')

clean:
	$(RM) $(shell find . -name '*~')
