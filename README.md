# WoW Forever Addons

**GuildWave** adds a movable list for greeting nearby players in WoW Forever (interface 16001).

## Install GuildWave

Copy the `GuildWave` folder into the Forever client's `_forever_/Interface/AddOns/` directory. The manifest should be at `_forever_/Interface/AddOns/GuildWave/GuildWave.toc`.

On macOS, run `make install-guildwave` from the repository root to install or update it in `/Applications/World of Warcraft/_forever_/Interface/AddOns/GuildWave/`. For a custom install, pass `WOW_FOREVER_ADDONS_DIR="/path/to/_forever_/Interface/AddOns"`.

Restart Forever after a first install or run `/reload` after updating.

## Use GuildWave

- **Guild** shows members of your own guild whom the client exposes on visible nameplates. Enable friendly nameplates in the game's options. Left-click defaults to Wave.
- **Party/Raid** shows nearby group members using accessible group range and nameplate data. Left-click defaults to Dance.
- **Anyone** shows any friendly player on a visible nameplate, including players without a guild.
- **Other Guild** shows friendly players on visible nameplates who match the full guild name you enter in **Other Guild → Guild name → Edit** in GuildWave's Options. The name and last selected view are saved per character.
- **Right-click the window header or background** to change views. Right-click a name and choose **Target** to select that player while out of combat. The menu also offers Wave, Dance, Say hello, Cheer, Salute, Say thanks, Fart, Whistle, Chicken, and Whisper. Whisper opens a draft addressed to that player.
- Player rows, exact-name targeting, and whisper drafts use the full Forever character name, with a space between the first name and surname.
- **Options** opens the current view's settings. Set a separate left-click action for Guild, Party/Raid, Anyone, and Other Guild. Anyone and Other Guild share Guild's right-click menu and list limit. The limit starts at six names and supports 1–12. Settings and window position are saved per character.
- **Pin selected target to top** in Options gives the player or NPC you've selected its own row above the nearby-name limit in every view. The row changes when you select someone else and disappears when you clear your target. A target with a restricted identity may appear with its actions unavailable. Use `/guildwave debug` to check the pin setting and selected target status.

Drag the header to move the panel. As rows appear, the window grows downward from that position. Use the mouse wheel to reach more rows when the list reaches the bottom of the screen. Use `/guildwave` to toggle the window, `/guildwave options` to open the current view's options, or `/guildwave guild`, `/guildwave group`, `/guildwave anyone`, and `/guildwave other Guild Name` to open a view.

Left-click the GuildWave minimap button to toggle the panel and right-click it for Options. MinimapButtonButton can collect it automatically. To include it manually, run `/mbb include GuildWaveMinimapButton`.

If the list is empty, switch to **Anyone** and click **Enable friendly player nameplates** if the button appears. Type `/guildwave debug` near a friendly player to see the setting, the number of nameplates the client exposed, and why any units were skipped.

Debug logging is off by default. `/guildwave debug` prints a one-time scan in chat. Turn on **Save debug reports** in GuildWave's main Options category or use `/guildwave debug on` to save diagnostics. While enabled, GuildWave keeps the latest manual and shutdown snapshots in the character's `WTF/Account/<account>/<realm>/<character>/SavedVariables/GuildWave.lua` under `GuildWaveDB.debugReports`. A Target report includes the command, observed client calls or errors, and the immediate and delayed selection results. `/guildwave debug off` clears the reports from SavedVariables on the next reload or logout.

## Validate

Run `make validate-forever-addons` with Lua on your PATH for syntax, discovery, and action checks. Follow the [manual validation checklist](VALIDATION.md) for checks that require the game.
