-- Saved listener library (moved from the base radio).
-- Players save external sources here; the base radio has no concept of a
-- saved URL library and never sees this table.

if Config and Config.SavedLibraryEnabled == false then
    return
end

local savedLibrariesBySrc = {}
local prewarmQueue = {}
local prewarmQueued = {}
local prewarmRunning = false

local function logInfo(message)
    if type(RSInfo) == "function" then
        RSInfo(("[saved_library] %s"):format(tostring(message or "")))
    else
        print(("[rs_radio][saved_library] %s"):format(tostring(message or "")))
    end
end

local function logWarn(message)
    if type(RSWarn) == "function" then
        RSWarn(("[saved_library] %s"):format(tostring(message or "")))
    else
        print(("[rs_radio][saved_library][WARN] %s"):format(tostring(message or "")))
    end
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function getIdentifier(src)
    local fallback = ("src:%s"):format(tostring(src))
    local ids = GetPlayerIdentifiers(src)
    if type(ids) ~= "table" then
        return fallback
    end

    for _, id in ipairs(ids) do
        if tostring(id):match("^license:") then
            return tostring(id)
        end
    end
    return tostring(ids[1] or fallback)
end

local function normalizeLibraryType(value)
    local kind = tostring(value or "listener"):lower()
    if kind == "dj" or kind == "station" then
        return kind
    end
    return "listener"
end

local function normalizeStationId(value)
    if type(NormalizeRadioStationId) == "function" then
        return NormalizeRadioStationId(value)
    end
    return tostring(value or Config and Config.DefaultRadioStation or "south")
end

local function weakTitle(title)
    local value = trim(title)
    if value == "" then return true end
    local lower = value:lower()
    return lower == "youtube"
        or lower == "youtube url"
        or lower == "youtube video"
        or lower == "soundcloud"
        or lower == "soundcloud track"
        or lower == "unknown track"
        or lower == "untitled"
        or value:match("^YouTube Video [%w%-_]+$") ~= nil
end

local function isResolverPageUrl(value)
    local raw = trim(value)
    if raw == "" then return false end
    if type(RSRadioExternalIsSoundCloudUrl) == "function" then
        if RSRadioExternalIsSoundCloudUrl(raw) == true then
            return true
        end
    end
    local lower = raw:lower()
    return lower:match("^https://soundcloud%.com/") ~= nil
        or lower:match("^https://www%.soundcloud%.com/") ~= nil
end

local function isYoutubePageUrl(value)
    if type(RSRadioEmbedSourcesEnabled) ~= "function" or not RSRadioEmbedSourcesEnabled() then
        return false
    end

    local raw = trim(value):lower()
    return raw:match("^https://youtube%.com/") ~= nil
        or raw:match("^https://www%.youtube%.com/") ~= nil
        or raw:match("^https://music%.youtube%.com/") ~= nil
        or raw:match("^https://youtu%.be/") ~= nil
end

local function cleanPlayableUrl(value)
    local url = trim(value)
    if url == "" or isResolverPageUrl(url) or isYoutubePageUrl(url) then return "" end
    local path = url:match("^https?://[^/]+(/[^?#]*)")
    if path and path:match("^/stream/") then return "" end
    return url
end

local function isSavableLibraryUrl(value)
    return trim(value):lower():match("^https://") ~= nil
end

local function soundCloudDurationLimitMessage(actualSec, maxSec)
    return ("SoundCloud track is too long (%s min). Max allowed is %s min."):format(
        tostring(math.floor((tonumber(actualSec) or 0) / 60 + 0.5)),
        tostring(math.floor((tonumber(maxSec) or 0) / 60 + 0.5))
    )
end

local function soundCloudLimitFromError(err)
    local actual, max = tostring(err or ""):match("^source_duration_exceeds_limit:(%d+):(%d+)$")
    if actual and max then
        return soundCloudDurationLimitMessage(actual, max)
    end
    return nil
end

local function trackHasPlayableUrl(track)
    return type(track) == "table" and trim(track.file or track.url) ~= ""
end

local function extractYoutubeVideoId(rawUrl)
    local raw = trim(rawUrl)
    return raw:match("[?&]v=([%w%-_]+)")
        or raw:match("youtu%.be/([%w%-_]+)")
        or raw:match("/shorts/([%w%-_]+)")
        or raw:match("/embed/([%w%-_]+)")
        or ""
end

