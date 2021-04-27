local class = require 'pl.class'
local LogKafka = class()


function LogKafka:_init(tLog, fActivateDebugging)
  self.date = require 'date'
  self.dkjson = require 'dkjson'

  local kafka = require 'kafka'
  tLog.info('Using kafka %s', kafka.version())
  self.kafka = kafka

  local pl = require'pl.import_into'()
  self.pl = pl

  self.tLog = tLog

  local ulid = require("ulid")
  self.ulid = ulid
  local socket = require("socket")
  ulid.set_time_func(socket.gettime)

  -- Convert the argument to boolean.
  self.m_fDebuggingIsActive = fActivateDebugging
  if fActivateDebugging==true then
    tLog.debug('Kafka debugging is active.')
  end

  self.m_atSystemAttributes = {}
  self.m_atAttributes = {}

  self.m_astrLogMessages = {}
  self.m_sizLogMessages = 0
  self.m_sizLogMessagesMax = 32768

  self.m_strUlidTestRun = nil
  self.m_strUlidTestStep = nil

  self.m_astrLogLevel = {
   [1] = 'EMERG',
   [2] = 'ALERT',
   [3] = 'FATAL',
   [4] = 'ERROR',
   [5] = 'WARNING',
   [6] = 'NOTICE',
   [7] = 'INFO',
   [8] = 'DEBUG',
   [9] = 'TRACE'
  }

--  local strBrokerList = 'reportportal01.hilscher.local:9092'
  self.m_strBrokerList = nil

  self.tProducer = nil
  self.tTopic_teststations = nil
  self.tTopic_logs = nil
  self.tTopic_events = nil
  if fActivateDebugging==true then
    self.tTopic_teststations_cnt = 0
    self.tTopic_logs_cnt = 0
    self.tTopic_events_cnt = 0
    local strPath = '/tmp/muhkuh-production-teststations-%03d.json'
    self.tTopic_teststations_template = strPath
    tLog.debug('Write messages for the testatations topic to: %s', strPath)

    strPath = '/tmp/muhkuh-production-logs-%03d.json'
    self.tTopic_logs_template = strPath
    tLog.debug('Write messages for the logs topic to: %s', strPath)

    strPath = '/tmp/muhkuh-production-events-%03d.json'
    self.tTopic_events_template = strPath
    tLog.debug('Write messages for the events topic to: %s', strPath)
  end
end



function LogKafka:__flushMessages(uiTimeout)
  local tProducer = self.tProducer
  if tProducer~=nil then
    tProducer:flush(uiTimeout)
  end
end



function LogKafka:__sendMessage(tTopic, strMessage)
  local tLog = self.tLog
  local kafka = self.kafka

  local tResult, strError = tTopic:send(-1, strMessage)
  if tResult==kafka.RD_KAFKA_RESP_ERR._QUEUE_FULL then
    tLog.debug('[Kafka] Queue full, resend after 500ms.')
    tTopic:poll(500)
    tResult, strError = tTopic:send(-1, strMessage)
    if tResult==kafka.RD_KAFKA_RESP_ERR._QUEUE_FULL then
      tLog.debug('[Kafka] Queue still full, resend after 2000ms.')
      tTopic:poll(2000)
      tResult, strError = tTopic:send(-1, strMessage)
      if tResult==kafka.RD_KAFKA_RESP_ERR._QUEUE_FULL then
        tLog.debug('[Kafka] Failed to deliver anything from the queue. Stopping kafka delivery.')
        self.tTopic_teststations = nil
        self.tTopic_logs = nil
        self.tTopic_events = nil
      end
    end
  end
  if tResult~=0 then
    tLog.debug('[Kafka] Failed to deliver message: %d %s', tResult, tostring(strError))
  end
end



function LogKafka:setSystemAttributes(atSystemAttributes)
  local pl = self.pl

  self.m_atSystemAttributes = atSystemAttributes

  -- Make a copy of the attributes.
  self.m_atAttributes = pl.tablex.deepcopy(atSystemAttributes)
end



