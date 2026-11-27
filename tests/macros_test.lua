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

-- Sharing ------------------------------------------------------------------------------------------------------

test('export and import: macros and places as text, round trip', function ()
    local ms = { { name = 'Restore', lines = { '!hp 99999 {who}', '', '!mp 99999 {who}' } }, { name = 'Hide', lines = { '!hide' } } }
    local ps = { { name = 'Jeuno AH', x = -12.5, y = 0, z = 33.25, zone = 246 } }
    local text = macros.export(ms, ps)
    assert(text:find('[Restore]\n!hp 99999 {who}\n!mp 99999 {who}', 1, true), text)
    assert(text:find('@ Jeuno AH: -12.5 0 33.25 246', 1, true), text)
    local ms2, ps2, bad = macros.import(text)
    eq(bad, {})
    eq(ms2, { { name = 'Restore', lines = { '!hp 99999 {who}', '!mp 99999 {who}' } }, { name = 'Hide', lines = { '!hide' } } })
    eq(ps2, ps)
end)

test('import: tidies lines, says which it left out', function ()
    local ms, ps, bad = macros.import('stray line\r\n[ Fix ]\nhp  1   {me}\n!x \195\169\n[]\n@ nowhere\n# a note\n\n[Empty]\n')
    eq(ms, { { name = 'Fix', lines = { '!hp 1 {me}' } } }, 'tidied; an empty macro left out')
    eq(ps, {})
    local lines = {}
    for _, b in ipairs(bad) do lines[#lines + 1] = b[1] end
    eq(lines, { 1, 4, 5, 6, 9 }, 'before any macro, not ASCII, no name, not a place, no lines')
end)

test('merge: the same skipped, a taken name renamed', function ()
    local list = { { name = 'Restore', lines = { '!hp 1 {who}' } } }
    local added, skipped = macros.merge(list, { { name = 'Restore', lines = { '!hp 1 {who}' } },
        { name = 'restore', lines = { '!hp 2 {who}' } }, { name = 'New', lines = { '!hide' } } }, macros.same_macro)
    eq({ added, skipped }, { 2, 1 })
    eq(list[2].name, 'restore 2')
    eq(list[3].name, 'New')
    local places = { { name = 'Home', x = 1, y = 2, z = 3, zone = 230 } }
    eq({ macros.merge(places, { { name = 'Home', x = 1.0004, y = 2, z = 3, zone = 230 } }, macros.same_place) }, { 0, 1 })
end)

test('import: a place in plain numbers within the map, a name in plain ASCII, at most so many', function ()
    local _, ps, bad = macros.import('@ a:b: -0.5 2 3 230\n@ x: 1e999 0 0 230\n@ y: 0x10 0 0 230\n@ z: 1 2 3 99999\n'
        .. '@ caf\195\169: 1 2 3 230\n[A\0B]\n!hide')
    eq(#ps, 1, 'only the first')
    eq(ps[1].name, 'a:b', 'a colon in a name')
    eq(#bad, 6, 'inf, hex, no such zone, a non-ASCII name, a control character; and its line after it')
    local many = {}
    for i = 1, macros.IMPORT_MAX + 5 do many[#many + 1] = ('[M%d]\n!hide'):format(i) end
    local ms, _, bad2 = macros.import(table.concat(many, '\n'))
    eq(#ms, macros.IMPORT_MAX)
    assert(#bad2 >= 5, 'the rest said')
    eq(macros.import('[' .. ('x'):rep(41) .. ']\n!hide'), {}, 'a name too long')
end)

test('merge: pasting the same text twice adds it once', function ()
    local list = { { name = 'A', lines = { '!hp 2 {who}' } } }
    local function paste() return macros.merge(list, { { name = 'A', lines = { '!hp 1 {who}' } } }, macros.same_macro) end
    eq({ paste() }, { 1, 0 })
    eq(list[2].name, 'A 2')
    eq({ paste() }, { 0, 1 }, 'A 2 is it already')
    eq(#list, 2)
end)

test('export: a macro or place with no name keeps one', function ()
    local text = macros.export({ { name = '', lines = { '!hide' } } }, { { name = ' ', x = 1, y = 2, z = 3, zone = 230 } })
    local ms, ps, bad = macros.import(text)
    eq({ #ms, #ps, #bad }, { 1, 1, 0 })
end)
