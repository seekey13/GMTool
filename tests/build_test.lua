-- core/build.lua: forms made into lines.
local build = require('core.build')
local catalog = require('core.catalog')

local C = catalog.by_key
local PC = { name = 'Kupipi', kind = 'pc', sid = 1001, index = 1100 }
local MOB = { name = 'Crab', kind = 'mob', sid = 17000001, index = 120 }

local function ctx(mode, target, name) return { me = 'Seekey', target = target, mode = mode, name = name } end

test('a player box left empty takes the acting-on choice', function ()
    eq(build.line(C.hp, { '100' }, ctx('me')), '!hp 100 Seekey', 'me')
    eq(build.line(C.hp, { '100' }, ctx('target', PC)), '!hp 100 Kupipi', 'a player target, named')
    eq(build.line(C.hp, { '100' }, ctx('name', nil, 'Ajido')), '!hp 100 Ajido', 'the typed name')
    eq(build.line(C.hp, { '100' }, ctx('none', PC)), '!hp 100', 'none: the server picks')
end)

test('a name typed in the box wins', function ()
    eq(build.line(C.hp, { '100', 'Trion' }, ctx('target', PC)), '!hp 100 Trion', 'typed')
    eq(build.line(C.hp, { '100', '<t>' }, ctx('me', PC)), '!hp 100 Kupipi', '<t> is the target')
    eq(build.line(C.hp, { '100', '<me>' }, ctx('target', PC)), '!hp 100 Seekey', '<me> is you')
end)

local NPC = { name = 'Door', kind = 'npc', sid = 17200001, index = 300 }

test('a mob target: cursor commands go with no name, the rest name you', function ()
    local line, info = build.line(C.hp, { '0' }, ctx('target', MOB))
    eq(line, '!hp 0', 'the server takes the cursor')
    eq(info.cursor, true, 'so it waits for the server to have the target')
    eq(build.line(C.homepoint, {}, ctx('target', MOB)), '!homepoint Seekey', 'no player targeted: you, by name')
end)

test('an NPC target never goes as a cursor player: the server would act on you', function ()
    local line, why = build.line(C.hp, { '0' }, ctx('target', NPC))
    eq(line, nil)
    assert(why:find('NPC'), why)
end)

test('target mode with nothing targeted: you, by name', function ()
    eq(build.line(C.raise, {}, ctx('target', nil)), '!raise 3 Seekey')
    eq(build.line(C.hp, { '5' }, ctx('target', nil)), '!hp 5 Seekey', 'a cursor command too: named, so no cursor')
end)

test('a command that needs a name never takes yours from Acting on', function ()
    local line, why = build.line(C['goto'], {}, ctx('me'))
    eq(line, nil, 'goto in Me mode')
    assert(why:find('type a name'), why)
    eq(build.line(C['goto'], {}, ctx('target', PC)), '!goto Kupipi', 'a player target is fine')
    local l2 = build.line(C['goto'], {}, ctx('target', MOB))
    eq(l2, nil, 'a mob target isn\'t')
end)

test('a risky command takes a name only from its own box', function ()
    for _, mode in ipairs({ 'me', 'target', 'name', 'none' }) do
        local line, why = build.line(C.jail, {}, ctx(mode, PC, 'Ajido'))
        eq(line, nil, 'jail, ' .. mode)
        assert(why:find('risky'), why)
        eq(build.line(C.promote, { nil, '0' }, ctx(mode, PC, 'Ajido')), nil, 'promote, ' .. mode)
        eq(build.line(C.delallinventory, {}, ctx(mode, PC, 'Ajido')), nil, 'delallinventory, ' .. mode)
    end
    eq(build.line(C.jail, { 'Trion' }, ctx('me')), '!jail Trion', 'typed')
end)

