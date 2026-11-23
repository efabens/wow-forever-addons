WOW_FOREVER_ADDONS_DIR ?= /Applications/World of Warcraft/_forever_/Interface/AddOns
GUILDWAVE_INSTALL_DIR := $(WOW_FOREVER_ADDONS_DIR)/GuildWave

.PHONY: validate-forever-addons install-guildwave

validate-forever-addons:
	test -f GuildWave/GuildWave.toc
	lua -e 'assert(loadfile("GuildWave/Core.lua")); assert(loadfile("GuildWave/UI.lua"))'
	lua tests/guildwave.lua

install-guildwave:
	@test -d "$(WOW_FOREVER_ADDONS_DIR)" || { echo "Forever AddOns folder not found: $(WOW_FOREVER_ADDONS_DIR)" >&2; exit 1; }
	mkdir -p "$(GUILDWAVE_INSTALL_DIR)"
	install -m 644 GuildWave/GuildWave.toc GuildWave/Core.lua GuildWave/UI.lua "$(GUILDWAVE_INSTALL_DIR)/"
	@echo "Installed GuildWave in $(GUILDWAVE_INSTALL_DIR)"
