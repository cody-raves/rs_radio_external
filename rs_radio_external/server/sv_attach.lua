-- Attachment to the base radio.
--
-- Everything this resource does flows through the base's output session API.
-- If the base is missing, older than this build, or restarting, we simply do
-- not attach: the radio carries on playing local files and no external media is
-- offered. Failures are reported here, in this resource's own console, because
-- the base has no knowledge of us.

local attached = false
local attachAttempt = 0

local function log(message)
    print(("[rs_radio_external] %s"):format(tostring(message or "")))
end

local function trace(message)
    if Config and Config.Trace == true then
        log(message)
    end
end

local function baseResource()
    return RSRadioExternalBaseResource and RSRadioExternalBaseResource() or "rs_radio"
end

local function baseIsRunning()
    return GetResourceState(baseResource()) == "started"
end

-- Reads the base's advertised contract level. Any error here is treated as
-- "not available yet" rather than a hard failure, because the usual cause is
-- simply that the base has not finished starting.
local function readBaseContract()
    local name = baseResource()
    local ok, result = pcall(function()
        return exports[name]:getIntegrationVersion()
    end)

    if not ok or type(result) ~= "table" then
        return nil
    end

    return {
        api = tonumber(result.api) or 0,
        build = tostring(result.build or "")
    }
end

function RSRadioExternalIsAttached()
    return attached == true
end

-- Guarded entry point for the rest of the resource. Anything that wants to
-- reach the base goes through here so a detached state can never turn into a
-- half-applied change.
function RSRadioExternalWithBase(fn)
    if not attached or type(fn) ~= "function" then
        return nil, "not_attached"
    end

    local ok, result, err = pcall(fn, exports[baseResource()])
    if not ok then
        return nil, tostring(result or "base_call_failed")
    end
    return result, err
end

local function detach(reason)
    if not attached then
        return
    end
    attached = false

    if type(RSRadioExternalReleaseAllSessions) == "function" then
        pcall(RSRadioExternalReleaseAllSessions, tostring(reason or "detached"))
    end
    if type(RSRadioExternalUnregisterAdapter) == "function" then
        pcall(RSRadioExternalUnregisterAdapter)
    end

    log(("detached from %s (%s); radio continues with local files"):format(
        baseResource(), tostring(reason or "unknown")
    ))
end

local function attach()
    if attached then
        return true
    end

    if not baseIsRunning() then
        trace("base resource is not running yet")
        return false
    end

    local contract = readBaseContract()
    if contract == nil then
        trace("base has not published an integration contract yet")
        return false
    end

    local required = tonumber(RSRadioExternalContract and RSRadioExternalContract.requiredApi) or 0
    if contract.api ~= required then
        log(("not attaching: %s reports integration api %s, this build needs %s. "):format(
            baseResource(), tostring(contract.api), tostring(required)
        ) .. "Update both resources to matching versions. The radio is unaffected.")
        return false
    end

    attached = true
    log(("attached to %s (api %s, build %s)"):format(
        baseResource(), tostring(contract.api), tostring(contract.build)
    ))

    if type(RSRadioExternalOnAttached) == "function" then
        local ok, err = pcall(RSRadioExternalOnAttached)
        if not ok then
            log(("startup step failed after attach: %s"):format(tostring(err)))
        end
    end

    return true
end

RSRadioExternalAttach = attach

-- Retry while the base is starting, then stop. A server without the base
-- installed should not log on a loop forever.
local function attachWithBackoff()
    attachAttempt = 0
    CreateThread(function()
        while not attached and attachAttempt < 30 do
            attachAttempt = attachAttempt + 1
            if attach() then
                return
            end
            Wait(2000)
        end

        if not attached and baseIsRunning() then
            log(("gave up attaching to %s after %s attempts"):format(baseResource(), tostring(attachAttempt)))
        end
    end)
end

AddEventHandler("onResourceStart", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        attachWithBackoff()
        return
    end

    -- The base restarted underneath us: every session it was holding is gone.
    if resourceName == baseResource() then
        detach("base_restarted")
        attachWithBackoff()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == baseResource() then
        detach("base_stopped")
        return
    end

    if resourceName == GetCurrentResourceName() then
        detach("resource_stopped")
    end
end)
