# triggerbot-roblox

`Triggerbot.lua` combines triggerbot, camlock, ESP and settings controls.
By default, Q toggles camlock, T toggles ESP, and Right Shift opens the
settings menu. These keys can be rebound in the Aimbot tab.
Drag the menu by its title bar to reposition it. When target stats are visible,
they can also be dragged while the menu is open.

The scrollable settings pages include team and wall checks, aim prediction,
target indicators, ESP styles, movement controls, and camera and lighting
effects. Flight uses WASD, Space and Ctrl. Speed, flight, visual effects and
prediction are disabled by default; the triggerbot and checks are enabled.
Use the prediction toggle and enter a custom lead time from 0 to 1 second in
the Aimbot tab. Its FOV toggle removes the targeting limit and hides the circle.
The FOV circle can also be hidden separately in the Visuals tab.

The triggerbot compatibility scan can kick the player if it finds no supported
tool. Disabling the triggerbot or compatibility scan cancels pending scans;
re-enabling either allows scans on the next character spawn.

For mock-based checks, run `lua tests/combined_features.lua` from the repository
root. These checks do not replace testing inside Roblox.