-- URL classification and admission rules.
--
-- Everything a player or DJ submits passes through here before any request is
-- made. The job is to decide what a link is, and to refuse anything that could
-- turn the server into a probe for hosts it should not be reaching.

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lowerHostOf(rawUrl)
    local host = trim(rawUrl):lower():match("^https://([^/%?#]+)")
    if not host then
        return nil
    end
    return host
end

-- Splits host:port and strips a trailing dot ("example.com." and "example.com"
-- resolve identically, so they must not classify differently).
local function normalizeHost(host)
    local value = tostring(host or ""):gsub(":%d+$", ""):gsub("%.$", "")
    return value
end

-- ---------------------------------------------------------------------------
-- Address safety
-- ---------------------------------------------------------------------------

local BLOCKED_HOST_NAMES = {
    ["localhost"] = true,
    ["localhost.localdomain"] = true,
    ["ip6-localhost"] = true,
    ["ip6-loopback"] = true
}

local function isDecimalIpv4(host)
    local a, b, c, d = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return nil
    end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return a, b, c, d
end

-- Literal addresses that must never be fetched: loopback, private ranges,
-- link-local, carrier NAT, multicast, broadcast and the reserved blocks.
local function isReservedIpv4(a, b, c, d)
    if a == 0 or a == 10 or a == 127 then return true end
    if a == 169 and b == 254 then return true end
    if a == 172 and b >= 16 and b <= 31 then return true end
    if a == 192 and b == 168 then return true end
    if a == 192 and b == 0 and (c == 0 or c == 2) then return true end
    if a == 198 and (b == 18 or b == 19) then return true end
    if a == 198 and b == 51 and c == 100 then return true end
    if a == 203 and b == 0 and c == 113 then return true end
    if a == 100 and b >= 64 and b <= 127 then return true end
    if a >= 224 then return true end
    if a == 255 and b == 255 and c == 255 and d == 255 then return true end
    return false
end

local function isReservedIpv6(host)
    local value = host:gsub("^%[", ""):gsub("%]$", ""):lower()
    if not value:find(":", 1, true) then
        return false
    end
    if value == "::1" or value == "::" then return true end
    -- unique local (fc00::/7) and link-local (fe80::/10)
    if value:match("^f[cd]") or value:match("^fe[89ab]") then return true end
    -- IPv4-mapped: fall through to the v4 rules
    local mapped = value:match("::ffff:(%d+%.%d+%.%d+%.%d+)$")
    if mapped then
        local a, b, c, d = isDecimalIpv4(mapped)
        return a ~= nil and isReservedIpv4(a, b, c, d)
    end
    return false
end

-- A host is unsafe when it names this machine or a network the server can only
-- reach from inside. Encoded forms are rejected rather than decoded, because
-- anything needing a decode pass to look ordinary has no business here.
function RSRadioExternalIsUnsafeHost(rawHost)
    local host = normalizeHost(rawHost)
    if host == "" then
        return true
    end

    -- Percent-encoding, or any non-hostname character, in the authority.
    if host:find("%%") or host:find("@", 1, true) or host:find("[^%w%.%-%[%]:]") then
        return true
    end

    if BLOCKED_HOST_NAMES[host] then
        return true
    end

    -- Trailing-dot / bare hostnames with no public suffix cannot be public.
    if not host:find("%.") and not host:find(":", 1, true) then
        return true
    end

    if isReservedIpv6(host) then
        return true
    end

    -- Non-decimal IPv4 spellings (octal, hex, dword) are a classic bypass.
    if host:match("^%d") and not host:find(":", 1, true) then
        local a, b, c, d = isDecimalIpv4(host)
        if a == nil then
            if host:match("^[%dxXa-fA-F%.]+$") then
                return true
            end
        elseif isReservedIpv4(a, b, c, d) then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Admission
-- ---------------------------------------------------------------------------

