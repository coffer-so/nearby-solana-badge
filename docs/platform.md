# Solana OS reference

Reviewed 2026-11-16 against official upstream commit
[`7c22c44d8db16dd8c6f90d5f61ead8eba055b973`](https://github.com/solana-foundation/solana-os/tree/7c22c44d8db16dd8c6f90d5f61ead8eba055b973).
These sources describe the platform; source documents do not grant permission to
change firmware or unrelated apps.

## Nearby and profiles

[`docs/LUA_API.md`](https://github.com/solana-foundation/solana-os/blob/7c22c44d8db16dd8c6f90d5f61ead8eba055b973/docs/LUA_API.md)
documents `mesh.nearby()`, `mesh.info()`, `mesh.pause()` / `mesh.resume()`,
`profile.me(cb)`, `profile.get(badgeId, cb)` and host-allowlisted `http`.

`mesh.nearby()` exposes at most 16 entries to Lua: `id`, `name`, `level`, `rssi`,
`kind` and `bridged`. Bridge entries are not physical proximity measurements.
`profile.get` returns the owner's public profile; a linked Solana address is
omitted unless its owner made it public. Profiles never expose an email or wallet
private key. Mesh presence alone is not verified identity.

The native
[X Dex app](https://github.com/solana-foundation/solana-os/blob/7c22c44d8db16dd8c6f90d5f61ead8eba055b973/main/apps/xdex/xdex_app.c)
uses the same OS peer table and filters badge peers. No documented Lua API opens
X Dex's internal collection directly. Opening a mesh app may suspend Wi-Fi if it
is joined on a different radio channel; profile requests require network access.

## Wi-Fi and console

The official
[console source](https://github.com/solana-foundation/solana-os/blob/7c22c44d8db16dd8c6f90d5f61ead8eba055b973/main/core/console.c)
supports `wifi status`, `wifi on`, `wifi off`, `wifi connect` and `wifi forget`.
There is no `wifi scan` console command. Saved network credentials stay in the OS;
the Nearby app/package contains none.

For a scan without deleting saved credentials, close the Lua app with `open home`,
run `wifi off`, then `open wifi`. The
[native Wi-Fi app](https://github.com/solana-foundation/solana-os/blob/7c22c44d8db16dd8c6f90d5f61ead8eba055b973/main/apps/wifi/wifi_app.c)
scans 2.4 and 5 GHz on entry; RIGHT rescans. A busy/start failure retries after
1.5 seconds. Completion is event-driven and the app does not impose a scan timeout.
Hidden networks require their exact SSID through the native console connection
command. Do not commit credentials, network screenshots or console output.

The documented upload protocol is `lua recv`, acknowledged in base64 blocks,
followed by `lua sums` SHA-256 verification. The helper keeps all write/run commands
scoped to app ID `nearby`. Firmware is an external prerequisite, not part of this
project's upload.