test('a mob-only cursor command needs a mob target', function ()
    local line, why = build.line(C['hp:Mob HP'], { '0' }, ctx('me', nil))
    eq(line, nil, 'no target: it would be you')
    assert(why:find('target a mob'), why)
    eq(build.line(C['hp:Mob HP'], { '0' }, ctx('me', PC)), nil, 'a player target: it would be them')
    eq(build.line(C['hp:Mob HP'], { '0' }, ctx('me', MOB)), '!hp 0', 'a mob')
end)

test('a leading id left out reads the cursor, wherever it sits', function ()
    local _, info = build.line(C.animatenpc, { nil, '5' }, ctx('me'))
    eq(info.cursor, true, 'animatenpc')
    local _, info2 = build.line(C.mobsub, { nil, '5' }, ctx('me'))
    eq(info2.cursor, true, 'mobsub')
    local _, info3 = build.line(C.animatenpc, { '17200001', '5' }, ctx('me'))
    eq(info3.cursor, false, 'an id given')
    local _, info4 = build.line(C.checkvar, { nil, 'Immortal' }, ctx('me'))
    eq(info4.cursor, true, 'checkvar with no owner')
    local _, info5 = build.line(C.geteffects, {}, ctx('me'))
    eq(info5.cursor, true, 'geteffects with no one')
end)

test('flags the server takes as yes whatever their word: only Yes goes', function ()
    eq(build.line(C.mobhere, { '5' }, ctx('me')), '!mobhere 5', 'left out: despawns as usual')
    eq(build.line(C.mobhere, { '5', '1' }, ctx('me')), '!mobhere 5 1', 'kept')
    eq(build.line(C.givemagianitem, { 'Kupipi', '12' }, ctx('me')), '!givemagianitem Kupipi 12', 'the trial item')
    eq(build.line(C['goto'], { 'Kupipi', '0' }, ctx('me')), '!goto Kupipi 0', 'no zone-in')
end)

test('changejob: Master needs a level given', function ()
    local line, why = build.line(C.changejob, { 'WAR', nil, '1' }, ctx('me'))
    eq(line, nil)
    assert(why:find('Level'), why)
    eq(build.line(C.changejob, { 'WAR' }, ctx('me')), '!changejob WAR')
end)

test('setbag: a multiple of 5', function ()
    local _, why = build.line(C.setbag, { '33' }, ctx('me'))
    assert(why:find('multiple of 5'), why)
    eq(build.line(C.setbag, { '35' }, ctx('me')), '!setbag 35')
end)

test('required arguments', function ()
    local line, why = build.line(C.hp, {}, ctx('me'))
    eq(line, nil)
    assert(why:find('HP is needed'), why)
    local l2, why2 = build.line(C['goto'], {}, ctx('none'))
    eq(l2, nil, 'goto needs a name')
    assert(why2:find('Player'), why2)
end)

test('numbers are checked', function ()
    local _, why = build.line(C.hp, { 'abc' }, ctx('me'))
    assert(why:find('whole number'), why)
    local _, why2 = build.line(C.tp, { '5000' }, ctx('me'))
    assert(why2:find('3000 or less'), why2)
    local _, why3 = build.line(C.hp, { '-5' }, ctx('me'))
    assert(why3:find('0 or more'), why3)
    eq(build.line(C.hp, { '007' }, ctx('me')), '!hp 7 Seekey', 'written plainly')
end)

test('names are checked', function ()
    local _, why = build.line(C.hp, { '1', 'Bad Name' }, ctx('me'))
    assert(why:find('not a character name'), why)
    local _, why2 = build.line(C.hp, { '1', 'X1' }, ctx('me'))
    assert(why2:find('not a character name'), why2)
end)

test('a word has no spaces', function ()
    local _, why = build.line(C.givels, { 'My Shell' }, ctx('me'))
    assert(why:find('one word'), why)
end)

