local expect

do
    local h = fs.open("rom/modules/main/cc/expect.lua", "r")
    local f, err = loadstring(h.readAll(), "@expect.lua")
    h.close()

    if not f then error(err) end
    expect = f().expect
end

if _VERSION == "Lua 5.1" then
    local type = type
    local nativeload = load
    local nativeloadstring = loadstring
    local nativesetfenv = setfenv

    local function prefix(chunkname)
        if type(chunkname) ~= "string" then return chunkname end
        local head = chunkname:sub(1, 1)
        if head == "=" or head == "@" then
            return chunkname
        else
            return "=" .. chunkname
        end
    end

    function load(x, name, mode, env)
        expect(1, x, "function", "string")
        expect(2, name, "string", "nil")
        expect(3, mode, "string", "nil")
        expect(4, env, "table", "nil")

        local ok, p1, p2 = pcall(function()
            if type(x) == "string" then
                local result, err = nativeloadstring(x, name)
                if result then
                    if env then
                        env._ENV = env
                        nativesetfenv(result, env)
                    end
                    return result
                else
                    return nil, err
                end
            else
                local result, err = nativeload(x, name)
                if result then
                    if env then
                        env._ENV = env
                        nativesetfenv(result, env)
                    end
                    return result
                else
                    return nil, err
                end
            end
        end)
        if ok then
            return p1, p2
        else
            error(p1, 2)
        end
    end

    if _CC_DISABLE_LUA51_FEATURES then
        setfenv = nil
        getfenv = nil
        loadstring = nil
        unpack = nil
        math.log10 = nil
        table.maxn = nil
    else
        loadstring = function(string, chunkname) return nativeloadstring(string, prefix(chunkname)) end

        _G.bit = {
            bnot = bit32.bnot,
            band = bit32.band,
            bor = bit32.bor,
            bxor = bit32.bxor,
            brshift = bit32.arshift,
            blshift = bit32.lshift,
            blogic_rshift = bit32.rshift,
        }
    end
end

function sys.name()
    return "starBIOS server orientated BIOS 0.0.dev-1"
end

function sys.Event(sFilter)
    local eventData = table.pack(coroutine.yield(sFilter))
    if eventData[1] == "terminate" then
        error("Terminated", 0)
    end
    return table.unpack(eventData, 1, eventData.n)
end

-- Install globals
function sys.sleep(nTime)
    expect(1, nTime, "number", "nil")
    local timer = os.startTimer(nTime or 0)
    repeat
        local _, param = os.pullEvent("timer")
    until param == timer
end