function LogKafka:connect(strBrokerList, atOptions)
  atOptions = atOptions or {}
  local tLog = self.tLog
  local kafka = self.kafka
  local pl = self.pl

  if self.m_strBrokerList~=nil then
    tLog.alert('Refusing to connect an already connected instance.')
  else
    if strBrokerList~=nil then
      local tProducer_conf = {
        ['queue.buffering.max.messages'] = 256,
        ['queue.buffering.max.kbytes'] = 1024,
        ['queue.buffering.max.ms'] = 500,
        ['batch.num.messages'] = 32
      }
      -- Merge the options into the producer configuration.
      pl.tablex.update(tProducer_conf, atOptions)

      local tProducer = kafka.Producer(strBrokerList, tProducer_conf)
      self.tProducer = tProducer

      -- Compress all topics with GZIP. This takes the most CPU power to
      -- produce and consume messages, but it results in the smallest files
      -- compared to the alternatives snappy and lz4. As we are using kafka as
      -- a temporary storage for a while, it is our top priority to keep the
      -- disk usage as small as possible.
      local tTopic_conf = {
        ['compression.codec'] = 'gzip',
        ['compression.level'] = 9
      }
      self.tTopic_teststations = tProducer:create_topic('muhkuh-production-teststations', tTopic_conf)
      self.tTopic_logs = tProducer:create_topic('muhkuh-production-logs', tTopic_conf)
      self.tTopic_events = tProducer:create_topic('muhkuh-production-events', tTopic_conf)

      self.m_strBrokerList = strBrokerList
    end
  end
end



function LogKafka:announceInstance(atAttributes)
  local pl = self.pl

  -- Merge the attributes with the system attributes.
  local atAttrMerged = pl.tablex.deepcopy(atAttributes)
  pl.tablex.update(atAttrMerged, self.m_atSystemAttributes)
  atAttrMerged.timestamp = self.date(false):fmt('%Y-%m-%d %H:%M:%S')

  -- Convert the attributes to JSON.
  local strJson = self.dkjson.encode(atAttrMerged)

  -- Send the message to the Kafka topic.
  local tTopic = self.tTopic_teststations
  if tTopic~=nil then
    self:__sendMessage(tTopic, strJson)
  end

  -- Write the message to a temp file.
  if self.m_fDebuggingIsActive==true then
    local tFile = io.open(string.format(self.tTopic_teststations_template, self.tTopic_teststations_cnt), 'w')
    tFile:write(strJson)
    tFile:close()
    self.tTopic_teststations_cnt = self.tTopic_teststations_cnt + 1
  end
end



function LogKafka:__getNewUlid()
  return self.ulid.ulid()
end



function LogKafka:__sendMessageBuffer()
  -- Is something in the buffer?
  if self.m_sizLogMessages~=0 then
    -- Get all log messages.
    local strMsg = table.concat(self.m_astrLogMessages)
    -- Create a new message.
    local atAttr = self.m_atAttributes
    atAttr.log = strMsg
    local strJson = self.dkjson.encode(atAttr)
    atAttr.log = nil

    -- Send the message to the Kafka topic.
    local tTopic = self.tTopic_logs
    if tTopic~=nil then
      self:__sendMessage(tTopic, strJson)
    end

    -- Write the message to a temp file.
    if self.m_fDebuggingIsActive==true then
      local tFile = io.open(string.format(self.tTopic_logs_template, self.tTopic_logs_cnt), 'w')
      tFile:write(strJson)
      tFile:close()
      self.tTopic_logs_cnt = self.tTopic_logs_cnt + 1
    end
  end

  self.m_astrLogMessages = {}
  self.m_sizLogMessages = 0
end



function LogKafka:__sendEvent(strEventId, atAttributes)
  -- Create a new message.
  local atAttr = self.m_atAttributes
  atAttr.event = strEventId
  atAttr.eventAttr = atAttributes
  atAttr.timestamp = self.date(false):fmt('%Y-%m-%d %H:%M:%S')
  local strJson = self.dkjson.encode(atAttr)
  atAttr.event = nil
  atAttr.eventAttr = nil
  atAttr.timestamp = nil

  -- Send the event to the Kafka topic.
  local tTopic = self.tTopic_events
  if tTopic~=nil then
    self:__sendMessage(tTopic, strJson)
  end

  -- Write the event to a temp file.
  if self.m_fDebuggingIsActive==true then
    local tFile = io.open(string.format(self.tTopic_events_template, self.tTopic_events_cnt), 'w')
    tFile:write(strJson)
    tFile:close()
    self.tTopic_events_cnt = self.tTopic_events_cnt + 1
  end
end



