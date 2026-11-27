-- core/send.lua, core/store.lua, core/data.lua and core/game.lua: the queue, what's kept, the lists, the packets.
local data = require('core.data')
local game = require('core.game')
local send = require('core.send')
local store = require('core.store')
local util = require('core.util')

-- send -------------------------------------------------------------------------------------------------------

local out
local function capture()
    out = { packet = {}, typed = {}, echo = {}, said = {}, sent = {} }
    send.out = {
        packet = function (l) out.packet[#out.packet + 1] = l end,
        typed = function (l) out.typed[#out.typed + 1] = l end,
        echo = function (l) out.echo[#out.echo + 1] = l end,
        said = function (fmt, ...) out.said[#out.said + 1] = fmt:format(...) end,
        sent = function (l) out.sent[#out.sent + 1] = l end,
    }
    send.reset()
end
-- What the server heard as your target, your target now, picking a sub-target: core/game.lua's probe.
local function yes() return 0, 0, false end      -- no target, and the server knows it
local function heard(i) return function () return i, i, false end end
local function unheard(i) return function () return 0, i, false end end

test('the chat packet: 0x0B5, its size, say, the text, NUL-padded', function ()
    local b = send.packet_bytes('!hp 1')
    eq(b[1], 0xB5, 'id')
    eq(#b % 4, 0, 'a multiple of 4')
    eq(b[2], #b / 4 * 2, 'size in 4-byte units above the id\'s ninth bit')
    eq(b[5], 0, 'say')
    local s = {}
    for i = 7, 7 + 4 do s[#s + 1] = string.char(b[i]) end
    eq(table.concat(s), '!hp 1', 'the text')
    eq(b[12], 0, 'a NUL after it')
    eq(#send.packet_bytes('!abc'), 12, '6 + 4 + 2 of padding')
    eq(#send.packet_bytes('!ab'), 12, '6 + 3 + 3: always a NUL')
    eq(#send.packet_bytes('!abcdef'), 16, '6 + 7 + 3')
end)

test('lines go in order, a gap apart', function ()
    capture()
    send.line('!where')
    send.line('!time')
    send.tick(10, { mode = 'packet' }, yes)
    send.tick(10.01, { mode = 'packet' }, yes)
    eq(out.packet, { '!where' }, 'one, then the gap')
    send.tick(10.2, { mode = 'packet' }, yes)
    eq(out.packet, { '!where', '!time' }, 'both')
    eq(out.echo, { '!where', '!time' }, 'echoed')
    eq(out.sent, { '!where', '!time' }, 'remembered')
end)

test('typed lines go through the chat box, 1.6 s apart, unechoed when asked', function ()
    capture()
    send.lines({ '!where', '!time' })
    local cfg = { mode = 'typed', echo = true }
    send.tick(20, cfg, yes)
    send.tick(21, cfg, yes)
    eq(out.typed, { '!where' }, 'held by the gap')
    send.tick(21.7, cfg, yes)
    eq(out.typed, { '!where', '!time' })
    eq(out.echo, {}, 'no echo: the chat box shows a typed line')
    eq(out.packet, {}, 'no packets')
end)

test('a cursor line waits for the server to hear its target, then is dropped', function ()
    capture()
    send.line('!getid', { cursor = true, index = 120 })
    send.line('!where')
    send.tick(30, nil, unheard(120))
    send.tick(31, nil, unheard(120))
    eq(out.packet, {}, 'held, and the line behind it too')
    send.tick(31.5, nil, heard(120))
    eq(out.packet, { '!getid' }, 'gone once heard')
    capture()
    send.line('!getid', { cursor = true, index = 120 })
    send.tick(40, nil, unheard(120))
    send.tick(43.1, nil, unheard(120))
    eq(out.packet, {}, 'never sent at what the server last heard')
    eq(#out.said, 1, 'said why')
    eq(send.pending(), 0, 'dropped')
end)

test('a cursor line is dropped when you target something else first', function ()
    capture()
    send.line('!hp 0', { cursor = true, index = 120 })
    send.tick(50, nil, function () return 121, 121, false end)
    eq(out.packet, {}, 'never at the new target')
    eq(send.pending(), 0)
    assert(out.said[1]:find('something else'), out.said[1])
    -- targeting nothing in between is something else too
    send.line('!hp 0', { cursor = true, index = 120 })
    send.tick(51, nil, function () return 120, 0, false end)
    eq(out.packet, {}, 'not with no target')
    -- none at the click, none now, and the server knows it: it goes
    send.line('!getmod ATT', { cursor = true, index = 0 })
    send.tick(52, nil, yes)
    eq(out.packet, { '!getmod ATT' })
end)

test('a sub-target being picked holds a cursor line', function ()
    capture()
    send.line('!getid', { cursor = true, index = 120 })
    send.tick(60, nil, function () return 120, 120, true end)
    eq(out.packet, {})
    send.tick(60.5, nil, heard(120))
    eq(out.packet, { '!getid' })
end)

test('the queue can be seen and cleared', function ()
    capture()
    send.lines({ '!where', '!time' })
    eq(#send.queued(), 2)
    eq(send.clear(), 2)
    eq(send.pending(), 0)
end)

test('a bad line never queues; a batch is all or none', function ()
    capture()
    local ok = send.line('hp 1')
    eq(ok, nil, 'no !')
    local ok2 = send.lines({ '!where', '!bad\nline' })
    eq(ok2, nil, 'one bad line stops all')
    eq(send.pending(), 0)
end)

-- store ------------------------------------------------------------------------------------------------------

local function fresh() store.cfg = util.copy(store.DEFAULTS) end

test('history: newest first, a repeat updates its time, capped', function ()
    fresh()
    store.remember('!where', 1)
    store.remember('!where', 5)
    eq(#store.cfg.history, 1, 'a repeat')
    eq(store.cfg.history[1].t, 5, 'its time')
    for i = 1, store.HISTORY + 10 do store.remember('!hp ' .. i, i) end
    eq(#store.cfg.history, store.HISTORY, 'capped')
    eq(store.cfg.history[1].line, '!hp ' .. (store.HISTORY + 10), 'newest first')
end)

test('names from history and typed', function ()
    fresh()
    store.remember('!hp 100 Kupipi', 1)
    eq(store.cfg.names, {}, 'a line alone adds no name (a capitalised word is no name)')
    store.name_used('Kupipi')
    store.name_used('Ajido')
    store.name_used('kupipi')
    eq(store.cfg.names, { 'kupipi', 'Ajido' }, 'a name used moves it up, any case')
    store.name_used('Bad Name')
    eq(#store.cfg.names, 2, 'not a name')
end)

test('favorites toggle and move', function ()
    fresh()
    eq(store.toggle_favorite('hp'), true)
    store.toggle_favorite('zone')
    store.toggle_favorite('where')
    store.move_favorite('where', -1)
    eq(store.cfg.favorites, { 'hp', 'where', 'zone' })
    eq(store.toggle_favorite('hp'), false)
    eq(store.cfg.favorites, { 'where', 'zone' })
    assert(store.is_favorite('zone') and not store.is_favorite('hp'))
end)

test('forms keep their values; clear empties them', function ()
    fresh()
    store.set_value('hp', 1, '100')
    store.set_value('hp', 2, 'Kupipi')
    eq(store.form('hp'), { '100', 'Kupipi' })
    store.set_value('hp', 1, '')
    eq(store.form('hp')[1], nil, 'cleared')
    store.clear_form('hp')
    eq(store.form('hp'), {})
end)

test('an older file gets the settings it lacks', function ()
    local cfg = store.complete({ ui = { open = false }, favorites = { 'hp' } })
    eq(cfg.ui.open, false, 'kept')
    eq(cfg.ui.scale, 100, 'added')
    eq(cfg.send.mode, 'packet', 'a whole table added')
    eq(cfg.favorites, { 'hp' }, 'a list kept as it is')
end)

-- data -------------------------------------------------------------------------------------------------------

test('lists from the server enums', function ()
    local zones = data.list({ set = 'zones' })
    assert(#zones > 250, 'zones')
    local found = data.filter(zones, 'jeuno', 50)
    assert(#found >= 4, 'the Jeunos')
    local e = data.find({ set = 'effects' }, '3')
    eq(e and e.name, 'POISON', 'effect 3')
    eq(data.value({ set = 'mods', send = 'name' }, data.find({ set = 'mods', send = 'name' }, 'ATT')), 'ATT', 'a mod by name')
    eq(#data.list({ set = 'jobs' }), 22, 'jobs without NONE')
    local crafts = data.list({ set = 'skills', crafts = true })
    assert(#crafts >= 9 and #crafts <= 12, 'crafts only: ' .. #crafts)
    assert(#data.list({ set = 'currencies' }) > 100, 'currencies')
end)

test('a number finds the entry with that id', function ()
    local r = data.filter(data.list({ set = 'zones' }), '230', 5)
    local has
    for _, e in ipairs(r) do if e.id == 230 then has = true end end
    assert(has, 'zone 230')
end)

test('quests and missions by log', function ()
    local logs = data.list({ set = 'questlogs' })
    assert(#logs >= 10, 'quest logs')
    local sandy = data.list({ set = 'quests' }, 0)
    assert(#sandy > 50, 'San d\'Oria quests')
    eq(data.find({ set = 'quests' }, '0', 0).name, 'A_SENTRYS_PERIL', 'quest 0')
    eq(#data.list({ set = 'quests' }, nil), 0, 'no log, no quests')
    assert(#data.list({ set = 'missions' }, 6) > 10, 'CoP missions')
end)

test('the client\'s names are indexed a slice at a time', function ()
    data.reset()
    data.res.item = function (id) return id % 2 == 0 and ('Item' .. id) or nil end
    data.index.items.last = 10
    eq(data.step('items', 4), false, 'not done')
    eq(data.step('items', 100), true, 'done')
    eq(#data.index.items.entries, 5, 'the even ones')
    eq(data.filter(data.index.items.entries, 'item4', 5)[1].id, 4)
    eq(data.name_of('items', 6), 'Item6')
    data.index.items.last = 65535
    data.reset()
end)

-- game -------------------------------------------------------------------------------------------------------

local function float_bytes(f)  -- IEEE 754 single, little-endian, for whole numbers and halves
    if f == 0 then return '\0\0\0\0' end
    local sign = f < 0 and 1 or 0
    f = math.abs(f)
    local e = math.floor(math.log(f) / math.log(2))
    local m = math.floor((f / 2 ^ e - 1) * 8388608 + 0.5)
    local exp = e + 127
    local b4 = sign * 128 + math.floor(exp / 2)
    local b3 = (exp % 2) * 128 + math.floor(m / 65536)
    return string.char(m % 256, math.floor(m / 256) % 256, b3, b4)
end

test('floats from a packet', function ()
    for _, f in ipairs({ 0, 1, -1, 12.5, -230.25, 1000 }) do
        eq(game.float(float_bytes(f), 1), f, tostring(f))
    end
end)

test('the position packet: your position and target as the server reads them', function ()
    local body = ('\0'):rep(4) .. float_bytes(10.5) .. float_bytes(-2) .. float_bytes(300) .. ('\0'):rep(6)
        .. string.char(0x34, 0x12) .. ('\0'):rep(8)
    game.on_packet_out(0x015, body)
    eq(game.heard.index, 0x1234, 'target index at 0x16')
    eq({ game.heard.x, game.heard.y, game.heard.z }, { 10.5, -2, 300 }, 'x, y (height), z')
    game.on_packet_out(0x016, ('\0'):rep(40))
    eq(game.heard.index, 0x1234, 'another packet changes nothing')
end)

test('ready: the server heard of the target you have', function ()
    game.heard.index = 120
    eq(game.ready({ index = 120 }), true)
    eq(game.ready({ index = 121 }), false)
    eq(game.ready({ index = 120, sub = true }), false, 'picking a sub-target')
    game.heard.index = 0
    eq(game.ready(nil), true, 'none and none')
    game.heard.index = nil
    eq(game.ready({ index = 5 }), false, 'nothing heard yet')
end)

test('zoning forgets what the server heard', function ()
    game.heard = { index = 5, x = 1, y = 2, z = 3 }
    game.on_packet_in(0x00A)
    eq(game.heard.x, nil)
    eq(game.heard.index, nil)
    game.heard = { index = 5, x = 1, y = 2, z = 3 }
    game.on_packet_in(0x00D)
    eq(game.heard.index, 5, 'another packet changes nothing')
end)

test('a character switch: each character its own lists, never another\'s', function ()
    -- Ashita's library, faked: it fills what a file lacks with the defaults' own tables, as merge does
    local defaults, events = nil, {}
    local function merged(file)
        local s = {}
        for k, v in pairs(file) do s[k] = v end
        for k, v in pairs(defaults) do if s[k] == nil then s[k] = v end end
        return s
    end
    package.loaded['settings'] = {
        load = function (d) defaults = d return merged({}) end,
        save = function () end,
        register = function (_, _, fn) events[#events + 1] = fn end,
    }
    package.loaded['core.store'] = nil
    local st = require('core.store')
    st.load()
    st.watch()
    table.insert(st.cfg.macros, { name = 'A\'s' })
    -- a switch to B, then to C, neither with macros in its file
    events[1](merged({}))
    local b = st.cfg
    table.insert(b.macros, { name = 'B\'s' })
    events[1](merged({}))
    eq(#st.cfg.macros, 0, 'C starts with none of B\'s')
    assert(not rawequal(st.cfg.macros, b.macros), 'C\'s own table')
    package.loaded['settings'], package.loaded['core.store'] = nil, nil
end)
