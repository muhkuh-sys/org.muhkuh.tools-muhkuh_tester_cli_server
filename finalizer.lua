local t = ...
local strDistId = t:get_platform()

-- Copy all additional files.
t:install{
  ['local/cli_server.lua']              = '${install_base}/',
  ['local/server.cfg.template']         = '${install_base}/',

  ['local/lua/configuration_file.lua']  = '${install_lua_path}/',
  ['local/lua/log-kafka.lua']           = '${install_lua_path}/',
  ['local/lua/log-local.lua']           = '${install_lua_path}/',
  ['local/lua/process.lua']             = '${install_lua_path}/',
  ['local/lua/process_zmq.lua']         = '${install_lua_path}/',
  ['local/lua/test_controller.lua']     = '${install_lua_path}/',
  ['local/lua/test_description.lua']    = '${install_lua_path}/',

  ['${report_path}']                    = '${install_base}/.jonchki/'
}

-- Install the CLI init script.
if strDistId=='windows' then
  t:install('local/windows/run_server.bat', '${install_base}/')
elseif strDistId=='ubuntu' then
  t:install('local/linux/run_server', '${install_base}/')
end

t:createPackageFile()
t:createHashFile()
t:createArchive('${install_base}/../../../${default_archive_name}', 'native')

return true
