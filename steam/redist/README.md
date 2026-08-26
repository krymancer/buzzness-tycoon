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
