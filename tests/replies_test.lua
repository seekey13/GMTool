-- core/replies.lua: the server's answers kept with the line that asked.
local replies = require('core.replies')

test('codes cleaned out of chat text', function ()
    eq(replies.clean('\30\81[\30\06GMTool\30\81]\30\01 hi'), '[GMTool] hi')
    eq(replies.clean('Kupipi\'s ID: 1001\r\n'), 'Kupipi\'s ID: 1001')
    eq(replies.clean('a \253\2\2\1\9\253 b'), 'a b', 'auto-translate')
end)

test('what comes in the moment after a send is kept with it', function ()
    replies.reset()
    local entry = { line = '!getid' }
    replies.sent(entry, 10)
    eq(replies.text('Target ID: 17000001', 10.5), 'Target ID: 17000001')
    eq(replies.text('[GMTool] !getid', 10.6, 1, true), nil, 'an addon\'s line never (GM Tool\'s echo too)')
    eq(replies.text('', 10.7), nil, 'empty')
    eq(replies.text('late', 20), nil, 'past the window')
    eq(replies.of(entry), { 'Target ID: 17000001' })
end)

test('players\' chat is never an answer', function ()
    replies.reset()
    local entry = {}
    replies.sent(entry, 0)
    for _, s in ipairs({ 'Kupipi : hello', 'Kupipi[Jeuno]: wts', 'Kupipi>> hi', '>>Kupipi : hi', '(Kupipi) pull',
                         '<Kupipi> ls chat', '[1]<Kupipi> ls1', '{Kupipi} unity', '[12:30:01] Kupipi : stamped' }) do
        eq(replies.text(s, 0.2), nil, s)
    end
    eq(replies.text("Kupipi's position: X 1.0000  Y 2.0000  Z 3.0000  Rot 0  (Zone: 230)", 0.3) ~= nil, true, 'a position is')
    eq(replies.text('Set Kupipi\'s HP to 100.', 0.4) ~= nil, true)
end)

test('the window only grows: an answer late in it is still kept', function ()
    replies.reset()
    local entry = {}
    replies.sent(entry, 0)
    replies.text('first', 0.2)
    eq(replies.text('second', 2.0), 'second', 'within the first window, after an early answer')
    local t = 2
    while t < 12 do replies.text('more', t) t = t + 1.2 end
    assert(#replies.of(entry) < replies.MAX, 'capped by LONGEST')
end)

test('lines sent together share their answers, under the newest', function ()
    replies.reset()
    local a, b = { line = '!hp 99999 Kupipi' }, { line = '!mp 99999 Kupipi' }
    replies.sent(a, 0)
    replies.sent(b, 0.1)
    replies.text('Set Kupipi\'s HP to 1000.', 0.3)
    replies.text('Set Kupipi\'s MP to 500.', 0.4)
    eq(replies.of(b), { 'Set Kupipi\'s HP to 1000.', 'Set Kupipi\'s MP to 500.' })
    eq(replies.of(a), nil, 'not repeated under the first')
    -- a send after the window: a batch of its own
    local c = {}
    replies.sent(c, 20)
    eq(replies.of(c), nil)
    replies.text('x', 20.1)
    eq(replies.of(c), { 'x' })
end)

test('at most MAX lines', function ()
    replies.reset()
    local entry = {}
    replies.sent(entry, 0)
    for i = 1, 40 do replies.text('l' .. i, 0.1) end
    eq(#replies.of(entry), replies.MAX)
end)

test('a position as !pos prints it', function ()
    eq(replies.position("Kupipi's position: X 1.2340  Y -3.0000  Z 100.5000  Rot 12  (Zone: 230)"),
        { name = 'Kupipi', x = 1.234, y = -3, z = 100.5, zone = 230 })
    eq(replies.position('Target ID: 5'), nil)
end)

test('a status effect as !geteffects lists it', function ()
    eq(replies.effect('[2] PROTECT (40) - Power: 50 | Time: 29m 50s | [Dispelable]'),
        { n = 2, name = 'PROTECT', id = 40, power = 50, time = '29m 50s', flags = 'Dispelable' })
    eq(replies.effect('[1] FOOD (251) - Power: 1 | SubPower: 3 | Time: 1h 2m 3s | Tick: 3s | [Food,Dispelable]'),
        { n = 1, name = 'FOOD', id = 251, power = 1, sub = 3, time = '1h 2m 3s', tick = '3s', flags = 'Food,Dispelable' })
    eq(replies.effect('[3] Unknown Effect (999)'), { n = 3, name = 'Unknown Effect', id = 999 }, 'no details, a name with a space')
    eq(replies.effect('Kupipi\'s position: X 1'), nil)
end)

test('a listing: its effects, none, or no listing at all', function ()
    eq(#replies.effects({ '[1] PROTECT (40) - Power: 50', 'something else', '[2] SHELL (41)' }), 2)
    eq(replies.effects({ 'Kupipi has no active effects.' }), {}, 'none')
    eq(replies.effects({ 'Player Zeid not found. For mobs, target them...' }), nil, 'not a listing')
    eq(replies.effects(nil), nil)
end)

test('a long batch (typed lines, 1.6 s apart) keeps its last line\'s answers', function ()
    replies.reset()
    local entries = {}
    for i = 1, 7 do
        entries[i] = { line = 'l' .. i }
        replies.sent(entries[i], (i - 1) * 1.6)  -- the seventh goes at 9.6 s, past 8 s from the first
    end
    for k = 1, 5 do assert(replies.text('[' .. k .. '] PROTECT (40)', 9.7 + k * 0.05), 'kept ' .. k) end
    eq(#replies.of(entries[7]), 5)
    replies.reset()
end)

test('an effect after a timestamp addon\'s prefix', function ()
    eq(replies.effect('[12:00:00] [1] PROTECT (40) - Power: 50').id, 40)
end)
