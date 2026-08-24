# Official Steam Input layouts

Ships the official default controller layouts with the game. The release
workflow copies this folder into every release archive, so it lands in the
Steam depots unchanged (`<install dir>/steam_input/`). Steamworks >
Application > Steam Input > Default Controller Configuration is set to
"Custom Configuration" with the path `steam_input/action_manifest.vdf`.

## Updating the Steam Deck layout

1. On the Deck, tweak the layout in Game Mode as usual (game page >
   controller icon).
2. Switch to Desktop Mode, open Konsole, and run:

   ```bash
   steam "steam://dumpcontrollerconfig?appid=4980570"
   ```

   Steam writes the currently-applied layout VDF(s) into `~/Documents`.
3. Copy the Deck layout over `controller_neptune.vdf` in this folder,
   commit, and cut a release — the next Steam build carries it.

To add layouts for other controller types (Xbox, PS, Switch), dump them the
same way on a machine with that pad and add an entry under `configurations`
in `action_manifest.vdf` (`controller_xboxone`, `controller_ps4`,
`controller_switch_pro`, ...). Slot `"0"` per type is the default; higher
slots show as extra official layouts the player can pick.
