-- Installing the supplied stations into the base.
--
-- Only the neutral metadata goes across: labels, coordinates, blips, mic
-- channels. The catalogs stay in this resource. Installation is safe to repeat
-- and only ever touches rows stamped with this package.

local PACKAGE_LOGGED = false

local function packageId()
    return tostring(Config and Config.StationPackageId or "rs_radio_external.builtin")
end

-- Base package operations reply through a server event carrying our
-- correlation id; wait for that reply here so the rest of this file can stay
-- written in plain sequential style.
local packagedReplies = {}
local packagedReplySeq = 0

AddEventHandler("rs-radio:packageOperationResult", function(replyId, report)
    local waiter = packagedReplies[tostring(replyId or "")]
    if waiter ~= nil then
        packagedReplies[tostring(replyId)] = nil
        waiter:resolve(report)
    end
end)

local function awaitBasePackaged(method, argA, argB)
    if not (RSRadioExternalIsAttached and RSRadioExternalIsAttached()) then
        return nil, "not_attached"
    end

    packagedReplySeq = packagedReplySeq + 1
    local replyId = ("%s_%d_%d"):format(GetCurrentResourceName(), GetGameTimer(), packagedReplySeq)
    local p = promise.new()
    packagedReplies[replyId] = p

    local ok, err = pcall(function()
        local base = exports[RSRadioExternalBaseResource()]
        base[method](base, argA, argB, replyId)
    end)
    if not ok then
        packagedReplies[replyId] = nil
        return nil, tostring(err or "base_call_failed")
    end

    SetTimeout(30000, function()
        local waiter = packagedReplies[replyId]
        if waiter ~= nil then
            packagedReplies[replyId] = nil
            waiter:resolve(nil)
        end
    end)

    local report = Citizen.Await(p)
    if report == nil then
        return nil, "base_timeout"
    end
    return report
end

local function log(message)
    print(("[rs_radio_external][stations] %s"):format(tostring(message or "")))
end

local function describe(report)
    if type(report) ~= "table" then
        return "no report"
    end
    if report.ok == false then
        return ("failed: %s"):format(tostring(report.error or "unknown"))
    end

    local function count(list)
        return type(list) == "table" and #list or 0
    end
    return ("installed %d, updated %d, adopted %d, skipped %d"):format(
        count(report.installed), count(report.updated),
        count(report.adopted), count(report.skipped)
    )
end

local function reportSkips(report)
    if type(report) ~= "table" or type(report.skipped) ~= "table" then
        return
    end
    for _, skip in ipairs(report.skipped) do
        local reason = tostring(skip.reason or "")
        -- "unchanged" is the normal steady state, not worth a line every start.
        if reason ~= "unchanged" then
            if reason == "modified_needs_adoption" then
                log(("%s already exists and has been edited, so it was left alone. "):format(tostring(skip.stationId))
                    .. ("Run /%s adopt %s to take it over."):format(
                        tostring(Config and Config.AdminCommandName or "radioexternalstations"),
                        tostring(skip.stationId)))
            else
                log(("%s skipped (%s)"):format(tostring(skip.stationId), reason))
            end
        end
    end
end

function RSRadioExternalInstallStations()
    if Config and Config.StationPackageEnabled ~= true then
        return { ok = false, error = "disabled" }
    end

    local definitions = RSRadioExternalPackageDefinitions and RSRadioExternalPackageDefinitions() or {}
    if #definitions == 0 then
        return { ok = false, error = "no_definitions" }
    end

    local report, err
    for attempt = 1, 15 do
        report, err = awaitBasePackaged("installStationPackage", packageId(), definitions)
        local failure = type(report) ~= "table" and tostring(err or "") or tostring(report.error or "")
        -- The base registers its package exports after its own database comes
        -- up; keep trying while it is still booting or not yet answering.
        if not (failure:find("No such export", 1, true) or failure:find("base_timeout", 1, true)) then
            break
        end
        log(("install attempt %d: %s; retrying"):format(attempt, failure))
        Wait(2000)
    end

    if type(report) ~= "table" then
        report = { ok = false, error = tostring(err or "no_response") }
    end

    local allUnchanged = report.ok ~= false
        and #(report.installed or {}) == 0 and #(report.updated or {}) == 0 and #(report.adopted or {}) == 0
    local unchangedCount = 0
    for _, skip in ipairs(report.skipped or {}) do
        if tostring(skip.reason) == "unchanged" then unchangedCount = unchangedCount + 1 end
    end
    if allUnchanged and unchangedCount == #(report.skipped or {}) and unchangedCount > 0 then
        log(("stations ready (%d)"):format(unchangedCount))
    else
        log(describe(report))
    end
    PACKAGE_LOGGED = true
    reportSkips(report)
    return report
end

