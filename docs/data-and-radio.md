# Public data and radio discovery

Nearby is an independent Lua app. It does not patch X Dex or replace Solana OS.

## Badge ID to X profile

1. `mesh.nearby()` reads the OS's nearby-peer table. Nearby keeps `kind="badge"`
   entries and excludes its own ID and beacons.
2. `profile.get(badgeId, callback)` resolves the badge owner's linked X handle,
   public display name and level through Solana OS. A radio nickname is not
   treated as an authenticated X identity. Wallet fields are ignored.
3. `GET https://api.fxtwitter.com/2/profile/<handle>?about_account=0` retrieves public X name,
   biography, website and avatar URL without an API key. The documented parameter
   disables unnecessary about-account data. If that route returns
   HTTP or JSON code `404`, `405` or `501`, the app tries the same provider's
   legacy `GET https://api.fxtwitter.com/<handle>` route once. Other errors do
   not trigger this fallback. Both responses use the same validation, including
   a matching returned handle when present. FxTwitter is an independent public
   service, not X's official API; it can become unavailable or rate limit requests.
4. The avatar URL, restricted to X's avatar-image hosts, is passed to
   `https://wsrv.nl/` with `w=24&h=24&fit=cover&output=gif&encoding=base64&n=1`.
   This public image service returns a small ASCII data URL. The Lua decoder
   produces a 24×24 image with at most 64 colours. No image API key or custom
   backend is needed.

The supported Lua wrapper maps `profile.get(id, cb)` to
`GET /api/device/apps/nearby/profile/<badgeId>` and `profile.me(cb)` to
`GET /api/device/apps/nearby/profile`. The OS supplies its device authentication;
the app contains no token. Native X Dex separately uses `/api/device/xdex` and
`/api/device/me`; Nearby uses the documented public-profile wrapper instead of
depending on X Dex's private collection layout.

Solana OS sends HTTP requests through its server with the fixed upstream
`User-Agent: SolanaOS-Badge/1`; apps cannot override it. During integration,
unparameterized v2 returned `404`, while the primary route with
`?about_account=0` and the legacy route each returned `200` in two official SDK
proxy probes. Provider availability can still vary. The fallback uses public
keyless routes and retains the normal permission and rate checks.

Solana OS HTTP responses are UTF-8 text, capped at about 3.5 KB. Raw binary PNG
downloads cannot be used as image sources by this Lua API. The base64 GIF route
fits that transport; truncated responses and malformed images are rejected.
Requests are serialised and the app temporarily gives the radio back to Wi-Fi
when necessary, then resumes discovery. A failed Wi-Fi attempt backs off.

Public metadata and thumbnail caches are bounded and live only in app RAM.
Closing Nearby discards them. The app does not write an encounter history,
profiles, faces, locations or credentials to its storage, and sends no custom
profile messages over the mesh. Public handles reach FxTwitter; avatar URLs
reach wsrv. Solana OS proxies these HTTPS requests and attaches its documented
standard badge/app authentication headers. The public source and package contain
only code, branding and synthetic test fixtures.

## Which powered badges can be found?

The OS broadcasts ordinary HELLO presence messages every 1.5–2.5 seconds when
it has an assigned badge ID and its radio is on the mesh channel. Those messages
are independent of the current app: the other person does not need to open X Dex
or install Nearby. The Lua API exposes up to 16 nearby peers and the OS expires
unheard peers after 30 seconds.
HELLO IDs and labels are untrusted radio claims. A server-linked X profile does
not cryptographically prove who is transmitting a nearby HELLO.

This is ESP-NOW, not a Bluetooth scan. It cannot discover arbitrary phones or
Twitter accounts without badges. A badge joined to Wi-Fi on another channel,
paused, scanning or otherwise off the mesh channel may not be heard. LEFT scans
both supported channel bands and can switch Nearby to a channel where badges
were heard; other devices are not reconfigured.

RSSI is refreshed once a second in the UI and smoothed with an exponential
average. HOTTER/COLDER compares signal over approximately five seconds.
Qualitative proximity bands are estimates: walls, bodies, antennas, band and
orientation change the signal. They are not calibrated metres or GPS. Bridged
internet peers, missing peers and paused/scanning radio states never get a
physical-distance claim.

## Primary references

- [Solana OS Lua API](https://solana.com/breakpoint/badge/apps/docs)
- [HTTP headers and proxy contract](https://github.com/solana-foundation/solana-os/blob/main/docs/LUA_API.md#L1023)
- [Native profile and HTTP wrappers](https://github.com/solana-foundation/solana-os/blob/main/main/lua/lua_net.c)
- [Radio and networking guide](https://solana.com/breakpoint/badge/apps/docs/connectivity)
- [Native mesh implementation](https://github.com/solana-foundation/solana-os/blob/7c22c44d8db16dd8c6f90d5f61ead8eba055b973/main/core/os_mesh.c)
- [FxTwitter profile endpoint](https://docs.fxembed.com/api/twitter/operations/2profilehandle/)
- [FxEmbed legacy API route](https://github.com/FxEmbed/FxEmbed/blob/main/src/realms/api/router.ts#L103)
- [wsrv base64 output](https://wsrv.nl/docs/format#base64-data-url-encoding-base64)
