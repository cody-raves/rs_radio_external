-- SoundCloud resolution.
--
-- SoundCloud's public API needs a client id that is not published anywhere
-- stable, so it is discovered from the site's own script bundles and cached.
-- A configured id in config.lua takes priority and skips discovery entirely.

local FALLBACK_CLIENT_ID = "O2eFHIWUoLb36Z54Ap2ulmf322EiVGK4"

local clientId = ""
local clientIdPending = false
local clientIdWaiters = {}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function trace(message)
    if Config and Config.Trace == true then
        print(("[rs_radio_external][soundcloud] %s"):format(tostring(message or "")))
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

local BROWSER_HEADERS = {
    ["Accept"] = "*/*",
    ["User-Agent"] = "Mozilla/5.0 rs_radio_external"
}

local JSON_HEADERS = {
    ["Accept"] = "application/json",
    ["User-Agent"] = "Mozilla/5.0 rs_radio_external"
}

clientId = trim(Config and Config.SoundCloudClientId or "")

-- Walks the script bundles linked from the SoundCloud home page looking for an
-- embedded client id. Falls back to a known-good id if none is found.
local function fetchClientId(callback, forceRefresh)
    if forceRefresh == true then
        clientId = ""
    end
    if clientId ~= "" then
        callback(clientId)
        return
    end

    clientIdWaiters[#clientIdWaiters + 1] = callback
    if clientIdPending then
        return
    end
    clientIdPending = true

    PerformHttpRequest("https://soundcloud.com/", function(statusCode, body)
        local assets = {}
        if tonumber(statusCode) == 200 and type(body) == "string" then
            -- Bundling changes frequently; take every script the page loads
            -- and let the id pattern decide.
            for src in body:gmatch('src="(https://[^"]+%.js)"') do
                assets[#assets + 1] = src
            end
        end

        local waiters = clientIdWaiters
        clientIdWaiters = {}

        local function finish(id)
            clientIdPending = false
            clientId = trim(id)
            for index = 1, #waiters do
                if type(waiters[index]) == "function" then
                    waiters[index](clientId ~= "" and clientId or nil)
                end
            end
        end

        local cursor = 1
        local function tryNextAsset()
            local asset = assets[cursor]
            cursor = cursor + 1
            if not asset then
                finish(FALLBACK_CLIENT_ID)
                return
            end

            PerformHttpRequest(asset, function(assetStatus, js)
                local id = nil
                if tonumber(assetStatus) == 200 and type(js) == "string" then
                    id = js:match('client_id%s*[:=]%s*"([%w%-_]+)"')
                        or js:match('client_id=([%w%-_]+)')
                        or js:match('clientId%s*[:=]%s*"([%w%-_]+)"')
                end
                if id and #id >= 20 then
                    -- Validate before adopting; a stale id costs every later
                    -- resolve a round trip.
                    PerformHttpRequest(
                        ("https://api-v2.soundcloud.com/resolve?url=%s&client_id=%s"):format(
                            urlEncode("https://soundcloud.com/discover"), urlEncode(id)),
                        function(probeStatus)
                            if tonumber(probeStatus) == 200 or tonumber(probeStatus) == 404 then
                                -- 200/404 both mean the id was accepted; 401/403 means rejected.
                                trace(("discovered client id prefix=%s"):format(id:sub(1, 8)))
                                finish(id)
                            else
                                tryNextAsset()
                            end
                        end, "GET", "", JSON_HEADERS)
                    return
                end
                tryNextAsset()
            end, "GET", "", BROWSER_HEADERS)
        end

        tryNextAsset()
    end, "GET", "", {
        ["Accept"] = "text/html",
        ["User-Agent"] = "Mozilla/5.0 rs_radio_external"
    })
end

-- When a cached id is rejected, the track page itself usually carries a working
-- one. Each 32-character candidate is validated against the resolve endpoint
-- before being adopted.
local function discoverClientIdFromPage(sourceUrl, callback)
    local pageUrl = trim(sourceUrl)
    if pageUrl == "" then
        callback(nil)
        return
    end

    PerformHttpRequest(pageUrl, function(statusCode, body)
        if tonumber(statusCode) ~= 200 or type(body) ~= "string" or body == "" then
            callback(nil)
            return
        end

        local candidates, seen = {}, {}
        for candidate in body:gmatch("([%w%-_]+)") do
            if #candidate == 32 and not seen[candidate] then
                seen[candidate] = true
                candidates[#candidates + 1] = candidate
            end
        end

        local cursor = 1
        local function tryNext()
            local candidate = candidates[cursor]
            cursor = cursor + 1
            if not candidate then
                callback(nil)
                return
            end

            local probeUrl = ("https://api-v2.soundcloud.com/resolve?url=%s&client_id=%s")
                :format(urlEncode(pageUrl), urlEncode(candidate))
            PerformHttpRequest(probeUrl, function(probeStatus, probeBody)
                if tonumber(probeStatus) == 200 and type(probeBody) == "string" and probeBody ~= "" then
                    trace(("validated page client id prefix=%s"):format(candidate:sub(1, 8)))
                    clientId = candidate
                    callback(candidate)
                    return
                end
                tryNext()
            end, "GET", "", JSON_HEADERS)
        end

        tryNext()
    end, "GET", "", {
        ["Accept"] = "text/html,application/xhtml+xml",
        ["User-Agent"] = "Mozilla/5.0 rs_radio_external"
    })
end

-- Prefer a progressive MP3 stream. SoundCloud now serves most tracks as HLS
-- only; the base NUI stitches HLS with fragmented-MP4 audio (audio/mp4) into
-- one playable file, so that variant comes next. MPEG-TS style variants
-- ("audio/mpegurl") cannot be played by FiveM's browser and are a last resort.
local function chooseTranscoding(track)
    local media = type(track) == "table" and type(track.media) == "table" and track.media or {}
    local transcodings = type(media.transcodings) == "table" and media.transcodings or {}

    local hlsMp4, fallback = nil, nil
    for index = 1, #transcodings do
        local item = transcodings[index]
        if type(item) == "table" and trim(item.url) ~= "" and item.snipped ~= true then
            local format = type(item.format) == "table" and item.format or {}
            local protocol = tostring(format.protocol or "")
            local mimeType = tostring(format.mime_type or ""):lower()
            if protocol == "progressive" and mimeType:match("audio/mpeg") then
                return item
            end
            if protocol == "hls" and mimeType:match("^audio/mp4") then
                hlsMp4 = hlsMp4 or item
            end
            fallback = fallback or item
        end
    end
    return hlsMp4 or fallback
end

local resolveFailureLogs = 0

local function logResolveFailure(sourceUrl, err)
    if resolveFailureLogs >= 5 then
        return
    end
    resolveFailureLogs = resolveFailureLogs + 1
    print(("[rs_radio_external][soundcloud] resolve failed url=%s err=%s%s"):format(
        tostring(sourceUrl), tostring(err),
        resolveFailureLogs == 5 and " (further failures logged only with Config.Trace)" or ""))
end

function RSRadioExternalResolveSoundCloud(rawUrl, callback)
    if type(callback) ~= "function" then
        return
    end
    local outerCallback = callback
    callback = function(url, err, meta, mime)
        if url == nil and err ~= nil then
            logResolveFailure(rawUrl, err)
        end
        outerCallback(url, err, meta, mime)
    end

    local sourceUrl = trim(rawUrl)
    if not RSRadioExternalIsSoundCloudUrl(sourceUrl) then
        callback(nil, "unsupported_soundcloud_url")
        return
    end

    local function resolveWith(id, didRefresh)
        if not id or id == "" then
            callback(nil, "soundcloud_client_id_missing")
            return
        end

        local resolveUrl = ("https://api-v2.soundcloud.com/resolve?url=%s&client_id=%s")
            :format(urlEncode(sourceUrl), urlEncode(id))

        PerformHttpRequest(resolveUrl, function(statusCode, body)
            if tonumber(statusCode) ~= 200 or type(body) ~= "string" or body == "" then
                -- A 401 means the id went stale. Try the page, then rediscovery,
                -- but only once so a genuinely bad link cannot loop.
                if tonumber(statusCode) == 401 and didRefresh ~= true then
                    trace(("client id rejected; refreshing for %s"):format(sourceUrl))
                    discoverClientIdFromPage(sourceUrl, function(pageId)
                        if pageId and pageId ~= "" and pageId ~= id then
                            resolveWith(pageId, true)
                            return
                        end
                        fetchClientId(function(refreshedId)
                            if refreshedId and refreshedId ~= "" and refreshedId ~= id then
                                resolveWith(refreshedId, true)
                            else
                                callback(nil, "soundcloud_resolve_http_401")
                            end
                        end, true)
                    end)
                    return
                end
                callback(nil, "soundcloud_resolve_http_" .. tostring(statusCode or "unknown"))
                return
            end

            local ok, track = pcall(json.decode, body)
            if not ok or type(track) ~= "table" then
                callback(nil, "soundcloud_resolve_invalid_json")
                return
            end
            if tostring(track.kind or "track") ~= "track" then
                callback(nil, "soundcloud_not_track")
                return
            end

            local durationSec = math.max(1, math.floor((tonumber(track.duration) or 0) / 1000 + 0.5))
            local maxDurationSec = math.max(1, math.floor(tonumber(Config and Config.SoundCloudMaxDurationSec) or 21600))
            if durationSec > maxDurationSec then
                callback(nil, ("soundcloud_duration_exceeds_limit:%s:%s"):format(durationSec, maxDurationSec))
                return
            end

            local chosen = chooseTranscoding(track)
            local transcodingUrl = type(chosen) == "table" and trim(chosen.url) or ""
            if transcodingUrl == "" then
                callback(nil, "soundcloud_transcoding_missing")
                return
            end

            local mediaUrl = ("%s%sclient_id=%s"):format(
                transcodingUrl,
                transcodingUrl:find("?", 1, true) and "&" or "?",
                urlEncode(id)
            )

            PerformHttpRequest(mediaUrl, function(mediaStatus, mediaBody)
                if tonumber(mediaStatus) ~= 200 or type(mediaBody) ~= "string" or mediaBody == "" then
                    callback(nil, "soundcloud_media_http_" .. tostring(mediaStatus or "unknown"))
                    return
                end

                local mediaOk, media = pcall(json.decode, mediaBody)
                if not mediaOk or type(media) ~= "table" or trim(media.url) == "" then
                    callback(nil, "soundcloud_media_invalid_json")
                    return
                end

                local format = type(chosen.format) == "table" and chosen.format or {}
                local mimeType = tostring(format.mime_type or "audio/mpeg")

                callback(trim(media.url), nil, {
                    kind = "soundcloud_track",
                    title = firstNonEmpty(track.title, track.permalink, "SoundCloud Track"),
                    sourceUrl = sourceUrl,
                    durationSec = durationSec,
                    canonicalSourceKey = ("soundcloud:%s"):format(tostring(track.id or track.permalink_url or sourceUrl)),
                    soundcloudId = tostring(track.id or ""),
                    streamUrl = trim(media.url),
                    mimeType = mimeType
                }, mimeType)
            end, "GET", "", JSON_HEADERS)
        end, "GET", "", JSON_HEADERS)
    end

    fetchClientId(function(id)
        if id and id ~= "" then
            resolveWith(id, false)
            return
        end
        -- Homepage discovery failed; the track page itself usually carries a
        -- working id.
        discoverClientIdFromPage(sourceUrl, function(pageId)
            resolveWith(pageId, true)
        end)
    end)
end

-- Discovering a client id takes several requests; do it once at start so the
-- first track resolve is fast.
CreateThread(function()
    Wait(3000)
    fetchClientId(function(id)
        if id and id ~= "" then
            if Config and Config.Trace == true then
                print(("[rs_radio_external][soundcloud] client id ready (prefix %s)"):format(id:sub(1, 6)))
            end
        else
            print("[rs_radio_external][soundcloud] client id discovery failed; will retry from track pages on demand")
        end
    end)
end)
