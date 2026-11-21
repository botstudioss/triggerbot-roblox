# triggerbot-roblox

Only startup and Camlock events produce notifications. Invalid keybinds and
prediction values are shown in the settings menu.
With the menu closed, hold left-click over an eligible player to use the
triggerbot. Revolver shots are limited to 200 studs and shotgun shots to 75
studs; unsupported weapon or game behavior can still prevent firing.

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

The Silent Aim hook approach is adapted from
[Averiias/Universal-SilentAim](https://github.com/Averiias/Universal-SilentAim),
licensed under MIT; the license notice is included in `Triggerbot.lua`.