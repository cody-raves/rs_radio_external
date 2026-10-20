-- Resolution dispatch and metadata hydration.
--
-- One entry point decides which provider owns a link. Metadata lookups are
-- queued rather than fired on demand, because a station switching tracks can
-- ask about a dozen links at once and each one costs an outbound request.

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function trace(message)
    if Config and Config.Trace == true then
        print(("[rs_radio_external][resolve] %s"):format(tostring(message or "")))
    end
end

-- ---------------------------------------------------------------------------
-- Playable url
-- ---------------------------------------------------------------------------

function RSRadioExternalResolvePlayable(rawUrl, callback, options)
    if type(callback) ~= "function" then
        return
    end

    local sourceUrl = trim(rawUrl)
    if sourceUrl == "" then
        callback(nil, "empty_url")
        return
    end

    if RSRadioExternalIsSoundCloudUrl(sourceUrl) then
        RSRadioExternalResolveSoundCloud(sourceUrl, callback)
        return
    end

    -- A direct link is already playable; the player fetches it itself, so the
    -- server never follows it.
    if RSRadioExternalIsDirectAudioUrl(sourceUrl) then
        callback(sourceUrl, nil, {
            kind = "direct_audio",
            sourceUrl = sourceUrl,
            streamUrl = sourceUrl,
            canonicalSourceKey = ("direct:%s"):format(sourceUrl:lower())
        }, nil)
        return
    end

    if RSRadioExternalIsYoutubeUrl(sourceUrl) then
        RSRadioExternalResolveYoutube(sourceUrl, callback, options)
        return
    end

    callback(nil, "unsupported_url")
end

-- ---------------------------------------------------------------------------
-- Metadata hydration
-- ---------------------------------------------------------------------------

local queue = {}
local inflight = {}
local cache = {}
local active = 0
local seq = 0
local pump

local function concurrency()
    return math.max(1, math.min(8, math.floor(tonumber(Config and Config.MetadataHydrateConcurrency) or 3)))
end

local function finishJob(key, token, meta, err)
    local entry = inflight[key]
    if type(entry) ~= "table" or tonumber(entry.token) ~= tonumber(token) then
        return
    end

    inflight[key] = nil
    active = math.max(0, active - 1)

    local info = type(meta) == "table" and meta or nil
    if info and ((tonumber(info.durationSec) or 0) > 0 or trim(info.title) ~= "") then
        cache[key] = {
            meta = info,
            expiresAt = os.time() + math.max(300, math.floor(tonumber(Config and Config.MetadataCacheTtlSec) or 21600))
        }
    end

    for _, waiter in ipairs(type(entry.waiters) == "table" and entry.waiters or {}) do
        if type(waiter) == "function" then
            local ok, callbackErr = pcall(waiter, info, err)
            if not ok then
                print(("[rs_radio_external][resolve] metadata callback failed source=%s error=%s")
                    :format(tostring(entry.sourceUrl or key), tostring(callbackErr)))
            end
        end
    end

    SetTimeout(0, function()
        if type(pump) == "function" then
            pump()
        end
    end)
end

pump = function()
    local limit = concurrency()
    while active < limit and #queue > 0 do
        local job = table.remove(queue, 1)
        local key = tostring(job and job.key or "")
        local sourceUrl = tostring(job and job.sourceUrl or "")
        local token = tonumber(job and job.token) or 0

        if key ~= "" and type(inflight[key]) == "table" and tonumber(inflight[key].token) == token then
            active = active + 1

            SetTimeout(math.max(5000, math.floor(tonumber(Config and Config.MetadataHydrateTimeoutMs) or 20000)), function()
                finishJob(key, token, nil, "metadata_timeout")
            end)

            if RSRadioExternalIsSoundCloudUrl(sourceUrl) then
                RSRadioExternalResolveSoundCloud(sourceUrl, function(_url, err, meta)
                    finishJob(key, token, meta, err)
                end)
            elseif RSRadioExternalIsYoutubeUrl(sourceUrl) then
                RSRadioExternalFetchYoutubeMetadata(sourceUrl, function(meta)
                    local info = type(meta) == "table" and meta or {}
                    local videoId = RSRadioExternalExtractYoutubeVideoId(sourceUrl)
                    info.sourceUrl = sourceUrl
                    info.videoId = videoId ~= "" and videoId or nil
                    info.canonicalSourceKey = videoId ~= "" and ("youtube_video:%s"):format(videoId) or nil
                    finishJob(key, token, info, nil)
                end)
            elseif RSRadioExternalIsDirectAudioUrl(sourceUrl) then
                -- Nothing to look up; the link carries no metadata of its own.
                finishJob(key, token, {
                    sourceUrl = sourceUrl,
                    canonicalSourceKey = ("direct:%s"):format(sourceUrl:lower())
                }, nil)
            else
                finishJob(key, token, nil, "unsupported_metadata_source")
            end
        end
    end
end

function RSRadioExternalResolveMetadata(rawUrl, callback, options)
    if type(callback) ~= "function" then
        return
    end

    local sourceUrl = trim(rawUrl)
    local key = sourceUrl:lower()
    if key == "" then
        callback(nil, "empty_url")
        return
    end

    local cached = cache[key]
    if type(cached) == "table" and (tonumber(cached.expiresAt) or 0) > os.time() then
        callback(type(cached.meta) == "table" and cached.meta or nil, nil)
        return
    end
    cache[key] = nil

    -- Already being fetched: join the existing job rather than starting a
    -- second identical request.
    local pending = inflight[key]
    if type(pending) == "table" then
        pending.waiters[#pending.waiters + 1] = callback
        if type(options) == "table" and options.priority == true then
            for index = #queue, 1, -1 do
                local queued = queue[index]
                if tostring(queued and queued.key or "") == key
                    and tonumber(queued and queued.token) == tonumber(pending.token) then
                    table.remove(queue, index)
                    table.insert(queue, 1, queued)
                    break
                end
            end
        end
        return
    end

    seq = seq + 1
    local token = seq
    inflight[key] = {
        token = token,
        sourceUrl = sourceUrl,
        waiters = { callback },
        queuedAt = GetGameTimer()
    }

    local job = { key = key, token = token, sourceUrl = sourceUrl }
    if type(options) == "table" and options.priority == true then
        table.insert(queue, 1, job)
    else
        queue[#queue + 1] = job
    end

    trace(("queued metadata for %s (%s waiting)"):format(sourceUrl, tostring(#queue)))
    pump()
end

function RSRadioExternalGetResolveHealth()
    local inflightCount, cacheCount = 0, 0
    for _ in pairs(inflight) do inflightCount = inflightCount + 1 end
    for _ in pairs(cache) do cacheCount = cacheCount + 1 end

    return {
        active = active,
        queued = #queue,
        inflight = inflightCount,
        cached = cacheCount,
        concurrency = concurrency()
    }
end