test('text keeps its spaces where the server reads the rest of the line', function ()
    eq(build.line(C.exec, { 'player:setHP(1)  ' }, ctx('me')), '!exec player:setHP(1)', 'trimmed')
    eq(build.line(C.breaklinkshell, { 'My Shell' }, ctx('me')), '!breaklinkshell My Shell', 'spaces kept')
end)

test('a leading player can be left out: the server shifts', function ()
    eq(build.line(C.addeffect, { nil, '3' }, ctx('none')), '!addeffect 3', 'no name')
    eq(build.line(C.addeffect, { nil, '3', '10', '120' }, ctx('me')), '!addeffect Seekey 3 10 120', 'with the default name')
    eq(build.line(C.addeffect, { nil, '3', nil, '120' }, ctx('none')), '!addeffect 3 1 120', 'power filled to give seconds')
end)

test('positions fill what comes between', function ()
    eq(build.line(C.additem, { '4096', nil, '5', '10' }, ctx('me')), '!additem 4096 1 5 10', 'quantity filled for the augment')
    local _, why = build.line(C.raise, { nil, 'Kupipi' }, ctx('me'))
    eq(_, '!raise 3 Kupipi', 'a raise tier filled: ' .. tostring(why))
end)

test('a player filled with your name to give what follows', function ()
    eq(build.line(C.checkmissionstatus, { nil, '1' }, ctx('none')), '!checkmissionstatus Seekey 1', 'checkmissionstatus')
    eq(build.line(C.checkmissionstatus, {}, ctx('none')), '!checkmissionstatus', 'nothing after it: left out')
end)

test('pos: X, Y and Z together', function ()
    eq(build.line(C.pos, {}, ctx('none')), '!pos', 'prints yours')
    eq(build.line(C.pos, { nil, nil, nil, nil, 'Kupipi' }, ctx('none')), '!pos Kupipi', 'prints theirs')
    eq(build.line(C.pos, { '1.5', '-2', '30', nil, 'Kupipi' }, ctx('none')), '!pos 1.5 -2 30 Kupipi', 'moves them, their zone')
    eq(build.line(C.pos, { '1', '2', '3', '230' }, ctx('none')), '!pos 1 2 3 230', 'to a zone')
    local _, why = build.line(C.pos, { '1', '2' }, ctx('none'))
    assert(why:find('together'), why)
    local _, why2 = build.line(C.pos, { nil, nil, nil, '230' }, ctx('none'))
    assert(why2:find('needs X'), why2)
end)

test('picks send their id, or their name where the form says', function ()
    eq(build.line(C.zone, { '230' }, ctx('me')), '!zone 230', 'zone id')
    eq(build.line(C.setmod, { 'ATT', '100' }, ctx('target', PC)), '!setmod ATT 100 Kupipi', 'mod by name')
    eq(build.line(C.changejob, { 'WHM', '75' }, ctx('me')), '!changejob WHM 75', 'job by abbreviation')
end)

test('a mob entity filled from the target', function ()
    eq(build.line(C.mobskill, { '100', nil, '1000' }, ctx('target', MOB)), '!mobskill 100 17000001 1000', 'mob id filled')
    local _, why = build.line(C.mobskill, { '100', nil, '1000' }, ctx('target', PC))
    assert(why:find('needed'), why)
end)

test('cursor commands say so', function ()
    local _, info = build.line(C['hp:Mob HP'], { '0' }, ctx('me', MOB))
    eq(info.cursor, true, 'Mob HP')
    local _, info2 = build.line(C.getid, {}, ctx('me'))
    eq(info2.cursor, true, 'getid')
    local _, info3 = build.line(C.despawnmob, {}, ctx('me'))
    eq(info3.cursor, true, 'an empty mob id is the cursor')
    local _, info4 = build.line(C.despawnmob, { '5' }, ctx('me'))
    eq(info4.cursor, false, 'a mob id given')
    local _, info5 = build.line(C.hp, { '5' }, ctx('me'))
    eq(info5.cursor, false, 'named')
end)

