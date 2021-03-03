local class = require 'pl.class'
local TestDescription = class()


function TestDescription:_init(tLog)
  self.tLog = tLog

  self.pl = require'pl.import_into'()
  self.lxp = require 'lxp'

  self.strTitle = nil
  self.strSubtitle = nil
  self.strPre = nil
  self.strPost = nil
  self.atTestCases = nil
  self.uiNumberOfTests = nil
  self.astrTestNames = nil
  self.tSystem = nil
  self.atDocuments = nil
end


--- Expat callback function for starting an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when a new element is opened.
-- @param tParser The parser object.
-- @param strName The name of the new element.
function TestDescription.__parseTests_StartElement(tParser, strName, atAttributes)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn, iPosAbs = tParser:pos()

  table.insert(aLxpAttr.atCurrentPath, strName)
  local strCurrentPath = table.concat(aLxpAttr.atCurrentPath, "/")
  aLxpAttr.strCurrentPath = strCurrentPath

  if strCurrentPath=='/MuhkuhTest' then
    local strTitle = atAttributes['title']
    local strSubtitle = atAttributes['subtitle']
    local strPre = atAttributes['pre']
    local strPost = atAttributes['post']
    aLxpAttr.strTitle = strTitle
    aLxpAttr.strSubtitle = strSubtitle
    aLxpAttr.strPre = strPre
    aLxpAttr.strPost = strPost

  elseif strCurrentPath=='/MuhkuhTest/Testcase' then
    local strID = atAttributes['id']
    local strFile = atAttributes['file']
    local strName = atAttributes['name']
    local strPre = atAttributes['pre']
    local strPost = atAttributes['post']
    if (strID==nil or strID=='') and (strFile==nil or strFile=='') then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: one of "id" or "file" must be present, but none found.', iPosLine, iPosColumn)
    elseif (strID~=nil and strID~='') and (strFile~=nil and strFile~='') then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: one of "id" or "file" must be present, but both found.', iPosLine, iPosColumn)
    elseif strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      local tTestCase = {
        id = strID,
        file = strFile,
        name = strName,
        pre = strPre,
        post = strPost,
        parameter = {}
      }
      aLxpAttr.tTestCase = tTestCase
      aLxpAttr.strParameterName = nil
      aLxpAttr.strParameterValue = nil
    end

  elseif strCurrentPath=='/MuhkuhTest/Testcase/Parameter' then
    local strName = atAttributes['name']
    if strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      aLxpAttr.strParameterName = strName
    end

  elseif strCurrentPath=='/MuhkuhTest/Testcase/Connection' then
    local strName = atAttributes['name']
    if strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      aLxpAttr.strParameterName = strName
    end

  elseif strCurrentPath=='/MuhkuhTest/System' then
    aLxpAttr.strParameterName = nil
    aLxpAttr.strParameterValue = nil

  elseif strCurrentPath=='/MuhkuhTest/System/Parameter' then
    local strName = atAttributes['name']
    if strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      aLxpAttr.strParameterName = strName
    end

  elseif strCurrentPath=='/MuhkuhTest/Documents' then
    aLxpAttr.strDocumentName = nil
    aLxpAttr.strDocumentUrl = nil

  elseif strCurrentPath=='/MuhkuhTest/Documents/Document' then
    local strName = atAttributes['name']
    if strName==nil or strName=='' then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    else
      aLxpAttr.strDocumentName = strName
    end


  end
end



--- Expat callback function for closing an element.
-- This function is part of the callbacks for the expat parser.
-- It is called when an element is closed.
-- @param tParser The parser object.
-- @param strName The name of the closed element.
function TestDescription.__parseTests_EndElement(tParser, strName)
  local aLxpAttr = tParser:getcallbacks().userdata
  local iPosLine, iPosColumn, iPosAbs = tParser:pos()

  local strCurrentPath = aLxpAttr.strCurrentPath

  if strCurrentPath=='/MuhkuhTest/Testcase' then
    table.insert(aLxpAttr.atTestCases, aLxpAttr.tTestCase)
    aLxpAttr.tTestCase = nil

  elseif strCurrentPath=='/MuhkuhTest/Testcase/Parameter' then
    if aLxpAttr.strParameterName==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    elseif aLxpAttr.strParameterValue==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing value for parameter.', iPosLine, iPosColumn)
    else
      table.insert(aLxpAttr.tTestCase.parameter, {name=aLxpAttr.strParameterName, value=aLxpAttr.strParameterValue})
    end

  elseif strCurrentPath=='/MuhkuhTest/Testcase/Connection' then
    if aLxpAttr.strParameterName==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    elseif aLxpAttr.strParameterConnection==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing connection for parameter.', iPosLine, iPosColumn)
    else
      table.insert(aLxpAttr.tTestCase.parameter, {name=aLxpAttr.strParameterName, connection=aLxpAttr.strParameterConnection})
    end

  elseif strCurrentPath=='/MuhkuhTest/System/Parameter' then
    if aLxpAttr.strParameterName==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    elseif aLxpAttr.strParameterValue==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing value for parameter.', iPosLine, iPosColumn)
    else
      table.insert(aLxpAttr.tSystem.parameter, {name=aLxpAttr.strParameterName, value=aLxpAttr.strParameterValue})
    end

  elseif strCurrentPath=='/MuhkuhTest/Documents/Document' then
    if aLxpAttr.strDocumentName==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing "name".', iPosLine, iPosColumn)
    elseif aLxpAttr.strDocumentUrl==nil then
      aLxpAttr.tResult = nil
      aLxpAttr.tLog.error('Error in line %d, col %d: missing value for document.', iPosLine, iPosColumn)
    else
      table.insert(aLxpAttr.atDocuments, {name=aLxpAttr.strDocumentName, url=aLxpAttr.strDocumentUrl})
    end
  end

  table.remove(aLxpAttr.atCurrentPath)
  aLxpAttr.strCurrentPath = table.concat(aLxpAttr.atCurrentPath, "/")