function LogKafka:onLogMessage(uiLogLevel, strLogMessage)
  local date = self.date
  local sizLogMessagesMax = self.m_sizLogMessagesMax
  local astrLogMessages = self.m_astrLogMessages

  -- Get the log level as a string.
  local strLogLevel = self.m_astrLogLevel[uiLogLevel]
  if strLogLevel==nil then
    strLogLevel = tostring(uiLogLevel)
  end

  -- Combine the pretty-print level with the log message.
  local strMsg = date(false):fmt('%Y-%m-%d %H:%M:%S')..' ['..strLogLevel..'] '..tostring(strLogMessage)
  local sizMsg = string.len(strMsg)

  -- Does the new log message fit into the buffer?
  if (self.m_sizLogMessages+sizMsg)>sizLogMessagesMax then
    -- Flush the message buffer.
    self:__sendMessageBuffer()

    -- Chunk the new message.
    repeat
      -- Get the size of the next chunk.
      local sizChunk = sizMsg
      -- Does the chunk fit into the buffer?
      if sizChunk>sizLogMessagesMax then
        sizChunk = sizLogMessagesMax
        -- Add a part of the message to the buffer.
        table.insert(astrLogMessages, string.sub(strMsg, 1, sizChunk))
        -- Update the size of the buffer.
        self.m_sizLogMessages = self.m_sizLogMessages + sizChunk

        -- Flush the buffer.
        self:__sendMessageBuffer()

        sizMsg = sizMsg - sizChunk
        strMsg = string.sub(strMsg, sizChunk+1)
      else
        -- Add the complete message to the buffer.
        table.insert(astrLogMessages, strMsg)
        -- Update the size of the buffer.
        self.m_sizLogMessages = self.m_sizLogMessages + sizMsg

        sizMsg = 0
      end
    until sizMsg==0
  else
    -- The new message fits into the buffer.
    table.insert(astrLogMessages, strMsg)
    -- Update the size of the buffer.
    self.m_sizLogMessages = self.m_sizLogMessages + sizMsg
  end
end



function LogKafka:onEvent(strEventId, tEventAttributes)
  self:__sendEvent(strEventId, tEventAttributes)
end



function LogKafka:onTestStepStarted(uiStepIndex, strTestCaseId, strTestCaseName, atLogAttributes)
  local pl = self.pl

  -- Send any waiting messages.
  self:__sendMessageBuffer()

  -- Create a new ULID for the test step.
  local strUlidTestStep = self:__getNewUlid()
  self.m_strUlidTestStep = strUlidTestStep

  -- Make a copy of the attributes.
  local atAttributes = pl.tablex.deepcopy(atLogAttributes)
  pl.tablex.update(atAttributes, self.m_atSystemAttributes)

  -- Append the ULID for the test run.
  atAttributes.test_run_ulid = self.m_strUlidTestRun
  -- Append the test step.
  atAttributes.test_step = uiStepIndex
  -- Append the test ID and name.
  atAttributes.test_id = strTestCaseId
  atAttributes.test_name = strTestCaseName
  -- Append the ULID for the test step.
  atAttributes.test_step_ulid = strUlidTestStep

  self.m_atAttributes = atAttributes
end



function LogKafka:onTestStepFinished()
  -- Send any waiting messages.
  self:__sendMessageBuffer()

  local atAttributes = self.m_atAttributes

  self.m_strUlidTestStep = nil

  -- Remove the test step from the attributes.
  atAttributes.test_step = nil
  -- Remove the test ID and name.
  atAttributes.test_id = nil
  atAttributes.test_name = nil
  -- Remove the test step ULID from the attributes.
  atAttributes.test_step_ulid = nil

  -- Try to flush a few messages.
  self:__flushMessages(500)
end



function LogKafka:onTestRunStarted(atLogAttributes)
  local pl = self.pl

  -- Send any waiting messages.
  self:__sendMessageBuffer()

  -- Create a new ULID for the test.
  local strUlidTestRun = self:__getNewUlid()
  self.m_strUlidTestRun = strUlidTestRun
  -- Clear any old ULID for the test step.
  self.m_strUlidTestStep = nil

  -- Make a copy of the attributes.
  local atAttributes = pl.tablex.deepcopy(atLogAttributes)
  pl.tablex.update(atAttributes, self.m_atSystemAttributes)

  -- Append the ULID for the test run.
  atAttributes.test_run_ulid = strUlidTestRun

  self.m_atAttributes = atAttributes
end



function LogKafka:onTestRunFinished()
  -- Send any waiting messages.
  self:__sendMessageBuffer()

  local atAttributes = self.m_atAttributes

  self.m_strUlidTestRun = nil
  self.m_strUlidTestStep = nil

  -- Remove the test run ULID from the attributes.
  atAttributes.test_run_ulid = nil
  -- Remove the test step from the attributes.
  atAttributes.test_step = nil
  -- Remove the test step ULID from the attributes.
  atAttributes.test_step_ulid = nil

  -- Try to flush the rest of the messages.
  self:__flushMessages(2000)
end



return LogKafka