test('the line limit', function ()
    local long = ('x'):rep(130)
    local _, why = build.line(C.exec, { long }, ctx('me'))
    assert(why:find('bytes'), why)
    local ok, why2 = build.check('!hp 1 \226\152\131')
    eq(ok, false)
    assert(why2:find('ASCII'), why2)
end)

test('a typed line is tidied', function ()
    eq(build.tidy('  hp   5   Kupipi '), '!hp 5 Kupipi', 'a ! added, single spaces')
    eq(build.tidy('!where'), '!where', 'as it is')
    eq(build.tidy('   '), nil, 'nothing')
    eq(build.tidy('!'), nil, 'a ! alone')
    eq(build.tidy('! hp 5'), '!hp 5', 'a space after the !')
    eq(build.tidy('!hp 0 <t>', ctx('me', PC)), '!hp 0 Kupipi', '<t> filled in')
    eq(build.tidy('!hp 0 <me>', ctx('me', PC)), '!hp 0 Seekey', '<me> filled in')
    local l, why = build.tidy('!hp 0 <t>', ctx('me', MOB))
    eq(l, nil, '<t> a mob: refused')
    assert(why:find('not a player'), why)
end)

test('a typed line that reads the cursor', function ()
    eq(build.reads_cursor('!hp 0'), true, 'no name')
    eq(build.reads_cursor('!hp 0 Kupipi'), false, 'named')
    eq(build.reads_cursor('!getid'), true, 'always')
    eq(build.reads_cursor('!where'), false, 'never')
    eq(build.reads_cursor('!despawnmob'), true, 'no mob id')
    eq(build.reads_cursor('!despawnmob 123'), false, 'a mob id')
    eq(build.reads_cursor('!nosuch'), false, 'unknown')
    eq(build.reads_cursor('!animatenpc 5'), true, 'a leading id left out')
    eq(build.reads_cursor('!animatenpc 17200001 5'), false, 'given')
    eq(build.reads_cursor('!checkvar Immortal'), true, 'checkvar with no owner')
    eq(build.reads_cursor('!addeffect 3'), false, 'addeffect falls back to you, not the cursor')
end)

