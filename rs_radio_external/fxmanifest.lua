fx_version 'cerulean'
game 'gta5'

name 'rs_radio_external'
author 'codyraves'
description 'External media support for rs_radio: YouTube, SoundCloud and direct audio links'
version '1.0.5'

-- rs_radio owns every emitter, station and listener system; this resource only
-- supplies media it cannot fetch itself. Start order is handled by the attach
-- code (server/sv_attach.lua, client/cl_attach.lua), which waits for the base
-- and re-registers whenever it restarts.
--
-- Deliberately NOT a manifest `dependencies` entry: FiveM stops dependents
-- when their dependency restarts and never starts them again, so a plain
-- `restart rs_radio` used to leave this resource stopped. Every station whose
-- tracks were external then came back with an empty playlist and went silent
-- until someone noticed and restarted this by hand.

shared_scripts {
    'shared/sh_version.lua',
    'config.lua',
    'data/stations.lua'
}

files {
    'data/product_ads.json',
    'nui/adapter.js'
}

client_scripts {
    'client/cl_attach.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_attach.lua',
    'server/sv_url_rules.lua',
    'server/sv_soundcloud.lua',
    'server/sv_youtube.lua',
    'server/sv_resolve.lua',
    'server/sv_adapter.lua',
    'server/sv_station_package.lua',
    'server/sv_saved_library.lua',
    'server/sv_migrate.lua'
}
