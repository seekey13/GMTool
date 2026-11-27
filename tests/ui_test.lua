-- ui/window.lua against a fake ImGui (tests/fake_imgui.lua): every page, every card open, every popup's list,
-- in each acting-on mode and with each kind of target; then clicks reach `act` and the store.
local fake = require('tests.fake_imgui')
package.loaded['ui.kit'], package.loaded['ui.window'] = nil, nil
local catalog = require('core.catalog')
local data = require('core.data')
local kit = require('ui.kit')
local store = require('core.store')
local util = require('core.util')
local window = require('ui.window')

local tick = 0
kit.clock = function () tick = tick + 1; return tick end

data.res.item = function (id) return id < 50 and ('Item' .. id) or nil end
data.res.spell = function (id) return id < 20 and ('Spell' .. id) or nil end
data.res.zone = function (id) return id == 230 and 'Southern San d\'Oria' or nil end
data.index.items.last, data.index.spells.last = 100, 30

local calls
local function act()
    calls = { send = {}, toast = {}, close = 0, clear = 0, lines = {} }
    return {
        send = function (line, info) calls.send[#calls.send + 1] = { line = line, info = info } end,
        send_lines = function (lines, name) calls.lines[#calls.lines + 1] = { lines = lines, name = name } end,
        toast = function (text, kind) calls.toast[#calls.toast + 1] = { text = text, kind = kind } end,
        close = function () calls.close = calls.close + 1 end,
        clear_history = function () calls.clear = calls.clear + 1 end,
        clear_queue = function () calls.cleared = (calls.cleared or 0) + 1 end,
    }
end

local PC = { name = 'Kupipi', kind = 'pc', sid = 1001, index = 1100 }
local MOB = { name = 'Crab', kind = 'mob', sid = 17000001, index = 120 }

local function view(o)
    o = o or {}
    local v = { cfg = store.cfg, me = { name = 'Seekey', zone = 230, sid = 1, index = 1024, x = 1.5, y = -2, z = 30 },
                target = PC, ready = true,
                players = { { name = 'Ajido', dist = 4, party = true }, { name = 'Trion', dist = 12 } },
                zone_name = 'Southern San d\'Oria', now = 100, time = 1000, pending = 0,
                entities = { { index = 1100, name = 'Kupipi', kind = 'pc', sid = 1001, hpp = 100, dist = 3 },
                             { index = 120, name = 'Crab', kind = 'mob', sid = 17000001, hpp = 50, dist = 7 },
                             { index = 300, name = 'Door', kind = 'npc', sid = 17200001, hpp = 100, dist = 9 } } }
    for k, x in pairs(o) do v[k] = x end
    if o.target == false then v.target = nil end
    return v
end

-- One frame; returns the frame. Raises the window's error.
local function frame(clicks, o)
    local f = fake.frame(clicks)
    local ok, err = pcall(window.render, view(o), act())
    fake.check()
    assert(ok, err)
    return f
end

local function fresh()
    store.cfg = util.copy(store.DEFAULTS)
    store.cfg.ui.show_server = true
    window.state.page, window.state.open, window.state.more, window.state.bufs = nil, {}, {}, {}
end

local function open_all()
    for _, c in ipairs(catalog.list) do window.state.open[c.key] = true end
end

-- Every page, so every page's own code runs.
local PAGES = { 'favorites', 'target', 'players', 'nearby', 'zones', 'console', 'history', 'settings', 'macros', 'places' }
for _, p in ipairs(catalog.PAGES) do PAGES[#PAGES + 1] = p[1] end

test('every page draws, every card open, every list shown', function ()
    fresh()
    open_all()
    store.cfg.ui.adv = true
    for _, id in ipairs(PAGES) do
        window.state.page = id
        frame()
    end
end)

test('every page in each acting-on mode and with each target', function ()
    fresh()
    open_all()
    for _, mode in ipairs({ 'me', 'target', 'name', 'party', 'none' }) do
        store.cfg.acting.mode = mode
        for _, t in ipairs({ PC, MOB, false }) do
            for _, id in ipairs(PAGES) do
                window.state.page = id
                frame({}, { target = t, ready = t ~= MOB })
            end
        end
    end
end)

test('cards draw folded too, and with no one logged in', function ()
    fresh()
    for _, id in ipairs(PAGES) do
        window.state.page = id
        frame({}, { me = false, target = false, players = {} })
    end
end)

test('every form filled in draws its line', function ()
    fresh()
    open_all()
    for _, c in ipairs(catalog.list) do
        for i, a in ipairs(c.args) do
            local v = a.options and a.options[1][1] or (a[2] == 'player' and 'Kupipi') or (a[2] == 'word' and 'abc')
                or (a[2] == 'text' and 'some text') or '1'
            store.set_value(c.key, i, v)
        end
    end
    for _, id in ipairs(PAGES) do
        window.state.page = id
        frame()
    end
end)

test('a search lists matching commands', function ()
    fresh()
    window.state.search[1] = 'key item'
    window.state.page = 'search'
    frame()
    assert(fake.drew('!addkeyitem'), 'found')
    window.state.search[1] = ''
end)

test('Send builds the line and hands it to act', function ()
    fresh()
    window.state.page = 'vitals'
    store.set_value('hp', 1, '500')
    frame({ ['##gm_send_hp'] = true })
    eq(calls.send[1] and calls.send[1].line, '!hp 500 Kupipi', 'the target, named')
    -- a mob target: no name, and it reads the cursor
    frame({ ['##gm_send_hp'] = true }, { target = MOB })
    eq(calls.send[1].line, '!hp 500')
    eq(calls.send[1].info.cursor, true)
end)

test('a form that can\'t build opens to say why', function ()
    fresh()
    window.state.page = 'vitals'
    frame({ ['##gm_send_hp'] = true })
    eq(#calls.send, 0, 'nothing sent')
    eq(calls.toast[1].kind, 'error')
    eq(window.state.open.hp, true, 'opened')
end)

test('a preset sends at once with its values', function ()
    fresh()
    window.state.page = 'vitals'
    window.state.open.hp = true
    frame({ ['##gm_pre_hp_1'] = true })
    eq(calls.send[1].line, '!hp 99999 Kupipi', 'Full')
end)

test('a risky command asks twice', function ()
    fresh()
    window.state.page = 'mobs'
    frame({ ['##gm_send_provokeall'] = true })
    eq(#calls.send, 0, 'armed, not sent')
    frame({ ['##gm_send_provokeall'] = true })
    eq(calls.send[1].line, '!provokeall', 'sent on the second')
    store.cfg.send.confirm = false
    frame({ ['##gm_send_provokeall'] = true })
    eq(calls.send[1].line, '!provokeall', 'once, with confirming off')
end)

test('the star makes a favorite, and Favorites lists it', function ()
    fresh()
    window.state.page = 'travel'
    frame({ ['##gm_fav_zone'] = true })
    eq(store.cfg.favorites, { 'zone' })
    window.state.page = 'favorites'
    frame()
    assert(fake.drew('!zone'), 'listed')
end)

test('the starter set of favorites', function ()
    fresh()
    window.state.page = 'favorites'
    frame({ ['##gm_suggest'] = true })
    assert(#store.cfg.favorites >= 10, 'added')
    for _, k in ipairs(store.cfg.favorites) do assert(catalog.by_key[k], 'a real command: ' .. k) end
end)

test('acting on: a click changes the mode', function ()
    fresh()
    window.state.page = 'vitals'
    frame({ ['##gm_mode_me'] = true })
    eq(store.cfg.acting.mode, 'me')
    store.cfg.acting.mode = 'name'
    frame({ ['##gm_acting_name'] = 'Trion' })
    eq(store.cfg.acting.name, 'Trion', 'typed')
end)

test('typing in a box keeps the value; a pick sets it', function ()
    fresh()
    window.state.page = 'vitals'
    window.state.open.hp = true
    frame({ ['##gm_hp_1_v'] = '1234' })
    eq(store.form('hp')[1], '1234')
    window.state.page = 'travel'
    window.state.open.zone = true
    -- the zone list is open (every popup is): click a zone in it
    local f = frame()
    local label
    for _, s in ipairs(f.selectables) do if s:find('Southern San d\'Oria', 1, true) then label = s end end
    assert(label, 'the client\'s zone name listed')
    frame({ [label] = true })
    eq(store.form('zone')[1], '230')
end)

test('the player list offers you, the target, the party, nearby and recent names', function ()
    fresh()
    store.cfg.names = { 'Oldfriend' }
    window.state.page = 'vitals'
    window.state.open.raise = true
    local f = frame()
    local want = { Seekey = false, Kupipi = false, Ajido = false, Trion = false, Oldfriend = false }
    for _, s in ipairs(f.selectables) do
        for n in pairs(want) do if s:find(n, 1, true) then want[n] = true end end
    end
    for n, seen in pairs(want) do assert(seen, n .. ' listed') end
end)

test('the Target button fills a mob id', function ()
    fresh()
    window.state.page = 'mobs'
    window.state.open.despawnmob = true
    frame({ ['##gm_despawnmob_1_tgt'] = true }, { target = MOB })
    eq(store.form('despawnmob')[1], '17000001')
end)

test('the item finder reads the client\'s names a slice at a time', function ()
    fresh()
    data.reset()
    window.state.page = 'items'
    window.state.open.additem = true
    for _ = 1, 3 do frame({ ['##filter##gm_additem_1_find'] = 'item4' }) end
    assert(data.index.items.done, 'indexed')
    local f = frame({ ['##filter##gm_additem_1_find'] = 'item4' })
    local label
    for _, s in ipairs(f.selectables) do if s:find('Item4 (4)', 1, true) then label = s end end
    assert(label, 'found by name')
    frame({ ['##filter##gm_additem_1_find'] = 'item4', [label] = true })
    eq(store.form('additem')[1], '4')
end)

test('the console sends what is typed, tidied', function ()
    fresh()
    window.state.page = 'console'
    frame({ ['##gm_console'] = '  hp  5   Kupipi ' })
    eq(calls.send[1].line, '!hp 5 Kupipi')
    eq(calls.send[1].info.cursor, false, 'named: no cursor')
    frame({ ['##gm_console'] = 'getid' })
    eq(calls.send[1].info.cursor, true, 'getid reads the cursor')
    frame({ ['##gm_console'] = '!ad' })
    assert(fake.drew('!addeffect'), 'matches listed')
end)

test('history: send again, edit, clear', function ()
    fresh()
    store.remember('!where', 990)
    window.state.page = 'history'
    frame({ ['##gm_hist_send_1'] = true })
    eq(calls.send[1].line, '!where')
    frame({ ['##gm_hist_edit_1'] = true })
    eq(window.state.page, 'console', 'to the console')
    eq(window.state.console[1], '!where')
    window.state.page = 'history'
    frame({ ['##gm_hist_clear'] = true })
    frame({ ['##gm_hist_clear'] = true })
    eq(calls.clear, 1, 'cleared after asking twice')
end)

test('settings change the store', function ()
    fresh()
    window.state.page = 'settings'
    frame({ ['##gm_set_Send as2'] = true })
    eq(store.cfg.send.mode, 'typed')
    frame({ ['##gm_set_My GM level4'] = true })
    eq(store.cfg.gm_level, 3)
    frame({ ['##gm_set_Echo each line in chat'] = true })
    eq(store.cfg.send.echo, false)
end)

test('the server page hides unless shown', function ()
    fresh()
    store.cfg.ui.show_server = false
    window.state.page = 'server'
    frame()
    eq(window.state.page, 'favorites', 'sent back to Favorites')
end)

test('the close mark closes', function ()
    fresh()
    frame({ ['##gm_close'] = true })
    eq(calls.close, 1)
end)

test('a sidebar click shows a page', function ()
    fresh()
    frame({ ['##gm_page_items'] = true })
    eq(window.state.page, 'items')
    eq(store.cfg.ui.page, 'items', 'kept')
end)

test('macros: examples, run, edit, delete', function ()
    fresh()
    window.state.page = 'macros'
    frame()
    frame({ ['##gm_mac_examples'] = true })
    assert(#store.cfg.macros >= 5, 'examples added')
    frame({ ['##gm_mac_run_1'] = true })
    eq(calls.lines[1].lines, { '!hp 99999 Kupipi', '!mp 99999 Kupipi', '!tp 3000 Kupipi' }, 'Restore on the target')
    -- with a mob target {who} can't be made: nothing goes, it opens to say why
    frame({ ['##gm_mac_run_1'] = true }, { target = MOB })
    eq(#calls.lines, 0)
    eq(calls.toast[1].kind, 'error')
    -- its editor is open now: type a line, add one, drop one
    frame({ ['##gm_mac_1_l1'] = '!hp 1 {me}' })
    eq(store.cfg.macros[1].lines[1], '!hp 1 {me}')
    frame({ ['##gm_mac_1_add'] = true })
    eq(#store.cfg.macros[1].lines, 4)
    frame({ ['##gm_mac_1_drop4'] = true })
    frame({ ['##gm_mac_1_drop4'] = true })
    eq(#store.cfg.macros[1].lines, 3, 'dropped after asking twice')
    local n = #store.cfg.macros
    frame({ ['##gm_mac_del_2'] = true })
    frame({ ['##gm_mac_del_2'] = true })
    eq(#store.cfg.macros, n - 1, 'deleted')
    frame({ ['##gm_mac_new'] = true })
    eq(store.cfg.macros[#store.cfg.macros].name, 'Macro', 'a new one')
end)

test('macros: move up and down', function ()
    fresh()
    store.cfg.macros = { { name = 'A', lines = { '!where' } }, { name = 'B', lines = { '!time' } } }
    window.state.page = 'macros'
    frame({ ['##gm_mac_fold_2'] = true })
    frame({ ['##gm_mac_2_up'] = true })
    eq(store.cfg.macros[1].name, 'B')
end)

test('places: save here, go, send, delete', function ()
    fresh()
    window.state.page = 'places'
    frame({ ['##gm_place_name'] = 'Home' })
    frame({ ['##gm_place_save'] = true })
    local p = store.cfg.places[1]
    eq({ p.name, p.x, p.y, p.z, p.zone }, { 'Home', 1.5, -2, 30, 230 })
    local id = p.uid
    frame({ ['##gm_place_go_' .. id] = true })
    eq(calls.send[1].line, '!pos 1.5 -2 30', 'you are in its zone: no zone, so no zoning in')
    frame({ ['##gm_place_go_' .. id] = true }, { me = { name = 'Seekey', zone = 231, x = 1, y = 2, z = 3 } })
    eq(calls.send[1].line, '!pos 1.5 -2 30 230', 'from another zone: with it')
    frame({ ['##gm_place_send_' .. id] = true })
    eq(calls.send[1].line, '!pos 1.5 -2 30 230 Kupipi', 'a player whose zone isn\'t known: with it')
    frame({ ['##gm_place_send_' .. id] = true }, { players = { { name = 'Kupipi', dist = 3, zone = 230 } } })
    eq(calls.send[1].line, '!pos 1.5 -2 30 Kupipi', 'one in its zone: without')
    frame({ ['##gm_place_del_' .. id] = true })
    frame({ ['##gm_place_del_' .. id] = true })
    eq(#store.cfg.places, 0)
    -- no position yet: nothing to save
    frame({ ['##gm_place_save'] = true }, { me = { name = 'Seekey', zone = 230 } })
    eq(#store.cfg.places, 0)
end)

test('target page: actions for a player, a mob, an NPC', function ()
    fresh()
    window.state.page = 'target'
    frame({}, { target = false })
    assert(fake.drew('Target a player'), 'nothing targeted')
    frame({ ['##gm_tact_pc_1100_Restore'] = true })
    eq(calls.lines[1].lines, { '!hp 99999 Kupipi', '!mp 99999 Kupipi', '!tp 3000 Kupipi' })
    frame({ ['##gm_tact_mob_120_Despawn'] = true }, { target = MOB })
    eq(calls.lines[1].lines, { '!despawnmob 17000001' })
    frame({ ['##gm_tact_pc_1100_Kill'] = true })
    eq(#calls.lines, 0, 'Kill asks twice')
    frame({ ['##gm_tact_pc_1100_Kill'] = true })
    eq(calls.lines[1].lines, { '!hp 0 Kupipi' })
    -- armed on one player, then another targeted: nothing carries over
    frame({ ['##gm_tact_pc_1100_Kill'] = true })
    local AJIDO = { name = 'Ajido', kind = 'pc', sid = 1002, index = 1101 }
    frame({ ['##gm_tact_pc_1101_Kill'] = true }, { target = AJIDO })
    eq(#calls.lines, 0, 'Ajido\'s Kill asks again')
    frame({}, { target = { name = 'Door', kind = 'npc', sid = 17200001, index = 300 } })
    frame({}, { target = { name = 'Carbuncle', kind = 'other', sid = 0x700, index = 0x700 } })
end)

test('history shows what the server said back', function ()
    fresh()
    local replies = require('core.replies')
    replies.reset()
    store.remember('!getid', 990)
    replies.sent(store.cfg.history[1], 0)
    for i = 1, 6 do replies.text('Answer line ' .. i, 0.1) end
    window.state.page = 'history'
    frame({ over = true })
    assert(fake.drew('Answer line 1'), 'the first')
    assert(fake.drew('(+2 more)'), 'the rest counted')
end)

test('nearby: every entity with its actions, filtered', function ()
    fresh()
    window.state.page = 'nearby'
    frame()
    assert(fake.drew('Crab') and fake.drew('Door') and fake.drew('Kupipi'), 'all three')
    frame({ ['##gm_near_120_17000001_Despawn'] = true })
    eq(#calls.send, 0, 'Despawn asks twice')
    frame({ ['##gm_near_120_17000001_Despawn'] = true })
    eq(calls.send[1].line, '!despawnmob 17000001')
    frame({ ['##gm_near_120_17000001_Go to'] = true })
    eq(calls.send[1].line, '!gotoid 17000001', 'Go to at once')
    frame({ ['##gm_near_1100_1001_Bring'] = true })
    frame({ ['##gm_near_1100_1001_Bring'] = true })
    eq(calls.send[1].line, '!bring Kupipi')
    frame({ ['##gm_near_kind_mob'] = true })
    frame()
    assert(fake.drew('Crab') and not fake.drew('Door'), 'mobs only')
    window.state.near = nil
end)

test('a folded card with boxes filled shows the line it sends', function ()
    fresh()
    window.state.page = 'vitals'
    store.set_value('hp', 1, '0')
    store.set_value('hp', 2, 'Ajido')
    frame()
    assert(fake.drew('!hp 0 Ajido'), 'the line, not the description')
    store.set_value('hp', 1, 'x')
    frame()
    assert(fake.drew('whole number'), 'or why it can\'t go')
end)

test('an optional choice clears when its chosen segment is clicked again', function ()
    fresh()
    window.state.page = 'mobs'
    window.state.open.mobhere = true
    frame({ ['##gm_mobhere_2_s1'] = true })
    eq(store.form('mobhere')[2], '1', 'chosen')
    frame({ ['##gm_mobhere_2_s1'] = true })
    eq(store.form('mobhere')[2], nil, 'cleared')
end)

test('a risky history line asks twice', function ()
    fresh()
    store.remember('!jail Trion', 990)
    window.state.page = 'history'
    frame({ ['##gm_hist_send_1'] = true })
    eq(#calls.send, 0, 'armed')
    frame({ ['##gm_hist_send_1'] = true })
    eq(calls.send[1].line, '!jail Trion')
end)

test('the queue shows and clears', function ()
    fresh()
    window.state.page = 'vitals'
    local f = frame({ ['##gm_queue_clear'] = true }, { pending = 2, queued = { { line = '!hp 0', cursor = true }, { line = '!where' } } })
    eq(calls.cleared, 1)
    local _ = f
    assert(fake.drew('2 queued'))
end)

test('a mob\'s name fills with underscores, as the server spells it', function ()
    fresh()
    window.state.page = 'travel'
    window.state.open.gotoname = true
    frame({ ['##gm_gotoname_1_tgt'] = true }, { target = { name = 'Tunnel Worm', kind = 'mob', sid = 17000002, index = 121 } })
    eq(store.form('gotoname')[1], 'Tunnel_Worm')
end)

test('the GM Bar: favorites as buttons, up with the window closed', function ()
    fresh()
    store.cfg.ui.open, store.cfg.ui.bar = false, true
    frame()
    assert(fake.drew('Star commands'), 'empty, it says how to fill it')
    store.toggle_favorite('where')
    store.toggle_favorite('hp')
    frame({ ['##gmbar_where'] = true })
    eq(calls.send[1].line, '!where', 'sent')
    -- hp has no HP yet: a click opens its form in the main window
    frame({ ['##gmbar_hp'] = true })
    eq(#calls.send, 0)
    eq(store.cfg.ui.open, true, 'the window opened')
    eq(window.state.page, 'favorites')
    eq(window.state.open.hp, true, 'on its card')
    frame({ ['##gmbar_open'] = true })
    eq(store.cfg.ui.open, false, 'GM closes it again')
end)

test('Enter in a box sends its card; a risky one still wants its button', function ()
    fresh()
    window.state.page = 'vitals'
    window.state.open.hp = true
    frame({ ['##gm_hp_1_v'] = '77' })
    eq(calls.send[1] and calls.send[1].line, '!hp 77 Kupipi', 'typed and Enter')
    window.state.page = 'moderation'
    window.state.open.jail = true
    frame({ ['##gm_jail_1_v'] = 'Trion' })
    eq(#calls.send, 0, 'jail is not sent by Enter')
end)

test('a reply can be copied, and a position saved as a place', function ()
    fresh()
    local replies = require('core.replies')
    replies.reset()
    store.remember('!pos Kupipi', 990)
    replies.sent(store.cfg.history[1], 0)
    replies.text("Kupipi's position: X 1.2340  Y -3.0000  Z 100.5000  Rot 12  (Zone: 230)", 0.1)
    window.state.page = 'history'
    frame({ ['##gm_hist_place_1_1'] = true })
    eq(#store.cfg.places, 1)
    eq(store.cfg.places[1].zone, 230)
    assert(store.cfg.places[1].name:find('Kupipi'), store.cfg.places[1].name)
    frame({ ['##gm_hist_copy_1_1'] = true })
    assert(calls.toast[1].text:find('Copied'), 'copied')
end)

test('zone browser: rows from the database, spawn, bring twice, a group opens to its ids', function ()
    local spawns = require('core.spawns')
    local real = spawns.source
    local base = spawns.id(230, 0)
    spawns.source = function ()
        return { zones = { [230] = 'm|Crab|1|3|0|300|0|1|1|10-12\nm|Leaping Lizzy|10|11|2|0|32|1|1|20\nn|Door|0|30\nm|Cursed Chest|1|1|0|0|0|1|1|40\nn|Cursed Chest|0|40',
                           [107] = 'm|Bubbly Bernie|9|10|2|0|128|1|1|5' }, families = { [1] = 'Crab' } }
    end
    spawns.reset()
    fresh()
    window.state.page, window.state.zb = 'zones', nil
    local lizzy, crab = base + 20, base + 10
    local f = frame(nil, { entities = { { index = 20, name = 'Leaping Lizzy', kind = 'mob', sid = lizzy, hpp = 100, dist = 5 } } })
    assert(fake.drew('Leaping Lizzy') and fake.drew('Crab') and fake.drew('Door'), 'every row')
    assert(f, 'drew')
    frame({ ['##gm_zb_230:2_' .. lizzy .. '_Spawn'] = true })
    eq(calls.send[1].line, '!spawnmob ' .. lizzy, 'spawn at once')
    eq(calls.send[1].info.cursor, false, 'by id, not the cursor')
    frame({ ['##gm_zb_230:2_' .. lizzy .. '_Bring'] = true })
    eq(#calls.send, 0, 'bring asks twice')
    frame({ ['##gm_zb_230:2_' .. lizzy .. '_Bring'] = true })
    eq(calls.send[1].line, '!mobhere ' .. lizzy)
    -- a group of three opens to a row per id
    frame()
    assert(not fake.drew(tostring(crab) .. '  \194\183  index 10'), 'folded')
    frame({ ['##gm_zb_row_230:1'] = true })
    frame()
    assert(fake.drew(tostring(crab) .. '  \194\183  index 10'), 'its ids listed')
    frame({ ['##gm_zb_230:1_' .. (crab + 1) .. '_Spawn'] = true })
    eq(calls.send[1].line, '!spawnmob ' .. (crab + 1))
    -- NMs only
    frame({ ['##gm_zb_kind_nm'] = true })
    frame()
    assert(fake.drew('Leaping Lizzy') and not fake.drew('Door'), 'NMs only')
    -- another zone: no Bring, and Mine goes back
    window.state.zb.zone, window.state.zb.kind = 107, 1
    frame()
    assert(fake.drew('Bubbly Bernie'), 'the other zone')
    frame({ ['##gm_zb_107:1_' .. spawns.id(107, 5) .. '_Bring'] = true })
    eq(#calls.send, 0, 'no bring in another zone')
    frame({ ['##gm_zb_mine'] = true })
    eq(window.state.zb.zone, nil, 'back to yours')
    spawns.source = real
    spawns.reset()
    window.state.zb = nil
end)

test('target page: what the database says of a targeted mob', function ()
    local spawns = require('core.spawns')
    local real = spawns.source
    local sid = spawns.id(230, 20)
    spawns.source = function ()
        return { zones = { [230] = 'm|Leaping Lizzy|10|11|2|0|32|1|1|20' }, families = { [1] = 'Lizard' } }
    end
    spawns.reset()
    fresh()
    window.state.page = 'target'
    frame(nil, { target = { name = 'Leaping Lizzy', kind = 'mob', sid = sid, index = 20 } })
    assert(fake.drew('NM, Lottery  \194\183  Lv 10-11'), 'its tags and levels')
    spawns.source = real
    spawns.reset()
end)

test('acting on: Party sends a card\'s line for each member, all at once', function ()
    fresh()
    window.state.page = 'vitals'
    frame({ ['##gm_mode_party'] = true })
    eq(store.cfg.acting.mode, 'party')
    store.set_value('hp', 1, '99999')
    frame()
    assert(fake.drew('2: Seekey, Ajido'), 'the strip names whom')
    frame({ ['##gm_send_hp'] = true })
    eq(#calls.send + #calls.lines, 0, 'a line apiece asks twice')
    frame({ ['##gm_send_hp'] = true })
    eq(#calls.send, 0, 'not one by one')
    eq(calls.lines[1].lines, { '!hp 99999 Seekey', '!hp 99999 Ajido' })
    -- a preset to the party asks again too; Enter won't fan out
    window.state.open.hp = true
    frame({ ['##gm_pre_hp_2'] = true })
    eq(#calls.lines, 0, 'Kill to the party: not at once')
    eq(calls.toast[1].kind, 'warn')
    frame({ ['##gm_pre_hp_2'] = true })
    eq(calls.lines[1].lines, { '!hp 0 Seekey', '!hp 0 Ajido' })
    window.state.enter = 'hp'
    frame()
    eq(#calls.lines + #calls.send, 0, 'Enter: press Send')
    -- a risky one still wants a name
    store.set_value('jail', 1, '')
    frame({ ['##gm_send_jail'] = true })
    frame({ ['##gm_send_jail'] = true })
    eq(#calls.lines + #calls.send, 0, 'jail never fans out')
    -- alone
    frame(nil, { players = {} })
    assert(fake.drew('you alone'), 'says so')
    store.cfg.acting.mode = 'target'
end)

test('players: any player by name, the cursor\'s actions only while targeted', function ()
    fresh()
    window.state.page, window.state.pl = 'players', nil
    frame(nil, { target = false })
    assert(fake.drew('Type or pick a player'), 'asks for a name')
    assert(fake.drew('Ajido') and fake.drew('Trion'), 'the names it knows')
    frame({ ['##gm_pl_pick_trion'] = true }, { target = false })
    eq(window.state.pl.name[1], 'Trion', 'a click picks')
    frame(nil, { target = false })
    assert(fake.drew('12.0 yalms away'), 'where they are')
    frame({ ['##gm_pact_trion_Bring'] = true }, { target = false })
    eq(calls.lines[1].lines, { '!bring Trion' })
    eq(store.cfg.names[1], 'Trion', 'a recent name now')
    frame({ ['##gm_pact_trion_Kick'] = true }, { target = false })
    eq(#calls.lines, 0, 'kick asks twice')
    frame({ ['##gm_pact_trion_Server id'] = true }, { target = false })
    eq(#calls.lines, 0, 'no cursor action for one not targeted')
    -- targeted: the cursor's actions too
    window.state.pl.name[1] = 'Kupipi'
    frame({ ['##gm_pact_kupipi_Server id'] = true })
    eq(calls.lines[1].lines, { '!getid' })
    -- not a name
    window.state.pl.name[1] = 'Ku pipi'
    frame()
    assert(fake.drew('is not a character name'), 'says so')
    -- someone GM Tool can't see
    window.state.pl.name[1] = 'Zeid'
    frame()
    assert(fake.drew('the server finds them by name'), 'by name anyway')
    window.state.pl = nil
end)

test('nearby: a player\'s name opens them on the Players page', function ()
    fresh()
    window.state.page, window.state.near, window.state.pl = 'nearby', nil, nil
    frame()
    frame({ ['##gm_near_1100_who'] = true })
    eq(window.state.page, 'players')
    eq(window.state.pl.name[1], 'Kupipi')
    window.state.pl, window.state.near = nil, nil
end)

test('status effects: the last listing as rows, Remove and Remove all', function ()
    fresh()
    local replies = require('core.replies')
    replies.reset()
    window.state.page, window.state.pl = 'players', { name = { 'Trion' } }
    frame(nil, { target = false })
    assert(fake.drew('Not listed yet this session'), 'not asked yet')
    frame({ ['##gm_fx_list_Trion'] = true }, { target = false })
    eq(calls.send[1].line, '!geteffects Trion')
    -- the server's answer, kept with the line sent
    store.remember('!geteffects Trion', 995)
    replies.sent(store.cfg.history[1], 0)
    replies.text('[1] PROTECT (40) - Power: 50 | Time: 29m 50s | [Dispelable]', 0.1)
    replies.text('[2] FOOD (251) - Power: 1 | [Food]', 0.2)
    frame(nil, { target = false })
    assert(fake.drew('Protect') and fake.drew('Food'), 'each effect')
    assert(fake.drew('2 effects, listed 5s ago.'), 'how many, and when')
    frame({ ['##gm_fx_del_Trion_1_40'] = true }, { target = false })
    eq(calls.lines[1].lines, { '!deleffect Trion 40', '!geteffects Trion' }, 'remove, then list again')
    frame({ ['##gm_fx_all_Trion'] = true }, { target = false })
    eq(#calls.lines, 0, 'remove all asks twice')
    frame({ ['##gm_fx_all_Trion'] = true }, { target = false })
    eq(calls.lines[1].lines, { '!deleffect Trion 40', '!deleffect Trion 251', '!geteffects Trion' })
    -- none
    store.remember('!geteffects Trion', 999)
    replies.sent(store.cfg.history[1], 10)
    replies.text('Trion has no active effects.', 10.1)
    frame(nil, { target = false })
    assert(fake.drew('No effects.'), 'says so')
    -- a mob on the Target page: listed, no Remove
    window.state.page = 'target'
    store.remember('!geteffects 17000001', 1000)
    replies.sent(store.cfg.history[1], 20)
    replies.text('[1] SLOW (13) - Power: 3000', 20.1)
    frame(nil, { target = MOB })
    assert(fake.drew('Slow'), 'the mob\'s effect')
    frame({ ['##gm_fx_del_17000001_1_13'] = true }, { target = MOB })
    eq(#calls.lines, 0, 'no Remove for a mob')
    replies.reset()
    window.state.pl = nil
end)

test('players: a button armed for one player never sends for the next', function ()
    fresh()
    window.state.page, window.state.pl = 'players', { name = { 'Trion' } }
    frame({ ['##gm_pact_trion_Kick'] = true }, { target = false })
    eq(#calls.lines, 0, 'armed for Trion')
    window.state.pl.name[1] = 'Ajido'
    frame({ ['##gm_pact_ajido_Kick'] = true }, { target = false })
    eq(#calls.lines, 0, 'Ajido\'s asks again')
    frame({ ['##gm_pact_ajido_Kick'] = true }, { target = false })
    eq(calls.lines[1].lines, { '!logoff Ajido' })
    -- typed in another case: as the game spells it
    window.state.pl.name[1] = 'trion'
    frame({ ['##gm_pact_trion_Bring'] = true }, { target = false })
    eq(calls.lines[1].lines, { '!bring Trion' })
    eq(store.cfg.names[1], 'Trion', 'recent, as spelt')
    -- Reset recasts clears YOUR effects: it asks twice
    frame({ ['##gm_pact_trion_Reset recasts'] = true }, { target = false })
    eq(#calls.lines, 0, 'reset asks twice')
    window.state.pl = nil
end)