test('every form builds with its required boxes filled', function ()
    -- A value for each kind, so every form's path runs.
    local function value(a)
        if a.options then return a.options[1][1] end
        if a[2] == 'player' then return 'Kupipi' end
        if a[2] == 'num' then return '1.5' end
        if a[2] == 'pick' and (a.send == 'name' or a.set == 'currencies') then return 'NAME' end
        if a[2] == 'word' or a[2] == 'text' or a[2] == 'spell' then return 'abc' end
        return tostring(math.max(a.min or 1, 1))
    end
    for _, c in ipairs(catalog.list) do
        local v = {}
        for i, a in ipairs(c.args) do if a.req or (c.danger and a[2] == 'player') then v[i] = value(a) end end
        if c.pos then v = {} end
        local line, why = build.line(c, v, ctx('me', c.cursor == 'mob' and MOB or PC))
        assert(line, c.key .. ': ' .. tostring(why))
        assert(line:sub(1, #c.cmd + 1) == '!' .. c.cmd, c.key .. ': ' .. line)
        -- and with every box filled
        local all = {}
        for i, a in ipairs(c.args) do all[i] = value(a) end
        if c.pos then all = { '1', '2', '3', '230', 'Kupipi' } end
        local full, why2 = build.line(c, all, ctx('me', c.cursor == 'mob' and MOB or PC))
        assert(full, c.key .. ' (all): ' .. tostring(why2))
    end
end)

test('a typed or macro line: never a mob\'s command at a player, never a cursor player at an NPC', function ()
    eq(build.cursor_check('!hp 0', MOB), true, 'a bare !hp at a mob')
    local ok, why = build.cursor_check('!hp 0', PC)
    eq(ok, false, 'a bare !hp at a player: it would kill them')
    assert(why:find('isn\'t a mob'), why)
    eq((build.cursor_check('!hp 0', nil)), false, 'with nothing targeted it would be you')
    eq(build.cursor_check('!hp 0 Kupipi', PC), true, 'named: no cursor')
    eq((build.cursor_check('!immortal', NPC)), false, 'an NPC: the server would act on you')
    eq(build.cursor_check('!getid', PC), true, 'an any-target cursor command')
    eq(build.cursor_check('!where', nil), true)
    eq(build.cursor_check('!setmoblevel 1', MOB), true)
    eq((build.cursor_check('!setmoblevel 1', PC)), false)
end)

-- Acting on: Party ---------------------------------------------------------------------------------------------

local function party(target) return { me = 'Seekey', target = target, mode = 'party', party = { 'Seekey', 'Ajido', 'Trion' } } end

test('party: an empty player box sends a line apiece, you first', function ()
    local lines, info = build.lines(C.hp, { '99999' }, party(PC))
    eq(lines, { '!hp 99999 Seekey', '!hp 99999 Ajido', '!hp 99999 Trion' })
    eq(info.names, { 'Seekey', 'Ajido', 'Trion' })
    eq(info.cursor, false, 'every line names its player')
    eq(build.lines(C.raise, {}, party()), { '!raise 3 Seekey', '!raise 3 Ajido', '!raise 3 Trion' }, 'a fill before the name')
end)

test('party: a name typed in the box, or no player box, sends one line', function ()
    eq(build.lines(C.hp, { '5', 'Kupipi' }, party()), { '!hp 5 Kupipi' }, 'typed wins')
    eq(build.lines(C.where, {}, party()), { '!where' }, 'no player box')
    eq(build.lines(C['hp:Mob HP'], { '0' }, party(MOB)), { '!hp 0' }, 'the mob form still reads the cursor')
end)

test('party: a command that needs another player leaves you out', function ()
    eq(build.lines(C.bring, {}, party()), { '!bring Ajido', '!bring Trion' })
    eq(build.lines(C.giveitem, { '', '4096' }, party()), { '!giveitem Seekey 4096', '!giveitem Ajido 4096', '!giveitem Trion 4096' },
        'a command that needs a name: you too, by name')
    local g, gwhy = build.lines(C['goto'], {}, party())
    eq(g, nil, 'goto goes to one player')
    assert(gwhy:find('one player'), gwhy)
    eq(build.lines(C['goto'], { 'Ajido' }, party()), { '!goto Ajido' }, 'typed, it goes')
    local none, why = build.lines(C.bring, {}, { me = 'Seekey', mode = 'party', party = { 'Seekey' } })
    eq(none, nil)
    assert(why:find('but you'), why)
end)

test('party: a risky command never fans out', function ()
    local lines, why = build.lines(C.jail, {}, party())
    eq(lines, nil)
    assert(why:find('type the name'), why)
    eq(build.lines(C.jail, { 'Kupipi' }, party()), { '!jail Kupipi' }, 'typed, it goes')
end)

test('party: build.line alone never picks a member', function ()
    local l, why = build.line(C.hp, { '1' }, party())
    eq(l, nil)
    assert(why:find('a line apiece'), why)
    eq(build.lines(C.hp, { '1' }, { me = 'Seekey', mode = 'party', party = {} }), nil, 'no one at all')
end)

test('party: one bad box fails every line', function ()
    local lines, why = build.lines(C.hp, { 'lots' }, party())
    eq(lines, nil)
    assert(why:find('whole number'), why)
end)

test('flags: one (goto) and notself (bring)', function ()
    assert(build.flag('!bring Kupipi', 'notself'))
    assert(build.flag('goto', 'one'))
    assert(not build.flag('!hp 5 Kupipi', 'notself'))
    assert(not build.flag('!nosuch', 'one'))
end)