local function canonicalSourceKey(url, meta)
    local info = type(meta) == "table" and meta or {}
    local videoId = trim(info.videoId or info.id or extractYoutubeVideoId(url))
    if videoId ~= "" then
        return ("embed_video:%s"):format(videoId), videoId
    end
    if type(info.canonicalSourceKey) == "string" and trim(info.canonicalSourceKey) ~= "" then
        return trim(info.canonicalSourceKey), ""
    end
    return ("source:%s"):format(trim(url):lower()), ""
end

local function installSchema()
    if not MySQL or not MySQL.query or not MySQL.query.await then
        logWarn("oxmysql MySQL.query.await unavailable; saved library disabled for this start")
        return false
    end

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `rs_radio_saved_tracks` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `owner_identifier` VARCHAR(80) NOT NULL,
                `owner_name` VARCHAR(80) NULL,
                `station_id` VARCHAR(64) NOT NULL DEFAULT 'south',
                `library_type` VARCHAR(24) NOT NULL DEFAULT 'listener',
                `original_url` TEXT NOT NULL,
                `canonical_source_key` VARCHAR(255) NULL,
                `video_id` VARCHAR(32) NULL,
                `title` VARCHAR(255) NULL,
                `duration_sec` INT NULL,
                `thumbnail` TEXT NULL,
                `resolved_url` TEXT NULL,
                `stream_url` TEXT NULL,
                `deck_url` TEXT NULL,
                `sort_order` INT NOT NULL DEFAULT 0,
                `resolve_status` VARCHAR(24) NOT NULL DEFAULT 'stale',
                `last_resolved_at` TIMESTAMP NULL DEFAULT NULL,
                `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uniq_rs_radio_saved_track` (`owner_identifier`, `library_type`, `station_id`, `canonical_source_key`),
                KEY `idx_rs_radio_saved_owner_type` (`owner_identifier`, `library_type`, `station_id`),
                KEY `idx_rs_radio_saved_canonical` (`canonical_source_key`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
        local scrubbed = MySQL.update.await([[
            UPDATE `rs_radio_saved_tracks`
            SET `resolved_url` = NULL,
                `stream_url` = NULL,
                `deck_url` = NULL,
                `resolve_status` = CASE WHEN `resolve_status` = 'ready' THEN 'source' ELSE `resolve_status` END,
                `last_resolved_at` = NULL
            WHERE `resolved_url` IS NOT NULL
               OR `stream_url` IS NOT NULL
               OR `deck_url` IS NOT NULL
        ]])
        if tonumber(scrubbed) and tonumber(scrubbed) > 0 then
            logInfo(("scrubbed stale playable URLs from %d saved track row(s)"):format(tonumber(scrubbed)))
        end
        local removedLocal = MySQL.update.await([[
            DELETE FROM `rs_radio_saved_tracks`
            WHERE LOWER(`original_url`) NOT LIKE 'https://%'
        ]])
        if tonumber(removedLocal) and tonumber(removedLocal) > 0 then
            logInfo(("removed %d local/non-HTTPS saved library row(s)"):format(tonumber(removedLocal)))
        end
    end)

    if not ok then
        logWarn(("SQL install failed: %s"):format(tostring(err)))
        return false
    end
    logInfo("SQL table ready: rs_radio_saved_tracks")
    return true
end

local schemaReady = false

CreateThread(function()
    Wait(500)
    schemaReady = installSchema()
end)

local function rowToTrack(row)
    local originalUrl = tostring(row.original_url or "")
    local storedResolveStatus = trim(row.resolve_status)
    return {
        id = tonumber(row.id) or 0,
        file = originalUrl,
        url = originalUrl,
        title = trim(row.title) ~= "" and tostring(row.title) or "External URL",
        durationSec = tonumber(row.duration_sec) or nil,
        thumbnail = tostring(row.thumbnail or ""),
        resolvedUrl = "",
        streamResolvedUrl = "",
        deckResolvedUrl = "",
        canonicalSourceKey = tostring(row.canonical_source_key or ""),
        videoId = tostring(row.video_id or ""),
        resolveStatus = storedResolveStatus ~= "" and storedResolveStatus or "source",
        savedLibraryType = tostring(row.library_type or "listener"),
        stationId = tostring(row.station_id or "south")
    }
end

