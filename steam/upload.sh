#!/usr/bin/env bash
# Push the staged depot content to Steam via SteamPipe (local fallback; the
# usual path is the "Steam Deploy" GitHub Action, .github/workflows/steam-deploy.yml).
#
# Usage: STEAM_USER=<login> steam/upload.sh
#
# First time on a machine: run `steamcmd +login <login>` yourself once to
# cache the session (password + Steam Guard prompt). Uploads never
# auto-publish (SetLive is empty) — set the build live on 'default' in
# Steamworks > SteamPipe > Builds.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
: "${STEAM_USER:?set STEAM_USER=<steam login>}"

if [[ ! -d "$HERE/content/all" || ! -d "$HERE/content/macos" ]]; then
    echo "error: no staged content — run steam/stage.sh <release-tag> first" >&2
    exit 1
fi

steamcmd +login "$STEAM_USER" +run_app_build "$HERE/scripts/app_build.vdf" +quit

echo "== Uploaded. Review and set live on 'default':"
echo "   https://partner.steamgames.com/apps/builds/4980570"
