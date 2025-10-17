fx_version 'cerulean'
game 'common'
use_experimental_fxv2_oal 'yes'
lua54 'yes'

name 'oxmysql repository extension'
author 'Altera Vita RP'
version '0.2.0'
license 'LGPL-3.0-or-later'
repository 'https://github.com/alteravitarp/oxmysql-repository'
description 'A Spring Data JPA-like repository extension for oxmysql created by Altera Vita RP'

dependencies {
    '/server:12913',
}

client_script 'ui.lua'
server_script 'dist/build.js'

files {
	'web/build/index.html',
	'web/build/**/*'
}

ui_page 'web/build/index.html'

provide 'mysql-async'
provide 'ghmattimysql'

convar_category 'OxMySQL' {
	'Configuration',
	{
		{ 'Connection string', 'mysql_connection_string', 'CV_STRING', 'mysql://user:password@localhost/database' },
		{ 'Debug', 'mysql_debug', 'CV_BOOL', 'false' }
	}
}