-- Rejects credentials in the authority, control characters, and anything that
-- is not plainly an https URL.
function RSRadioExternalIsAdmissibleUrl(rawUrl)
    local value = trim(rawUrl)
    if value == "" or #value > 2048 then
        return false
    end
    if value:find("[%c]") then
        return false
    end
    if not value:lower():match("^https://") then
        return false
    end

    local authority = value:match("^[hH][tT][tT][pP][sS]://([^/%?#]+)")
    if not authority then
        return false
    end
    -- user-info section ("https://user:pass@host") is never accepted
    if authority:find("@", 1, true) then
        return false
    end

    return not RSRadioExternalIsUnsafeHost(authority)
end

-- ---------------------------------------------------------------------------
-- Providers
-- ---------------------------------------------------------------------------

function RSRadioExternalIsYoutubeUrl(rawUrl)
    if Config and Config.YoutubeEnabled ~= true then
        return false
    end
    if not RSRadioExternalIsAdmissibleUrl(rawUrl) then
        return false
    end

    local host = normalizeHost(lowerHostOf(rawUrl)):gsub("^www%.", "")
    return host == "youtube.com"
        or host == "youtu.be"
        or host == "music.youtube.com"
        or host == "m.youtube.com"
end

function RSRadioExternalIsSoundCloudUrl(rawUrl)
    if Config and Config.SoundCloudEnabled ~= true then
        return false
    end
    if not RSRadioExternalIsAdmissibleUrl(rawUrl) then
        return false
    end

    local host = normalizeHost(lowerHostOf(rawUrl)):gsub("^www%.", "")
    return host == "soundcloud.com" or host:match("%.soundcloud%.com$") ~= nil
end

-- Google's media endpoints are the delivery side of a resolve, never something
-- a player should be able to submit directly.
local function isDeliveryEndpoint(rawUrl)
    local lower = trim(rawUrl):lower()
    local host = normalizeHost(lowerHostOf(lower) or "")
    local path = lower:match("^https://[^/%?#]+([^%?#]*)") or ""
    return (host == "googlevideo.com" or host:match("%.googlevideo%.com$") ~= nil)
        and path:find("/videoplayback", 1, true) ~= nil
end

local DIRECT_AUDIO_EXTENSIONS = {
    ogg = true, oga = true, opus = true, mp3 = true, wav = true,
    m4a = true, aac = true, flac = true, webm = true, mp4 = true
}

function RSRadioExternalIsDirectAudioUrl(rawUrl)
    if Config and Config.DirectLinksEnabled ~= true then
        return false
    end
    if not RSRadioExternalIsAdmissibleUrl(rawUrl) then
        return false
    end
    if isDeliveryEndpoint(rawUrl) then
        return false
    end

    local path = trim(rawUrl):lower():match("^https://[^/%?#]+([^%?#]*)") or ""
    local extension = tostring(path:match("%.([%w]+)$") or "")
    return DIRECT_AUDIO_EXTENSIONS[extension] == true
end

function RSRadioExternalIsSupportedUrl(rawUrl)
    return RSRadioExternalIsYoutubeUrl(rawUrl)
        or RSRadioExternalIsSoundCloudUrl(rawUrl)
        or RSRadioExternalIsDirectAudioUrl(rawUrl)
end

function RSRadioExternalClassifyUrl(rawUrl)
    local value = trim(rawUrl)
    if value == "" then
        return "invalid"
    end
    if RSRadioExternalIsSoundCloudUrl(value) then
        return "soundcloud_track"
    end
    if RSRadioExternalIsDirectAudioUrl(value) then
        return "direct_audio"
    end
    if not RSRadioExternalIsYoutubeUrl(value) then
        return "invalid"
    end

    if value:match("youtube%.com/live/") then
        return "youtube_live"
    end
    if RSRadioExternalExtractYoutubeVideoId(value) ~= "" then
        return "youtube_video"
    end
    if value:match("[?&]list=") or value:match("youtube%.com/playlist%?") then
        return "youtube_playlist"
    end
    return "youtube_video"
end

