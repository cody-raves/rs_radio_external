# rs_radio_external

External media support for `rs_radio`: YouTube (video, playlist and supported
live), SoundCloud, and direct HTTPS audio links.

Install this resource **beside** `rs_radio`. Never copy its files into the base
resource and never overwrite base files.

```cfg
ensure oxmysql
ensure rs_radio
ensure rs_radio_external
```

## What it adds

- Remote music, station ads, product ads and SFX for station programming.
- Listener custom sources: players can point a radio they control at their own
  links. Vehicle, boombox and prop playback stays shared spatial audio for
  everyone nearby; the Walkboy stays personal to its wearer.
- The saved listener library (SQL) and remote queues.
- The three supplied stations — Rebel Radio South, Rebel Radio North and
  SubSonic FM — including their full remote catalogs and product ads.

## How it attaches

On start, the resource checks the base radio's integration API version. If it
matches, it registers a source adapter (server) and a UI module (client), and
installs its station package. If anything does not match, it logs to its own
console and stays detached; the base radio continues as a local-file product.

Stopping this resource stops remote playback; radios return to normal local
operation. When the base restarts, this resource re-attaches automatically.

## Configuration

Everything lives in `config.lua`:

- `Config.YoutubeEnabled` / `Config.SoundCloudEnabled` / `Config.DirectLinksEnabled`
  — per-provider switches.
- `Config.ListenerCustom*` — what ordinary players may play through radios they
  control.
- `Config.ListenerCustomAllowlist` — optional list of links players are limited
  to (YouTube ids/URLs, playlists, SoundCloud tracks, direct URLs or folder
  prefixes). Empty means any supported link; DJ decks and station playlists are
  never filtered.
- `Config.StationPackageEnabled` — auto-install of the supplied stations
  (idempotent, ownership-scoped, never overwrites admin-edited rows).
- `Config.Migration*` — legacy data import (see below).
- `Config.StationControlAcePermission` — ACE permission for the admin command.

## Resolver load handling

Metadata lookups share in-flight work for the same URL. The
`Config.MetadataHydrateTimeoutMs` deadline includes time waiting in the queue
(20 seconds by default). Expired queued work is removed; late provider replies
cannot complete it twice.

The adapter admits up to 1,024 waiting dispatches and processes at most 32 per
worker tick, yielding earlier when a batch has used 2 ms. Metadata has separate
limits of 1,024 pending URLs, 1,024 waiters per URL, and 1,024 cached results.
Excess work receives a busy response instead of growing the queue indefinitely.
Use the matching updated base resource so it handles rejected dispatches
immediately.

YouTube metadata uses oEmbed first, then a single canonical watch-page request.
The parser searches the complete page using literal anchors and limits pattern
matching to 8 KiB field windows, avoiding repeated whole-page pattern scans.

## Supplied stations

`/radioexternalstations` (console or ACE-permitted player):

- `status` — attachment state and owned rows
- `install` — install/reconcile the package
- `remove` — remove only the package-owned stations
- `release` — keep the stations but release package ownership
- `adopt <stationId>` — deliberately take over an edited legacy row

Rows the package installs are stamped with its package id. A station an
administrator created or edited is never modified or removed.

## Migration from all-in-one installs

Runs automatically once (receipts prevent repeats), and never deletes source
data:

- Remote entries in legacy station rows (`music_json`/`ads_json`/`sfx_json`)
  are **copied** into `rs_radio_external_station_media`.
- The saved listener library table is used in place — nothing to convert.
- Browser-local named playlists are imported once per player into
  `rs_radio_external_player_playlists`, through a bridge that can only read the
  single allow-listed playlist key.

## Security notes

- Direct links must be plain `https://` with an audio extension. Credentials in
  the URL, encoded host tricks, and local/private/reserved addresses are
  rejected.
- Direct links are fetched by the requesting player's media player, never by
  the server. If your deployment needs redirect-chain validation, keep
  `Config.DirectLinksEnabled = false` unless links are constrained by a
  trusted validating proxy.
- Raw delivery endpoints (the URLs a resolve step produces) are rejected when
  submitted directly.

## Media compliance

Enabling external integrations does not grant a license to stream, rebroadcast
or download third-party media. The server owner is responsible for complying
with the Cfx Creator Platform License Agreement and the terms of each platform,
and for choosing media appropriate for their server. For the lowest-risk setup,
use the base radio's local files only.

## Troubleshooting

- **"not attaching: rs_radio reports integration api X"** — the two resources
  are from different releases; update both.
- **Remote links rejected as unsupported** — check the provider switch for that
  link type, and confirm the resource is attached (`/radioexternalstations`).
- **Supplied stations missing** — run `/radioexternalstations install` and read
  the skip reasons; `modified_needs_adoption` means an edited legacy row is
  waiting for an explicit `adopt`.
- **No sound on YouTube links** — the embed player needs the player's browser
  runtime; check the client console for `embed_api_not_ready`.
