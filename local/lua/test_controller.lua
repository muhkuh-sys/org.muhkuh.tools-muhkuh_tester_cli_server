local class = require 'pl.class'
local TestController = class()

function TestController:_init(tLog, tLogTest, tLogKafka, tLogLocal, atTestFolder)
  self.tLog = tLog
  self.tLogTest = tLogTest

  self.atTestFolder = atTestFolder

  self.json = require 'dkjson'
  self.pl = require'pl.import_into'()
  self.ProcessZmq = require 'process_zmq'
  self.uv = require 'lluv'

  self.m_testProcess = nil

  self.m_logKafka = tLogKafka
  self.m_logLocal = tLogLocal
  self.m_logConsumer = { tLogLocal }

  self.m_zmqContext = nil
  self.m_zmqSocket = nil
  self.m_zmqPort = nil
  self.m_zmqServerAddress = nil
  self.m_zmqPoll = nil

  self.m_tKeepAliveTimer = nil

  self.STATE_IDLE = 0
  self.STATE_RUNNING = 1
  self.m_tState = self.STATE_IDLE
end



function TestController:__sendErrorResponse(strMessage)
  local json = self.json
  local tSocket = self.m_zmqSocket
  if tSocket~=nil then
    local strResponse = json.encode{
      id = 'error',
      message = strMessage
    }
    tSocket:send(strResponse)
  end
end



function TestController:__sendStillRunning()
  local tSocket = self.m_zmqSocket
  if tSocket~=nil then
    tSocket:send('STILL_RUNNING')
  end
end



function TestController:__startTest(tMessage)
  local tLog = self.tLog
  local pl = self.pl
  local uv = self.uv

  if self.m_tState~=self.STATE_IDLE then
    tLog.error('Rejecting "run" command - not in idle state.')
    self:__sendErrorResponse('Not in idle state.')
  else
    -- Get the test ID.
    local strTestID = tMessage.testid
    if strTestID==nil then
      tLog.error('The command has no "testid" attribute:')
      self:__sendErrorResponse('The request has no "testid" attribute.')
    else
      local strTestPath = self.atTestFolder[strTestID]
      if strTestPath==nil then
        self:__sendErrorResponse('The request has an unknown test ID.')
      else
        -- Try to read the test name and VCS version from the package file.
        local strTestPackageName
        local strTestPackageVcsId
        local strPackageFile = pl.path.join(strTestPath, '.jonchki', 'package.txt')
        if pl.path.exists(strPackageFile)~=strPackageFile then
          tLog.warning('The package file "%s" does not exist.', strPackageFile)
        else
          local tPackage, strError = pl.config.read(strPackageFile)
          if tPackage==nil then
            tLog.warning('Failed to read the package file "%s": %s', strPackageFile, tostring(strError))
          else
            pl.pretty.dump(tPackage)
            strTestPackageName = tPackage.PACKAGE_NAME
            strTestPackageVcsId = tPackage.PACKAGE_VCS_ID
          end
        end

        local strTestXmlFile = pl.path.join(strTestPath, 'tests.xml')

        local TestDescription = require 'test_description'
        local tTestDescription = TestDescription(tLog)
        local tResult = tTestDescription:parse(strTestXmlFile)
        if tResult~=true then
          tLog.error('Failed to parse the test description.')
          self:__sendErrorResponse(string.format('Test "%s" has an invalid test description.', tostring(strTestXmlFile)))
        else
          -- Set the new system attributes.
          local tSystemAttributes = {
            hostname = uv.os_gethostname(),
            test = {
              title = tTestDescription:getTitle(),
              subtitle = tTestDescription:getSubtitle(),
              package_name = strTestPackageName,
              package_vcs_id = strTestPackageVcsId
            }
          }
          self.m_logKafka:setSystemAttributes(tSystemAttributes)

          -- Detect the LUA interpreter. Try LUA5.4 first, then fallback to LUA5.1 .
          local strExeSuffix = ''
          if pl.path.is_windows then
            strExeSuffix = '.exe'
          end
          local strInterpreterPath = pl.path.abspath(pl.path.join(strTestPath, 'lua5.4'..strExeSuffix))
          tLog.debug('Looking for the LUA5.4 interpreter in "%s".', strInterpreterPath)
          if pl.path.exists(strInterpreterPath)~=strInterpreterPath then
            strInterpreterPath = pl.path.abspath(pl.path.join(strTestPath, 'lua5.1'..strExeSuffix))
            tLog.debug('Looking for the LUA5.1 interpreter in "%s".', strInterpreterPath)
            if pl.path.exists(strInterpreterPath)~=strInterpreterPath then
              tLog.error('No LUA interpreter found.')
              self:__sendErrorResponse('No LUA interpreter found in the test folder.')
              strInterpreterPath = nil
            end
          end
          if strInterpreterPath~=nil then
            -- Create the command.
            local astrCmd = {'system.lua', '--server-port', '${ZMQPORT}'}
            local tParameter = tMessage.parameter
            if tParameter~=nil then
              if type(tParameter)=='table' then
                for _, strParameter in ipairs(tParameter) do
                  table.insert(astrCmd, strParameter)
                end
              else
                table.insert(astrCmd, tostring(tParameter))
              end
            end

            -- Create a new ZMQ process.
            local tTestProc = self.ProcessZmq(tLog, self.tLogTest, strInterpreterPath, astrCmd, strTestPath)
            -- Set the current log consumer.
            for _, tLogConsumer in ipairs(self.m_logConsumer) do
              tTestProc:addLogConsumer(tLogConsumer)
            end

            -- Set the state to "running".
            self.m_tState = self.STATE_RUNNING

            -- Send a keep alive message each 2 seconds.
            local this = self
            self.m_tKeepAliveTimer = uv.timer():start(2000, function(tTimer)
              this:__sendStillRunning()
              tTimer:again(2000)
            end)

            -- Run the test and set this as the consumer for the terminate message.
            tTestProc:run(self.onTestTerminate, self)

            self.m_testProcess = tTestProc
          end
        end
      end
    end
  end