function sys.write(sText)
    expect(1, sText, "string", "number")

    local w, h = term.getSize()
    local x, y = term.getCursorPos()

    local nLinesPrinted = 0
    local function newLine()
        if y + 1 <= h then
            term.setCursorPos(1, y + 1)
        else
            term.setCursorPos(1, h)
            term.scroll(1)
        end
        x, y = term.getCursorPos()
        nLinesPrinted = nLinesPrinted + 1
    end

    -- Print the line with proper word wrapping
    sText = tostring(sText)
    while #sText > 0 do
        local whitespace = string.match(sText, "^[ \t]+")
        if whitespace then
            -- Print whitespace
            term.write(whitespace)
            x, y = term.getCursorPos()
            sText = string.sub(sText, #whitespace + 1)
        end

        local newline = string.match(sText, "^\n")
        if newline then
            -- Print newlines
            newLine()
            sText = string.sub(sText, 2)
        end

        local text = string.match(sText, "^[^ \t\n]+")
        if text then
            sText = string.sub(sText, #text + 1)
            if #text > w then
                -- Print a multiline word
                while #text > 0 do
                    if x > w then
                        newLine()
                    end
                    term.write(text)
                    text = string.sub(text, w - x + 2)
                    x, y = term.getCursorPos()
                end
            else
                -- Print a word normally
                if x + #text - 1 > w then
                    newLine()
                end
                term.write(text)
                x, y = term.getCursorPos()
            end
        end
    end

    return nLinesPrinted
end

function read(_sReplaceChar, _tHistory, _fnComplete, _sDefault)
    expect(1, _sReplaceChar, "string", "nil")
    expect(2, _tHistory, "table", "nil")
    expect(3, _fnComplete, "function", "nil")
    expect(4, _sDefault, "string", "nil")

    term.setCursorBlink(true)

    local sLine
    if type(_sDefault) == "string" then
        sLine = _sDefault
    else
        sLine = ""
    end
    local nHistoryPos
    local nPos, nScroll = #sLine, 0
    if _sReplaceChar then
        _sReplaceChar = string.sub(_sReplaceChar, 1, 1)
    end

    local tCompletions
    local nCompletion
    local function recomplete()
        if _fnComplete and nPos == #sLine then
            tCompletions = _fnComplete(sLine)
            if tCompletions and #tCompletions > 0 then
                nCompletion = 1
            else
                nCompletion = nil
            end
        else
            tCompletions = nil
            nCompletion = nil
        end
    end

    local function uncomplete()
        tCompletions = nil
        nCompletion = nil
    end

    local w = term.getSize()
    local sx = term.getCursorPos()

    local function redraw(_bClear)
        local cursor_pos = nPos - nScroll
        if sx + cursor_pos >= w then
            -- We've moved beyond the RHS, ensure we're on the edge.
            nScroll = sx + nPos - w
        elseif cursor_pos < 0 then
            -- We've moved beyond the LHS, ensure we're on the edge.
            nScroll = nPos
        end

        local _, cy = term.getCursorPos()
        term.setCursorPos(sx, cy)
        local sReplace = _bClear and " " or _sReplaceChar
        if sReplace then
            term.write(string.rep(sReplace, math.max(#sLine - nScroll, 0)))
        else
            term.write(string.sub(sLine, nScroll + 1))
        end

        if nCompletion then
            local sCompletion = tCompletions[nCompletion]
            local oldText, oldBg
            if not _bClear then
                oldText = term.getTextColor()
                oldBg = term.getBackgroundColor()
                term.setTextColor(colors.white)
                term.setBackgroundColor(colors.gray)
            end
            if sReplace then
                term.write(string.rep(sReplace, #sCompletion))
            else
                term.write(sCompletion)
            end
            if not _bClear then
                term.setTextColor(oldText)
                term.setBackgroundColor(oldBg)
            end
        end

        term.setCursorPos(sx + nPos - nScroll, cy)
    end

    local function clear()
        redraw(true)
    end

    recomplete()
    redraw()

    local function acceptCompletion()
        if nCompletion then
            -- Clear
            clear()

            -- Find the common prefix of all the other suggestions which start with the same letter as the current one
            local sCompletion = tCompletions[nCompletion]
            sLine = sLine .. sCompletion
            nPos = #sLine

            -- Redraw
            recomplete()
            redraw()
        end
    end
    while true do
        local sEvent, param, param1, param2 = os.pullEvent()
        if sEvent == "char" then
            -- Typed key
            clear()
            sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
            nPos = nPos + 1
            recomplete()
            redraw()

        elseif sEvent == "paste" then
            -- Pasted text
            clear()
            sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
            nPos = nPos + #param
            recomplete()
            redraw()

        elseif sEvent == "key" then
            if param == keys.enter then
                -- Enter
                if nCompletion then
                    clear()
                    uncomplete()
                    redraw()
                end
                break

            elseif param == keys.left then
                -- Left
                if nPos > 0 then
                    clear()
                    nPos = nPos - 1
                    recomplete()
                    redraw()
                end

            elseif param == keys.right then
                -- Right
                if nPos < #sLine then
                    -- Move right
                    clear()
                    nPos = nPos + 1
                    recomplete()
                    redraw()
                else
                    -- Accept autocomplete
                    acceptCompletion()
                end

            elseif param == keys.up or param == keys.down then
                -- Up or down
                if nCompletion then
                    -- Cycle completions
                    clear()
                    if param == keys.up then
                        nCompletion = nCompletion - 1
                        if nCompletion < 1 then
                            nCompletion = #tCompletions
                        end
                    elseif param == keys.down then
                        nCompletion = nCompletion + 1
                        if nCompletion > #tCompletions then
                            nCompletion = 1
                        end
                    end
                    redraw()

                elseif _tHistory then
                    -- Cycle history
                    clear()
                    if param == keys.up then
                        -- Up
                        if nHistoryPos == nil then
                            if #_tHistory > 0 then
                                nHistoryPos = #_tHistory
                            end
                        elseif nHistoryPos > 1 then
                            nHistoryPos = nHistoryPos - 1
                        end
                    else
                        -- Down
                        if nHistoryPos == #_tHistory then
                            nHistoryPos = nil
                        elseif nHistoryPos ~= nil then
                            nHistoryPos = nHistoryPos + 1
                        end
                    end
                    if nHistoryPos then
                        sLine = _tHistory[nHistoryPos]
                        nPos, nScroll = #sLine, 0
                    else
                        sLine = ""
                        nPos, nScroll = 0, 0
                    end
                    uncomplete()
                    redraw()

                end

            elseif param == keys.backspace then
                -- Backspace
                if nPos > 0 then
                    clear()
                    sLine = string.sub(sLine, 1, nPos - 1) .. string.sub(sLine, nPos + 1)
                    nPos = nPos - 1
                    if nScroll > 0 then nScroll = nScroll - 1 end
                    recomplete()
                    redraw()
                end

            elseif param == keys.home then
                -- Home
                if nPos > 0 then
                    clear()
                    nPos = 0
                    recomplete()
                    redraw()
                end

            elseif param == keys.delete then
                -- Delete
                if nPos < #sLine then
                    clear()
                    sLine = string.sub(sLine, 1, nPos) .. string.sub(sLine, nPos + 2)
                    recomplete()
                    redraw()
                end

            elseif param == keys["end"] then
                -- End
                if nPos < #sLine then
                    clear()
                    nPos = #sLine
                    recomplete()
                    redraw()
                end

            elseif param == keys.tab then
                -- Tab (accept autocomplete)
                acceptCompletion()

            end

        elseif sEvent == "mouse_click" or sEvent == "mouse_drag" and param == 1 then
            local _, cy = term.getCursorPos()
            if param1 >= sx and param1 <= w and param2 == cy then
                -- Ensure we don't scroll beyond the current line
                nPos = math.min(math.max(nScroll + param1 - sx, 0), #sLine)
                redraw()
            end

        elseif sEvent == "term_resize" then
            -- Terminal resized
            w = term.getSize()
            redraw()

        end
    end

    local _, cy = term.getCursorPos()
    term.setCursorBlink(false)
    term.setCursorPos(w + 1, cy)
    write("\n")

    return sLine
end

function loadfile(filename, mode, env)
    -- Support the previous `loadfile(filename, env)` form instead.
    if type(mode) == "table" and env == nil then
        mode, env = nil, mode
    end

    expect(1, filename, "string")
    expect(2, mode, "string", "nil")
    expect(3, env, "table", "nil")

    local file = fs.open(filename, "r")
    if not file then return nil, "File not found" end

    local func, err = load(file.readAll(), "@" .. fs.getName(filename), mode, env)
    file.close()
    return func, err
end

function sys.runfile(_sFile)
    expect(1, _sFile, "string")

    local fnFile, e = loadfile(_sFile, nil, _G)
    if fnFile then
        return fnFile()
    else
        error(e, 2)
    end
end

function sys.run(envt, path)
    expect(1, envt, "table")
    expect(2, path, "string")

    setmetatable(envt, { __index = _G })
    local rundata,_ = loadfile(_sPath, nil, tEnv)
    rundata()
end

function sys.loadAPI(path)
    expect(1, path, "string")

    envt = {}
    setmetatable(envt, { __index = _G })
    api,_ = loadfile(path,nil,envt)
    api()
end

local nativeShutdown = os.shutdown
function os.shutdown()
    nativeShutdown()
    while true do
        coroutine.yield()
    end
end

local nativeReboot = os.reboot
function os.reboot()
    nativeReboot()
    while true do
        coroutine.yield()
    end
end

-- Install the lua part of the HTTP api (if enabled)
if http then
    local nativeHTTPRequest = http.request

    local methods = {
        GET = true, POST = true, HEAD = true,
        OPTIONS = true, PUT = true, DELETE = true,
        PATCH = true, TRACE = true,
    }

    local function checkKey(options, key, ty, opt)
        local value = options[key]
        local valueTy = type(value)

        if (value ~= nil or not opt) and valueTy ~= ty then
            error(("bad field '%s' (expected %s, got %s"):format(key, ty, valueTy), 4)
        end
    end

    local function checkOptions(options, body)
        checkKey(options, "url", "string")
        if body == false then
          checkKey(options, "body", "nil")
        else
          checkKey(options, "body", "string", not body)
        end
        checkKey(options, "headers", "table", true)
        checkKey(options, "method", "string", true)
        checkKey(options, "redirect", "boolean", true)

        if options.method and not methods[options.method] then
            error("Unsupported HTTP method", 3)
        end
    end

    local function wrapRequest(_url, ...)
        local ok, err = nativeHTTPRequest(...)
        if ok then
            while true do
                local event, param1, param2, param3 = os.pullEvent()
                if event == "http_success" and param1 == _url then
                    return param2
                elseif event == "http_failure" and param1 == _url then
                    return nil, param2, param3
                end
            end
        end
        return nil, err
    end

    http.get = function(_url, _headers, _binary)
        if type(_url) == "table" then
            checkOptions(_url, false)
            return wrapRequest(_url.url, _url)
        end

        expect(1, _url, "string")
        expect(2, _headers, "table", "nil")
        expect(3, _binary, "boolean", "nil")
        return wrapRequest(_url, _url, nil, _headers, _binary)
    end

    http.post = function(_url, _post, _headers, _binary)
        if type(_url) == "table" then
            checkOptions(_url, true)
            return wrapRequest(_url.url, _url)
        end

        expect(1, _url, "string")
        expect(2, _post, "string")
        expect(3, _headers, "table", "nil")
        expect(4, _binary, "boolean", "nil")
        return wrapRequest(_url, _url, _post, _headers, _binary)
    end

    http.request = function(_url, _post, _headers, _binary)
        local url
        if type(_url) == "table" then
            checkOptions(_url)
            url = _url.url
        else
            expect(1, _url, "string")
            expect(2, _post, "string", "nil")
            expect(3, _headers, "table", "nil")
            expect(4, _binary, "boolean", "nil")
            url = _url.url
        end

        local ok, err = nativeHTTPRequest(_url, _post, _headers, _binary)
        if not ok then
            os.queueEvent("http_failure", url, err)
        end
        return ok, err
    end

    local nativeCheckURL = http.checkURL
    http.checkURLAsync = nativeCheckURL
    http.checkURL = function(_url)
        local ok, err = nativeCheckURL(_url)
        if not ok then return ok, err end

        while true do
            local _, url, ok, err = os.pullEvent("http_check")
            if url == _url then return ok, err end
        end
    end

    local nativeWebsocket = http.websocket
    http.websocketAsync = nativeWebsocket
    http.websocket = function(_url, _headers)
        expect(1, _url, "string")
        expect(2, _headers, "table", "nil")

        local ok, err = nativeWebsocket(_url, _headers)
        if not ok then return ok, err end

        while true do
            local event, url, param = os.pullEvent( )
            if event == "websocket_success" and url == _url then
                return param
            elseif event == "websocket_failure" and url == _url then
                return false, param
            end
        end
    end
end

local expect = dofile("rom/modules/main/cc/expect.lua").expect


_G.CHANNEL_BROADCAST = 65535

_G.CHANNEL_REPEAT = 65533

_G.rednetID = os.getComputerID()

_G.duplicate_msg = false

_G.rednet_seed = (os.time()^5)

_G.rednet_reply = os.getComputerID()

_G.override_hostname_check = false

math.randomseed(rednet_seed)

local tReceivedMessages = {}
local tReceivedMessageTimeouts = {}
local tHostnames = {}

function open(modem)
    expect(1, modem, "string")
    if peripheral.getType(modem) ~= "modem" then
        error("No such modem: " .. modem, 2)
    end
    peripheral.call(modem, "open", rednetID)
    peripheral.call(modem, "open", CHANNEL_BROADCAST)
end

function close(modem)
    expect(1, modem, "string", "nil")
    if modem then
        if peripheral.getType(modem) ~= "modem" then
            error("No such modem: " .. modem, 2)
        end
        peripheral.call(modem, "close", rednetID)
        peripheral.call(modem, "close", CHANNEL_BROADCAST)
    else
        for _, modem in ipairs(peripheral.getNames()) do
            if isOpen(modem) then
                close(modem)
            end
        end
    end
end

function isOpen(modem)
    expect(1, modem, "string", "nil")
    if modem then
        if peripheral.getType(modem) == "modem" then
            return peripheral.call(modem, "isOpen", os.getComputerID()) and peripheral.call(modem, "isOpen", CHANNEL_BROADCAST)
        end
    else
        for _, modem in ipairs(peripheral.getNames()) do
            if isOpen(modem) then
                return true
            end
        end
    end
    return false
end

function send(nRecipient, message, sProtocol)
    expect(1, nRecipient, "number")
    expect(3, sProtocol, "string", "nil")

    local nMessageID = math.random(1, 2147483647)
    tReceivedMessages[nMessageID] = duplicate_msg
    tReceivedMessageTimeouts[os.startTimer(30)] = nMessageID

    local nReplyChannel = rednet_reply
    local tMessage = {
        nMessageID = nMessageID,
        nRecipient = nRecipient,
        message = message,
        sProtocol = sProtocol,
    }

    local sent = false
    if nRecipient == rednetID then
        os.queueEvent("rednet_message", nReplyChannel, message, sProtocol)
        sent = true
    else
        for _, sModem in ipairs(peripheral.getNames()) do
            if isOpen(sModem) then
                peripheral.call(sModem, "transmit", nRecipient, nReplyChannel, tMessage)
                peripheral.call(sModem, "transmit", CHANNEL_REPEAT, nReplyChannel, tMessage)
                sent = true
            end
        end
    end

    return sent
end

function broadcast(message, sProtocol)
    expect(2, sProtocol, "string", "nil")
    send(CHANNEL_BROADCAST, message, sProtocol)
end

function receive(sProtocolFilter, nTimeout)
    if type(sProtocolFilter) == "number" and nTimeout == nil then
        sProtocolFilter, nTimeout = nil, sProtocolFilter
    end
    expect(1, sProtocolFilter, "string", "nil")
    expect(2, nTimeout, "number", "nil")

    local timer = nil
    local sFilter = nil
    if nTimeout then
        timer = os.startTimer(nTimeout)
        sFilter = nil
    else
        sFilter = "rednet_message"
    end

    while true do
        local sEvent, p1, p2, p3 = os.pullEvent(sFilter)
        if sEvent == "rednet_message" then
            local nSenderID, message, sProtocol = p1, p2, p3
            if sProtocolFilter == nil or sProtocol == sProtocolFilter then
                return nSenderID, message, sProtocol
            end
        elseif sEvent == "timer" then
            if p1 == timer then
                return nil
            end
        end
    end
end

function host(sProtocol, sHostname)
    expect(1, sProtocol, "string")
    expect(2, sHostname, "string")
    if sHostname == "localhost" then
        error("Reserved hostname", 2)
    end
    if tHostnames[sProtocol] ~= sHostname then
        if lookup(sProtocol, sHostname) ~= nil then
            if override_hostname_check == false then
                error("Hostname in use", 2)
            end
        end
        tHostnames[sProtocol] = sHostname
    end
end

function unhost(sProtocol)
    expect(1, sProtocol, "string")
    tHostnames[sProtocol] = nil
end

function lookup(sProtocol, sHostname)
    expect(1, sProtocol, "string")
    expect(2, sHostname, "string", "nil")

    local tResults = nil
    if sHostname == nil then
        tResults = {}
    end

    if tHostnames[sProtocol] then
        if sHostname == nil then
            table.insert(tResults, os.getComputerID())
        elseif sHostname == "localhost" or sHostname == tHostnames[sProtocol] then
            return os.getComputerID()
        end
    end

    if not isOpen() then
        if tResults then
            return table.unpack(tResults)
        end
        return nil
    end

    -- Broadcast a lookup packet
    broadcast({
        sType = "lookup",
        sProtocol = sProtocol,
        sHostname = sHostname,
    }, "dns")

    local timer = os.startTimer(2)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local nSenderID, tMessage, sMessageProtocol = p1, p2, p3
            if sMessageProtocol == "dns" and type(tMessage) == "table" and tMessage.sType == "lookup response" then
                if tMessage.sProtocol == sProtocol then
                    if sHostname == nil then
                        table.insert(tResults, nSenderID)
                    elseif tMessage.sHostname == sHostname then
                        return nSenderID
                    end
                end
            end
        else
            if p1 == timer then
                break
            end
        end
    end
    if tResults then
        return table.unpack(tResults)
    end
    return nil
end

local bRunning = false

function run()
    if bRunning then
        error("rednet is already running", 2)
    end
    bRunning = true

    while bRunning do
        local sEvent, p1, p2, p3, p4 = os.pullEventRaw()
        if sEvent == "modem_message" then
            local sModem, nChannel, nReplyChannel, tMessage = p1, p2, p3, p4
            if isOpen(sModem) and (nChannel == os.getComputerID() or nChannel == CHANNEL_BROADCAST) then
                if type(tMessage) == "table" and tMessage.nMessageID then
                    if not tReceivedMessages[tMessage.nMessageID] then
                        tReceivedMessages[tMessage.nMessageID] = true
                        tReceivedMessageTimeouts[os.startTimer(30)] = tMessage.nMessageID
                        os.queueEvent("rednet_message", nReplyChannel, tMessage.message, tMessage.sProtocol)
                    end
                end
            end

        elseif sEvent == "rednet_message" then
            local nSenderID, tMessage, sProtocol = p1, p2, p3
            if sProtocol == "dns" and type(tMessage) == "table" and tMessage.sType == "lookup" then
                local sHostname = tHostnames[tMessage.sProtocol]
                if sHostname ~= nil and (tMessage.sHostname == nil or tMessage.sHostname == sHostname) then
                    rednet.send(nSenderID, {
                        sType = "lookup response",
                        sHostname = sHostname,
                        sProtocol = tMessage.sProtocol,
                    }, "dns")
                end
            end

        elseif sEvent == "timer" then
            local nTimer = p1
            local nMessage = tReceivedMessageTimeouts[nTimer]
            if nMessage then
                tReceivedMessageTimeouts[nTimer] = nil
                tReceivedMessages[nMessage] = nil
            end
        end
    end
end

function fs.isDriveRoot(sPath)
    expect(1, sPath, "string")
    return fs.getDir(sPath) == ".." or fs.getDrive(sPath) ~= fs.getDrive(fs.getDir(sPath))
end

local ok, err = pcall(parallel.waitForAny,
    function()
        os.run({}, "starShell.lua")
    end,
    rednet.run
)

term.redirect(term.native())
if not ok then
    write(err)
    pcall(function()
        term.setCursorBlink(false)
        write("\nPress any key to continue")
        os.pullEvent("key")
    end)
end

os.shutdown()
