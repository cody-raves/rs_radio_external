-- Source adapter registration.
--
-- This is the bridge between this resource and the base radio's source
-- registry. The base speaks in neutral terms (embed pages, stream pages,
-- direct audio); this file translates those to the concrete providers we
-- support: YouTube, SoundCloud and direct HTTPS audio links.

local ADAPTER_NAME = "rs_radio_external"

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Provider kinds -> the neutral kinds the base radio and its UI understand.
local KIND_MAP = {
    youtube_video = "embed_video",
    youtube_playlist = "embed_playlist",
    youtube_live = "embed_live",
    soundcloud_track = "stream_track",
    direct_audio = "direct_audio",
    invalid = "invalid"
}

local function neutralKind(kind)
    return KIND_MAP[tostring(kind or "invalid")] or "invalid"
end

-- Error codes that leave this resource use neutral vocabulary too.
local function neutralError(err)
    local value = tostring(err or "")
    value = value:gsub("^soundcloud_duration_exceeds_limit", "source_duration_exceeds_limit")
    return value
end

local function neutralizeMeta(meta)
    if type(meta) ~= "table" then
        return meta
    end
    if meta.kind ~= nil then
        meta.kind = neutralKind(meta.kind)
    end
    return meta
end

local function capabilities()
    return {
        embedSources = Config.YoutubeEnabled == true,
        embedBackend = true,
        embedMaxPlayers = tonumber(Config.EmbedMaxPlayers) or 4,
        embedAnalyzerRetries = tonumber(Config.EmbedAnalyzerRetries) or 1,
        embedOnePerActiveSong = Config.EmbedOnePerActiveSong ~= false,
        embedReleaseGraceMs = tonumber(Config.EmbedReleaseGraceMs) or 15000,
        stressDefaultUrl = tostring(Config.StressDefaultUrl or ""),
        listenerSources = Config.ListenerCustomSourcesEnabled == true,
        listenerEmbedVideos = Config.ListenerCustomYoutubeVideosEnabled == true,
        listenerEmbedPlaylists = Config.ListenerCustomYoutubePlaylistsEnabled == true,
        listenerEmbedLive = Config.ListenerCustomYoutubeLiveEnabled == true,
        listenerStreamLinks = Config.ListenerCustomSoundCloudEnabled == true,
        listenerControllerOnly = Config.ListenerCustomSourceControllerOnly ~= false,
        listenerPlaylistMaxItems = tonumber(Config.ListenerCustomPlaylistMaxItems) or 25
    }
end

local function isBlockedResolved(rawUrl)
    local lower = trim(rawUrl):lower()
    if lower == "" then
        return false
    end
    local host, path = lower:match("^https://([^/%?#]+)([^%?#]*)")
    if not host then
        return false
    end
    host = host:gsub(":%d+$", "")
    -- Raw delivery endpoints only ever come out of a resolve step; a submitted
    -- one is someone trying to skip validation.
    return (host == "googlevideo.com" or host:match("%.googlevideo%.com$") ~= nil)
        and tostring(path or ""):find("/videoplayback", 1, true) ~= nil
end

local function isTrustedResolvedHost(rawUrl)
    local host = trim(rawUrl):lower():match("^https://([^/%?#]+)")
    if not host then
        return false
    end
    host = host:gsub(":%d+$", "")
    return host == "cf-media.sndcdn.com" or host:match("%.sndcdn%.com$") ~= nil
end

-- Station media catalogs for the supplied station package.
local productAdsCache = nil

local function loadProductAds()
    if productAdsCache ~= nil then
        return productAdsCache
    end
    productAdsCache = {}
    local raw = LoadResourceFile(GetCurrentResourceName(), "data/product_ads.json")
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == "table" then
            productAdsCache = decoded
        end
    end
    return productAdsCache
end

local function stationMedia(stationId)
    if Config.StationPackageEnabled ~= true then
        return nil
    end
    local catalog = type(RSRadioExternalPackageCatalog) == "function"
        and RSRadioExternalPackageCatalog(stationId) or nil
    if type(catalog) ~= "table" then
        return nil
    end
    -- Music/ads/sfx are seeded into the station rows at install time; only
    -- the shared product-ad pool flows live from this resource.
    return {
        music = {},
        stationAds = {},
        sfx = {},
        productAds = tostring(stationId) ~= "subsonic" and loadProductAds() or {}
    }
end

local adapter = {
    name = ADAPTER_NAME,
    resource = GetCurrentResourceName(),
    capabilities = capabilities(),

    classify = function(url)
        return neutralKind(RSRadioExternalClassifyUrl(url))
    end,

    extractMediaId = function(url)
        return RSRadioExternalExtractYoutubeVideoId(url)
    end,

    resolve = function(url, cb, options)
        RSRadioExternalResolvePlayable(url, function(resolvedUrl, err, meta, mimeType)
            cb(resolvedUrl, neutralError(err), neutralizeMeta(meta), mimeType)
        end, options)
    end,

    resolveMetadata = function(url, cb, options)
        RSRadioExternalResolveMetadata(url, function(meta, err)
            cb(neutralizeMeta(meta), neutralError(err))
        end, options)
    end,

    health = function()
        return RSRadioExternalGetResolveHealth()
    end,

    stationMedia = stationMedia,
    isBlockedResolved = isBlockedResolved,
    isTrustedResolvedHost = isTrustedResolvedHost
}

local registered = false

