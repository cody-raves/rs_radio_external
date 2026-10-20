Config = Config or {}

-- ---------------------------------------------------------------------------
-- Providers
-- ---------------------------------------------------------------------------
-- Each provider is independent. Turning one off stops this resource offering
-- it at all; the base radio keeps playing local files regardless.

Config.YoutubeEnabled = true
Config.SoundCloudEnabled = true
Config.DirectLinksEnabled = true

-- Direct links are fetched by the requesting player's media player, never by
-- the server, so the server cannot follow a redirect chain to see where a link
-- finally lands. Leave this off unless the links your players can reach are
-- constrained by a proxy you trust.
Config.DirectLinksAllowRedirects = false

Config.SoundCloudClientId = ""
Config.SoundCloudMaxDurationSec = 21600

-- Embed player budget pushed to the base radio's clients. These match the
-- original product's iframe tuning.
Config.EmbedMaxPlayers = 4
Config.EmbedAnalyzerRetries = 1
Config.EmbedOnePerActiveSong = true
Config.EmbedReleaseGraceMs = 15000
Config.StressDefaultUrl = "https://youtu.be/3jtp0BDy_oE"

-- ---------------------------------------------------------------------------
-- Listener custom sources
-- ---------------------------------------------------------------------------
-- Whether ordinary players may point a radio they control at their own media.
-- Playing through a vehicle, boombox or prop is audible to everyone nearby,
-- exactly like any other station; only the Walkboy stays personal.

Config.ListenerCustomSourcesEnabled = true
Config.ListenerCustomYoutubeVideosEnabled = true
Config.ListenerCustomYoutubePlaylistsEnabled = true
Config.ListenerCustomYoutubeLiveEnabled = true
Config.ListenerCustomSoundCloudEnabled = true
Config.ListenerCustomSourceControllerOnly = true
Config.ListenerCustomPlaylistMaxItems = 25

Config.SavedLibraryMaxRowsPerPlayer = 200
Config.SavedLibraryRateLimitMs = 1500

-- ---------------------------------------------------------------------------
-- Station package
-- ---------------------------------------------------------------------------
-- The three supplied stations and their catalogs belong to this resource. When
-- enabled, their station metadata is installed into the base on start and kept
-- reconciled. Installation only ever touches rows this package owns, so stations
-- your admins created are never modified or removed.

Config.StationPackageEnabled = true
Config.StationPackageId = "rs_radio_external.builtin"
Config.StationPackageStations = { "south", "north", "subsonic" }
Config.StationPackageIncludeSubSonic = true

-- Adopt untouched station rows left behind by an older all-in-one install.
-- Rows an admin has edited are never adopted automatically; use
-- /radioexternalstations adopt <id> to take one over deliberately.
Config.StationPackageAdoptLegacyRows = true

-- ---------------------------------------------------------------------------
-- Migration
-- ---------------------------------------------------------------------------
-- Copies external entries out of legacy station rows and saved libraries into
-- this resource's own tables. Never deletes anything it reads.

Config.MigrationEnabled = true
Config.MigrationImportBrowserPlaylists = true

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

Config.StationControlAcePermission = "rsradio.external"
Config.AdminCommandName = "radioexternalstations"

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

Config.ResolveTimeoutMs = 35000
Config.MetadataCacheTtlSec = 21600
Config.MetadataHydrateConcurrency = 3
Config.MetadataHydrateTimeoutMs = 20000

-- Optional external resolver service. Leave blank to resolve in-process.
Config.AudioBackendYoutubeUrl = ""
Config.AudioBackendStationBaseUrl = ""
Config.AudioBackendAuthToken = ""

Config.Trace = false
