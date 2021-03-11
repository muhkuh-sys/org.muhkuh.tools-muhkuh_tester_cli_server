local ConfigurationFile = {}

function ConfigurationFile.read(tLog)
  tLog = tLog or {
    debug = function (...) print(string.format(...)) end
  }
  local pl = require'pl.import_into'()

  local strConfigurationFile = pl.path.abspath('server.cfg')
  local tConfigurationFromFile = {}
  if pl.path.isfile(strConfigurationFile)~=true then
    tLog.debug('The configuration file "%s" does not exist.', strConfigurationFile)
  else
    tLog.debug('Reading the configuration from "%s"...', strConfigurationFile)
    tConfigurationFromFile = pl.config.read(strConfigurationFile)
  end
  local tConfigurationDefault = {
    ssdp_name = 'Muhkuh Teststation',
    interface = '',
    zmq_port = 12336,
    kafka_broker = '',
    kafka_options = {},
    kafka_debugging = false
  }
  -- Join both configurations.
  local tConfiguration = {}
  for strKey, tValue in pairs(tConfigurationDefault) do
    local tValueFile = tConfigurationFromFile[strKey]
    if tValueFile~=nil then
      tValue = tValueFile
      tLog.debug('  [%s] from file = %s', strKey, pl.pretty.write(tValueFile))
    else
      tLog.debug('  [%s] default = %s', strKey, pl.pretty.write(tValue))
    end
    tConfiguration[strKey] = tValue
  end
  -- Collect all "folder_*" entries.
  local atFolder = {}
  for strKey, tValue in pairs(tConfigurationFromFile) do
    local strID = string.match(strKey, '^folder_(.*)')
    if strID~=nil then
      atFolder[strID] = tValue
    end
  end
  tConfiguration.atFolder = atFolder
  -- Convert the "kafka_debugging" entry to a boolean.
  local tValue = tConfiguration.kafka_debugging
  local fValue = false
  if type(tValue)=='boolean' then
    fValue = tValue
  elseif type(tValue)=='string' and string.lower(tValue)=='true' then
    fValue = true
  end
  tConfiguration.kafka_debugging = fValue

  return tConfiguration
end


return ConfigurationFile