end



function TestController:__onZmqReceive(tHandle, strErr, tSocket)
  local tLog = self.tLog
  local json = self.json
  local pl = self.pl

  if strErr then
    return tHandle:close()
  else
    local strMessage = tSocket:recv()
    local tJson, uiPos, strJsonErr = json.decode(strMessage)
    if tJson==nil then
      tLog.error('JSON Error: %d %s', uiPos, strJsonErr)
    else
      tLog.debug('Message received:')
      tLog.debug(pl.pretty.write(tJson))

      local strId = tJson.id
      if strId==nil then
        tLog.error('Rejecting message without "id" field.')
        self:__sendErrorResponse('Missing "id" field.')

      elseif strId=='run' then
        tLog.debug('Received "run" command.')
        self:__startTest(tJson)

      elseif strCommand=='cancel' then
        tLog.debug('Received "cancel" command.')

      else
        tLog.error('Ignoring unknown command: "%s"', tostring(strCommand))
      end
    end
  end
end



function TestController:__zmq_init(strServerAddress, usServerPort)
  -- Create the 0MQ context and the socket.
  local zmq = require 'lzmq'
  local tZContext, strError = zmq.context()
  if tZContext==nil then
    error('Failed to create ZMQ context: ' .. tostring(strError))
  end
  self.m_zmqContext = tZContext

  local tZSocket, strError = tZContext:socket(zmq.PAIR)
  if tZSocket==nil then
    error('Failed to create ZMQ socket: ' .. tostring(strError))
  end
  self.m_zmqSocket = tZSocket

  local strSocketAddress = string.format('tcp://%s:%d', strServerAddress, usServerPort)
  local tResult, strError = tZSocket:bind(strSocketAddress)
  if tResult~=true then
    error('Failed to bind the socket: ' .. tostring(strError))
  end
  self.tLog.debug('Remote 0MQ listening on %s', strSocketAddress)
  self.m_zmqPort = usServerPort
  self.m_zmqServerAddress = strServerAddress
  
  local uv = require 'lluv'
  local this = self
  local tPoll = uv.poll_zmq(tZSocket)
  tPoll:start(function(tHandle, strErr, tSocket)
    this:__onZmqReceive(tHandle, strErr, tSocket)
  end)
  self.m_zmqPoll = tPoll
end



function TestController:__zmq_delete()
  local tPoll = self.m_zmqPoll
  if tPoll~=nil then
    tPoll:stop()
    tPoll:close()
    self.m_zmqPoll = nil
  end

  local zmqSocket = self.m_zmqSocket
  if zmqSocket~=nil then
    if zmqSocket:closed()==false then
      zmqSocket:disconnect(self.m_zmqServerAddress)
      zmqSocket:close()
    end
    self.m_zmqSocket = nil
  end

  local zmqContext = self.m_zmqContext
  if zmqContext~=nil then
    zmqContext:destroy()
    self.m_zmqContext = nil
  end

  self.m_zmqPort = nil

  self.tLog.debug('Remote 0MQ closed')
end



function TestController:addLogConsumer(tLogConsumer)
  table.insert(self.m_logConsumer, tLogConsumer)
end



function TestController:run(strServerAddress, usServerPort)
  self:__zmq_init(strServerAddress, usServerPort)
end



function TestController:onTestTerminate()
  local tLog = self.tLog
  local tSocket = self.m_zmqSocket
  local tLogLocal = self.m_logLocal
  local json = self.json

  tLog.info('onTestTerminate')

  -- Stop the keep alive timer.
  self.m_tKeepAliveTimer:stop()

  -- The test is not running anymore.
  self.m_tState = self.STATE_IDLE

  if tSocket~=nil then
    local strResponse = json.encode{
      id = 'result',
      result = tLogLocal:getResult(),
      log = tLogLocal:getAndClearLog()
    }
    tSocket:send(strResponse)
  end


end


function TestController:onCancel()
  local tLog = self.tLog

  tLog.info('Cancel: no test running.')
end


function TestController:shutdown()
  local tTestProcess = self.m_testProcess
  if tTestProcess~=nil then
    tTestProcess:shutdown()
  end
end


return TestController
