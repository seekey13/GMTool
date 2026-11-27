--[[
    The Target page's one-click actions: what a GM does most to whatever is targeted, as lines. Pure.

    Each line names the target, or gives its server id, wherever the server takes one, so the cursor race
    (core/game.lua) can't make it act on someone else; the few commands that only read the cursor (a mob's !hp,
    !getstats...) say so (`cursor`), and core/send.lua holds them until the server has the target.
]]--

local actions = {}

-- { label, group, tip, danger, cursor, lines = function (t) -> { line, ... } } per kind of target.
local PC = {
    { 'Go to', 'Move', 'Go to them (!goto)', lines = function (t) return { '!goto ' .. t.name } end },
    { 'Bring', 'Move', 'Bring them to you (!bring)', lines = function (t) return { '!bring ' .. t.name } end },
    { 'Home point', 'Move', 'Send them to their home point (revives the dead)', lines = function (t) return { '!homepoint ' .. t.name } end },
    { 'Return', 'Move', 'Send them back to their previous zone', lines = function (t) return { '!return ' .. t.name } end },
    { 'Where', 'Move', 'Print their position (!pos)', lines = function (t) return { '!pos ' .. t.name } end },
    { 'Restore', 'Vitals', 'Full HP and MP, 3000 TP', lines = function (t)
        return { '!hp 99999 ' .. t.name, '!mp 99999 ' .. t.name, '!tp 3000 ' .. t.name }
    end },
    { 'Raise', 'Vitals', 'Send them Raise III\'s menu (they must be dead)', lines = function (t) return { '!raise 3 ' .. t.name } end },
    { 'Kill', 'Vitals', 'Set their HP to 0', danger = true, lines = function (t) return { '!hp 0 ' .. t.name } end },
    { 'Immortal', 'Vitals', 'Toggle: their HP never falls below 1', lines = function (t) return { '!immortal ' .. t.name } end },
    { 'Reset recasts', 'Vitals', 'Their job abilities and spells ready. It also clears every effect on YOU, buffs too',
      danger = true, lines = function (t) return { '!reset ' .. t.name } end },
    { 'Effects', 'Look', 'List the server\'s status effects on them', lines = function (t) return { '!geteffects ' .. t.name } end },
    { 'Stats', 'Look', 'Print their stats (your cursor target)', cursor = true, lines = function () return { '!getstats' } end },
    { 'Server id', 'Look', 'Print their server id (your cursor target)', cursor = true, lines = function () return { '!getid' } end },
    { 'Pool', 'Look', 'Their treasure pool (your cursor target; GM 3)', cursor = true, lines = function () return { '!getpool' } end },
    { 'Release', 'Fix', 'Release them from a stuck event', lines = function (t) return { '!release ' .. t.name } end },
    { 'Wallhack', 'Fix', 'Toggle walking through walls for them', lines = function (t) return { '!wallhack ' .. t.name } end },
    { 'Jail', 'Moderate', 'Send them to Mordion Gaol', danger = true, lines = function (t) return { '!jail ' .. t.name } end },
    { 'Pardon', 'Moderate', 'Release them from jail', lines = function (t) return { '!pardon ' .. t.name } end },
    { 'Kick', 'Moderate', 'Log them off by force', danger = true, lines = function (t) return { '!logoff ' .. t.name } end },
}

