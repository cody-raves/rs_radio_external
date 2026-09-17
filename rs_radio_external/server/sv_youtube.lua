-- YouTube metadata and resolution.
--
-- Titles and durations come from oEmbed where possible, falling back to the
-- watch page. Playable audio comes from a configured resolver service when one
-- is set; without it the iframe playback path is used instead, which needs no
-- server-side stream fetch at all.

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function trace(message)
    if Config and Config.Trace == true then
        print(("[rs_radio_external][youtube] %s"):format(tostring(message or "")))
    end
end

local function urlEncode(value)
    return tostring(value or ""):gsub("([^%w%-%._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function firstNonEmpty(...)
    local values = { ... }
    for index = 1, #values do
        local value = trim(values[index])
        if value ~= "" then
            return value
        end
    end
    return ""
end

local function htmlDecode(value)
    return tostring(value or "")
        :gsub("&quot;", '"')
        :gsub("&#39;", "'")
        :gsub("&apos;", "'")
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&amp;", "&")
end

local PAGE_HEADERS = {
    ["Accept"] = "text/html,application/xhtml+xml",
    ["User-Agent"] = "Mozilla/5.0 rs_radio_external"
}

-- A title that is really just the video id, or a generic placeholder, is worse
-- than no title -- it should trigger a proper lookup instead of being kept.
local function isWeakTitle(title, videoId)
    local value = trim(title)
    if value == "" then
        return true
    end

    local lower = value:lower()
    local id = trim(videoId)
    return lower == "youtube"
        or lower == "youtube url"
        or lower == "youtube video"
        or lower == "custom source"
        or lower:match("^youtube %(.*%)$") ~= nil
        or value:match("^YouTube Video [%w%-_]+$") ~= nil
        or (id ~= "" and value == id)
end
RSRadioExternalIsWeakYoutubeTitle = isWeakTitle

local function parseIsoDuration(value)
    local text = tostring(value or "")
    if text == "" then
        return nil
    end
    local hours = tonumber(text:match("(%d+)H")) or 0
    local minutes = tonumber(text:match("(%d+)M")) or 0
    local seconds = tonumber(text:match("(%d+)S")) or 0
    local total = (hours * 3600) + (minutes * 60) + seconds
    return total > 0 and total or nil
end

-- Find literal anchors with Lua's fast plain search. Running a Lua pattern
-- over an entire multi-megabyte watch page once per field blocks the server
-- scheduler. Search the whole page, but match only a small field/tag window.
local function findHtmlField(html, anchor, pattern)
    local cursor = 1
    while true do
        local at = html:find(anchor, cursor, true)
        if not at then return nil end
        local value = html:sub(at, at + 8191):match("^" .. pattern)
        if value ~= nil then return value end
        cursor = at + #anchor
    end
end

local function parseDurationFromHtml(body)
    local html = tostring(body or "")
    if html == "" then
        return nil
    end

    local lengthSeconds = findHtmlField(html, '"lengthSeconds"', '"lengthSeconds"%s*:%s*"?(%d+)"?')
    if lengthSeconds then
        local duration = tonumber(lengthSeconds)
        if duration and duration > 0 then
            return math.max(1, math.floor(duration + 0.5))
        end
    end

    local durationMs = findHtmlField(html, '"approxDurationMs"', '"approxDurationMs"%s*:%s*"?(%d+)"?')
    if durationMs then
        local duration = (tonumber(durationMs) or 0) / 1000.0
        if duration > 0 then
            return math.max(1, math.floor(duration + 0.5))
        end
    end

    return parseIsoDuration(
        findHtmlField(html, 'itemprop=', 'itemprop=["\']duration["\'][^>]-content=["\']([^"\']+)["\']')
        or findHtmlField(html, 'content=', 'content=["\']([^"\']+)["\'][^>]-itemprop=["\']duration["\']')
    )
end

local function parseTitleFromHtml(body)
    local html = tostring(body or "")
    if html == "" then
        return nil
    end

    local title = findHtmlField(html, '<meta', '<meta%s+property=["\']og:title["\']%s+content=["\']([^"\']+)["\']')
        or findHtmlField(html, '<meta', '<meta%s+content=["\']([^"\']+)["\']%s+property=["\']og:title["\']')
        or findHtmlField(html, '<title>', '<title>(.-)</title>')
    title = htmlDecode(trim(title)):gsub("%s+%- YouTube%s*$", "")
    return title ~= "" and title or nil
end

local function fetchOEmbedTitle(watchUrl, callback)
    local raw = trim(watchUrl)
    if raw == "" then
        callback(nil)
        return
    end

    local endpoints = {
        ("https://www.youtube.com/oembed?format=json&url=%s"):format(urlEncode(raw)),
        ("https://noembed.com/embed?url=%s"):format(urlEncode(raw))
    }

    local function tryEndpoint(index)
        local endpoint = endpoints[index]
        if not endpoint then
            -- The caller fetches the canonical watch page once, extracting
            -- title and duration together even when both oEmbed hosts fail.
            callback(nil)
            return
        end

        PerformHttpRequest(endpoint, function(statusCode, body)
            if tonumber(statusCode) ~= 200 or type(body) ~= "string" or body == "" then
                tryEndpoint(index + 1)
                return
            end

            local ok, decoded = pcall(json.decode, body)
            if not ok or type(decoded) ~= "table" then
                tryEndpoint(index + 1)
                return
            end

            local title = firstNonEmpty(decoded.title)
            if title ~= "" then
                callback(title)
            else
                tryEndpoint(index + 1)
            end
        end, "GET", "", { ["Accept"] = "application/json" })
    end

    tryEndpoint(1)
end

-- bpctr/has_verified skip the age-gate interstitial, which otherwise returns a
-- consent page carrying no duration.
local function fetchWatchMetadata(watchUrl, callback)
    local raw = trim(watchUrl)
    if raw == "" then
        callback({})
        return
    end

    local videoId = RSRadioExternalExtractYoutubeVideoId(raw)
    local metadataUrl = videoId ~= ""
        and ("https://www.youtube.com/watch?v=%s&bpctr=9999999999&has_verified=1"):format(urlEncode(videoId))
        or raw

    PerformHttpRequest(metadataUrl, function(statusCode, body)
        if tonumber(statusCode) ~= 200 or type(body) ~= "string" or body == "" then
            trace(("metadata lookup failed url=%s status=%s"):format(raw, tostring(statusCode)))
            callback({})
            return
        end

        callback({
            title = parseTitleFromHtml(body),
            durationSec = parseDurationFromHtml(body)
        })
    end, "GET", "", PAGE_HEADERS)
end
RSRadioExternalFetchYoutubeWatchMetadata = fetchWatchMetadata

function RSRadioExternalFetchYoutubeMetadata(watchUrl, callback)
    if type(callback) ~= "function" then
        return
    end

    local raw = trim(watchUrl)
    if raw == "" then
        callback({})
        return
    end

    fetchOEmbedTitle(raw, function(oembedTitle)
        -- oEmbed answers in well under a second; the watch page takes several.
        -- Only scrape the page when oEmbed gave nothing (duration hydrates
        -- from the player itself at play time).
        if trim(oembedTitle) ~= "" then
            callback({ title = trim(oembedTitle), durationSec = nil })
            return
        end
        fetchWatchMetadata(raw, function(pageMeta)
            local page = type(pageMeta) == "table" and pageMeta or {}
            callback({
                title = firstNonEmpty(oembedTitle, page.title),
                durationSec = tonumber(page.durationSec) or nil
            })
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Optional resolver service
-- ---------------------------------------------------------------------------

local pending = {}
local pendingSeq = 0

local function nextToken()
    pendingSeq = pendingSeq + 1
    return ("yt_%s_%s"):format(GetGameTimer(), pendingSeq)
end

local function finish(token, resolvedUrl, mimeType, meta, err)
    local entry = pending[token]
    if type(entry) ~= "table" then
        return
    end
    pending[token] = nil

    if type(entry.callback) == "function" then
        entry.callback(
            type(resolvedUrl) == "string" and resolvedUrl or nil,
            type(err) == "string" and err or nil,
            type(meta) == "table" and meta or nil,
            type(mimeType) == "string" and mimeType or nil
        )
    end
end

local function authHeaders()
    local headers = {
        ["Content-Type"] = "application/json; charset=utf-8",
        ["Accept"] = "application/json"
    }
    local token = trim(Config and Config.AudioBackendAuthToken or "")
    if token ~= "" then
        headers["Authorization"] = ("Bearer %s"):format(token)
    end
    return headers
end

function RSRadioExternalResolveYoutube(rawUrl, callback, options)
    if type(callback) ~= "function" then
        return
    end

    local raw = trim(rawUrl)
    if not RSRadioExternalIsYoutubeUrl(raw) then
        callback(nil, "youtube_url_invalid")
        return
    end

    local backendUrl = trim(Config and Config.AudioBackendYoutubeUrl or "")
    if backendUrl == "" then
        -- No resolver service configured: playback happens through the embed
        -- (iframe) player on the client. The "resolved" url is the page url
        -- itself, flagged so the base knows the embed runtime owns it.
        local videoId = RSRadioExternalExtractYoutubeVideoId(raw)
        local meta = {
            kind = "youtube_video",
            sourceUrl = raw,
            videoId = videoId ~= "" and videoId or nil,
            embedPlayback = true,
            canonicalSourceKey = videoId ~= "" and ("embed_video:%s"):format(videoId) or nil,
            fastStream = false,
            cached = false
        }
        -- Reply immediately: the embed player reports real duration itself
        -- once it loads, and titles hydrate asynchronously. Blocking playback
        -- on page scrapes is what makes "Preparing" feel slow.
        callback(raw, nil, meta, nil)
        return
    end

    local token = nextToken()
    pending[token] = { callback = callback, createdAt = GetGameTimer(), rawUrl = raw }

    SetTimeout(math.max(1000, math.floor(tonumber(Config and Config.ResolveTimeoutMs) or 35000)), function()
        if type(pending[token]) == "table" then
            finish(token, nil, nil, nil, "resolver_timeout")
        end
    end)

    local opts = type(options) == "table" and options or {}
    local requestBody = json.encode({
        url = raw,
        preferCached = opts.preferCached == true,
        emitterReady = opts.emitterReady == true,
        waitForCache = opts.waitForCache == true,
        fastProxy = opts.fastProxy == true,
        prewarmOnly = opts.prewarmOnly == true,
        skipTitleLookup = opts.skipTitleLookup == true
    })

    PerformHttpRequest(backendUrl, function(statusCode, body, _headers, errorData)
        if tonumber(statusCode) ~= 200 or type(body) ~= "string" or body == "" then
            finish(token, nil, nil, nil, errorData or ("resolver_http_" .. tostring(statusCode or "unknown")))
            return
        end

        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= "table" then
            finish(token, nil, nil, nil, "resolver_invalid_json")
            return
        end
        if decoded.success ~= true then
            finish(token, nil, nil, nil, tostring(decoded.error or "resolver_failed"))
            return
        end

        local resolvedUrl = type(decoded.resolvedUrl) == "string" and decoded.resolvedUrl or ""
        if resolvedUrl == "" then
            finish(token, nil, nil, nil, "resolver_missing_url")
            return
        end

        local info = type(decoded.info) == "table" and decoded.info or {}
        info.sourceUrl = trim(info.sourceUrl ~= nil and info.sourceUrl or raw)
        info.videoId = trim(info.videoId or info.id or "")
        info.kind = trim(info.kind ~= nil and info.kind or "youtube_video")
        info.durationSec = tonumber(firstNonEmpty(
            info.durationSec, info.duration, info.lengthSeconds,
            decoded.durationSec, decoded.duration, decoded.lengthSeconds
        )) or nil
        info.fastStream = decoded.fastStream == true
        info.cached = decoded.cached == true
        info.title = firstNonEmpty(info.title, info.fulltitle, info.track, decoded.title, decoded.name)

        local needsTitle = isWeakTitle(info.title, info.videoId)
            and opts.skipTitleLookup ~= true
            and opts.prewarmOnly ~= true
        local needsDuration = not (tonumber(info.durationSec) and tonumber(info.durationSec) > 0)

        if not needsDuration and not needsTitle then
            finish(token, resolvedUrl, decoded.mimeType, info, nil)
            return
        end

        -- Metadata is a nice-to-have; never let it hold up playback.
        local settled = false
        local function complete(pageMeta)
            if settled or type(pending[token]) ~= "table" then
                return
            end
            settled = true

            local page = type(pageMeta) == "table" and pageMeta or {}
            if needsTitle then
                info.title = firstNonEmpty(page.title, info.title)
            end
            info.durationSec = tonumber(info.durationSec) or tonumber(page.durationSec) or nil
            finish(token, resolvedUrl, decoded.mimeType, info, nil)
        end

        if needsTitle then
            RSRadioExternalFetchYoutubeMetadata(raw, complete)
        else
            fetchWatchMetadata(raw, complete)
        end
        SetTimeout(1500, function() complete({}) end)
    end, "POST", requestBody, authHeaders())
end
