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