local MOB = {
    { 'Kill', 'Fight', 'Set its HP to 0 (your cursor target)', cursor = true, lines = function () return { '!hp 0' } end },
    { '1 HP', 'Fight', 'Leave it at 1 HP (your cursor target)', cursor = true, lines = function () return { '!hp 1' } end },
    { 'Full HP', 'Fight', 'Its HP back to full (your cursor target)', cursor = true, lines = function () return { '!hp 9999999' } end },
    { 'Level 1', 'Fight', 'A harmless mob to claim (your cursor target)', cursor = true, lines = function () return { '!setmoblevel 1' } end },
    { 'Stun', 'Fight', 'Toggle an hour of stun on it (your cursor target)', cursor = true, lines = function () return { '!stun' } end },
    { 'Despawn', 'Spawn', 'Despawn it', lines = function (t) return { '!despawnmob ' .. t.sid } end },
    { 'Bring here', 'Spawn', 'Move it to you (!mobhere)', lines = function (t) return { '!mobhere ' .. t.sid } end },
    { 'Go to', 'Spawn', 'Go to it (!gotoid)', lines = function (t) return { '!gotoid ' .. t.sid } end },
    { 'Stats', 'Look', 'Print its stats (your cursor target)', cursor = true, lines = function () return { '!getstats' } end },
    { 'Effects', 'Look', 'List the server\'s status effects on it', lines = function (t) return { '!geteffects ' .. t.sid } end },
    { 'Enmity', 'Look', 'Its enmity toward you, CE and VE (GM 2)', cursor = true, lines = function () return { '!getenmity' } end },
    { 'Action', 'Look', 'What it is doing now', lines = function (t) return { '!getmobaction ' .. t.sid } end },
    { 'Flags', 'Look', 'Its entity flags', lines = function (t) return { '!getmobflags ' .. t.sid } end },
    { 'Trick Attack', 'Look', 'Whom Trick Attack would pick against it', cursor = true, lines = function () return { '!getta' } end },
    { 'Local vars', 'Look', 'List its local variables (your cursor target)', cursor = true, lines = function () return { '!getlocalvars' } end },
}

local NPC = {
    { 'Go to', 'Move', 'Go to it (!gotoid)', lines = function (t) return { '!gotoid ' .. t.sid } end },
    { 'Bring here', 'Move', 'Move it to you (!npchere)', lines = function (t) return { '!npchere ' .. t.sid } end },
    { 'Server id', 'Look', 'Print its server id (your cursor target)', cursor = true, lines = function () return { '!getid' } end },
    { 'Local vars', 'Look', 'List its local variables (your cursor target)', cursor = true, lines = function () return { '!getlocalvars' } end },
}

-- A pet or a trust: its id, and what reads the cursor.
local OTHER = {
    { 'Go to', 'Move', 'Go to it (!gotoid)', lines = function (t) return { '!gotoid ' .. t.sid } end },
    { 'Kill', 'Fight', 'Set its HP to 0 (your cursor target)', cursor = true, danger = true, lines = function () return { '!hp 0' } end },
    { 'Full HP', 'Fight', 'Its HP back to full (your cursor target)', cursor = true, lines = function () return { '!hp 9999999' } end },
    { 'Stats', 'Look', 'Print its stats (your cursor target)', cursor = true, lines = function () return { '!getstats' } end },
    { 'Effects', 'Look', 'List the server\'s status effects on it (your cursor target)', cursor = true,
      lines = function () return { '!geteffects' } end },
}

local BY_KIND = { pc = PC, mob = MOB, npc = NPC, other = OTHER }

-- The actions for target `t` ({ name, kind, sid }), each { label, group, tip, danger, cursor, lines = { ... } },
-- with `me` (your name) left out where it's you (going to yourself, jailing yourself). Empty for no target.
function actions.for_target(t, me)
    if not t then return {} end
    local list = BY_KIND[t.kind] or OTHER
    local self = t.kind == 'pc' and me and t.name:lower() == me:lower()
    local SKIP_SELF = { ['Go to'] = true, Bring = true, Jail = true, Kick = true, Pardon = true }
    local out = {}
    for _, a in ipairs(list) do
        if not (self and SKIP_SELF[a[1]]) and (t.kind == 'pc' or t.sid) then
            out[#out + 1] = { label = a[1], group = a[2], tip = a[3], danger = a.danger, cursor = a.cursor, lines = a.lines(t) }
        end
    end
    return out
end

return actions