function RSRadioExternalRemoveStations(keepDefinitions)
    local report, err = awaitBasePackaged("removeStationPackage", packageId(), { keepDefinitions = keepDefinitions == true })
    if type(report) ~= "table" then
        return { ok = false, error = tostring(err or "no_response") }
    end
    return report
end

local function runSelfCheck()
    local function say(message)
        print(("[rs_radio_external][selfcheck] %s"):format(tostring(message)))
    end

    local okClassify, kind = pcall(function()
        return exports[RSRadioExternalBaseResource()]:classifySource("https://soundcloud.com/artist/track")
    end)
    say(("base classify soundcloud=%s (ok=%s)"):format(tostring(kind), tostring(okClassify)))

    for _, id in ipairs({ "south", "north", "subsonic" }) do
        local media = type(RSRadioExternalPackageCatalog) == "function"
            and RSRadioExternalPackageCatalog(id) or nil
        say(("catalog %s: music=%s stationAds=%s sfx=%s"):format(
            id,
            media and #(media.playlistItems or {}) or "nil",
            media and #(media.stationAdsItems or {}) or "nil",
            media and #(media.sfxItems or {}) or "nil"))
    end

    local adsRaw = LoadResourceFile(GetCurrentResourceName(), "data/product_ads.json")
    local adsOk, ads = pcall(json.decode, tostring(adsRaw or ""))
    say(("product ads: %s (served to south + north)"):format(
        adsOk and type(ads) == "table" and #ads or "unreadable"))

    for _, id in ipairs({ "south", "north", "subsonic" }) do
        local okDiag, diag = pcall(function()
            return exports[RSRadioExternalBaseResource()]:getStationDiag(id)
        end)
        if okDiag and type(diag) == "table" then
            say(("station %s: playlist=%s live=%s autonomous=%s resolving=%s onAir=%s"):format(
                id, tostring(diag.playlist), tostring(diag.live), tostring(diag.autonomous),
                tostring(diag.resolvePending), tostring(diag.onAir or "none")))
        else
            say(("station %s: diag failed (%s)"):format(id, tostring(diag)))
        end
    end
end

-- Called by sv_attach once the base has accepted the contract.
function RSRadioExternalOnAttached()
    if type(RSRadioExternalRegisterAdapter) == "function" then
        RSRadioExternalRegisterAdapter()
    end
    RSRadioExternalInstallStations()
    if Config and Config.Trace == true then
        SetTimeout(10000, runSelfCheck)
        SetTimeout(40000, runSelfCheck)
    end
end

-- ---------------------------------------------------------------------------
-- Reconciliation command
-- ---------------------------------------------------------------------------

local function isAllowed(src)
    if src == 0 then
        return true
    end
    return IsPlayerAceAllowed(src, tostring(Config and Config.StationControlAcePermission or "rsradio.external")) == true
end

local function reply(src, message)
    if src == 0 then
        print(("[rs_radio_external] %s"):format(message))
    else
        TriggerClientEvent("chat:addMessage", src, { args = { "rs_radio_external", message } })
    end
end

RegisterCommand(tostring(Config and Config.AdminCommandName or "radioexternalstations"), function(src, args)
    if not isAllowed(src) then
        reply(src, "You do not have permission to manage the station package.")
        return
    end

    local action = tostring(args and args[1] or "status"):lower()

    if action == "install" or action == "sync" then
        reply(src, describe(RSRadioExternalInstallStations()))

    elseif action == "remove" then
        local report = RSRadioExternalRemoveStations(false)
        reply(src, type(report.removed) == "table"
            and ("removed %d station(s)"):format(#report.removed)
            or ("failed: %s"):format(tostring(report.error)))

    elseif action == "release" then
        -- Leave the stations in place but stop owning them.
        local report = RSRadioExternalRemoveStations(true)
        reply(src, type(report.removed) == "table"
            and ("released %d station(s); they remain as ordinary stations"):format(#report.removed)
            or ("failed: %s"):format(tostring(report.error)))

    elseif action == "adopt" then
        local stationId = tostring(args and args[2] or "")
        if stationId == "" then
            reply(src, "Usage: adopt <stationId>")
            return
        end
        local report = awaitBasePackaged("adoptStationRow", packageId(), stationId)
        local adopted = type(report) == "table" and report.ok == true
        reply(src, adopted and ("adopted %s"):format(stationId)
            or ("could not adopt %s: %s"):format(stationId,
                tostring(type(report) == "table" and report.error or "no_response")))

    else
        local rows = awaitBasePackaged("getStationPackageRows", packageId())
        local owned = type(rows) == "table" and #rows or 0
        reply(src, ("attached=%s owned=%d package=%s"):format(
            tostring(RSRadioExternalIsAttached and RSRadioExternalIsAttached() or false),
            owned, packageId()
        ))
        reply(src, "Actions: status, install, remove, release, adopt <stationId>")
    end
end, false)
