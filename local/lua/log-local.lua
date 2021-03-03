local class = require 'pl.class'
local LogLocal = class()


function LogLocal:_init()
  self.date = require 'date'

  self.m_astrLogMessages = {}

  self.TESTRUNSTATE_Unknown = 0
  self.TESTRUNSTATE_Ok = 1
  self.TESTRUNSTATE_Error = 2
  self.m_tTestRunState = self.TESTRUNSTATE_Unknown

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
end



function LogLocal:getResult()
  local tResult = true
  if self.m_tTestRunState~=self.TESTRUNSTATE_Ok then
    tResult = false
  end
  return tResult
end



function LogLocal:getAndClearLog()
  -- Combine all messages in the log buffer to a string.
  local strLog = table.concat(self.m_astrLogMessages)

  -- Clear the log buffer.
  self.m_astrLogMessages = {}

  return strLog
end



function LogLocal:onLogMessage(uiLogLevel, strLogMessage)
  local date = self.date

  -- Get the log level as a string.
  local strLogLevel = self.m_astrLogLevel[uiLogLevel]
  if strLogLevel==nil then
    strLogLevel = tostring(uiLogLevel)
  end

  -- Combine the pretty-print level with the log message.
  local strMsg = date(false):fmt('%Y-%m-%d %H:%M:%S')..' ['..strLogLevel..'] '..tostring(strLogMessage)

  -- Append the message to the buffer.
  table.insert(self.m_astrLogMessages, strMsg)
end



function LogLocal:onEvent()
end



function LogLocal:onTestStepStarted(uiStepIndex, strTestCaseId, strTestCaseName, atLogAttributes)
end



function LogLocal:onTestStepFinished(strTestStepState)
  if strTestStepState=='ok' then
    -- Only overwrite the "unknown" state. Do not overwrite an "error" state.
    if self.m_tTestRunState==self.TESTRUNSTATE_Unknown then
      self.m_tTestRunState = self.TESTRUNSTATE_Ok
    end
  else
    self.m_tTestRunState = self.TESTRUNSTATE_Error
  end
end



function LogLocal:onTestRunStarted(atLogAttributes)
  -- Initialize the test state.
  self.m_tTestRunState = self.TESTRUNSTATE_Unknown
end



function LogLocal:onTestRunFinished()
end



return LogLocal
