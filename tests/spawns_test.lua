-- core/spawns.lua: the Zone Browser's lists, from data/spawns.lua (and from a small fake source).
local build = require('core.build')
local spawns = require('core.spawns')

local real = spawns.source

local FAKE = {
    zones = { [230] = 'm|Crab|1|3|0|300|0|1|1|10-12\nm|Leaping Lizzy|10|11|2|0|32|1|1|20\nn|Door|0|30,32\nn|Moogle|2|40' },
    families = { [1] = 'Crab' },
}
local function fake()
    spawns.source = function () return FAKE end
    spawns.reset()
end
local function restore()
    spawns.source = real
    spawns.reset()
end

test('ids and zones: 0x1000000 + zone * 4096 + index', function ()
    eq(spawns.id(107, 0), 0x1000000 + 107 * 4096)
    eq(spawns.zone_of(spawns.id(230, 4095)), 230)
    eq(spawns.zone_of(17215868), 107)
end)

test('a zone parses into mob groups and NPC names, ranges expanded', function ()
    fake()
    local z = spawns.zone(230)
    eq(#z, 4)
    eq(z[1].kind, 'mob')
    eq(z[1].ids, { spawns.id(230, 10), spawns.id(230, 11), spawns.id(230, 12) })
    eq({ z[1].lo, z[1].hi, z[1].respawn, z[1].nm }, { 1, 3, 300, false })
    eq(z[2].nm, true, 'mob type 2 is an NM')
    eq(z[3].ids, { spawns.id(230, 30), spawns.id(230, 32) })
    eq({ z[4].kind, z[4].status }, { 'npc', 2 })
    eq(spawns.zone(999), {}, 'a zone with none')
    eq(spawns.zone(nil), {})
    restore()
end)

test('find: the entry of a server id', function ()
    fake()
    eq(spawns.find(spawns.id(230, 11)).name, 'Crab')
    eq(spawns.find(spawns.id(230, 32)).name, 'Door')
    eq(spawns.find(spawns.id(230, 31)), nil, 'between ranges')
    eq(spawns.find(1001), nil, 'a player')
    eq(spawns.find(nil), nil)
    restore()
end)

test('filter: by kind, by words, by server id or index', function ()
    fake()
    local z = spawns.zone(230)
    eq(#spawns.filter(z, 'all', ''), 4)
    eq(#spawns.filter(z, 'mob', ''), 2)
    eq(spawns.filter(z, 'nm', '')[1].name, 'Leaping Lizzy')
    eq(#spawns.filter(z, 'npc', ''), 2)
    eq(spawns.filter(z, 'all', 'leap liz')[1].name, 'Leaping Lizzy', 'every word, any case')
    eq(#spawns.filter(z, 'all', 'liz crab'), 0)
    eq(spawns.filter(z, 'all', tostring(spawns.id(230, 12)))[1].name, 'Crab', 'a server id')
    eq(spawns.filter(z, 'all', '32')[1].name, 'Door', 'an index')
    eq(#spawns.filter(z, 'npc', '11'), 0, 'an index of another kind')
    restore()
end)

test('counts are by id', function ()
    fake()
    eq(spawns.counts(spawns.zone(230)), { mob = 4, nm = 1, npc = 3 })
    restore()
end)

test('tags, levels, durations and the description', function ()
    fake()
    local z = spawns.zone(230)
    eq(spawns.tags(z[2]), { 'NM', 'Lottery' })
    eq(spawns.tags(z[4]), { 'hidden' })
    eq(spawns.tags(z[1]), {})
    eq(spawns.levels(z[1]), 'Lv 1-3')
    eq(spawns.levels({ kind = 'mob', lo = 75, hi = 75 }), 'Lv 75')
    eq(spawns.levels({ kind = 'mob', lo = 0, hi = 0 }), '')
    eq(spawns.levels(z[3]), '')
    eq(spawns.duration(0), '')
    eq(spawns.duration(45), '45s')
    eq(spawns.duration(5400), '1h 30m')
    eq(spawns.duration(90000), '1d 1h')
    local d = spawns.describe(z[1], { [1] = 'WAR' })
    eq(d[1], 'Crab')
    eq(d[2], 'Lv 1-3, WAR, Crab family')
    eq(d[3], 'respawns in 5m')
    assert(d[4]:find('^Ids '), d[4])
    restore()
end)

test('buttons: lines the server reads; Bring only in your zone', function ()
    fake()
    local z = spawns.zone(230)
    local id = z[1].ids[1]
    local here, away = {}, {}
    for _, b in ipairs(spawns.buttons(z[1], id, true)) do here[b[1]] = b end
    for _, b in ipairs(spawns.buttons(z[1], id, false)) do away[b[1]] = b end
    eq(here.Spawn[2], '!spawnmob ' .. id)
    eq(here.Bring[2], '!mobhere ' .. id)
    eq(here.Despawn[4], true, 'despawn asks twice')
    eq(away.Bring, nil, 'no bring from another zone')
    assert(away['Go to'][3]:find('zones you'), 'going zones you')
    local npc = {}
    for _, b in ipairs(spawns.buttons(z[3], z[3].ids[1], true)) do npc[b[1]] = b end
    eq(npc.Bring[2], '!npchere ' .. z[3].ids[1])
    eq(npc.Spawn, nil, 'no spawning an NPC')
    for _, e in ipairs(z) do
        for _, b in ipairs(spawns.buttons(e, e.ids[1], true)) do
            assert(build.check(b[2]), b[2])
            assert(not build.reads_cursor(b[2]), 'by id, never the cursor: ' .. b[2])
        end
    end
    restore()
end)

-- The real data/spawns.lua: generated from the server's sql.
test('data/spawns.lua: every zone a known zone, every line one the parser reads', function ()
    restore()
    local src = spawns.source()
    local zones = {}
    for _, z in ipairs(require('data.zones')) do zones[z[1]] = true end
    local n = 0
    for z, s in pairs(src.zones) do
        assert(zones[z], 'zone ' .. z .. ' is not in data/zones.lua')
        local lines = 0
        for _ in s:gmatch('[^\n]+') do lines = lines + 1 end
        eq(#spawns.zone(z), lines, 'zone ' .. z .. ': every line parsed')
        n = n + 1
    end
    assert(n > 200, 'zones: ' .. n)
end)

test('data/spawns.lua: a known NM, with its levels and family', function ()
    restore()
    local lizzy = spawns.filter(spawns.zone(107), 'nm', 'leaping lizzy')[1]
    assert(lizzy, 'Leaping Lizzy in South Gustaberg')
    eq(lizzy.nm, true)
    eq(spawns.levels(lizzy), 'Lv 10-11')
    eq(spawns.find(lizzy.ids[1]), lizzy)
    assert(spawns.describe(lizzy)[2]:find('Lizard family'), 'its family')
end)

test('an id both a mob and an NPC: find by kind, the mob by default', function ()
    spawns.source = function ()
        return { zones = { [230] = 'm|Cursed Chest|1|1|0|0|0|0|1|40\nn|Cursed Chest|0|40' }, families = {} }
    end
    spawns.reset()
    local id = spawns.id(230, 40)
    eq(spawns.find(id, 'npc').kind, 'npc')
    eq(spawns.find(id, 'mob').kind, 'mob')
    eq(spawns.find(id).kind, 'mob')
    eq(spawns.find(id, 'other').kind, 'mob', 'a pet\'s kind: either')
    restore()
end)

test('filter: only plain digits are an id (not 0x10, 1e1)', function ()
    fake()
    local z = spawns.zone(230)
    eq(#spawns.filter(z, 'all', '0x10'), 0)
    eq(#spawns.filter(z, 'all', '1e1'), 0)
    eq(spawns.filter(z, 'all', '10')[1].name, 'Crab')
    restore()
end)

test('a battlefield\'s, event\'s or called mob asks twice to spawn', function ()
    for _, t in ipairs({ 0x08, 0x10, 0x20 }) do
        local e = { kind = 'mob', name = 'x', type = t, ids = { 1 } }
        eq(spawns.buttons(e, 1, true)[1][4], true, 'type ' .. t)
    end
    eq(spawns.buttons({ kind = 'mob', name = 'x', type = 2, ids = { 1 } }, 1, true)[1][4], false, 'an NM: at once')
end)

test('no scripted tag: most mobs are', function ()
    eq(spawns.tags({ kind = 'mob', type = 2, spawn = 0x80 }), { 'NM' })
    assert(spawns.describe({ kind = 'mob', name = 'x', type = 2, spawn = 0x80, respawn = 0, lo = 0, hi = 0, ids = { 1 } })[2]
        :find('by script'), 'the description says it')
end)
