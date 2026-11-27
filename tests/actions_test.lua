-- core/actions.lua: the Target page's actions.
local actions = require('core.actions')
local build = require('core.build')

test('every action is a list of lines the server can read', function ()
    for _, t in ipairs({ { name = 'Kupipi', kind = 'pc', sid = 1 }, { name = 'Crab', kind = 'mob', sid = 17000001 },
                         { name = 'Door', kind = 'npc', sid = 17200001 }, { name = 'Pet', kind = 'other', sid = 1800 } }) do
        local list = actions.for_target(t, 'Seekey')
        assert(#list > 0, t.kind)
        for _, a in ipairs(list) do
            assert(#a.lines > 0, a.label)
            for _, l in ipairs(a.lines) do
                assert(build.check(l), a.label .. ': ' .. l)
                eq(build.reads_cursor(l), a.cursor == true, ('%s %s: reads the cursor %s'):format(t.kind, a.label, l))
            end
        end
    end
end)

test('nothing for no target; no going to or jailing yourself', function ()
    eq(actions.for_target(nil), {})
    local mine = {}
    for _, a in ipairs(actions.for_target({ name = 'Seekey', kind = 'pc', sid = 1 }, 'seekey')) do mine[a.label] = true end
    assert(not mine['Go to'] and not mine.Jail and not mine.Kick, 'left out')
    assert(mine.Restore, 'the rest kept')
end)
