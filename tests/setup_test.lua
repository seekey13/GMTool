-- core/setup.lua: a test character's lines, in the order they must go.
local setup = require('core.setup')
local store = require('core.store')
local util = require('core.util')

local function o(t)
    local x = util.copy(store.DEFAULTS.setup)
    for k, v in pairs(t or {}) do x[k] = v end
    return x
end

test('jobs first, then skills, unlocks, gil, HP and MP', function ()
    local lines = setup.lines(o({ job = 'WHM', level = '75', master = true, sub = 'BLM', sub_level = '37', spells = true,
                                  mounts = true, gil = '1000000', restore = true }), 'Seekey')
    eq(lines, { '!changejob WHM 75 1', '!changesjob BLM 37', '!capallskills', '!addallspells Seekey', '!addallmounts Seekey',
                '!setgil 1000000', '!hp 99999 Seekey', '!mp 99999 Seekey' })
end)

test('a sub job at its own level; nothing set says so', function ()
    eq(setup.lines(o({ sub = 'NIN', skills = false, restore = false }), 'Seekey'), { '!changesjob NIN' })
    local l, why = setup.lines(o({ skills = false, restore = false }), 'Seekey')
    eq(l, nil)
    assert(why:find('choose'), why)
end)

test('bad levels and gil, a master with no job, not logged in', function ()
    for _, t in ipairs({ { job = 'WAR', level = '0' }, { job = 'WAR', level = '100' }, { job = 'WAR', level = 'x' },
                         { sub = 'WAR', sub_level = '-1' }, { gil = '1.5' }, { master = true } }) do
        local l, why = setup.lines(o(t), 'Seekey')
        eq(l, nil, why)
    end
    eq(setup.lines(o(), nil), nil)
end)

test('for a macro: {me} for the name; a name for it', function ()
    local lines = setup.lines(o({ job = 'PUP', level = '99', attachments = true }), '{me}')
    eq(lines[3], '!addallattachments {me}')
    eq(setup.name(o({ job = 'PUP', level = '99', sub = 'WAR', sub_level = '49' })), 'Setup PUP 99/WAR 49')
    eq(setup.name(o()), 'Setup')
end)

test('review: gil within what a character holds, sub job not the main, an empty level keeps yours', function ()
    eq(setup.lines(o({ gil = '999999999', skills = false }), 'Seekey'), { '!setgil 999999999' })
    eq(setup.lines(o({ gil = '1000000000', skills = false }), 'Seekey'), nil, 'over the most')
    local l, why = setup.lines(o({ job = 'WHM', sub = 'WHM' }), 'Seekey')
    eq(l, nil)
    assert(why:find('main job'), why)
    eq(setup.lines(o({ job = 'WAR', level = '', skills = false }), 'Seekey'), { '!changejob WAR' }, 'the level you have in it')
    eq(setup.lines(o({ job = 'WAR', level = '', master = true }), 'Seekey'), nil, 'mastering needs a level before its 1')
end)
