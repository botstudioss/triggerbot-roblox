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
The existing triggerbot compatibility scan can kick the player if it finds no
supported tool. Disable the triggerbot before the scan completes to skip it.

For mock-based checks, run `lua tests/combined_features.lua` from the repository
root. These checks do not replace testing inside Roblox.