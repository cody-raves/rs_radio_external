# Approved tracks (link allowlist)

By default any player who controls a car radio or boombox can paste any supported
link — YouTube, SoundCloud, or a direct audio URL — and it plays for everyone
nearby. The allowlist turns that into a curated list: **you** decide which links
exist, players pick from those, anything else is refused.

Nothing changes until you add an entry. An empty list is the old behaviour.

## Turning it on

In `rs_radio_external/config.lua`:

```lua
Config.ListenerCustomAllowlist = {
    "https://youtu.be/dQw4w9WgXcQ",                           -- a YouTube video
    "https://www.youtube.com/playlist?list=PLxxxxxxxxxxxxxxxx", -- a YouTube playlist
    "https://soundcloud.com/artist/track-name",                -- a SoundCloud track
    "https://cdn.example.com/radio/",                          -- every file under this folder
}
```

Restart `rs_radio_external` after editing. Requires `rs_radio` 2.0.5 or newer.

## What players see

- In the **car radio / boombox panel**, pasting a link that is not on the list
  shows *"This link is not on the server's approved list."* and nothing plays.
  Links on the list behave exactly as before.
- In the **phone app** (`rs_radio_phone`, if you run it), the Custom tab shows an
  **Approved tracks** list built from your entries — tap to play. Folder-prefix
  entries are enforced but not shown as rows, since they are not single tracks.
- **DJ decks and your station playlists are never filtered.** The list only
  applies to links ordinary players submit themselves.

## How a link is matched

Matching is by *identity*, not by the exact text, so players do not have to
paste the same URL form you used:

| Entry type | What is compared | Also matches |
|---|---|---|
| YouTube video | the 11-character video id | `youtu.be/…`, `youtube.com/watch?v=…`, `music.youtube.com`, `/shorts/`, `/live/`, extra `&t=` or `&si=` parameters |
| YouTube playlist | the `list=` id | any URL form carrying that `list=` |
| SoundCloud | host + `/artist/track` path, lower-cased | `www.`/`m.` prefixes, trailing slash, query string |
| Direct audio | the full URL, lower-cased | — |
| Direct folder (entry ends in `/`) | URL prefix | every file beneath it |

A bare 11-character id (`dQw4w9WgXcQ`) is accepted as a YouTube entry.

A URL that carries both `v=` and `list=` is treated as the **video**, because
that is what the radio plays for it. To approve a playlist, use the playlist URL
without `v=`.

## Display titles (phone app only)

Rows in the phone's Approved tracks list use the URL as the label unless you give
one:

```lua
Config.ListenerCustomTrackLabels = {
    ["https://youtu.be/dQw4w9WgXcQ"] = "Late Night Drive",
}
```

The key must be the exact string you used in `ListenerCustomAllowlist`.

## Checking a link

From the server console or as an ACE-permitted player:

```
radioexternaldiag https://youtu.be/dQw4w9WgXcQ
```

prints `listener allowlist active=true allowed=true|false` for that link.

## Limits and notes

- The phone list shows up to 200 exact entries; longer lists are still enforced.
- Saved-library entries and the UI's playlist rows are checked on play, so
  removing a link from the list also stops tracks players saved earlier.
- The provider switches still apply on top: if `Config.ListenerCustomSoundCloudEnabled`
  is `false`, SoundCloud entries on the list will not play either.
- The list is read once at resource start; edit → `restart rs_radio_external`.
