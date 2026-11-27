-- core/macros.lua: placeholders, macros, places.
local macros = require('core.macros')

local PC = { name = 'Kupipi', kind = 'pc', sid = 1001, index = 1100 }
local MOB = { name = 'Crab', kind = 'mob', sid = 17000001, index = 120 }
local function ctx(mode, target, o)
    local c = { me = 'Seekey', target = target, mode = mode, name = 'Ajido', pos = { x = 1.25, y = -3, z = 100.5 }, zone = 230 }
    for k, v in pairs(o or {}) do c[k] = v end
    return c
end

test('placeholders', function ()
    eq(macros.expand('!hp 99999 {who}', ctx('target', PC)), '!hp 99999 Kupipi', '{who}: the target')
    eq(macros.expand('!hp 99999 {who}', ctx('me', PC)), '!hp 99999 Seekey', '{who}: me')
    eq(macros.expand('!hp 99999 {who}', ctx('name', PC)), '!hp 99999 Ajido', '{who}: the typed name')
    eq(macros.expand('!gotoid {tid}', ctx('me', MOB)), '!gotoid 17000001', '{tid}')
    eq(macros.expand('!pos {x} {y} {z} {zone} {me}', ctx('me')), '!pos 1.25 -3 100.5 230 Seekey', 'where you stand')
    eq(macros.expand('hp 1   {ME}', ctx('me')), '!hp 1 Seekey', 'any case, tidied')
end)

test('a placeholder that can\'t be filled says why', function ()
    local l, why = macros.expand('!hp 1 {who}', ctx('target', MOB))
    eq(l, nil)
    assert(why:find('target a player'), why)
    local _, why2 = macros.expand('!x {nope}', ctx('me'))
    assert(why2:find('no {nope}'), why2)
    local _, why3 = macros.expand('!pos {x} {y} {z}', ctx('me', nil, { pos = {} }))
    assert(why3:find('position'), why3)
end)

test('a macro is all its lines, or none', function ()
    local lines = macros.lines({ lines = { '!hp 99999 {who}', '', '!mp 99999 {who}' } }, ctx('target', PC))
    eq(lines, { '!hp 99999 Kupipi', '!mp 99999 Kupipi' }, 'blank lines skipped')
    local none, why, at = macros.lines({ lines = { '!where', '!hp 1 {target}' } }, ctx('me', MOB))
    eq(none, nil)
    eq(at, 2, 'the line it failed on')
    assert(why:find('line 2'), why)
    eq(macros.lines({ lines = {} }, ctx('me')), nil, 'no lines')
end)

test('finding and naming', function ()
    local list = { { name = 'Restore' }, { name = 'Restore 2' } }
    local m, i = macros.find(list, ' restore ')
    eq(i, 1)
    eq(m.name, 'Restore')
    eq(macros.fresh_name(list, 'Restore'), 'Restore 3')
    eq(macros.fresh_name(list, 'New'), 'New')
end)

test('every example expands with a player target', function ()
    for _, m in ipairs(macros.EXAMPLES) do
        local lines, why = macros.lines(m, ctx('target', PC))
        assert(lines, m.name .. ': ' .. tostring(why))
    end
end)

test('places', function ()
    local p = macros.here(' Ru\'Lude ', ctx('me'))
    eq(p, { name = 'Ru\'Lude', x = 1.25, y = -3, z = 100.5, zone = 230 })
    eq(macros.place_line(p), '!pos 1.25 -3 100.5 230', 'you')
    eq(macros.place_line(p, 'Kupipi'), '!pos 1.25 -3 100.5 230 Kupipi', 'a player')
    eq(macros.coord(-0.0001), '0', 'no -0')
    eq(macros.coord(12), '12')
    eq(macros.coord(-7.12345), '-7.123')
    local none, why = macros.here('x', ctx('me', nil, { zone = false }))
    eq(none, nil)
    assert(why:find('zone'), why)
end)

