local class = require 'pl.class'
local Process = class()


function Process:_init(tLog)
  self.tLog = tLog

  self.pl = require'pl.import_into'()
  self.uv = require 'lluv'

  self.STATE_Idle = 0
  self.STATE_Running = 1
  self.STATE_RequestedShutdown = 2
  self.STATE_Killing = 3
  self.STATE_Terminated = 4

  self.tState = self.STATE_Idle
  self.tProc = nil
  self.tPipeStdOut = nil
  self.tPipeStdErr = nil
  self.fRequestedShutdown = false
  self.tShutdownTimer = nil
end



function Process:run_process(strCommand, astrArguments, strWorkingFolder)
  local tResult
  local tLog = self.tLog

  if (self.tState==self.STATE_Idle) or (self.tState==self.STATE_Terminated) then
    local this = self
    local uv = self.uv

    -- Run the command in the current working folder by default.
    if strWorkingFolder==nil then
      strWorkingFolder = uv.cwd();
    end

    -- Create pipes for the new process.
    local tPipeStdOut = uv.pipe(false)
    local tPipeStdErr = uv.pipe(false)

tLog.alert('strCommand: %s', strCommand)
tLog.alert('astrArguments: %s', table.concat(astrArguments, ','))
tLog.alert('strWorkingFolder: %s', strWorkingFolder)

    -- Start a new process.
    local tProc = uv.spawn(
      {
        file = strCommand,
        args = astrArguments,
        cwd = strWorkingFolder,
        stdio = {
          -- STDIN
          {},
          -- STDOUT
          {
            flags = uv.CREATE_PIPE + uv.WRITABLE_PIPE,
            stream = tPipeStdOut
          },
          -- STDERR
          {
            flags = uv.CREATE_PIPE + uv.WRITABLE_PIPE,
            stream = tPipeStdErr
          }
        }
      },
      function(tHandle, strError, tExitStatus, tTermSignal)
        this:_onTerminate(tHandle, strError, tExitStatus, tTermSignal)
      end
    )
    tPipeStdOut:start_read(function(tHandle, strError, strData) this:_onStdOut(tHandle, strError, strData) end)
    tPipeStdErr:start_read(function(tHandle, strError, strData) this:_onStdErr(tHandle, strError, strData) end)

    self.tProc = tProc
    self.tPipeStdOut = tPipeStdOut
    self.tPipeStdErr = tPipeStdErr

    self.tState = self.STATE_Running

    tResult = true
  else
    tLog.error('Not starting as not idle or terminated.')
  end

  return tResult
end



function Process:shutdown()
  self.fRequestedShutdown = true
  self.tProc:kill(self.uv.SIGHUP)

  self.tShutdownTimer = self.uv.timer():start(2000, function(tHandle)
    tHandle:close()
    self.tShutdownTimer = nil
    self.tProc:kill(self.uv.SIGKILL)
  end)
end



function Process:_onTerminate(tHandle, err, exit_status, term_signal)
  local tLog = self.tLog

  if tHandle==self.tProc then
    tHandle:close()

    -- Stop 
    local tShutdownTimer = self.tShutdownTimer
    if tShutdownTimer~=nil then
      tShutdownTimer:close()
      self.tShutdownTimer = nil
    end

    self.tState = self.STATE_Terminated

    tLog.notice('Process terminated: %s / %s / %s', tostring(err), tostring(exit_status), tostring(term_signal))

    self:onClose(err, exit_status, term_signal)
  else
    tLog.error('Unknown process handle')
  end
end



function Process:onClose(strError, iExitStatus, uiTermSignal)
  -- Do nothing by default.
end



function Process:_onStdOut(tHandle, strError, strData)
  if tHandle==self.tPipeStdOut then
    if strError==nil then
      self:onStdOut(strData)
    else
      self.tLog.debug('Closing STDOUT: %s', tostring(strError))
      tHandle:close()
      self.tPipeStdOut = nil
    end
  else
    self.tLog.error('Invalid handle for STDOUT.')
  end
end



function Process:_onStdErr(tHandle, strError, strData)
  if tHandle==self.tPipeStdErr then
    if strError==nil then
      self:onStdErr(strData)
    else
      self.tLog.debug('Closing STDERR: %s', tostring(strError))
      tHandle:close()
      self.tPipeStdErr = nil
    end
  else
    self.tLog.error('Invalid handle for STDERR.')
  end
end



function Process:onStdOut(strData)
  -- Do nothing by default.
end



function Process:onStdErr(strData)
  -- Do nothing by default.
end



return Process
