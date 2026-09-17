-- Supplied station package.
--
-- These three stations and every track behind them belong to this resource.
-- The base radio never ships them; it only receives the neutral metadata below
-- (labels, coordinates, blips, mic channels) through the station package API,
-- and the catalogs stay here where the media they point at is understood.

local catalogs = {
    south = {
        playlistItems =         {
            { title = "24 7 Run", file = "https://soundcloud.com/cody_raves/24_7_run-1/s-hXJxok3gDuJ", durationSec = 65 },
            { title = "After The Alarm", file = "https://soundcloud.com/cody_raves/after_the_alarm-2/s-s5o30B7kvTy", durationSec = 273 },
            { title = "Benny Built", file = "https://soundcloud.com/cody_raves/benny_built-3/s-aDOBo07iRcR", durationSec = 75 },
            { title = "Blaine County Smoke", file = "https://soundcloud.com/cody_raves/blaine_county_smoke-4/s-bN9vvz5iwwD", durationSec = 213 },
            { title = "Chrome Coast", file = "https://soundcloud.com/cody_raves/chrome_coast-5/s-2glCJwKuoup", durationSec = 215 },
            { title = "City Teeth", file = "https://soundcloud.com/cody_raves/city_teeth-6/s-EUNDPJ1tzlC", durationSec = 296 },
            { title = "Corner Green", file = "https://soundcloud.com/cody_raves/corner_green-7/s-iT7N9fNdB6c", durationSec = 2 },
            { title = "Diamond Dust", file = "https://soundcloud.com/cody_raves/diamond_dust-8/s-C2jYYKYtBDc", durationSec = 280 },
            { title = "Diamond Floor", file = "https://soundcloud.com/cody_raves/diamond_floor-9/s-niGlZ7lqYkH", durationSec = 83 },
            { title = "Dust Name", file = "https://soundcloud.com/cody_raves/dust_name-10/s-7PKq01Lh00C", durationSec = 303 },
            { title = "Dust On They Colors", file = "https://soundcloud.com/cody_raves/dust_on_they_colors-11/s-MB4eh4RU2Qa", durationSec = 290 },
            { title = "Engine Still Running", file = "https://soundcloud.com/cody_raves/engine_still_running-12/s-AfPbtEX5oWz", durationSec = 290 },
            { title = "Fleeca Friday", file = "https://soundcloud.com/cody_raves/fleeca_friday-13/s-7l9t9NBGc2y", durationSec = 50 },
            { title = "Ghost Keys", file = "https://soundcloud.com/cody_raves/ghost_keys-14/s-GARknOYDCZr", durationSec = 303 },
            { title = "Great Ocean Glide", file = "https://soundcloud.com/cody_raves/great_ocean_glide-15/s-8CLnXDHuWtA", durationSec = 275 },
            { title = "Green Ain't Gold", file = "https://soundcloud.com/cody_raves/green_aint_gold-16/s-RP6BqxfIeHL", durationSec = 310 },
            { title = "Green Rag", file = "https://soundcloud.com/cody_raves/green_rag-17/s-dPcr2f62FV7", durationSec = 290 },
            { title = "Heavy On Fig", file = "https://soundcloud.com/cody_raves/heavy_on_fig-18/s-eWKroYsJlAs", durationSec = 301 },
            { title = "Hot Ignition", file = "https://soundcloud.com/cody_raves/hot_ignition-19/s-TLYDOnnOaAl", durationSec = 305 },
            { title = "La Mesa", file = "https://soundcloud.com/cody_raves/la_mesa-20/s-tkvQDnAO8hq", durationSec = 60 },
            { title = "Lot Nights", file = "https://soundcloud.com/cody_raves/lot_nights-21/s-DZsdkrKS9S4", durationSec = 320 },
            { title = "Ls After Dark", file = "https://soundcloud.com/cody_raves/ls_after_dark-22/s-CnInDjaMnNI", durationSec = 92 },
            { title = "Marble Floors", file = "https://soundcloud.com/cody_raves/marble_floors-23/s-6zlNvHaZ2TE", durationSec = 217 },
            { title = "Mission Row Blues", file = "https://soundcloud.com/cody_raves/mission_row_blues-24/s-oVvg4i2FSfe", durationSec = 288 },
            { title = "Name In The Spray", file = "https://soundcloud.com/cody_raves/name_in_the_spray-25/s-iQaMdNQxGhJ", durationSec = 327 },
            { title = "Names On The Wall", file = "https://soundcloud.com/cody_raves/names_on_the_wall-26/s-uK9hYm2uF7W", durationSec = 302 },
            { title = "Northbound For Blood", file = "https://soundcloud.com/cody_raves/northbound_for_blood-27/s-Px2U7dn2hhl", durationSec = 272 },
            { title = "Punch The Clock", file = "https://soundcloud.com/cody_raves/punch_the_clock-28/s-Gik0vz8tEBd", durationSec = 305 },
            { title = "Purple Fade Fast", file = "https://soundcloud.com/cody_raves/purple_fade_fast-29/s-Sv1QvEnu2LC", durationSec = 300 },
            { title = "Purple Room", file = "https://soundcloud.com/cody_raves/purple_room-30/s-vTDPpdAicPR", durationSec = 322 },
            { title = "Rain On Alta", file = "https://soundcloud.com/cody_raves/rain_on_alta-31/s-eKDJ9WfCusW", durationSec = 285 },
            { title = "Redline Run", file = "https://soundcloud.com/cody_raves/redline_run-32/s-22Y4OV9CzIZ", durationSec = 207 },
            { title = "Strawberry To Del Perro", file = "https://soundcloud.com/cody_raves/strawberry_to_del_perro-33/s-tpnEGPIxJ8p", durationSec = 80 },
            { title = "Sunset On Vinewood", file = "https://soundcloud.com/cody_raves/sunset_on_vinewood-34/s-nOlTPZ4A7vn", durationSec = 271 },
            { title = "Tomorrow Came Today", file = "https://soundcloud.com/cody_raves/tomorrow_came_today-35/s-GkuPY9RHrg2", durationSec = 296 },
            { title = "Torch Cut", file = "https://soundcloud.com/cody_raves/torch_cut-36/s-AnqRNeABQ3B", durationSec = 304 },
            { title = "Trap House", file = "https://soundcloud.com/cody_raves/trap_house-37/s-6FBf1Q5uV8d", durationSec = 91 },
            { title = "Trunk Music", file = "https://soundcloud.com/cody_raves/trunk_music-38/s-uVWqOCpnkmP", durationSec = 91 },
            { title = "Vinewood Dreams", file = "https://soundcloud.com/cody_raves/vinewood_dreams-39/s-O2fqDUHwiKX", durationSec = 100 },
            { title = "Yellow Wash Out", file = "https://soundcloud.com/cody_raves/yellow_wash_out-40/s-kPtHFBqTvUk", durationSec = 299 }
        },
        stationAdsItems =         {
            { title = "Rebel Radio Ad 1", file = "https://soundcloud.com/cody_raves/rebel_radio_ad_1-1/s-gwF23cluC79", durationSec = 180 },
            { title = "Rebel Radio Ad 2", file = "https://soundcloud.com/cody_raves/rebel_radio_ad_2-2/s-6a7pRc0dSXl", durationSec = 180 },
            { title = "Rebel Radio Ad 3", file = "https://soundcloud.com/cody_raves/rebel_radio_ad_3-3/s-E6JXlebzaf8", durationSec = 180 },
            { title = "Rebel Radio Ad 4", file = "https://soundcloud.com/cody_raves/rebel_radio_ad_4-4/s-pfXSMP5nuTj", durationSec = 180 },
            { title = "Rebel Radio Ad 5", file = "https://soundcloud.com/cody_raves/rebel_radio_ad_5-5/s-s2qexMfJ9Pi", durationSec = 180 }
        },
        sfxItems =         {}
    },
    north = {
        playlistItems =         {
            { title = "Bonfire By The Alamo", file = "https://soundcloud.com/cody_raves/bonfire_by_the_alamo-1/s-lTgnNH2pHDt", durationSec = 299 },
            { title = "Coffee And Secrets", file = "https://soundcloud.com/cody_raves/coffee_and_secrets-2/s-uae8IOIfWPt", durationSec = 283 },
            { title = "County Line Owed", file = "https://soundcloud.com/cody_raves/county_line_owed-3/s-BDqFmR6lKQ2", durationSec = 300 },
            { title = "Dust On Route 68", file = "https://soundcloud.com/cody_raves/dust_on_route_68-4/s-tha2zJN5UWg", durationSec = 287 },
            { title = "Ghost On The Alamo", file = "https://soundcloud.com/cody_raves/ghost_on_the_alamo-5/s-XIbpWL5U6sI", durationSec = 315 },
            { title = "Girl At The Yellow Jack", file = "https://soundcloud.com/cody_raves/girl_at_the_yellow_jack-6/s-kkwH8tJR61A", durationSec = 294 },
            { title = "Grapeseed Gold", file = "https://soundcloud.com/cody_raves/grapeseed_gold-7/s-5bh7uLAmEeX", durationSec = 263 },
            { title = "Grease On My Hands", file = "https://soundcloud.com/cody_raves/grease_on_my_hands-8/s-0onIkuqtsTE", durationSec = 331 },
            { title = "Keeping Rust Alive", file = "https://soundcloud.com/cody_raves/keeping_rust_alive-9/s-eXSDxdExxqZ", durationSec = 290 },
            { title = "Midnight Southbound", file = "https://soundcloud.com/cody_raves/midnight_southbound-10/s-cUrfzadsECo", durationSec = 284 },
            { title = "Neon Left Me Lonely", file = "https://soundcloud.com/cody_raves/neon_left_me_lonely-11/s-sAlv3SOzrBm", durationSec = 333 },
            { title = "Passing Through Harmony", file = "https://soundcloud.com/cody_raves/passing_through_harmony-12/s-CiWxyicMz5n", durationSec = 293 },
            { title = "Rows Of Dust", file = "https://soundcloud.com/cody_raves/rows_of_dust-13/s-Y69t4ZMT0FR", durationSec = 294 },
            { title = "Sawdust And Smoke", file = "https://soundcloud.com/cody_raves/sawdust_and_smoke-14/s-sGOnX1glRS0", durationSec = 291 },
            { title = "Southbound Out Of Sandy", file = "https://soundcloud.com/cody_raves/southbound_out_of_sandy-15/s-t3fYdL1oCsw", durationSec = 305 },
            { title = "Tailgate Religion", file = "https://soundcloud.com/cody_raves/tailgate_religion-16/s-ciop4oGDjjv", durationSec = 279 },
            { title = "Trailer Light Blues", file = "https://soundcloud.com/cody_raves/trailer_light_blues-17/s-QJrXdLYWMCz", durationSec = 323 },
            { title = "Up By Chiliad", file = "https://soundcloud.com/cody_raves/up_by_chiliad-18/s-feQME83bIDX", durationSec = 287 },
            { title = "Waterline Sins", file = "https://soundcloud.com/cody_raves/waterline_sins-19/s-MKMGZFsMi6E", durationSec = 301 },
            { title = "White Lightning Country", file = "https://soundcloud.com/cody_raves/white_lightning_country-20/s-RCfR3IdEENh", durationSec = 277 }
        },
        stationAdsItems =         {
            { title = "Rebel Radio North 1", file = "https://soundcloud.com/cody_raves/rebel_radio_north_1-1/s-OvnKWu9X7JS", durationSec = 10 },
            { title = "Rebel Radio North 2", file = "https://soundcloud.com/cody_raves/rebel_radio_north_2-2/s-MzJ5t9zBj9i", durationSec = 10 },
            { title = "Rebel Radio North 3", file = "https://soundcloud.com/cody_raves/rebel_radio_north_3-3/s-2aS98PE15Qd", durationSec = 8 },
            { title = "Rebel Radio North 4", file = "https://soundcloud.com/cody_raves/rebel_radio_north_4-4/s-Asi3QoZw02L", durationSec = 8 },
            { title = "Rebel Radio North 5", file = "https://soundcloud.com/cody_raves/rebel_radio_north_5-5/s-ESra15uQEQX", durationSec = 8 }
        },
        sfxItems =         {}
    },
    subsonic = {
        playlistItems =         {
            { title = "3AM", file = "https://soundcloud.com/cody_raves/3am-1/s-fYVFopLYLvy", durationSec = 179 },
            { title = "Basement", file = "https://soundcloud.com/cody_raves/basement-2/s-xD6yeIz83ko", durationSec = 181 },
            { title = "Bass Atlas", file = "https://soundcloud.com/cody_raves/bass_atlas-3/s-NHzfb9PcWUL", durationSec = 155 },
            { title = "Bassline Roller", file = "https://soundcloud.com/cody_raves/bassline_roller-4/s-4oDv8u7fsZo", durationSec = 168 },
            { title = "Bent Circut", file = "https://soundcloud.com/cody_raves/bent_circut-5/s-j48weMJu5ny", durationSec = 249 },
            { title = "Chrome Hearts", file = "https://soundcloud.com/cody_raves/chrome_hearts-6/s-srJErkyMJxE", durationSec = 181 },
            { title = "Cinnamon", file = "https://soundcloud.com/cody_raves/cinnamon-7/s-73R9lOciZuT", durationSec = 158 },
            { title = "Concrete", file = "https://soundcloud.com/cody_raves/concrete-8/s-TECKKiciKns", durationSec = 155 },
            { title = "Creepin", file = "https://soundcloud.com/cody_raves/creepin-9/s-PFG1QxsRaMI", durationSec = 202 },
            { title = "Downbeat", file = "https://soundcloud.com/cody_raves/downbeat-10/s-SN8p4rgsAO3", durationSec = 184 },
            { title = "Fog On The Coast", file = "https://soundcloud.com/cody_raves/fog_on_the_coast-11/s-1rinPfzN2Hu", durationSec = 235 },
            { title = "Foghorn", file = "https://soundcloud.com/cody_raves/foghorn-12/s-jeVCv8MstS9", durationSec = 193 },
            { title = "Ghost Drive", file = "https://soundcloud.com/cody_raves/ghost_drive-13/s-r7cvzeRojmt", durationSec = 222 },
            { title = "Half Tone", file = "https://soundcloud.com/cody_raves/half_tone-14/s-PxABbgouI0I", durationSec = 186 },
            { title = "Jet Black", file = "https://soundcloud.com/cody_raves/jet_black-15/s-8vT8zllk2oz", durationSec = 197 },
            { title = "Los Santos 2 Step", file = "https://soundcloud.com/cody_raves/los_santos_2_step-16/s-bQyerhH9JAz", durationSec = 195 },
            { title = "Los Santos Shutdown", file = "https://soundcloud.com/cody_raves/los_santos_shutdown-17/s-XoAGtwT7c7m", durationSec = 200 },
            { title = "Lunar Module", file = "https://soundcloud.com/cody_raves/lunar_module-18/s-kptb22sdCf6", durationSec = 195 },
            { title = "Mega Dose", file = "https://soundcloud.com/cody_raves/mega_dose-19/s-LopAm3OpzIM", durationSec = 195 },
            { title = "Midnight Boiler", file = "https://soundcloud.com/cody_raves/midnight_boiler-20/s-LgqQxZFxW4O", durationSec = 222 },
            { title = "Nowhere", file = "https://soundcloud.com/cody_raves/nowhere-21/s-M5uBsekOWLs", durationSec = 240 },
            { title = "Rebar", file = "https://soundcloud.com/cody_raves/rebar-22/s-1EK5dc48q67", durationSec = 208 },
            { title = "Saffron", file = "https://soundcloud.com/cody_raves/saffron-23/s-dZh2jU3FMlO", durationSec = 187 },
            { title = "Sonic Pulse", file = "https://soundcloud.com/cody_raves/sonic_pulse-24/s-ymOA7gfOok9", durationSec = 183 },
            { title = "Syntax", file = "https://soundcloud.com/cody_raves/syntax-25/s-KJV3gPmS7Q6", durationSec = 207 },
            { title = "Two Stepper", file = "https://soundcloud.com/cody_raves/two_stepper-26/s-30Jl0kJfXBd", durationSec = 195 },
            { title = "Vespers", file = "https://soundcloud.com/cody_raves/vespers-27/s-sad9jIFRUIl", durationSec = 154 }
        },
        stationAdsItems =         {
            { title = "SubSonic Radio Ad 1", file = "https://soundcloud.com/cody_raves/subsonic_radio_ad_1-1/s-QbNKj6c5c5N", durationSec = 10 },
            { title = "SubSonic Radio Ad 2", file = "https://soundcloud.com/cody_raves/subsonic_radio_ad_2-2/s-A6zOVbjQpGy", durationSec = 9 },
            { title = "SubSonic Radio Ad 3", file = "https://soundcloud.com/cody_raves/subsonic_radio_ad_3-3/s-7E0iP95NLqr", durationSec = 7 },
            { title = "SubSonic Radio Ad 4", file = "https://soundcloud.com/cody_raves/subsonic_radio_ad_4-4/s-DMYrfVW4Pwp", durationSec = 7 },
            { title = "SubSonic Radio Ad 5", file = "https://soundcloud.com/cody_raves/subsonic_radio_ad_5-5/s-JPZb3B9qJ74", durationSec = 7 }
        },
        sfxItems =         {}
    },
}

