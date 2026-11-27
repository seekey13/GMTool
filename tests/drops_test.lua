-- core/drops.lua: mobs' drop lists, from data/drops.lua (and a fake).
local drops = require('core.drops')
local spawns = require('core.spawns')

local real = drops.source

test('a list: its drops, kinds and rates', function ()
    drops.source = function () return { [7] = '0,0,1000,926,240;1,1,500,852,200;2,0,1000,4362,0;4,0,1000,1,0' } end
    drops.reset()
    local l = drops.of(7)
    eq(#l, 4)
    eq({ l[1].kind, l[1].item, l[1].rate, l[1].rolls, l[1].chance }, { 'drop', 926, 240, 1, 0.24 })
    eq({ l[2].kind, l[3].kind, l[4].kind }, { 'group', 'steal', 'despoil' })
    eq(drops.chance(l[1]), '24%')
    eq(drops.chance(l[2]), '50% (group 1: 50%, then 100% of its picks)', 'alone in its group')
    eq(drops.chance(l[3]), 'steal')
    eq(drops.pct(5), '0.5%')
    eq(drops.pct(1000), '100%')
    eq(drops.of(0), {}, 'no list')
    eq(drops.of(99), {}, 'an unknown one')
    drops.source = real
    drops.reset()
end)

test('a group picks by weight: shares of what its rates add up to', function ()
    -- group 1 rolls at 50%, its rates add to 500: 200 is 40% of its picks (not 20%), 20% a kill
    drops.source = function () return { [8] = '1,1,500,10,200;1,1,500,11,300;1,2,1000,12,100;1,2,1000,12,100' } end
    drops.reset()
    local l = drops.of(8)
    eq(#l, 3, 'one item twice in a group: one row')
    eq(drops.chance(l[1]), '20% (group 1: 50%, then 40% of its picks)')
    eq(drops.chance(l[2]), '30% (group 1: 50%, then 60% of its picks)')
    eq({ l[3].rate, drops.chance(l[3]) }, { 200, '100% (group 2: 100%, then 100% of its picks)' }, 'its weights add')
    drops.source = real
    drops.reset()
end)

test('one item twice on its own rolls twice; a steal row with a rate drops on a kill too', function ()
    drops.source = function () return { [9] = '0,0,1000,842,150;0,0,1000,842,150;2,0,1000,1661,100' } end
    drops.reset()
    local l = drops.of(9)
    eq(#l, 2)
    eq({ l[1].rolls, drops.chance(l[1]) }, { 2, '27.8% (2 rolls of 15%)' })
    eq(drops.chance(l[2]), 'steal; 10% on a kill')
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
