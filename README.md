# triggerbot-roblox

Only startup and Camlock events produce notifications. Invalid keybinds and
prediction values are shown in the settings menu.
With the menu closed, hold left-click over an eligible player to use the
triggerbot. Revolver shots are limited to 200 studs and shotgun shots to 75
studs; unsupported weapon or game behavior can still prevent firing.

In **Player > Movement**, set speed from 0 to 200 studs per second and toggle
it with G by default. The speed key can be rebound in the same section. Games
may override or reject client-side speed changes.

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
distance in studs (1–100000). Enable **ESP named only** to show only players
listed in **Target usernames**. Enter comma-separated Roblox usernames, not
display names; matching ignores case. **Hidden usernames** always hides those
players from ESP, even if they are targeted. Clear a list to remove its entries.
The existing team check still applies, and these filters affect ESP only.

The Silent Aim hook approach is adapted from
[Averiias/Universal-SilentAim](https://github.com/Averiias/Universal-SilentAim),
licensed under MIT; the license notice is included in `Triggerbot.lua`.