function RSRadioExternalExtractYoutubeVideoId(rawUrl)
    local raw = trim(rawUrl)
    if raw == "" then
        return ""
    end

    local direct = raw:match("^[%w%-_]+$")
    if direct and #direct == 11 then
        return direct
    end

    local id = raw:match("[?&]v=([%w%-_]+)")
        or raw:match("youtu%.be/([%w%-_]+)")
        or raw:match("/shorts/([%w%-_]+)")
        or raw:match("/embed/([%w%-_]+)")
        or raw:match("/live/([%w%-_]+)")
    if id and #id >= 11 then
        return id:sub(1, 11)
    end
    return ""
end

-- ---------------------------------------------------------------------------
-- Listener allowlist
-- ---------------------------------------------------------------------------
-- Owner-curated links players may submit (Config.ListenerCustomAllowlist).
-- Matching is by identity, not by string: every YouTube URL form collapses to
-- the video id, playlists to the list id, SoundCloud to host + path, direct
-- links to the exact URL or an allowed folder prefix.

local allowlistIndex = nil

local function allowlistSoundCloudKey(rawUrl)
    local lower = trim(rawUrl):lower()
    local host, path = lower:match("^https://([^/%?#]+)([^%?#]*)")
    if not host then
        return nil
    end
    host = normalizeHost(host):gsub("^www%.", ""):gsub("^m%.", "")
    path = tostring(path or ""):gsub("/+$", "")
    if path == "" then
        return nil
    end
    return "sc:" .. host .. path
end

local function allowlistDirectKey(rawUrl)
    local lower = trim(rawUrl):lower():gsub("#.*$", "")
    return lower ~= "" and ("url:" .. lower) or nil
end

local function buildAllowlistIndex()
    local index = { keys = {}, prefixes = {}, count = 0 }
    local list = Config and Config.ListenerCustomAllowlist
    if type(list) ~= "table" then
        return index
    end
    for _, raw in pairs(list) do
        local value = trim(raw)
        if value ~= "" then
            local matched = false
            local videoId = RSRadioExternalExtractYoutubeVideoId(value)
            if videoId ~= "" then
                index.keys["yt:" .. videoId] = true
                matched = true
            end
            local listId = value:match("[?&]list=([%w%-_]+)")
            if listId then
                index.keys["ytlist:" .. listId] = true
                matched = true
            end
            local scKey = allowlistSoundCloudKey(value)
            if scKey then
                index.keys[scKey] = true
                matched = true
            end
            if not matched then
                local lower = value:lower():gsub("#.*$", "")
                if lower:sub(-1) == "/" then
                    index.prefixes[#index.prefixes + 1] = lower
                else
                    index.keys["url:" .. lower] = true
                end
            end
            index.count = index.count + 1
        end
    end
    return index
end

local function allowlist()
    if allowlistIndex == nil then
        allowlistIndex = buildAllowlistIndex()
    end
    return allowlistIndex
end

function RSRadioExternalListenerAllowlistActive()
    return allowlist().count > 0
end

function RSRadioExternalIsListenerAllowlistedUrl(rawUrl)
    local index = allowlist()
    if index.count == 0 then
        return true
    end
    local value = trim(rawUrl)
    local kind = RSRadioExternalClassifyUrl(value)
    if kind == "youtube_video" or kind == "youtube_live" then
        local videoId = RSRadioExternalExtractYoutubeVideoId(value)
        return videoId ~= "" and index.keys["yt:" .. videoId] == true
    end
    if kind == "youtube_playlist" then
        local listId = value:match("[?&]list=([%w%-_]+)")
        return listId ~= nil and index.keys["ytlist:" .. listId] == true
    end
    if kind == "soundcloud_track" then
        local key = allowlistSoundCloudKey(value)
        return key ~= nil and index.keys[key] == true
    end
    if kind == "direct_audio" then
        local key = allowlistDirectKey(value)
        if key and index.keys[key] == true then
            return true
        end
        local lower = value:lower()
        for i = 1, #index.prefixes do
            local prefix = index.prefixes[i]
            if lower:sub(1, #prefix) == prefix then
                return true
            end
        end
        return false
    end
    return false
end