end



--- Expat callback function for character data.
-- This function is part of the callbacks for the expat parser.
-- It is called when character data is parsed.
-- @param tParser The parser object.
-- @param strData The character data.
function TestDescription.__parseTests_CharacterData(tParser, strData)
  local aLxpAttr = tParser:getcallbacks().userdata

  local strCurrentPath = aLxpAttr.strCurrentPath
  if strCurrentPath=="/MuhkuhTest/Testcase/Parameter" then
    aLxpAttr.strParameterValue = strData

  elseif strCurrentPath=="/MuhkuhTest/Testcase/Connection" then
    aLxpAttr.strParameterConnection = strData

  elseif strCurrentPath=="/MuhkuhTest/System/Parameter" then
    aLxpAttr.strParameterValue = strData

  elseif strCurrentPath=='/MuhkuhTest/Documents/Document' then
    aLxpAttr.strDocumentUrl = strData

  end
end



function TestDescription:__parse_tests(strTestsFile)
  local tResult = nil
  local tLog = self.tLog

  -- Read the complete file.
  local strFileData, strError = self.pl.utils.readfile(strTestsFile)
  if strFileData==nil then
    tLog.error('Failed to read the test configuration file "%s": %s', strTestsFile, strError)
  else
    local lxp = self.lxp

    local aLxpAttr = {
      -- Start at root ("/").
      atCurrentPath = {""},
      strCurrentPath = nil,

      strTitle = nil,
      strSubtitle = nil,
      strPre = nil,
      strPost = nil,
      tTestCase = nil,
      tSystem = { parameter={} },
      strParameterName = nil,
      strParameterValue = nil,
      strParameterConnection = nil,
      atTestCases = {},
      strDocumentName = nil,
      strDocumentUrl = nil,
      atDocuments = {},

      tResult = true,
      tLog = tLog
    }

    local aLxpCallbacks = {}
    aLxpCallbacks._nonstrict    = false
    aLxpCallbacks.StartElement  = self.__parseTests_StartElement
    aLxpCallbacks.EndElement    = self.__parseTests_EndElement
    aLxpCallbacks.CharacterData = self.__parseTests_CharacterData
    aLxpCallbacks.userdata      = aLxpAttr

    local tParser = lxp.new(aLxpCallbacks)

    local tParseResult, strMsg, uiLine, uiCol, uiPos = tParser:parse(strFileData)
    if tParseResult~=nil then
      tParseResult, strMsg, uiLine, uiCol, uiPos = tParser:parse()
      if tParseResult~=nil then
        tParser:close()
      end
    end

    if tParseResult==nil then
      tLog.error('Failed to parse the test configuration "%s": %s in line %d, column %d, position %d.', strTestsFile, strMsg, uiLine, uiCol, uiPos)
    elseif aLxpAttr.tResult~=true then
      tLog.error('Failed to parse the test configuration.')
    else
      self.strTitle = aLxpAttr.strTitle
      self.strSubtitle = aLxpAttr.strSubtitle
      self.strPre = aLxpAttr.strPre
      self.strPost = aLxpAttr.strPost
      self.atTestCases = aLxpAttr.atTestCases
      self.tSystem = aLxpAttr.tSystem
      self.atDocuments = aLxpAttr.atDocuments
      tResult = true
    end
  end

  return tResult
end