function RSRadioExternalRegisterAdapter()
    if registered then
        return true
    end
    local ok = pcall(function()
        exports[RSRadioExternalBaseResource()]:registerSourceAdapter(adapter)
    end)
    registered = ok == true
    if registered then
        print("[rs_radio_external] source adapter registered")
    end
    return registered
end

function RSRadioExternalUnregisterAdapter()
    if not registered then
        return
    end
    registered = false
    pcall(function()
        exports[RSRadioExternalBaseResource()]:unregisterSourceAdapter(ADAPTER_NAME)
    end)
end

-- Title lookups arrive as events because the UI asks for them ad hoc. The base
-- no longer answers these; we do.
RegisterNetEvent("rs-radio:resolveSourceTitle", function(payload)
    local src = source
    local data = type(payload) == "table" and payload or {}
    local token = tostring(data.token or "")
    local raw = trim(data.url or data.file)

    if token == "" then
        return
    end

    local function reply(body)
        body.token = token
        TriggerClientEvent("rs-radio:resolveSourceTitleResult", src, body)
    end

    if raw == "" then
        reply({ ok = false, error = "empty_url" })
        return
    end
    if not RSRadioExternalIsSupportedUrl(raw) then
        reply({ ok = false, error = "unsupported_url" })
        return
    end

    -- Works for every supported source: YouTube titles come from oEmbed,
    -- SoundCloud titles come from the resolve metadata, direct links use
    -- their filename downstream.
    local videoId = RSRadioExternalExtractYoutubeVideoId(raw)
    RSRadioExternalResolveMetadata(raw, function(meta, err)
        local info = type(meta) == "table" and meta or {}
        local title = trim(info.title)
        reply({
            ok = title ~= "",
            title = title,
            durationSec = tonumber(info.durationSec) or nil,
            videoId = videoId ~= "" and videoId or nil,
            canonicalSourceKey = trim(info.canonicalSourceKey) ~= "" and trim(info.canonicalSourceKey)
                or (videoId ~= "" and ("embed_video:%s"):format(videoId) or nil),
            sourceUrl = raw,
            error = title == "" and tostring(err or "title_lookup_failed") or nil
        })
    end, { priority = true })
end)

-- ---------------------------------------------------------------------------
-- Export dispatch
-- ---------------------------------------------------------------------------
-- The base calls back into this resource through these exports rather than
-- through stored function references; export calls are the dependable
-- cross-resource path.

exports("adapterCall", function(method, arg)
    local fn = adapter[tostring(method or "")]
    if type(fn) ~= "function" then
        return nil
    end
    return fn(arg)
end)

-- Resolutions must run on this resource's own scheduler and answer through a
-- server event: replies produced inside an export invocation's context (or
-- through argument function references) do not reliably arrive.
local resolveQueue = {}

CreateThread(function()
    while true do
        Wait(25)
        while #resolveQueue > 0 do
            local job = table.remove(resolveQueue, 1)
            local fn = adapter[tostring(job.method or "")]
            if type(fn) ~= "function" then
                TriggerEvent("rs-radio:adapterResolveResult", job.replyId, nil, "unsupported_source", nil, nil)
            else
                local ok, err = pcall(fn, job.url, function(resolvedUrl, resolveErr, meta, mimeType)
                    TriggerEvent("rs-radio:adapterResolveResult", job.replyId, resolvedUrl, resolveErr, meta, mimeType)
                end, job.options)
                if not ok then
                    TriggerEvent("rs-radio:adapterResolveResult", job.replyId, nil, tostring(err or "adapter_error"), nil, nil)
                end
            end
        end
    end
end)

exports("adapterResolve", function(method, url, options, replyId)
    resolveQueue[#resolveQueue + 1] = {
        method = method,
        url = url,
        options = options,
        replyId = tostring(replyId or "")
    }
    return true
end)

-- ---------------------------------------------------------------------------
-- Diagnostics: /radioexternaldiag <url>
-- ---------------------------------------------------------------------------

RegisterCommand("radioexternaldiag", function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, tostring(Config.StationControlAcePermission or "rsradio.external")) then
        return
    end
    local url = tostring(args and args[1] or "https://youtu.be/dQw4w9WgXcQ")

    local function say(message)
        if src == 0 then
            print(("[rs_radio_external][diag] %s"):format(message))
        else
            TriggerClientEvent("chat:addMessage", src, { args = { "diag", message } })
        end
    end

    say(("attached=%s"):format(tostring(RSRadioExternalIsAttached())))
    say(("provider classify=%s"):format(tostring(RSRadioExternalClassifyUrl(url))))
    say(("adapter classify=%s"):format(tostring(adapter.classify(url))))

    local ok, baseKind = pcall(function()
        return exports[RSRadioExternalBaseResource()]:classifySource(url)
    end)
    say(("base classify=%s (call ok=%s)"):format(tostring(baseKind), tostring(ok)))

    local media = adapter.stationMedia("south")
    say(("station media south: music=%s ads=%s"):format(
        media and #(media.music or {}) or "nil",
        media and #(media.stationAds or {}) or "nil"))

    for _, id in ipairs({ "south", "north", "subsonic" }) do
        local okDiag, diag = pcall(function()
            return exports[RSRadioExternalBaseResource()]:getStationDiag(id)
        end)
        if okDiag and type(diag) == "table" then
            say(("station %s: playlist=%s autonomous=%s onAir=%s"):format(
                id, tostring(diag.playlist), tostring(diag.autonomous), tostring(diag.onAir or "none")))
        else
            say(("station %s: diag failed (%s)"):format(id, tostring(diag)))
        end
    end
end, false)
