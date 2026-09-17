-- Legacy data migration.
--
-- Older all-in-one installs kept remote entries inside the base radio's
-- station rows and players' browser storage. This copies that data into
-- tables this resource owns. Everything here is copy-only: no source row is
-- modified or deleted, and receipts make every step run at most once.

local MIGRATIONS_TABLE = "rs_radio_external_migrations"
local STATION_MEDIA_TABLE = "rs_radio_external_station_media"
local PLAYER_PLAYLISTS_TABLE = "rs_radio_external_player_playlists"
local LEGACY_STATION_TABLE = "rs_radio_admin_stations"
local BROWSER_PLAYLISTS_KEY = "rs_radio_listener_custom_playlists_v1"

local sqlReady = false

local function log(message)
    print(("[rs_radio_external][migrate] %s"):format(tostring(message or "")))
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function isRemoteUrl(value)
    return type(value) == "string" and value:lower():match("^https?://") ~= nil
end

local function ensureSql()
    if sqlReady then
        return true
    end
    if not MySQL or not MySQL.query or not MySQL.query.await then
        return false
    end

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `migration_key` VARCHAR(128) NOT NULL,
            `detail` VARCHAR(255) NULL DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`migration_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(MIGRATIONS_TABLE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `station_id` VARCHAR(64) NOT NULL,
            `category` VARCHAR(16) NOT NULL,
            `position` INT NOT NULL DEFAULT 0,
            `title` VARCHAR(255) NULL DEFAULT NULL,
            `url` TEXT NOT NULL,
            `duration_sec` INT NULL DEFAULT NULL,
            `migrated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `station_category` (`station_id`, `category`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(STATION_MEDIA_TABLE))

    MySQL.query.await(([[
        CREATE TABLE IF NOT EXISTS `%s` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(128) NOT NULL,
            `name` VARCHAR(120) NOT NULL,
            `items_json` LONGTEXT NOT NULL,
            `imported_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]):format(PLAYER_PLAYLISTS_TABLE))

    sqlReady = true
    return true
end

local function hasReceipt(key)
    local rows = MySQL.query.await(
        ("SELECT `migration_key` FROM `%s` WHERE `migration_key` = ?"):format(MIGRATIONS_TABLE),
        { key }
    ) or {}
    return rows[1] ~= nil
end

local function writeReceipt(key, detail)
    MySQL.update.await(
        ("INSERT IGNORE INTO `%s` (`migration_key`, `detail`) VALUES (?, ?)"):format(MIGRATIONS_TABLE),
        { key, tostring(detail or "") }
    )
end

-- ---------------------------------------------------------------------------
-- Station rows: copy remote entries out of legacy media json
-- ---------------------------------------------------------------------------

local function copyRemoteEntries(stationId, category, rawJson)
    local ok, decoded = pcall(json.decode, tostring(rawJson or ""))
    if not ok or type(decoded) ~= "table" then
        return 0
    end

    local copied = 0
    for position, entry in ipairs(decoded) do
        if type(entry) == "table" then
            local url = trim(entry.sourceUrl or entry.originalUrl or entry.file or entry.url)
            if isRemoteUrl(url) then
                MySQL.update.await(([[
                    INSERT INTO `%s` (`station_id`, `category`, `position`, `title`, `url`, `duration_sec`)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]]):format(STATION_MEDIA_TABLE), {
                    stationId,
                    category,
                    position,
                    trim(entry.title):sub(1, 255),
                    url,
                    tonumber(entry.durationSec) or nil
                })
                copied = copied + 1
            end
        end
    end
    return copied
end

function RSRadioExternalMigrateStationMedia()
    if not ensureSql() then
        return false, "sql_unavailable"
    end
    if hasReceipt("station_media_v1") then
        return true, "already_done"
    end

    local ok, rows = pcall(function()
        return MySQL.query.await(("SELECT `station_id`, `music_json`, `ads_json`, `sfx_json` FROM `%s`"):format(LEGACY_STATION_TABLE)) or {}
    end)
    if not ok then
        -- No legacy table at all: nothing to migrate.
        writeReceipt("station_media_v1", "no_legacy_table")
        return true, "no_legacy_table"
    end

    local total = 0
    for _, row in ipairs(rows) do
        local stationId = trim(row.station_id)
        if stationId ~= "" then
            total = total + copyRemoteEntries(stationId, "music", row.music_json)
            total = total + copyRemoteEntries(stationId, "ad", row.ads_json)
            total = total + copyRemoteEntries(stationId, "sfx", row.sfx_json)
        end
    end

    writeReceipt("station_media_v1", ("copied=%d rows=%d"):format(total, #rows))
    log(("station media migration: copied %d remote entr%s from %d station row(s)"):format(
        total, total == 1 and "y" or "ies", #rows
    ))
    return true, total
end

-- ---------------------------------------------------------------------------
-- Browser-local named playlists: one-time import per player
-- ---------------------------------------------------------------------------

local function playerOwner(src)
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if identifier:match("^license:") then
            return identifier
        end
    end
    return trim(GetPlayerIdentifiers(src) and GetPlayerIdentifiers(src)[1])
end

local function importBrowserPlaylists(src, rawJson)
    local owner = playerOwner(src)
    if owner == "" then
        return
    end
    local receiptKey = ("browser_playlists:%s"):format(owner)
    if hasReceipt(receiptKey) then
        return
    end

    local imported = 0
    local ok, decoded = pcall(json.decode, tostring(rawJson or ""))
    if ok and type(decoded) == "table" then
        for _, playlist in ipairs(decoded) do
            if type(playlist) == "table" then
                local name = trim(playlist.name or playlist.label):sub(1, 120)
                local items = type(playlist.items) == "table" and playlist.items
                    or (type(playlist.tracks) == "table" and playlist.tracks or nil)
                if name ~= "" and items ~= nil and #items > 0 then
                    MySQL.update.await(([[
                        INSERT INTO `%s` (`owner`, `name`, `items_json`) VALUES (?, ?, ?)
                    ]]):format(PLAYER_PLAYLISTS_TABLE), {
                        owner, name, json.encode(items)
                    })
                    imported = imported + 1
                end
            end
        end
    end

    writeReceipt(receiptKey, ("imported=%d"):format(imported))
    if imported > 0 then
        log(("imported %d browser playlist(s) for %s"):format(imported, owner))
    end
end

AddEventHandler("rs_radio_external:uiArchiveReply", function(src, key, data, err)
    if key ~= BROWSER_PLAYLISTS_KEY or type(data) ~= "string" or data == "" then
        return
    end
    if not ensureSql() then
        return
    end
    importBrowserPlaylists(src, data)
end)

local function requestBrowserPlaylists(src)
    if Config.MigrationImportBrowserPlaylists ~= true then
        return
    end
    if not ensureSql() then
        return
    end
    local owner = playerOwner(src)
    if owner == "" or hasReceipt(("browser_playlists:%s"):format(owner)) then
        return
    end

    RSRadioExternalWithBase(function(base)
        return base:requestUiArchive(src, BROWSER_PLAYLISTS_KEY, "rs_radio_external:uiArchiveReply")
    end)
end

AddEventHandler("playerJoining", function()
    local src = source
    SetTimeout(20000, function()
        if GetPlayerPing(src) > 0 then
            requestBrowserPlaylists(src)
        end
    end)
end)

-- Station media runs once, when we first attach with SQL available.
CreateThread(function()
    while not (RSRadioExternalIsAttached and RSRadioExternalIsAttached()) do
        Wait(2500)
    end
    if Config.MigrationEnabled == true then
        RSRadioExternalMigrateStationMedia()
    end
end)
