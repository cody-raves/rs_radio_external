-- Client attachment.
--
-- The base asks registered providers whether they recognise a segment's output
-- reference. We answer for references this resource minted, and hand back a
-- handle that owns the actual audio for as long as the segment is on air.
--
-- The base never learns what is behind the reference. It keeps doing what it
-- always does: placing the emitter, choosing the audience, applying volume and
-- EQ, and routing listeners.

local PROVIDER_NAME = "rs_radio_external"

local activeHandles = {}

local function trace(message)
    if Config and Config.Trace == true then
        print(("[rs_radio_external] %s"):format(tostring(message or "")))
    end
end

local function baseResource()
    return RSRadioExternalBaseResource and RSRadioExternalBaseResource() or "rs_radio"
end

-- References this resource minted are tagged so a session belonging to some
-- other provider is left alone.
local function isOwnReference(outputRef)
    return type(outputRef) == "string" and outputRef:sub(1, #PROVIDER_NAME + 1) == (PROVIDER_NAME .. ":")
end

local function closeHandle(sessionId, reason)
    local handle = activeHandles[sessionId]
    if type(handle) ~= "table" then
        return
    end
    activeHandles[sessionId] = nil

    if type(RSRadioExternalStopPlayback) == "function" then
        pcall(RSRadioExternalStopPlayback, handle, tostring(reason or "closed"))
    end
    trace(("released session %s (%s)"):format(tostring(sessionId), tostring(reason)))
end

local provider = {
    claim = function(descriptor)
        return type(descriptor) == "table" and isOwnReference(descriptor.outputRef)
    end,

    open = function(descriptor, context)
        local sessionId = tostring(descriptor.sessionId or descriptor.outputRef)

        -- A repeated open for the same session replaces the previous handle
        -- rather than stacking a second player on the same emitter.
        closeHandle(sessionId, "reopened")

        local handle = {
            sessionId = sessionId,
            outputRef = descriptor.outputRef,
            relayAsset = descriptor.relayAsset,
            context = type(context) == "table" and context or {}
        }

        if type(RSRadioExternalStartPlayback) == "function" then
            local ok, started = pcall(RSRadioExternalStartPlayback, handle)
            if not ok or started ~= true then
                trace(("could not start playback for %s"):format(tostring(sessionId)))
                return nil
            end
        end

        handle.close = function(reason)
            closeHandle(sessionId, reason)
        end

        activeHandles[sessionId] = handle
        trace(("opened session %s"):format(tostring(sessionId)))
        return handle
    end
}

local function register()
    local ok = pcall(function()
        exports[baseResource()]:registerOutputProvider(PROVIDER_NAME, provider)
    end)
    local uiOk = pcall(function()
        -- Version query busts CEF's cache so clients pick up adapter updates
        -- immediately instead of serving a stale module after upgrades.
        exports[baseResource()]:registerUiModule(PROVIDER_NAME, ("https://cfx-nui-%s/nui/adapter.js?v=%s"):format(
            GetCurrentResourceName(),
            GetResourceMetadata(GetCurrentResourceName(), "version", 0) or "0"
        ))
    end)
    if ok and uiOk then
        trace("registered output provider and ui module")
    end
    return ok and uiOk
end

local function releaseAll(reason)
    for sessionId in pairs(activeHandles) do
        closeHandle(sessionId, reason)
    end
end

RSRadioExternalReleaseAllClientSessions = releaseAll

CreateThread(function()
    -- Wait for the base to be up before registering; it owns the registry.
    local attempts = 0
    while attempts < 30 do
        attempts = attempts + 1
        if GetResourceState(baseResource()) == "started" and register() then
            return
        end
        Wait(2000)
    end
end)

AddEventHandler("onClientResourceStart", function(resourceName)
    if resourceName == baseResource() then
        releaseAll("base_restarted")
        register()
    end
end)

AddEventHandler("onClientResourceStop", function(resourceName)
    if resourceName == baseResource() then
        releaseAll("base_stopped")
        return
    end

    if resourceName == GetCurrentResourceName() then
        releaseAll("resource_stopped")
        pcall(function()
            exports[baseResource()]:unregisterOutputProvider(PROVIDER_NAME)
        end)
    end
end)