test('a risky command never takes its name from a placeholder; a macro with one is risky', function ()
    local none, why = macros.lines({ lines = { '!jail {who}' } }, ctx('target', PC))
    eq(none, nil)
    assert(why:find('risky'), why)
    local _, why2 = macros.lines({ lines = { '!promote {target} 5' } }, ctx('target', PC))
    assert(why2:find('risky'), why2)
    local lines, risky = macros.lines({ lines = { '!where', '!jail Trion' } }, ctx('me'))
    eq(lines, { '!where', '!jail Trion' }, 'spelled out')
    eq(risky, true, 'so Run asks twice')
    local _, safe = macros.lines({ lines = { '!where' } }, ctx('me'))
    eq(safe, false)
end)

test('{who} under Acting on: None names no one', function ()
    local l, why = macros.expand('!hp 1 {who}', ctx('none', PC))
    eq(l, nil)
    assert(why:find('None'), why)
end)

test('a place in the zone the one moved is in leaves the zone out', function ()
    local p = { name = 'Home', x = 1, y = 2, z = 3, zone = 230 }
    eq(macros.place_line(p, nil, 230), '!pos 1 2 3', 'already there: no zoning in')
    eq(macros.place_line(p, nil, 231), '!pos 1 2 3 230')
    eq(macros.place_line(p, 'Kupipi', nil), '!pos 1 2 3 230 Kupipi', 'their zone unknown: with it')
    eq(macros.place_line(p, 'Kupipi', 230), '!pos 1 2 3 Kupipi')
end)

test('party: {who} lines for each member, the rest once, you left out of a bring', function ()
    local c = ctx('party', nil, { party = { 'Seekey', 'Ajido', 'Trion' } })
    local m = { name = 'Bring and restore', lines = { '!hide', '!bring {who}', '!hp 99999 {who}' } }
    local lines = macros.lines(m, c)
    eq(lines, { '!hide', '!hp 99999 Seekey', '!bring Ajido', '!hp 99999 Ajido', '!bring Trion', '!hp 99999 Trion' })
    eq(macros.lines({ name = 'x', lines = { '!hide', '!togglegm' } }, c), { '!hide', '!togglegm' }, 'no {who}: once')
end)

test('party: a risky line still never takes {who}; no party says so', function ()
    local c = ctx('party', nil, { party = { 'Seekey', 'Ajido' } })
    local l, why = macros.lines({ name = 'x', lines = { '!jail {who}' } }, c)
    eq(l, nil)
    assert(why:find('never takes its name'), why)
    local l2, why2 = macros.lines({ name = 'x', lines = { '!hp 1 {who}' } }, ctx('party', nil, { party = {} }))
    eq(l2, nil)
    assert(why2:find('no one'), why2)
    local _, why3 = macros.expand('!hp 1 {who}', c)
    assert(why3:find('Party'), 'expanding one line alone says to run it')
end)

test('party: lines before the first {who} go once first, after the last once last', function ()
    local c = ctx('party', nil, { party = { 'Seekey', 'Ajido', 'Trion' } })
    local lines, risky, fans = macros.lines({ name = 'x', lines = { '!hp 100 {who}', '!hide', '!bring {who}', '!godmode' } }, c)
    eq(lines, { '!hp 100 Seekey', '!hide', '!hp 100 Ajido', '!bring Ajido', '!hp 100 Trion', '!bring Trion', '!godmode' })
    eq({ risky, fans }, { false, true }, 'it fans out: its Run asks twice')
    local _, _, one = macros.lines({ name = 'x', lines = { '!bring {who}' } }, ctx('party', nil, { party = { 'Seekey', 'Ajido' } }))
    eq(one, false, 'to one member only (you left out of a bring): no fan')
    local l, why = macros.lines({ name = 'x', lines = { '!goto {who}' } }, c)
    eq(l, nil, 'goto goes to one player')
    assert(why:find('one player'), why)
    local _, _, f2 = macros.lines({ name = 'x', lines = { '!hp 1 {who}' } }, ctx('me'))
    eq(f2, false, 'not party: no fan')
end)