-- Neutral metadata handed to the base. No media, no links.
local definitions = {
    south = {
        stationId = "south",
        label = "Rebel Radio South",
        shortLabel = "Rebel Radio South",
        format = "Rap / Hip-Hop",
        audienceKey = "rs-radio:south",
        micChannel = 6901,
        autonomous = false,
        published = true,
        djLocation = { x = -1278.32, y = -1618.21, z = 3.37 },
        blip = {
            enabled = true,
            label = "Rebel Radio South",
            coords = { x = -1271.81, y = -1615.12, z = 3.37 }
        }
    },
    north = {
        stationId = "north",
        label = "Rebel Radio North",
        shortLabel = "Rebel Radio North",
        format = "Country / Blues",
        audienceKey = "rs-radio:north",
        micChannel = 6902,
        autonomous = false,
        published = true,
        djLocation = { x = 724.02, y = 2524.22, z = 72.51 },
        blip = {
            enabled = true,
            label = "Rebel Radio North",
            coords = { x = 731.75, y = 2523.49, z = 72.51 }
        }
    },
    subsonic = {
        stationId = "subsonic",
        label = "SubSonic FM",
        shortLabel = "SubSonic FM",
        format = "EDM / Rave",
        audienceKey = "rs-radio:subsonic",
        micChannel = 6903,
        published = true,
        autonomousOnly = true
    }
}

