--[[
    A fake ImGui for the window's tests, after Sidekick's tests/ui_window_test.lua: every scope opened must be
    closed, every style var popped, every widget id unique per window, every point a { x, y }, every text a string.
    Every opener reports open (so every popup's body draws) unless a test sets clicks[opener or popup id] = false.
    A click is clicks[label] = true; typing is clicks[label] = 'text' (and Enter, for EnterReturnsTrue).

    fake.frame(clicks) starts a frame; fake.check() after it asserts the stacks are empty.
]]--

local fake = {}

-- The ImGui constants .luacheckrc lets the code use, as distinct numbers.
local rc = { files = {} }
setfenv(assert(loadfile('.luacheckrc')), rc)()
for i, name in ipairs(rc.read_globals) do
    if name:match('^ImGui') then rawset(_G, name, i) end
end

local CLOSER = {
    Begin = 'End', BeginChild = 'EndChild', BeginPopup = 'EndPopup', BeginTooltip = 'EndTooltip',
    PushStyleColor = 'PopStyleColor', PushItemWidth = 'PopItemWidth',
}
local ALWAYS = { Begin = true, BeginChild = true, PushStyleColor = true, PushItemWidth = true }
local IDS = { Button = true, InvisibleButton = true }

local frame
fake.log = {}  -- every frame's texts, for the tests to look in

local function pop(closer)
    local top = table.remove(frame.stack)
    assert(top == closer, ('%s, but %s is open'):format(closer, tostring(top)))
end

local function point(p, what)
    assert(type(p) == 'table' and type(p[1]) == 'number' and type(p[2]) == 'number', what .. ': must be { x, y }')
    assert(p[1] == p[1] and p[2] == p[2], what .. ': NaN')
end

local POINTS = { AddRectFilled = { 1, 2 }, AddRect = { 1, 2 }, AddLine = { 1, 2 }, AddCircleFilled = { 1 },
                 AddCircle = { 1 }, AddTriangleFilled = { 1, 2, 3 } }

local LIST = setmetatable({}, { __index = function (_, name)
    return function (_, ...)
        local args = { ... }
        for _, i in ipairs(POINTS[name] or {}) do point(args[i], name) end
        if name == 'AddText' then
            local at = type(args[2]) == 'number' and 3 or 1
            point(args[at], name)
            assert(type(args[at + 2]) == 'string', 'AddText: text must be a string')
            frame.texts[#frame.texts + 1] = args[at + 2]
        end
    end
end })

local handlers = {
    Text = function (s) assert(not s:gsub('%%%%', ''):find('%%'), 'unescaped %: ' .. s) frame.texts[#frame.texts + 1] = s end,
    TextDisabled = function (s) assert(not s:gsub('%%%%', ''):find('%%'), 'unescaped %: ' .. s) frame.texts[#frame.texts + 1] = s end,
    TextUnformatted = function (s) assert(type(s) == 'string') frame.texts[#frame.texts + 1] = s end,
    PushFont = function (font, px)
        assert(font ~= nil and px == nil, 'PushFont: the face alone on 1.81')
        table.insert(frame.stack, 'PopFont')
    end,
    PopFont = function () pop('PopFont') end,
    SetWindowFontScale = function () end,
    IsItemHovered = function () return true end,
    IsItemActive = function () return false end,
    IsAnyItemActive = function () return false end,
    IsMouseHoveringRect = function () return frame.clicks.over == true end,
    IsWindowHovered = function () return true end,
    IsWindowAppearing = function () return frame.clicks.appearing == true end,
    IsMouseClicked = function (b) return frame.clicks['mouse' .. b] == true end,
    IsPopupOpen = function (id) return frame.clicks[id] ~= false end,
    OpenPopup = function (id) frame.opened[#frame.opened + 1] = id end,
    CloseCurrentPopup = function () end,
    SetKeyboardFocusHere = function () end,
    SetNextWindowSize = function (size) point(size, 'SetNextWindowSize') end,
    SetNextWindowPos = function (p) point(p, 'SetNextWindowPos') end,
    SetNextWindowSizeConstraints = function (a, b) point(a, 'constraint min') point(b, 'constraint max') end,
    CalcTextSize = function (s) return #s * 7, 13 end,
    GetFontSize = function () return 13 end,
    GetFont = function () return 'font' end,
    GetIO = function () return { DisplaySize = { x = 1920, y = 1080 }, Fonts = { Fonts = {} } } end,
    -- where the last SetCursorScreenPos put it (a window starts at 100, 50), as a child's content starts there
    GetCursorScreenPos = function () local c = frame.cursor or { 100, 50 } return c[1], c[2] end,
    GetWindowDrawList = function () return LIST end,
    PushStyleVar = function (var, v)
        if var == ImGuiStyleVar_WindowPadding then point(v, 'WindowPadding') end
        frame.vars = frame.vars + 1
    end,
    PopStyleVar = function (n)
        frame.vars = frame.vars - (n or 1)
        assert(frame.vars >= 0, 'PopStyleVar with none pushed')
    end,
    PopStyleColor = function (n) for _ = 1, n or 1 do pop('PopStyleColor') end end,
    SetCursorScreenPos = function (p) point(p, 'SetCursorScreenPos') frame.cursor = p end,
    Dummy = function (size) point(size, 'Dummy') end,
    SetScrollHereY = function () end,
    InvisibleButton = function (label, size)
        point(size, label)
        assert(size[1] > 0 and size[2] > 0, label .. ': ImGui asserts on a zero size')
        return frame.clicks[label] == true
    end,
    Button = function (label) return frame.clicks[label] == true end,
    Selectable = function (label)
        frame.selectables[#frame.selectables + 1] = label
        return frame.clicks[label] == true
    end,
    InputText = function (label, v, max)
        assert(type(v) == 'table' and type(v[1]) == 'string', label .. ': value must be { string }')
        assert(type(max) == 'number' and max > 0, label .. ': a size')
        frame.inputs[#frame.inputs + 1] = label
        local typed = frame.clicks[label]
        if type(typed) ~= 'string' then return false end
        v[1] = typed
        return true  -- (with EnterReturnsTrue: Enter pressed too)
    end,
    PushItemWidth = function (w) assert(type(w) == 'number', 'PushItemWidth: a number') table.insert(frame.stack, 'PopItemWidth') end,
    GetMousePos = function () return 0, 0 end,
}

fake.imgui = setmetatable({}, { __index = function (_, name)
    return function (...)
        local label = ...
        if IDS[name] then
            assert(type(label) == 'string', name .. ': a label')
            local id = label:match('###.*') or label
            local key = (frame.window or '') .. '|' .. id
            assert(not frame.ids[key], 'duplicate widget id ' .. id)
            frame.ids[key] = true
        end
        if CLOSER[name] then
            local open = frame.clicks[name] ~= false and (name ~= 'BeginPopup' or frame.clicks[label] ~= false)
            if name == 'PushItemWidth' then return handlers.PushItemWidth(...) end
            if open or ALWAYS[name] then table.insert(frame.stack, CLOSER[name]) end
            if name == 'Begin' then
                frame.window, frame.cursor = label, nil
                local p_open = select(2, ...)
                if frame.clicks.close == label and type(p_open) == 'table' then p_open[1] = false end
            end
            if name == 'BeginPopup' then frame.popups[#frame.popups + 1] = label end
            return open
        elseif name:match('^End') or name == 'PopItemWidth' then
            pop(name)
        elseif handlers[name] then
            return handlers[name](...)
        end
        return false
    end
end })

function fake.frame(clicks)
    frame = { stack = {}, vars = 0, texts = {}, ids = {}, clicks = clicks or {}, opened = {}, popups = {},
              selectables = {}, inputs = {} }
    fake.current = frame
    return frame
end

function fake.check()
    assert(#frame.stack == 0, 'left open: ' .. table.concat(frame.stack, ', '))
    assert(frame.vars == 0, 'style vars left pushed: ' .. frame.vars)
end

-- Whether the last frame drew a text holding `s`.
function fake.drew(s)
    for _, t in ipairs(frame.texts) do if t:find(s, 1, true) then return true end end
    return false
end

package.preload['imgui'] = function () return fake.imgui end

return fake
