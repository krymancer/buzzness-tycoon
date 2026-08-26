# Steamworks redistributables

Drop the Steamworks SDK's `redistributable_bin/` contents here and commit them:

```
steam/redist/linux64/libsteam_api.so
steam/redist/win64/steam_api64.dll
steam/redist/osx/libsteam_api.dylib
```

The release workflow (`.github/workflows/build.yml`) bundles each one next
to its binary, `steam/stage.sh` does the same for local depots, and the game
(`src/steam.zig`) loads it at runtime — from its own folder in shipped builds,
from here when run from the repo root (`just steam-dev`). Missing files only
mean achievements stay local (no Steam unlocks); the game still runs.

Keep the SDK version in sync with `SteamAPI_SteamUserStats_v0NN` accessors
tried in `src/steam.zig` (v011–v013 today).

## Current files

Valve's unmodified redistributables (SDK 1.6x: `SteamAPI_InitFlat`,
`ISteamUserStats` v013), taken from the Steamworks.NET 2025.164.1 standalone
release (`OSX-Linux-x64/`, `Windows-x64/`) because the partner-site SDK
download needs a login. Swapping in the same files from the official SDK zip
is a drop-in replacement.
