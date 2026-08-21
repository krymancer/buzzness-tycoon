# Buzzness Tycoon

Buzzness Tycoon is a simple game that I'm working on to learn Zig and have an excuse to use raylib.

## Concept

A chill, cozy idle game. On an isometric floating meadow, bees drift between flowers gathering pollen and carrying it back to the hive to make honey. Spend honey in the shop and upgrade tree to unlock faster bees, bigger grids, labs, and prestige — then sit back and watch the little world hum along.

## Ambience & feel

The meadow is meant to be relaxing to leave running:

- **Day/night cycle** — a slow (~5 min) dawn → day → dusk → night loop with a gradient sky, drifting clouds, a rising/setting sun, a soft moon and a twinkling star field. The whole scene is lit by the current time of day.
- **A living world** — bees bob and buzz with soft shadows, flowers sway in the breeze and cast shadows, the hive gently breathes, and pollen-laden bees glow.
- **Fireflies** — daytime pollen dust warms into glowing fireflies at night.
- **Procedural audio** — a gentle synthesized music-box loop plus soft pentatonic chimes when honey is delivered. No sample assets; it's all generated at startup.

## Controls

- **Mouse** — drag to pan, scroll to zoom, click tiles/flowers/bubbles to interact, use the side panel to buy.
- **B / M** — activate Burst / Bloom labs (once unlocked).
- **N** — mute / unmute audio.
- **Esc** — close popups / open the pause menu.
- **Alt+Enter** — toggle fullscreen.
- **Cmd/Ctrl + / − / 0** — grow / shrink / reset the UI scale (saved with your progress). The UI also auto-scales to the screen, so text stays readable on large and Retina displays.

The game autosaves every 10 seconds and whenever it is paused or closed. Save
data is stored in the platform user-data directory so Steam installs and game
updates do not overwrite progress.

English and Brazilian Portuguese are included. The initial language follows
the system locale, and can be changed from the title screen or pause menu.

Dev/debug env vars: `BT_WINDOWED=1` launches in a window instead of fullscreen; `BT_AUTOPLAY=1` skips the title screen; `BT_LANG=pt-BR` overrides locale detection; `BT_SAVE_PATH=/path/to/save.txt` overrides the save location; `BT_PHASE=0..1` freezes the time of day; `BT_SHOOT=N` renders N frames, writes `bt_shot.png`, then exits; `BT_UI_SCALE=X` pins the UI scale factor (in framebuffer pixels), bypassing auto-fit and the saved preference.

## Screenshot

![Buzzness Tycoon Screenshot](.github/game.png)

## Build

Requires **Zig 0.16** (uses `raylib-zig` 6.0.0).

You can use debug for vscode if you have the C/C++ extension. 

Or if you have Zig installed:

```shell
zig build run # this will build and run the project
```

Or: 

```shell
zig build 
./zig-out/bin/buzzness-tycoon.exe # or only buzzness-tycoon if in unix
```