function TestDescription:parse(strTestsFile)
  local tResult = true
  local pl = self.pl
  local tLog = self.tLog

  if strTestsFile==nil then
    tLog.error('Missing argument test configuration file.')
    tResult = nil
  elseif pl.path.exists(strTestsFile)~=strTestsFile then
    tLog.error('The test configuration file "%s" does not exist.', strTestsFile)
    tResult = nil
  elseif pl.path.isfile(strTestsFile)~=true then
    tLog.error('The path "%s" is no regular file.', strTestsFile)
    tResult = nil
  else
    tLog.debug('Parsing tests file "%s".', strTestsFile)
    tResult = self:__parse_tests(strTestsFile)
    if tResult~=true then
      tLog.error('Failed to parse the test configuration file "%s".', strTestsFile)
      tResult = nil
    else
      local atTestCases = self.atTestCases

      -- Get the number of available test cases.
      self.uiNumberOfTests = #atTestCases

      -- Get a lookup table with the test names.
      local astrTestNames = {}
      for uiTestIndex, tTestCase in ipairs(atTestCases) do
        table.insert(astrTestNames, tTestCase.name)
      end
      self.astrTestNames = astrTestNames
    end
  end

  return tResult
end



function TestDescription:getTitle()
  return self.strTitle
end



function TestDescription:getSubtitle()
  return self.strSubtitle
end



function TestDescription:getPre()
  return self.strPre
end



function TestDescription:getPost()
  return self.strPost
end



function TestDescription:getSystemParameter()
  local tResult

  if self.tSystem~=nil then
    tResult = self.tSystem.parameter
  end

  return tResult
end



function TestDescription:getNumberOfTests()
  return self.uiNumberOfTests
end



function TestDescription:getTestNames()
  return self.astrTestNames
end



function TestDescription:getTestCaseName(uiTestCase)
  local tLog = self.tLog
  local tResult

  -- Is the test case valid?
  local strType = type(uiTestCase)
  if strType=='number' then
    if uiTestCase>0 and uiTestCase<=self.uiNumberOfTests then
      tResult = self.astrTestNames[uiTestCase]
    else
      tLog.error('Invalid test case index for test cases 1 to %d: %d .', self.uiNumberOfTests, uiTestCase)
    end
  else
    tLog.error('5 The test case must be a number, here it has the type %s.', strType)
  end

  return tResult
end



function TestDescription:getTestCaseId(uiTestCase)
  local tLog = self.tLog
  local tResult

  -- Is the test case valid?
  local strType = type(uiTestCase)
  if strType=='number' then
    if uiTestCase>0 and uiTestCase<=self.uiNumberOfTests then
      local tAttr = self.atTestCases[uiTestCase]
      if tAttr~=nil then
        tResult = tAttr.id
      end
    else
      tLog.error('Invalid test case index for test cases 1 to %d: %d .', self.uiNumberOfTests, uiTestCase)
    end
  else
    tLog.error('1 The test case must be a number, here it has the type %s.', strType)
  end

  return tResult
end



function TestDescription:getTestCaseIndex(strTestCaseName)
  local tLog = self.tLog
  local tResult

  -- Is the test case valid?
  local strType = type(strTestCaseName)
  if strType=='string' then
    for uiIndex, strName in ipairs(self.astrTestNames) do
      if strName==strTestCaseName then
        tResult = uiIndex
        break
      end
    end
    if tResult==nil then
      tLog.error('No test with the name "%s" found.', strTestCaseName)
    end
  else
    tLog.error('The test case must be a string, here it has the type %s.', strType)
  end

  return tResult
end



function TestDescription:getTestCaseParameters(uiTestCase)
  local tLog = self.tLog
  local tResult

  -- Is the test case valid?
  local strType = type(uiTestCase)
  if strType=='number' then
    if uiTestCase>0 and uiTestCase<=self.uiNumberOfTests then
      tResult = self.atTestCases[uiTestCase].parameter
    else
      tLog.error('Invalid test case index for test cases 1 to %d: %d .', self.uiNumberOfTests, uiTestCase)
    end
  else
    tLog.error('2 The test case must be a number, here it has the type %s.', strType)
  end

  return tResult
end



function TestDescription:getTestCaseActionPre(uiTestCase)
  local tLog = self.tLog
  local tResult

  -- Is the test case valid?
  local strType = type(uiTestCase)
  if strType=='number' then
    if uiTestCase>0 and uiTestCase<=self.uiNumberOfTests then
      tResult = self.atTestCases[uiTestCase].pre
    else
      tLog.error('Invalid test case index for test cases 1 to %d: %d .', self.uiNumberOfTests, uiTestCase)
    end
  else
    tLog.error('3 The test case must be a number, here it has the type %s.', strType)
  end

  return tResult
end



function TestDescription:getTestCaseActionPost(uiTestCase)
  local tLog = self.tLog
  local tResult

  -- Is the test case valid?
  local strType = type(uiTestCase)
  if strType=='number' then
    if uiTestCase>0 and uiTestCase<=self.uiNumberOfTests then
      tResult = self.atTestCases[uiTestCase].post
    else
      tLog.error('Invalid test case index for test cases 1 to %d: %d .', self.uiNumberOfTests, uiTestCase)
    end
  else
    tLog.error('4 The test case must be a number, here it has the type %s.', strType)
  end

  return tResult
end



function TestDescription:getDocuments()
  return self.atDocuments
end


return TestDescription
