-- core/drops.lua: mobs' drop lists, from data/drops.lua (and a fake).
local drops = require('core.drops')
local spawns = require('core.spawns')

local real = drops.source

test('a list: its drops, kinds and rates', function ()
    drops.source = function () return { [7] = '0,0,1000,926,240;1,1,500,852,200;2,0,1000,4362,0;4,0,1000,1,0' } end
    drops.reset()
    local l = drops.of(7)
    eq(#l, 4)
    eq(l[1], { kind = 'drop', group = 0, group_rate = 1000, item = 926, rate = 240 })
    eq({ l[2].kind, l[3].kind, l[4].kind }, { 'group', 'steal', 'despoil' })
    eq(drops.chance(l[1]), '24%')
    eq(drops.chance(l[2]), 'group 1 at 50%: 20% of it')
    eq(drops.chance(l[3]), 'steal')
    eq(drops.pct(5), '0.5%')
    eq(drops.pct(1000), '100%')
    eq(drops.of(0), {}, 'no list')
    eq(drops.of(99), {}, 'an unknown one')
    drops.source = real
    drops.reset()
end)

test('data: Leaping Lizzy drops a Lizard Tail and Bounding Boots', function ()
    drops.source = real
    drops.reset()
    spawns.reset()
    local lizzy = spawns.filter(spawns.zone(107), 'nm', 'leaping lizzy')[1]
    assert(lizzy.drop > 0, 'its group names a list')
    local items = {}
    for _, d in ipairs(drops.of(lizzy.drop)) do items[d.item] = d end
    assert(items[926] and items[15351], 'Lizard Tail (926) and Bounding Boots (15351)')
end)