local function loadLibrary(src, libraryType, stationId)
    if not schemaReady then return {} end
    local owner = getIdentifier(src)
    local rows = MySQL.query.await([[
        SELECT * FROM `rs_radio_saved_tracks`
        WHERE `owner_identifier` = ? AND `library_type` = ? AND `station_id` = ?
        ORDER BY `sort_order` ASC, `created_at` DESC
        LIMIT 250
    ]], { owner, normalizeLibraryType(libraryType), normalizeStationId(stationId) }) or {}

    local tracks = {}
    for i = 1, #rows do
        tracks[#tracks + 1] = rowToTrack(rows[i])
    end
    return tracks
end

local function pushLibraries(src, stationId)
    stationId = normalizeStationId(stationId)
    local sourceAdapterActive = type(RSRadioExternalIsAttached) == "function"
        and RSRadioExternalIsAttached()
    local listener = sourceAdapterActive and loadLibrary(src, "listener", stationId) or {}
    local dj = sourceAdapterActive and loadLibrary(src, "dj", stationId) or {}
    savedLibrariesBySrc[src] = {
        stationId = stationId,
        listener = listener,
        dj = dj
    }
    TriggerClientEvent("rs-radio:savedLibrary", src, {
        stationId = stationId,
        listener = listener,
        dj = dj
    })
end

local function queuePrewarm(src, tracks)
    if not (RSRadioExternalIsAttached ~= nil and RSRadioExternalIsAttached()) then return end
    if Config and Config.SavedLibraryServerPrewarmEnabled ~= true then return end
    if Config and Config.SavedLibraryPrewarmOnLogin == false then return end
    if type(tracks) ~= "table" then return end
    for i = 1, #tracks do
        local track = tracks[i]
        local url = trim(track.file or track.url)
        local needsPlayableUrl = not trackHasPlayableUrl(track)
        local status = trim(track.resolveStatus)
        local shouldPrewarm = url ~= ""
            and (status == "pending" or status == "resolving" or status == "stale" or status == "failed" or weakTitle(track.title) or needsPlayableUrl)
        local id = tonumber(track.id) or 0
        local queueKey = ("%s:%s:%s"):format(tostring(src), tostring(id), url)
        if shouldPrewarm and id > 0 and not prewarmQueued[queueKey] then
            prewarmQueued[queueKey] = true
            prewarmQueue[#prewarmQueue + 1] = {
                src = src,
                id = id,
                url = url,
                key = queueKey
            }
        end
    end
end

local function pumpPrewarmQueue()
    if not (RSRadioExternalIsAttached ~= nil and RSRadioExternalIsAttached()) then
        prewarmQueue = {}
        prewarmQueued = {}
        return
    end
    if prewarmRunning then return end
    prewarmRunning = true
    CreateThread(function()
        while #prewarmQueue > 0 do
            local job = table.remove(prewarmQueue, 1)
            if type(job) == "table" and job.id > 0 and type(RSRadioExternalResolvePlayable) == "function" then
                local queueKey = tostring(job.key or "")
                local done = false
                MySQL.update.await("UPDATE `rs_radio_saved_tracks` SET `resolve_status` = 'resolving' WHERE `id` = ?", { job.id })
                RSRadioExternalResolvePlayable(job.url, function(resolvedUrl, _err, meta)
                    local info = type(meta) == "table" and meta or {}
                    local canonical, videoId = canonicalSourceKey(job.url, info)
                    if type(resolvedUrl) == "string" and resolvedUrl ~= "" then
                        MySQL.update.await([[
                            UPDATE `rs_radio_saved_tracks`
                            SET `resolved_url` = ?, `stream_url` = ?, `deck_url` = ?, `title` = ?,
                                `duration_sec` = ?, `canonical_source_key` = ?, `video_id` = ?,
                                `resolve_status` = 'ready', `last_resolved_at` = CURRENT_TIMESTAMP
                            WHERE `id` = ?
                        ]], {
                            resolvedUrl,
                            tostring(info.streamUrl or resolvedUrl),
                            tostring(info.deckCachePath or info.cachePath or resolvedUrl),
                            trim(info.title) ~= "" and trim(info.title) or nil,
                            tonumber(info.durationSec) or nil,
                            canonical,
                            videoId,
                            job.id
                        })
                    else
                        MySQL.update.await("UPDATE `rs_radio_saved_tracks` SET `resolve_status` = 'failed' WHERE `id` = ?", { job.id })
                    end
                    done = true
                    end, {
                    preferCached = true,
                    waitForCache = true,
                    fastProxy = true
                })
                local deadline = GetGameTimer() + (tonumber(Config.ResolveTimeoutMs) or 120000) + 1000
                while not done and GetGameTimer() < deadline do
                    Wait(250)
                end
                if not done then
                    MySQL.update.await("UPDATE `rs_radio_saved_tracks` SET `resolve_status` = 'failed' WHERE `id` = ?", { job.id })
                end
                if queueKey ~= "" then
                    prewarmQueued[queueKey] = nil
                end
                if GetPlayerName(job.src) then
                    pushLibraries(job.src, savedLibrariesBySrc[job.src] and savedLibrariesBySrc[job.src].stationId or Config.DefaultRadioStation)
                end
            end
            Wait(100)
        end
        prewarmRunning = false
    end)
end

local function loadAndPrewarmForPlayer(src, stationId, options)
    if not schemaReady then return end
    pushLibraries(src, stationId or Config.DefaultRadioStation)
    local opts = type(options) == "table" and options or {}
    if opts.prewarm == false then
        return
    end
    local cache = savedLibrariesBySrc[src] or {}
    queuePrewarm(src, cache.listener)
    queuePrewarm(src, cache.dj)
    pumpPrewarmQueue()
end

RegisterNetEvent("rs-radio:requestSavedLibrary", function(payload)
    local src = source
    local stationId = normalizeStationId(type(payload) == "table" and payload.stationId or Config.DefaultRadioStation)
    loadAndPrewarmForPlayer(src, stationId)
end)

RegisterNetEvent("rs-radio:saveLibraryTrack", function(payload)
    local src = source
    if not schemaReady then return end
    if not (RSRadioExternalIsAttached ~= nil and RSRadioExternalIsAttached()) then
        local message = type(RSRadioT) == "function"
            and RSRadioT("notify.external_media_disabled")
            or "External media is disabled by this server."
        TriggerClientEvent("rs-radio:notify", src, message)
        return
    end
    local data = type(payload) == "table" and payload or {}
    local url = trim(data.url or data.file or data.originalUrl)
    if url == "" then return end
    if not isSavableLibraryUrl(url) then return end
    if type(RSRadioExternalIsSoundCloudUrl) == "function" and RSRadioExternalIsSoundCloudUrl(url) == true then
        local maxDurationSec = math.max(1, math.floor(tonumber(Config and Config.SoundCloudMaxDurationSec) or 21600))
        local durationSec = tonumber(data.durationSec) or 0
        if durationSec > maxDurationSec then
            TriggerClientEvent("rs-radio:notify", src, soundCloudDurationLimitMessage(durationSec, maxDurationSec))
            return
        end
        if type(RSRadioExternalResolvePlayable) ~= "function" then
            TriggerClientEvent("rs-radio:notify", src, "SoundCloud resolver unavailable.")
            return
        end

        local done = false
        local resolvedUrl, resolveErr, resolveMeta, resolveMimeType = nil, nil, nil, nil
        RSRadioExternalResolvePlayable(url, function(nextUrl, err, meta, mimeType)
            resolvedUrl = nextUrl
            resolveErr = err
            resolveMeta = meta
            resolveMimeType = mimeType
            done = true
        end, { mode = "single" })

        local deadline = GetGameTimer() + (tonumber(Config.ResolveTimeoutMs) or 120000) + 1000
        while not done and GetGameTimer() < deadline do
            Wait(100)
        end

        if type(resolvedUrl) ~= "string" or resolvedUrl == "" then
            TriggerClientEvent("rs-radio:notify", src, soundCloudLimitFromError(resolveErr) or ("SoundCloud track could not be added (%s)."):format(tostring(resolveErr or "resolver_failed")))
            return
        end

        local info = type(resolveMeta) == "table" and resolveMeta or {}
        data.resolvedUrl = resolvedUrl
        data.streamResolvedUrl = tostring(info.streamUrl or resolvedUrl)
        data.deckResolvedUrl = tostring(info.deckCachePath or info.cachePath or resolvedUrl)
        data.durationSec = tonumber(info.durationSec) or tonumber(data.durationSec) or nil
        data.title = trim(info.title) ~= "" and trim(info.title) or data.title
        data.canonicalSourceKey = trim(info.canonicalSourceKey) ~= "" and trim(info.canonicalSourceKey) or data.canonicalSourceKey
        data.resolveStatus = "ready"
        data.mimeType = tostring(resolveMimeType or info.mimeType or data.mimeType or "")
    end
    local stationId = normalizeStationId(data.stationId)
    local libraryType = normalizeLibraryType(data.libraryType)
    local canonical, videoId = canonicalSourceKey(url, data)
    local requestedResolveStatus = trim(data.resolveStatus)
    local resolveStatus = requestedResolveStatus ~= "" and requestedResolveStatus or "source"
    if resolveStatus == "ready" then
        resolveStatus = "source"
    end
    MySQL.insert.await([[
        INSERT INTO `rs_radio_saved_tracks`
            (`owner_identifier`, `owner_name`, `station_id`, `library_type`, `original_url`,
             `canonical_source_key`, `video_id`, `title`, `duration_sec`, `thumbnail`,
             `resolved_url`, `stream_url`, `deck_url`, `resolve_status`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `title` = COALESCE(VALUES(`title`), `title`),
            `duration_sec` = COALESCE(VALUES(`duration_sec`), `duration_sec`),
            `thumbnail` = COALESCE(NULLIF(VALUES(`thumbnail`), ''), `thumbnail`),
            `resolved_url` = NULL,
            `stream_url` = NULL,
            `deck_url` = NULL,
            `resolve_status` = VALUES(`resolve_status`),
            `last_resolved_at` = NULL,
            `updated_at` = CURRENT_TIMESTAMP
    ]], {
        getIdentifier(src),
        GetPlayerName(src) or "",
        stationId,
        libraryType,
        url,
        canonical,
        videoId,
        trim(data.title) ~= "" and trim(data.title) or nil,
        tonumber(data.durationSec) or nil,
        trim(data.thumbnail),
        nil,
        nil,
        nil,
        resolveStatus
    })
    loadAndPrewarmForPlayer(src, stationId, { prewarm = false })
end)

RegisterNetEvent("rs-radio:deleteLibraryTrack", function(payload)
    local src = source
    if not schemaReady then return end
    local data = type(payload) == "table" and payload or {}
    local owner = getIdentifier(src)
    local stationId = normalizeStationId(data.stationId)
    local libraryType = normalizeLibraryType(data.libraryType)
    local id = math.floor(tonumber(data.id) or 0)

    if id > 0 then
        MySQL.update.await([[
            DELETE FROM `rs_radio_saved_tracks`
            WHERE `id` = ?
              AND `owner_identifier` = ?
              AND `library_type` = ?
              AND `station_id` = ?
        ]], {
            id,
            owner,
            libraryType,
            stationId
        })
        loadAndPrewarmForPlayer(src, stationId, { prewarm = false })
        return
    end

    local url = trim(data.url or data.file or data.originalUrl)
    if url == "" and trim(data.canonicalSourceKey) == "" then return end
    local canonical = trim(data.canonicalSourceKey)
    if canonical == "" then
        canonical = canonicalSourceKey(url, data)
    end
    MySQL.update.await([[
        DELETE FROM `rs_radio_saved_tracks`
        WHERE `owner_identifier` = ?
          AND `library_type` = ?
          AND `station_id` = ?
          AND `canonical_source_key` = ?
    ]], {
        owner,
        libraryType,
        stationId,
        canonical
    })
    loadAndPrewarmForPlayer(src, stationId, { prewarm = false })
end)

RegisterNetEvent("QBCore:Server:OnPlayerLoaded", function(player)
    local src = type(player) == "table" and (player.PlayerData and player.PlayerData.source or player.source) or source
    if tonumber(src) then loadAndPrewarmForPlayer(tonumber(src), Config.DefaultRadioStation) end
end)

RegisterNetEvent("QBCore:Server:PlayerLoaded", function(player)
    local src = type(player) == "table" and (player.PlayerData and player.PlayerData.source or player.source) or source
    if tonumber(src) then loadAndPrewarmForPlayer(tonumber(src), Config.DefaultRadioStation) end
end)

RegisterNetEvent("qbx_core:server:playerLoaded", function(src)
    if tonumber(src) then loadAndPrewarmForPlayer(tonumber(src), Config.DefaultRadioStation) end
end)

AddEventHandler("esx:playerLoaded", function(src)
    if tonumber(src) then loadAndPrewarmForPlayer(tonumber(src), Config.DefaultRadioStation) end
end)

AddEventHandler("playerDropped", function()
    savedLibrariesBySrc[source] = nil
end)