RSRadioExternalStationPackage = {
    definitions = definitions,
    catalogs = catalogs
}

-- Station ids in the package, honouring the SubSonic toggle.
function RSRadioExternalPackageStationIds()
    local wanted = {}
    for _, id in ipairs(Config and Config.StationPackageStations or { "south", "north", "subsonic" }) do
        if id ~= "subsonic" or (Config and Config.StationPackageIncludeSubSonic ~= false) then
            if definitions[id] ~= nil then
                wanted[#wanted + 1] = id
            end
        end
    end
    return wanted
end

-- Definitions in the shape the base station package API expects.
function RSRadioExternalPackageDefinitions()
    local out = {}
    for _, id in ipairs(RSRadioExternalPackageStationIds()) do
        local definition = {}
        for key, value in pairs(definitions[id]) do
            definition[key] = value
        end
        -- The install seeds the full catalogs into the station rows, the
        -- same way the original product's seeder did, so the lists are
        -- visible and editable in the Station Creator.
        local catalog = catalogs[id] or {}
        definition.music = catalog.playlistItems or {}
        definition.stationAds = catalog.stationAdsItems or {}
        definition.sfx = catalog.sfxItems or {}
        -- Product ads flow from this resource at runtime; SubSonic runs
        -- without them, matching the original.
        definition.productAds = id ~= "subsonic" and "data/product_ads.json" or false
        out[#out + 1] = definition
    end
    return out
end

function RSRadioExternalPackageCatalog(stationId)
    return catalogs[tostring(stationId or "")]
end
