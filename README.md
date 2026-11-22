# triggerbot-roblox

Only startup and Camlock events produce notifications. Invalid keybinds and
prediction values are shown in the settings menu.
With the menu closed, hold left-click over an eligible player to use the
triggerbot. Revolver shots are limited to 200 studs and shotgun shots to 75
studs; unsupported weapon or game behavior can still prevent firing.

In **Player > Movement**, set speed from 0 to 200 studs per second and toggle
it with G by default. The speed key can be rebound in the same section. Games
may override or reject client-side speed changes.

In the free version's **Aimbot > Camlock player selection**, select one or more
players and enable **Selected players only**. Camlock chooses the closest
eligible selected player to the cursor, subject to its FOV, wall and team
checks. An empty selection locks nobody. This does not filter other aim modes;
selections are saved with configs and remain selected if a player rejoins.

In the **Config** tab, click the name field, enter a name and save, or select a
saved config on the right and click Load. Saving an existing name replaces it.
**Export JSON** saves the selected config as `Azure_Public_Export_<name>.json`
or `Azure_Paid_Export_<name>.json` in the executor workspace; repeated exports
get numbered filenames. To import, put a JSON file in
that workspace, enter its filename and a config name, and click **Import JSON**;
an existing config with that name is replaced. Import files from the same
script edition. Use Refresh list to reload the saved names. The executor must
provide `isfile`, `writefile` and `readfile`; errors are shown in the menu.
The files are `Azure_Public_Config.json` and `Azure_Paid_Config.json` in the
executor's file workspace. Existing single configs appear as `Default`.
Loading may partially apply settings if a feature
cannot be enabled in the current game or executor.

The **Aim modes** tab adds a separate camera aimbot and experimental Silent Aim.
Both have independent FOV radii, circles, limits, target parts, team checks and
wall checks. The camera aimbot uses E by default, supports hold or toggle mode,
and yields to an active Camlock. Both modes use the prediction settings on the
Aimbot tab.

Silent Aim supports selectable `Mouse.Hit/Target` and `Workspace:Raycast`
methods, requires executor hook APIs, and only redirects while a tool is
equipped and the menu is closed. Raycast mode can affect non-weapon game rays.
Neither method has been verified in Z ZHD or DAS HOODS; games that send target
positions through other interfaces or validate shots on the server may not
work. Unsupported hook APIs are reported in the menu.
Some Xeno versions may lack these APIs; the menu identifies the missing one
and keeps Silent Aim off rather than claiming it is working.

The experimental **Z ZHD** Silent Aim method instead enables the game's
client aim-lock attributes; it does not need executor hooks. Select the method,
turn Silent wall and team checks off, keep the Silent FOV limit enabled at 50
or more, and enable Silent Aim. The game selects targets itself, without
prediction or these checks, and may validate or reject shots on the server.
This method is restricted to Z ZHD and has not been verified in-game. It
activates only with a Revolver, Double-Barrel or Tactical Shotgun equipped and
the menu closed. It restores the attributes it changed when disabled; an existing gamepass or
character aim-lock setting can keep the game's aim lock active independently.

In **Visuals > ESP filters**, enable the distance limit and enter the maximum
distance in studs (1–100000). Enable **ESP named only** to show players listed
by username or display name; separate names with commas. ASCII letter matching
ignores case, and shared display names match multiple players. **Hidden
usernames** always hides those players, even if targeted. Clear a list to remove
its entries. The team check still applies. ESP requires the game to replicate
the player's character to the client and may not work in every game.

The Silent Aim hook approach is adapted from
[Averiias/Universal-SilentAim](https://github.com/Averiias/Universal-SilentAim),
licensed under MIT; the license notice is included in `Triggerbot.lua`.