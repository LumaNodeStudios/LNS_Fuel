fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'LumaNode Studios'
description 'LumaNode Studios Fuel Management System'
version '1.0.0'

ui_page 'web/dist/index.html'

files {
	'locales/*.json',
	'client/*.lua',
	'web/dist/**',
}

shared_scripts {
	'@ox_lib/init.lua',
	'shared/settings.lua'
}

client_scripts {
	'client/cl_init.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/sv_fuel.lua',
	'server/sv_ownership.lua'
}

ox_libs {
	'math',
	'locale',
}

dependencies {
	'ox_lib',
	'ox_inventory',
}

provides {
	'ox_fuel',
	'cdn-fuel',
	'LegacyFuel'
}

use_experimental_fxv2_oal 'yes'