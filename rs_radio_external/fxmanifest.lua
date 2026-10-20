fx_version 'cerulean'
game 'gta5'

name 'rs_radio_external'
author 'codyraves'
description 'External media support for rs_radio: YouTube, SoundCloud and direct audio links'
version '1.0.2'

-- rs_radio must start first. It owns every emitter, station and listener
-- system; this resource only supplies media it cannot fetch itself.
dependencies {
    'rs_radio'
}

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
