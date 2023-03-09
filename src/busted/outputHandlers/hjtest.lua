-- Partial code from https://github.com/lunarmodules/busted
-- *********************************************************************************
-- MIT License Terms
-- =================
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- *********************************************************************************

-- Partial code from https://github.com/hishamhm/busted-htest
-- *********************************************************************************
-- MIT License Terms
-- =================

-- Copyright (c) 2012-2020 Olivine Labs, LLC.
-- Copyright (c) 2020 Hisham Muhammad

-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- *********************************************************************************


local pretty            = require('pl.pretty')
local term              = require('term')
local io                = io
local xml               = require('pl.xml')
local string            = require("string")
local type              = type
local string_format     = string.format
local io_open           = io.open
local io_write          = io.write
local io_flush          = io.flush
local os_date           = os.date
local table_insert      = table.insert
local table_remove      = table.remove


local junit_handler = {}
do
  local top
  local output_file_name
  local stack = {}
  local testcase_node

  junit_handler.init = function(busted, base_handler, options)
    junit_handler.busted = busted
    setmetatable(junit_handler, { __index = base_handler })
    junit_handler.options = options

    output_file_name = options[1] or 'report.xml'

    top = {
      start_tick = busted.monotime(),
      xml_doc = xml.new('testsuites', {
        tests = 0,
        errors = 0,
        failures = 0,
        skip = 0,
      })
    }
  end

  junit_handler.suiteStart = function(suite, count, total)
    local suite_xml = {
      start_tick = suite.starttick,
      xml_doc = xml.new('testsuite', {
        name = 'Run ' .. count .. ' of ' .. total,
        tests = 0,
        errors = 0,
        failures = 0,
        skip = 0,
        timestamp = os_date('!%Y-%m-%dT%H:%M:%S'),
      })
    }
    top.xml_doc:add_direct_child(suite_xml.xml_doc)
    table_insert(stack, top)
    top = suite_xml

    return nil, true
  end

  local function formatDuration(duration)
    return string_format("%.2f", duration)
  end

  local function elapsed(start_time)
    return formatDuration(junit_handler.busted.monotime() - start_time)
  end

  junit_handler.suiteEnd = function(suite, count, total)
    local suite_xml = top
    suite_xml.xml_doc.attr.time = formatDuration(suite.duration)

    top = table_remove(stack)
    top.xml_doc.attr.tests = top.xml_doc.attr.tests + suite_xml.xml_doc.attr.tests
    top.xml_doc.attr.errors = top.xml_doc.attr.errors + suite_xml.xml_doc.attr.errors
    top.xml_doc.attr.failures = top.xml_doc.attr.failures + suite_xml.xml_doc.attr.failures
    top.xml_doc.attr.skip = top.xml_doc.attr.skip + suite_xml.xml_doc.attr.skip

    return nil, true
  end

  junit_handler.exit = function()
    top.xml_doc.attr.time = elapsed(top.start_tick)
    local output_string = xml.tostring(top.xml_doc, '', '\t', nil, false)
    local file
    if 'string' == type(output_file_name) then
      file = io_open(output_file_name, 'w+b' )
    end
    if file then
      file:write(output_string)
      file:write('\n')
      file:close()
    else
      io_write(output_string)
      io_write("\n")
      io_flush()
    end
    return nil, true
  end

  local function testStatus(element, parent, message, status, trace)
    if status ~= 'success' then
      testcase_node:addtag(status)
      if status ~= 'pending' and parent and parent.randomseed then
        testcase_node:text('Random seed: ' .. parent.randomseed .. '\n')
      end
      if message then testcase_node:text(message) end
      if trace and trace.traceback then testcase_node:text(trace.traceback) end
      testcase_node:up()
    end
  end

  junit_handler.testStart = function(element, parent)
    testcase_node = xml.new('testcase', {
      classname = element.trace.short_src .. ':' .. element.trace.currentline,
      name = junit_handler.getFullName(element),
    })
    top.xml_doc:add_direct_child(testcase_node)

    return nil, true
  end

  junit_handler.testEnd = function(element, parent, status)
    top.xml_doc.attr.tests = top.xml_doc.attr.tests + 1
    testcase_node:set_attrib("time", formatDuration(element.duration))

    if status == 'success' then
      testStatus(element, parent, nil, 'success')
    elseif status == 'pending' then
      top.xml_doc.attr.skip = top.xml_doc.attr.skip + 1
      local formatted = junit_handler.pendings[#junit_handler.pendings]
      local trace = element.trace ~= formatted.trace and formatted.trace
      testStatus(element, parent, formatted.message, 'skipped', trace)
    end

    return nil, true
  end

  junit_handler.failureTest = function(element, parent, message, trace)
    top.xml_doc.attr.failures = top.xml_doc.attr.failures + 1
    testStatus(element, parent, message, 'failure', trace)
    return nil, true
  end

  junit_handler.errorTest = function(element, parent, message, trace)
    top.xml_doc.attr.errors = top.xml_doc.attr.errors + 1
    testStatus(element, parent, message, 'error', trace)
    return nil, true
  end

  junit_handler.error = function(element, parent, message, trace)
    if element.descriptor ~= 'it' then
      top.xml_doc.attr.errors = top.xml_doc.attr.errors + 1
      top.xml_doc:addtag('error')
      top.xml_doc:text(message)
      if trace and trace.traceback then
        top.xml_doc:text(trace.traceback)
      end
      top.xml_doc:up()
    end

    return nil, true
  end
end

local htest_handler = {}
do
  local colors

  local isatty = io.type(io.stdout) == 'file' and term.isatty(io.stdout)

  local isWindows = package.config:sub(1,1) == '\\'

  if isWindows and not os.getenv("ANSICON") then
    colors = setmetatable({}, {__index = function() return function(s) return s end end})
    isatty = false

  else
    colors = require 'term.colors'
  end

  local clreol = "\27[K"
  local cursorup = isatty and "\27[1A" or ""

  local repeatSuiteString = '\nRepeating all tests (run %u of %u) . . .\n\n'
  local randomizeString  = colors.yellow('Note: Randomizing test order with a seed of %u.\n')
  local suiteStartString = colors.green  ('=======') .. ' Running tests from scanned files.\n'
  local globalSetup      = colors.green  ('-------') .. ' Global test environment setup.\n'
  local fileStartString  = colors.green  ('-------') .. ' Running tests from ' .. colors.cyan('%s') .. ' :\n'
  local runningString    = colors.green  (' RUN') .. ' %s'
  local successString    = colors.green  ('  OK') .. clreol .. ' %s'
  local skippedString    = colors.yellow ('SKIP') .. clreol .. ' %s'

  local failureStartString   = colors.red ('        __________' .. clreol .. '\n        FAIL') .. ' %s'
  local failureString        = colors.red ('__________')

  local errorStartString  = colors.magenta('        __________' .. clreol .. '\n         ERR') .. ' %s'
  local errorString       = colors.magenta('__________')
  local errorAltEndString = colors.magenta('        __________') .. '\n\n'

  local fileEndString    = colors.green  ('-------') .. ' %u %s from %s (%.2f ms total)\n\n'
  local globalTeardown   = colors.green  ('-------') .. ' Global test environment teardown.\n'
  local suiteEndString   = colors.green  ('=======') .. ' %u %s from %u test %s ran. (%.2f ms total)\n'
  local successStatus    = colors.green  ('PASSED ') .. ' %u %s.\n\n'

  local summaryStrings = {
    skipped = {
      header = 'SKIPPED %u %s, listed below:\n',
      test   = colors.yellow ('SKIPPED') .. ' %s\n',
      footer = ' %u SKIPPED %s\n',
    },

    failure = {
      header = ' FAILED %u %s, listed below:\n',
      test   = colors.red    (' FAILED') .. ' %s\n',
      footer = ' %u FAILED %s\n',
    },

    error = {
      header = '  ERROR %u %s, listed below:\n',
      test   = colors.magenta('  ERROR') .. ' %s\n',
      footer = ' %u %s\n',
    },
  }

  local fileCount = 0
  local fileTestCount = 0
  local testCount = 0
  local successCount = 0
  local skippedCount = 0
  local failureCount = 0
  local errorCount = 0

  local pendingDescription = function(pending)
    local string = ''

    if type(pending.message) == 'string' then
      string = string .. pending.message .. '\n'
    elseif pending.message ~= nil then
      string = string .. pretty.write(pending.message) .. '\n'
    end

    return string
  end

  local failureDescription = function(failure)
    local string = failure.randomseed and ('Random seed: ' .. failure.randomseed .. '\n') or ''
    if type(failure.message) == 'string' then
      string = string .. failure.message
    elseif failure.message == nil then
      string = string .. 'Nil error'
    else
      string = string .. pretty.write(failure.message)
    end

    string = '\n' .. string .. '\n'

    if htest_handler.options.verbose and failure.trace and failure.trace.traceback then
      string = string .. failure.trace.traceback .. '\n'
    end

    return string
  end

  local getFileLine = function(element)
    local fileline = ''
    if element.trace and element.trace.source then
      fileline = colors.cyan(element.trace.source:gsub("^@", "")) .. ':' ..
                 colors.cyan(element.trace.currentline) .. ': '
    end
    return fileline
  end

  local getTestList = function(status, count, list, getDescription)
    local string = ''
    local header = summaryStrings[status].header
    if count > 0 and header then
      local tests = (count == 1 and 'test' or 'tests')
      local errors = (count == 1 and 'error' or 'errors')
      string = header:format(count, status == 'error' and errors or tests)

      local testString = summaryStrings[status].test
      if testString then
        for _, t in ipairs(list) do
          local fullname = getFileLine(t.element) .. colors.bright(t.name)
          string = string .. testString:format(fullname)
          if htest_handler.options.deferPrint then
            string = string .. getDescription(t)
          end
        end
      end
    end
    return string
  end

  local getSummary = function(status, count)
    local string = ''
    local footer = summaryStrings[status].footer
    if count > 0 and footer then
      local tests = (count == 1 and 'TEST' or 'TESTS')
      local errors = (count == 1 and 'ERROR' or 'ERRORS')
      string = footer:format(count, status == 'error' and errors or tests)
    end
    return string
  end

  local getSummaryString = function()
    local tests = (successCount == 1 and 'test' or 'tests')
    local string = successStatus:format(successCount, tests)

    string = string .. getTestList('skipped', skippedCount, htest_handler.pendings, pendingDescription)
    string = string .. getTestList('failure', failureCount, htest_handler.failures, failureDescription)
    string = string .. getTestList('error', errorCount, htest_handler.errors, failureDescription)

    string = string .. ((skippedCount + failureCount + errorCount) > 0 and '\n' or '')
    string = string .. getSummary('skipped', skippedCount)
    string = string .. getSummary('failure', failureCount)
    string = string .. getSummary('error', errorCount)

    return string
  end

  local getTestName = function(element)
    local out = {}
    for text, hashtag in htest_handler.getFullName(element):gmatch("([^#]*)(#?[%w_-]*)") do
      table.insert(out, colors.bright(text))
      table.insert(out, colors.bright(colors.cyan(hashtag)))
    end
    return table.concat(out)
  end

  local getFullName = function(element)
    return getFileLine(element) .. getTestName(element)
  end

  local clock = function(ms)
    if ms < 1000 then
      return colors.cyan(("%7.2f"):format(ms))
    elseif ms < 10000 then
      return colors.yellow(("%7.2f"):format(ms))
    else
      return colors.bright(colors.red(("%7.2f"):format(ms)))
    end
  end

  htest_handler.init = function(busted, base_handler, options)
    htest_handler.options = options
    setmetatable(htest_handler, { __index = base_handler })
    htest_handler.busted = busted
  end

  htest_handler.suiteReset = function()
    fileCount = 0
    fileTestCount = 0
    testCount = 0
    successCount = 0
    skippedCount = 0
    failureCount = 0
    errorCount = 0

    return nil, true
  end

  htest_handler.suiteStart = function(suite, count, total, randomseed)
    if total > 1 then
      io.write(repeatSuiteString:format(count, total))
    end
    if randomseed then
      io.write(randomizeString:format(randomseed))
    end
    io.write(suiteStartString)
    io.write(globalSetup)
    io.flush()

    return nil, true
  end

  htest_handler.suiteEnd = function(suite, count, total)
    local elapsedTime_ms = suite.duration * 1000
    local tests = (testCount == 1 and 'test' or 'tests')
    local files = (fileCount == 1 and 'file' or 'files')
    io.write(globalTeardown)
    io.write(suiteEndString:format(testCount, tests, fileCount, files, elapsedTime_ms))
    io.write(getSummaryString())
    io.flush()

    return nil, true
  end

  htest_handler.fileStart = function(file)
    fileTestCount = 0

    io.write(fileStartString:format(file.name))
    io.flush()
    return nil, true
  end

  htest_handler.fileEnd = function(file)
    local elapsedTime_ms = file.duration * 1000
    local tests = (fileTestCount == 1 and 'test' or 'tests')
    fileCount = fileCount + 1
    io.write(fileEndString:format(fileTestCount, tests, file.name, elapsedTime_ms))
    io.flush()
    return nil, true
  end

  htest_handler.testStart = function(element, parent)
    if isatty then
      local successName = colors.cyan(element.trace.currentline) .. ': '.. getTestName(element)
      local str = '....... ' .. runningString:format(successName) .. '\n'
      io.write(str)
      io.flush()
    end

    return nil, true
  end

  htest_handler.testEnd = function(element, parent, status, debug)
    local elapsedTime_ms = element.duration * 1000
    local string

    fileTestCount = fileTestCount + 1
    testCount = testCount + 1
    local successName = colors.cyan(element.trace.currentline) .. ': '.. getTestName(element)
    if status == 'success' then
      io.write(cursorup)
      successCount = successCount + 1
      string = clock(elapsedTime_ms) .. ' ' .. successString:format(successName) .. '\n'
    elseif status == 'pending' then
      io.write(cursorup)
      skippedCount = skippedCount + 1
      string = '        ' .. skippedString:format(successName) .. '\n'
    elseif status == 'failure' then
      failureCount = failureCount + 1
      string = clock(elapsedTime_ms) .. ' ' .. failureString .. '\n\n'
    elseif status == 'error' then
      errorCount = errorCount + 1
      string = clock(elapsedTime_ms) .. ' ' .. errorString ..  '\n\n'
    end

    io.write(string)
    io.flush()

    return nil, true
  end

  htest_handler.testFailure = function(element, parent, message, debug)
    if not htest_handler.options.deferPrint then
      io.write(failureStartString:format(getFullName(element)))
      io.write(failureDescription(htest_handler.failures[#htest_handler.failures]))
      io.flush()
    end
    return nil, true
  end

  htest_handler.testError = function(element, parent, message, debug)
    if not htest_handler.options.deferPrint then
      io.write(errorStartString:format(getFullName(element)))
      io.write(failureDescription(htest_handler.errors[#htest_handler.errors]))
      io.flush()
    end
    return nil, true
  end

  htest_handler.error = function(element, parent, message, debug)
    if element.descriptor ~= 'it' then
      if not htest_handler.options.deferPrint then
        io.write(errorStartString:format(getFullName(element)))
        io.write(failureDescription(htest_handler.errors[#htest_handler.errors]))
        io.write(errorAltEndString)
        io.flush()
      end
      errorCount = errorCount + 1
    end

    return nil, true
  end
end

return function(options)
  local busted = require 'busted'
  local handler = require 'busted.outputHandlers.base'()

  junit_handler.init(busted, handler, options)
  htest_handler.init(busted, handler, options)

  handler.suiteReset = function()
    htest_handler.suiteReset()
  end

  handler.suiteStart = function(suite, count, total, randomseed)
    htest_handler.suiteStart(suite, count, total, randomseed)
    junit_handler.suiteStart(suite, count, total)
    return nil, true
  end

  handler.suiteEnd = function(suite, count, total)
    htest_handler.suiteStart(suite, count, total)
    junit_handler.suiteEnd(suite, count, total)
    return nil, true
  end

  handler.fileStart = function(file)
    htest_handler.fileStart(file)
    return nil, true
  end

  handler.fileEnd = function(file)
    htest_handler.fileEnd(file)
    return nil, true
  end

  handler.testStart = function(element, parent)
    htest_handler.testStart(element, parent)
    junit_handler.testStart(element, parent)
    return nil, true
  end

  handler.testEnd = function(element, parent, status, debug)
    htest_handler.testEnd(element, parent, status, debug)
    junit_handler.testEnd(element, parent, status)
    return nil, true
  end

  handler.testFailure = function(element, parent, message, debug)
    htest_handler.testFailure(element, parent, message, debug)
    return nil, true
  end

  handler.testError = function(element, parent, message, debug)
    htest_handler.testError(element, parent, message, debug)
    return nil, true
  end

  handler.failureTest = function(element, parent, message, trace)
    junit_handler.failureTest(element, parent, message, trace)
  end

  handler.errorTest = function(element, parent, message, trace)
    junit_handler.errorTest(element, parent, message, trace)
    return nil, true
  end

  handler.error = function(element, parent, message, debug)
    htest_handler.error(element, parent, message, debug)
    junit_handler.error(element, parent, message, debug)
    return nil, true
  end

  handler.exit = function()
    junit_handler.exit()
    return nil, true
  end

  busted.subscribe({ 'suite', 'reset' }, handler.suiteReset)
  busted.subscribe({ 'suite', 'start' }, handler.suiteStart)
  busted.subscribe({ 'suite', 'end' }, handler.suiteEnd)
  busted.subscribe({ 'file', 'start' }, handler.fileStart)
  busted.subscribe({ 'file', 'end' }, handler.fileEnd)
  busted.subscribe({ 'test', 'start' }, handler.testStart, { predicate = handler.cancelOnPending })
  busted.subscribe({ 'test', 'end' }, handler.testEnd, { predicate = handler.cancelOnPending })
  busted.subscribe({ 'failure', 'it' }, handler.testFailure)
  busted.subscribe({ 'error', 'it' }, handler.testError)
  busted.subscribe({ 'failure', 'describe' }, handler.failureTest)
  busted.subscribe({ 'error', 'describe' }, handler.errorTest)
  busted.subscribe({ 'failure' }, handler.error)
  busted.subscribe({ 'error' }, handler.error)
  busted.subscribe({ 'exit' }, handler.exit)

  return handler
end
