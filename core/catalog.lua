--[[
    Every GM command the CatsEyeXI server has (scripts/commands/*.lua), as forms: what each one does, its arguments
    in the order the server reads them, and the page it is listed on. tests/catalog_test.lua checks it against
    data/server.lua (generated from the server): every command is here, and no argument list is longer than the
    server reads. Each command's GM level comes from data/server.lua, never from here.

    How the server reads a line (src/map/command_handler.cpp):
      - the words split on spaces; a word for a number is read with atoi (a word that isn't one becomes 0);
      - text with spaces survives only for a command whose one parameter is text ('s'), or one that reads the
        whole line ('b'): !exec, !pos, !zone, !send, !breaklinkshell. Everywhere else an argument is one word;
      - arguments go by position: to give the fourth, the second and third must be given too (`fill`).

    An argument is { label, kind, ... }:
      kind     'int' | 'num' | 'word' | 'text' | 'player' | 'pick' | 'choice' | 'entity' | 'item' | 'spell'
      req      it must be given
      fill     what goes in its place when it's left empty but a later one is given ('me' for your name)
      shift    the server can tell when it's left out (a leading player name): nothing goes in its place
      min/max  a number's range
      set      a pick's list: a data/<set>.lua ('zones', 'effects', 'mods', ...)
      send     what a pick sends: 'id' (the default) or 'name' (lower case for 'lower')
      options  a choice's { value, label } list
      who      a player's when left empty: 'you' (you), 'cursor' (your cursor's player or mob, else you),
               'cursor_pc' (your cursor's player, else you), 'none' (a name is required)
      hint     the placeholder: what the server does with it empty
      adv      shown only when the command's form is expanded fully (augments and the like)
]]--

local catalog = {}

local function util_trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- Pages, in the sidebar's order: { id, title, blurb }.
catalog.PAGES = {
    { 'vitals', 'Player', 'HP, MP and TP, raising, immortality and resets for a player.' },
    { 'jobs', 'Jobs & Skills', 'Jobs, levels, merits, job points, experience and skills.' },
    { 'abilities', 'Spells & Abilities', 'Spells, trusts, weapon skills, attachments and Monstrosity.' },
    { 'effects', 'Effects & Mods', 'Status effects and modifiers on players and mobs.' },
    { 'items', 'Items', 'Items, the treasure pool, bags and linkshells.' },
    { 'currency', 'Gil & Currency', 'Gil, currencies, Abyssea lights and timers.' },
    { 'unlocks', 'Key Items & Titles', 'Key items, maps, mounts, titles and chocobos.' },
    { 'quests', 'Quests & Missions', 'Quest and mission logs, their variables and records.' },
    { 'nation', 'Nation & Fame', 'Nation, rank, allegiance, fame, conquest and garrisons.' },
    { 'travel', 'Travel', 'Zones, warps to players and entities, positions.' },
    { 'mobs', 'Mobs', 'Spawning, levels, skills, flags and enmity.' },
    { 'npcs', 'NPCs & Entities', 'NPCs, animations, names and entity info.' },
    { 'world', 'Appearance & World', 'Looks, costumes, music, weather, speed and visibility.' },
    { 'vars', 'Variables', 'Character, server and local variables.' },
    { 'debug', 'Events & Debug', 'Cutscenes, menus, packets, messages and instances.' },
    { 'moderation', 'Moderation', 'Jail, chat bans, kicks, promotions and account fixes.' },
    { 'server', 'Server', 'Server-wide commands (GM level 4 and 5): reloads, the clock, crashes.' },
}

-- Arguments -------------------------------------------------------------------------------------------------------

local function arg(label, kind, o)
    o = o or {}
    o[1], o[2] = label, kind
    return o
end
local function int(label, o) return arg(label, 'int', o) end
local function num(label, o) return arg(label, 'num', o) end
local function word(label, o) return arg(label, 'word', o) end
local function text(label, o) return arg(label, 'text', o) end
local function pick(label, set, o) o = o or {}; o.set = set; return arg(label, 'pick', o) end
local function choice(label, options, o) o = o or {}; o.options = options; return arg(label, 'choice', o) end
local function entity(label, o) return arg(label, 'entity', o) end
local function item(label, o) return arg(label, 'item', o) end
local function spell(label, o) return arg(label, 'spell', o) end

-- A player: `who` says what the server does with none (above).
local function player(who, o)
    o = o or {}
    o.who = who or 'you'
    if o.who == 'none' then o.req = true end
    return arg(o.label or 'Player', 'player', o)
end

local LIGHTS = { { 'pearl', 'Pearl' }, { 'azure', 'Azure' }, { 'ruby', 'Ruby' }, { 'amber', 'Amber' },
                 { 'gold', 'Gold' }, { 'silver', 'Silver' }, { 'ebon', 'Ebon' } }
local WS_SLOTS = { { '0', 'Main' }, { '1', 'Sub' }, { '2', 'Ranged' } }
local WS_SLOT_NAMES = { { 'main', 'Main' }, { 'sub', 'Sub' }, { 'ranged', 'Ranged' } }
local VAR_OWNERS = { { 'player', 'Player' }, { 'mob', 'Mob' }, { 'npc', 'NPC' } }
local MUSIC_TYPES = { { '0', 'BGM (day)' }, { '1', 'BGM (night)' }, { '2', 'Solo battle' }, { '3', 'Party battle' },
                      { '4', 'Chocobo' }, { '5', 'Death' }, { '6', 'Mog House' }, { '7', 'Fishing' } }
local STATS = { { '1', 'Base' }, { '2', 'Defensive' }, { '3', 'Offensive' }, { '4', 'Elements' } }
local MENTOR = { { '0', 'Not a mentor' }, { '1', 'Unlocked, flag off' }, { '2', 'Unlocked, flag on' } }
local HOME_NATIONS = { { '0', 'San d\'Oria' }, { '1', 'Bastok' }, { '2', 'Windurst' } }
local CAMPAIGN = { { 'NONE', 'None' }, { 'SANDORIA', 'San d\'Oria' }, { 'BASTOK', 'Bastok' }, { 'WINDURST', 'Windurst' } }
local CHOCO_COLORS = { { 'yellow', 'Yellow' }, { 'black', 'Black' }, { 'blue', 'Blue' }, { 'red', 'Red' }, { 'green', 'Green' } }
local CHOCO_TRAITS = { { 'head', 'Large beak' }, { 'tail', 'Large tail' }, { 'feet', 'Large feet' } }
local TRUST_ENGAGE = { { '0', 'Retail: master engages and swings' }, { '1', 'Attack: master engages' } }
local YELL = { { 'ban', 'Ban' }, { 'unban', 'Unban' } }
local GARRISON = { { 'start', 'Start' }, { 'stop', 'Stop' }, { 'win', 'Win' } }
local RAISE = { { '1', 'Raise' }, { '2', 'Raise II' }, { '3', 'Raise III' } }
local GODMODE = { { '1', 'Tier 1: Regen, Refresh, Regain, Chainspell, Manafont' } }
local HIDE = { { 'status', 'Show status only' } }
local ZONE_IN = { { '0', 'No: in the same zone, just move' } }  -- forceZone: 1 (zone in) when left out

-- Commands --------------------------------------------------------------------------------------------------------

catalog.list = {}
local list = catalog.list
local function C(t) list[#list + 1] = t; return t end

-- Player --------------------------------------------------------------------------------------------------------
C{ cmd = 'hp', page = 'vitals', desc = 'Set HP. 0 kills; more than the max gives the max.',
   args = { int('HP', { req = true, min = 0 }), player('cursor') },
   presets = { { 'Full', { '99999' } }, { 'Kill', { '0' } }, { '1 HP', { '1' } } },
   note = 'A dead player is refused: raise them first.' }
C{ cmd = 'mp', page = 'vitals', desc = 'Set MP; more than the max gives the max.',
   args = { int('MP', { req = true, min = 0 }), player('cursor') }, presets = { { 'Full', { '99999' } }, { 'Empty', { '0' } } } }
C{ cmd = 'tp', page = 'vitals', desc = 'Set TP (0 to 3000). Their pet\'s TP is set too.',
   args = { int('TP', { req = true, min = 0, max = 3000 }), player('cursor') },
   presets = { { '3000', { '3000' } }, { '1000', { '1000' } }, { '0', { '0' } } } }
C{ cmd = 'raise', page = 'vitals', desc = 'Send the raise menu to a dead player, who still has to take it.',
   args = { choice('Raise', RAISE, { fill = '3', hint = 'Raise III' }), player('you') } }
C{ cmd = 'immortal', page = 'vitals', desc = 'Toggle: HP never falls below 1. A punching bag that still takes damage.',
   args = { player('cursor') }, note = 'Its state is the char var Immortal (!checkvar <name> Immortal).' }
C{ cmd = 'godmode', page = 'vitals', desc = 'Toggle on yourself: invincible, Perfect Dodge, Regen, Refresh, +1000% HP and more.',
   args = { choice('Tier', GODMODE, { hint = 'full god mode' }) } }
C{ cmd = 'petgodmode', page = 'vitals', desc = 'Toggle god mode on your pet.' }
C{ cmd = 'pettp', page = 'vitals', desc = 'Set your pet\'s TP.', args = { int('TP', { req = true, min = 0, max = 3000 }) } }
C{ cmd = 'reset', page = 'vitals', desc = 'Reset job ability and spell recasts to 0.',
   args = { player('you') }, note = 'It also clears YOUR debuffs, whoever is named.' }
C{ cmd = 'homepoint', page = 'vitals', desc = 'Send a player to their home point (revives the dead at full HP and MP).',
   args = { player('you') } }
C{ cmd = 'release', page = 'vitals', desc = 'Release a player stuck in an event or cutscene.', args = { player('you') } }

-- Jobs & Skills ---------------------------------------------------------------------------------------------------
C{ cmd = 'changejob', page = 'jobs', desc = 'Change your main job.',
   args = { pick('Job', 'jobs', { req = true, send = 'name', skip = { 0 } }), int('Level', { min = 1, max = 99, hint = 'current' }),
            choice('Master it', { { '1', 'Yes' } }, { hint = 'no' }) } }
C{ cmd = 'changesjob', page = 'jobs', desc = 'Change your sub job (held to the server\'s sub level cap).',
   args = { pick('Job', 'jobs', { req = true, send = 'name', skip = { 0 } }), int('Level', { min = 1, max = 99, hint = 'current' }) } }
C{ cmd = 'setplayerlevel', page = 'jobs', desc = 'Set a player\'s main job level.',
   args = { player('you', { shift = true }), int('Level', { req = true, min = 1, max = 99 }) } }
C{ cmd = 'masterjob', page = 'jobs', desc = 'Master a player\'s current job.', args = { player('you') } }
C{ cmd = 'givexp', page = 'jobs', desc = 'Give experience points.', args = { int('EXP', { req = true, min = 1 }), player('you') } }
C{ cmd = 'takexp', page = 'jobs', desc = 'Take experience points away.', args = { int('EXP', { req = true, min = 1 }), player('you') } }
C{ cmd = 'setmerits', page = 'jobs', desc = 'Set a player\'s merit point count.', args = { int('Merits', { req = true, min = 0 }), player('you') } }
C{ cmd = 'setjobpoints', page = 'jobs', desc = 'Set a player\'s job point count.', args = { int('Job points', { req = true, min = 0 }), player('you') } }
C{ cmd = 'setcapacitypoints', page = 'jobs', desc = 'Set a player\'s capacity points.',
   args = { int('Capacity points', { req = true, min = 0 }), player('you') } }
C{ cmd = 'cp', page = 'jobs', desc = 'Give yourself capacity points.', args = { int('Amount', { req = true }) } }
C{ cmd = 'capallskills', page = 'jobs', desc = 'Cap every combat and magic skill for your job and level.' }
C{ cmd = 'capskill', page = 'jobs', desc = 'Cap one of your skills.', args = { pick('Skill', 'skills', { req = true }) } }
C{ cmd = 'setskill', page = 'jobs', desc = 'Set a skill\'s level.',
   args = { pick('Skill', 'skills', { req = true }), int('Level', { req = true, min = 0, max = 1000 }), player('cursor_pc') } }
C{ cmd = 'getskill', page = 'jobs', desc = 'Show a skill\'s level.', args = { pick('Skill', 'skills', { req = true }), player('cursor_pc') } }
C{ cmd = 'setcraftrank', page = 'jobs', desc = 'Set a crafting skill\'s rank.',
   args = { pick('Craft', 'skills', { req = true, crafts = true }), pick('Rank', 'craftranks', { req = true }), player('cursor_pc') } }
C{ cmd = 'getcraftrank', page = 'jobs', desc = 'Show a crafting skill\'s rank.',
   args = { pick('Craft', 'skills', { req = true, crafts = true }), player('cursor_pc') } }
C{ cmd = 'setmentor', page = 'jobs', desc = 'Set a player\'s mentor status.', args = { choice('Mode', MENTOR, { req = true }), player('you') } }

-- Spells & Abilities ----------------------------------------------------------------------------------------------
C{ cmd = 'addallspells', page = 'abilities', desc = 'Learn every valid spell but the trusts.', args = { player('you') } }
C{ cmd = 'addspell', page = 'abilities', desc = 'Learn one spell (its id, or its name with underscores).',
   args = { spell('Spell', { req = true }), player('you') } }
C{ cmd = 'delspell', page = 'abilities', desc = 'Forget one spell.', args = { spell('Spell', { req = true }), player('you') } }
C{ cmd = 'addalltrusts', page = 'abilities', desc = 'Learn every trust.', args = { player('you') } }
C{ cmd = 'addallweaponskills', page = 'abilities', desc = 'Learn every weapon skill that is learned by quest.', args = { player('you') } }
C{ cmd = 'delallweaponskills', page = 'abilities', desc = 'Forget every learned weapon skill.', args = { player('you') } }
C{ cmd = 'addweaponskillpoints', page = 'abilities', desc = 'Add weapon skill points to an equipped weapon.',
   args = { choice('Slot', WS_SLOTS, { req = true }), int('Points', { req = true, min = 0 }), player('you') } }
C{ cmd = 'getwspoints', page = 'abilities', desc = 'Show an equipped weapon\'s weapon skill points.',
   args = { choice('Slot', WS_SLOT_NAMES, { fill = 'main', hint = 'main' }), player('cursor') } }
C{ cmd = 'addallattachments', page = 'abilities', desc = 'Unlock every automaton attachment.', args = { player('you') } }
C{ cmd = 'addallmonstrosity', page = 'abilities', desc = 'Unlock every Monstrosity species, instinct and variant.', args = { player('you') } }
C{ cmd = 'monstrosity', page = 'abilities', desc = 'Open the Monstrosity debug menu.' }
C{ cmd = 'trustengage', page = 'abilities', desc = 'Set when your trusts engage (if the server allows custom engagement).',
   args = { choice('Type', TRUST_ENGAGE, { hint = 'show current' }) } }

-- Effects & Mods --------------------------------------------------------------------------------------------------
C{ cmd = 'addeffect', page = 'effects', desc = 'Give a status effect outright: no resist, no immunity.',
   args = { player('you', { shift = true }), pick('Effect', 'effects', { req = true }), int('Power', { min = 0, fill = '1', hint = '1' }),
            int('Seconds', { min = 0, fill = '60', hint = '60' }), int('Sub id', { min = 0, fill = '0', hint = '0', adv = true }),
            int('Sub power', { min = 0, hint = '0', adv = true }) },
   note = 'Trusts and mobs can\'t be named: use !exec on your cursor target for them.' }
C{ cmd = 'deleffect', page = 'effects', desc = 'Remove a status effect.',
   args = { player('you', { shift = true }), pick('Effect', 'effects', { req = true }) } }
C{ cmd = 'geteffects', page = 'effects', desc = 'List the server\'s status effects on someone, with power and time left.',
   args = { word('Player or mob id', { hint = 'cursor target, else you', target = 'name_or_id', cursor = true }) } }
C{ cmd = 'setmod', page = 'effects', desc = 'Set a modifier on a player (or your cursor target).',
   args = { pick('Modifier', 'mods', { req = true, send = 'name' }), int('Value', { req = true }), player('cursor') },
   note = 'With no name it acts on your cursor target, never on you.' }
C{ cmd = 'getmod', cursor = 'any', page = 'effects', desc = 'Show a modifier on you or your cursor target.', args = { pick('Modifier', 'mods', { req = true, send = 'name' }) } }
C{ cmd = 'stun', cursor = 'any', page = 'effects', desc = 'Toggle an hour of stun on your cursor target (player or mob).',
   note = 'Acts on your cursor target only.' }

-- Items -----------------------------------------------------------------------------------------------------------
local AUGMENTS = {}
for i = 1, 4 do
    AUGMENTS[#AUGMENTS + 1] = int('Augment ' .. i, { min = 0, fill = '0', adv = true })
    AUGMENTS[#AUGMENTS + 1] = int('Value ' .. i, { min = 0, fill = '0', adv = true })
end
local function with(base, extra)
    local out = {}
    for _, a in ipairs(base) do out[#out + 1] = a end
    for _, a in ipairs(extra) do out[#out + 1] = a end
    return out
end
C{ cmd = 'additem', page = 'items', desc = 'Add an item to your own inventory.',
   args = with({ item('Item', { req = true }), int('Quantity', { min = 1, fill = '1', hint = '1' }) },
       with(AUGMENTS, { int('Magian trial', { min = 0, adv = true }) })) }
C{ cmd = 'giveitem', page = 'items', desc = 'Give an item to a player (the server says when they\'re full).',
   args = with({ player('none'), item('Item', { req = true }), int('Quantity', { min = 1, fill = '1', hint = '1' }) }, AUGMENTS) }
C{ cmd = 'delitem', page = 'items', desc = 'Delete one of an item a player holds.', args = { item('Item', { req = true }), player('you') } }
C{ cmd = 'hasitem', page = 'items', desc = 'Check whether a player has an item.', args = { item('Item', { req = true }), player('cursor_pc') } }
C{ cmd = 'addtempitem', page = 'items', desc = 'Add a temporary item to your inventory.',
   args = { item('Item', { req = true }), int('Quantity', { min = 1, hint = '1' }) } }
C{ cmd = 'addtreasure', page = 'items', desc = 'Drop an item straight into the treasure pool.',
   args = { item('Item', { req = true }), player('you', { fill = 'me' }), entity('Dropper id', { hint = 'none', adv = true }) } }
C{ cmd = 'getpool', cursor = 'any', page = 'items', desc = 'Show your cursor target\'s treasure pool.' }
C{ cmd = 'givemagianitem', page = 'items', desc = 'Give the item for a Magian trial.',
   args = { player('none'), int('Trial id', { req = true, min = 1 }), choice('Item', { { 'reward', 'Reward item' } }, { hint = 'trial item' }) },
   note = 'Any third word gives the reward item: leave it empty for the trial item.' }
C{ cmd = 'setbag', page = 'items', desc = 'Set your inventory size (30 to 80, a multiple of 5).',
   args = { int('Size', { req = true, min = 30, max = 80, step = 5 }) } }
C{ cmd = 'addfish', page = 'items', desc = 'Add a measured fish to your inventory.',
   args = { item('Fish', { req = true }), int('Length', { req = true, min = 0 }), int('Weight', { req = true, min = 0 }),
            choice('Ranked', { { '1', 'Ranked' } }, { hint = 'no' }) } }
C{ cmd = 'givels', page = 'items', desc = 'Make a linkpearl (a pearlsack for a GM) for a linkshell.',
   args = { word('Linkshell', { req = true }), player('you') } }
C{ cmd = 'delallinventory', page = 'items', desc = 'Delete EVERY item in a player\'s inventory.', args = { player('cursor_pc') }, danger = true }
C{ cmd = 'delcontaineritems', page = 'items', desc = 'Delete every item in one of a player\'s containers.',
   args = { pick('Container', 'containers', { req = true }), player('cursor_pc') }, danger = true }

-- Gil & Currency --------------------------------------------------------------------------------------------------
C{ cmd = 'givegil', page = 'currency', desc = 'Give gil.', args = { int('Gil', { req = true, min = 1 }), player('you') },
   presets = { { '1M', { '1000000' } }, { '100k', { '100000' } } } }
C{ cmd = 'takegil', page = 'currency', desc = 'Take gil away.', args = { int('Gil', { req = true, min = 1 }), player('you') } }
C{ cmd = 'setgil', page = 'currency', desc = 'Set your own gil.', args = { int('Gil', { req = true, min = 0 }) } }
C{ cmd = 'addcurrency', page = 'currency', desc = 'Add a currency (conquest points, seals, sparks...).',
   args = { pick('Currency', 'currencies', { req = true, send = 'name' }), int('Amount', { req = true, min = 1 }), player('you') } }
C{ cmd = 'delcurrency', page = 'currency', desc = 'Remove some of a currency.',
   args = { pick('Currency', 'currencies', { req = true, send = 'name' }), int('Amount', { req = true, min = 1 }), player('you') } }
C{ cmd = 'addlights', page = 'currency', desc = 'Add Abyssea lights.',
   args = { choice('Light', LIGHTS, { req = true }), int('Amount', { req = true, min = 1 }), player('you') } }
C{ cmd = 'resetlights', page = 'currency', desc = 'Reset every Abyssea light to 0.', args = { player('you') } }
C{ cmd = 'addabytime', page = 'currency', desc = 'Add minutes to an Abyssea visitant timer.',
   args = { int('Minutes', { req = true }), player('you') } }
C{ cmd = 'adddynatime', page = 'currency', desc = 'Add minutes to a Dynamis timer.', args = { int('Minutes', { req = true }), player('you') } }

-- Key Items & Titles ----------------------------------------------------------------------------------------------
C{ cmd = 'addkeyitem', page = 'unlocks', desc = 'Give a key item.', args = { pick('Key item', 'keyitems', { req = true }), player('you') } }
C{ cmd = 'delkeyitem', page = 'unlocks', desc = 'Take a key item away.', args = { pick('Key item', 'keyitems', { req = true }), player('you') } }
C{ cmd = 'haskeyitem', page = 'unlocks', desc = 'Check whether a player has a key item.',
   args = { pick('Key item', 'keyitems', { req = true }), player('cursor_pc') } }
C{ cmd = 'addallmaps', page = 'unlocks', desc = 'Give every map.', args = { player('you') } }
C{ cmd = 'addallatma', page = 'unlocks', desc = 'Give every atma.', args = { player('you') } }
C{ cmd = 'addallmounts', page = 'unlocks', desc = 'Give every mount key item.', args = { player('you') } }
C{ cmd = 'mount', page = 'unlocks', desc = 'Put a player on a mount.', args = { pick('Mount', 'mounts', { req = true }), player('you') } }
C{ cmd = 'chocobo', page = 'unlocks', desc = 'Register and ride a chocobo with a chosen look.',
   args = { choice('Color', CHOCO_COLORS, { fill = 'yellow', hint = 'yellow' }), choice('Trait', CHOCO_TRAITS, { hint = 'none' }),
            choice('Trait', CHOCO_TRAITS, { hint = 'none' }), choice('Trait', CHOCO_TRAITS, { hint = 'none' }) } }
C{ cmd = 'addtitle', page = 'unlocks', desc = 'Give and set a title.', args = { pick('Title', 'titles', { req = true }), player('you') } }
C{ cmd = 'hastitle', page = 'unlocks', desc = 'Check whether a player has a title.', args = { pick('Title', 'titles', { req = true }), player('you') } }

-- Quests & Missions -----------------------------------------------------------------------------------------------
local function qlog(o) o = o or {}; if o.req == nil then o.req = true end; return pick('Quest log', 'questlogs', o) end
local function quest(o) o = o or {}; if o.req == nil then o.req = true end; o.log = o.log or 1; return pick('Quest', 'quests', o) end
local function mlog(o) o = o or {}; if o.req == nil then o.req = true end; return pick('Mission log', 'missionlogs', o) end
local function mission(o) o = o or {}; if o.req == nil then o.req = true end; o.log = o.log or 1; return pick('Mission', 'missions', o) end
C{ cmd = 'quest', page = 'quests', desc = 'Open the quest menu: add, complete or delete it, see and clear its vars.',
   args = { qlog(), quest(), player('cursor_pc') } }
C{ cmd = 'addquest', page = 'quests', desc = 'Add a quest to the log.', args = { qlog(), quest(), player('you') } }
C{ cmd = 'completequest', page = 'quests', desc = 'Complete a quest.', args = { qlog(), quest(), player('you') } }
C{ cmd = 'delquest', page = 'quests', desc = 'Delete a quest from the log.', args = { qlog(), quest(), player('you') } }
C{ cmd = 'checkquest', page = 'quests', desc = 'Show a quest\'s status.', args = { qlog(), quest(), player('cursor_pc') } }
C{ cmd = 'getquestvar', page = 'quests', desc = 'Show a quest variable.',
   args = { player('none'), qlog(), quest({ log = 2 }), word('Variable', { req = true }) } }
C{ cmd = 'setquestvar', page = 'quests', desc = 'Set a quest variable.',
   args = { player('none'), qlog(), quest({ log = 2 }), word('Variable', { req = true }), int('Value', { req = true }) } }
C{ cmd = 'mission', page = 'quests', desc = 'Open the mission menu: add, complete or delete it, see its status.',
   args = { mlog(), mission(), player('cursor_pc') } }
C{ cmd = 'addmission', page = 'quests', desc = 'Add a mission.', args = { mlog(), mission(), player('you') } }
C{ cmd = 'completemission', page = 'quests', desc = 'Complete the given mission, if it is the current one.',
   args = { mlog(), mission(), player('you') } }
C{ cmd = 'delmission', page = 'quests', desc = 'Delete a mission.', args = { mlog(), mission(), player('you') } }
C{ cmd = 'checkmission', page = 'quests', desc = 'Show the current mission of a log.', args = { mlog(), player('cursor_pc') } }
C{ cmd = 'checkmissionstatus', page = 'quests', desc = 'Show a mission log\'s status value.',
   args = { player('cursor_pc', { fill = 'me' }), mlog({ req = false, hint = 'your own nation\'s' }), int('Index', { min = 0, max = 7, hint = 'all' }) } }
C{ cmd = 'setmissionstatus', page = 'quests', desc = 'Set a mission log\'s status value.',
   args = { player('cursor_pc', { fill = 'me' }), int('Value', { req = true, min = 0 }), mlog({ req = false, hint = 'your own nation\'s' }),
            int('Index', { min = 0, max = 7, hint = '0' }) } }
C{ cmd = 'completerecord', page = 'quests', desc = 'Complete a Records of Eminence objective.',
   args = { int('Record id', { req = true, min = 0 }), player('you') } }

-- Nation & Fame ---------------------------------------------------------------------------------------------------
C{ cmd = 'setplayernation', page = 'nation', desc = 'Set a player\'s home nation (mission vars are left as they are).',
   args = { player('you', { shift = true }), choice('Nation', HOME_NATIONS, { req = true }) } }
C{ cmd = 'setrank', page = 'nation', desc = 'Set a player\'s nation rank.', args = { player('none'), int('Rank', { req = true, min = 1, max = 10 }) } }
C{ cmd = 'setallegiance', page = 'nation', desc = 'Set a player\'s allegiance.',
   args = { pick('Allegiance', 'allegiances', { req = true }), player('cursor') } }
C{ cmd = 'cnation', page = 'nation', desc = 'Show or change a player\'s Campaign allegiance.',
   args = { player('none'), choice('Allegiance', CAMPAIGN, { hint = 'show it' }) } }
C{ cmd = 'getfame', page = 'nation', desc = 'Show a player\'s fame (every area, or one).',
   args = { player('cursor_pc', { fill = 'me' }), pick('Area', 'fame', { hint = 'every area' }) },
   note = 'With no area the server lists YOUR fame, whoever is named (its bug): pick an area for theirs.' }
C{ cmd = 'setfamelevel', page = 'nation', desc = 'Set a player\'s fame level in an area.',
   args = { pick('Area', 'fame', { req = true }), int('Level', { req = true, min = 0, max = 9 }), player('you') } }
C{ cmd = 'garrison', page = 'nation', desc = 'Start, stop or win a garrison in your zone.',
   args = { choice('Command', GARRISON, { req = true }), player('cursor') } }
C{ cmd = 'updateconquest', page = 'nation', desc = 'Update every conquest guard (after changing the database).',
   args = { int('Update type', { req = true, min = 0 }) } }

-- Travel ----------------------------------------------------------------------------------------------------------
C{ cmd = 'zone', page = 'travel', desc = 'Go to a zone.', args = { pick('Zone', 'zones', { req = true }) } }
C{ cmd = 'goto', page = 'travel', desc = 'Go to a player, in any zone.',
   args = { player('none'), choice('Zone in', ZONE_IN, { hint = 'yes' }) } }
C{ cmd = 'bring', page = 'travel', desc = 'Bring a player to you.', args = { player('none'), choice('Zone in', ZONE_IN, { hint = 'yes' }) } }
C{ cmd = 'send', page = 'travel', desc = 'Send a player to another player, or to a zone.',
   args = { player('none'), word('To (player or zone id)', { req = true, target = 'name' }) } }
C{ cmd = 'gotoname', page = 'travel', desc = 'Go to a mob or NPC by name in your zone.',
   args = { word('Name', { req = true, target = 'name' }), int('Which', { min = 1, hint = 'first' }) } }
C{ cmd = 'gotoid', page = 'travel', desc = 'Go to a mob or NPC by its id.', args = { entity('Mob or NPC id', { req = true }) } }
C{ cmd = 'pos', page = 'travel', desc = 'Show a position (no coordinates), or move someone to one.',
   args = { num('X'), num('Y'), num('Z'), pick('Zone', 'zones', { hint = 'theirs' }), player('you') },
   note = 'With no coordinates it prints the player\'s position: X Y Z, rotation, zone.', pos = true }
C{ cmd = 'where', page = 'travel', desc = 'Show your position.' }
C{ cmd = 'return', page = 'travel', desc = 'Send a player back to their previous zone.', args = { player('you') } }
C{ cmd = 'gmhome', page = 'travel', desc = 'Go to the GM home zone (210).' }
C{ cmd = 'up', page = 'travel', desc = 'Move someone (or your cursor target) up.', args = { int('Yalms', { hint = '1', fill = '1' }), player('cursor') } }
C{ cmd = 'down', page = 'travel', desc = 'Move someone (or your cursor target) down.', args = { int('Yalms', { hint = '1', fill = '1' }), player('cursor') } }
C{ cmd = 'getprevzoneline', cursor = 'any', page = 'travel', desc = 'Show the id of your last zone line (or your cursor target\'s).' }
C{ cmd = 'instance', page = 'travel', desc = 'Load an instance and go there.', args = { int('Instance id', { req = true, min = 1 }) } }

-- Mobs ------------------------------------------------------------------------------------------------------------
C{ cmd = 'spawnmob', page = 'mobs', desc = 'Spawn a mob at its spawn point.',
   args = { entity('Mob id', { req = true }), int('Despawn (s)', { min = 0, fill = '0', hint = 'never' }), int('Respawn (s)', { min = 0, hint = 'default' }) } }
C{ cmd = 'despawnmob', page = 'mobs', desc = 'Despawn a mob.', args = { entity('Mob id', { hint = 'cursor target' }) } }
C{ cmd = 'mobhere', page = 'mobs', desc = 'Spawn a mob if needed and bring it to you.',
   args = { entity('Mob id', { hint = 'cursor target', fill = 'target' }), choice('Keep spawned', { { '1', 'Yes' } }, { hint = 'no' }) } }
C{ cmd = 'hp', title = 'Mob HP', page = 'mobs', desc = 'Set your cursor target\'s HP (0 kills).',
   args = { int('HP', { req = true, min = 0 }) }, cursor = 'mob', presets = { { 'Kill', { '0' } }, { '1 HP', { '1' } } } }
C{ cmd = 'setmoblevel', page = 'mobs', desc = 'Set your cursor target mob\'s level.', args = { int('Level', { req = true, min = 1, max = 255 }) },
   cursor = 'mob', presets = { { 'Level 1', { '1' } } } }
C{ cmd = 'mobskill', page = 'mobs', desc = 'Make a mob use a mob skill.',
   args = { int('Skill id', { req = true, min = 0 }), entity('Mob id', { hint = 'cursor target', fill = 'target' }), int('TP', { min = 0, max = 3000, hint = 'current' }) } }
C{ cmd = 'getmobaction', page = 'mobs', desc = 'Show a mob\'s current action.', args = { entity('Mob id', { hint = 'cursor target' }) } }
C{ cmd = 'getmobflags', page = 'mobs', desc = 'Show a mob\'s entity flags.', args = { entity('Mob id', { hint = 'cursor target' }) } }
C{ cmd = 'setmobflags', page = 'mobs', desc = 'Set a mob\'s name flags.',
   args = { word('Flags', { req = true, hint = 'a number, 0x.. too' }), entity('Mob id', { hint = 'cursor target' }) } }
C{ cmd = 'setmobmod', page = 'mobs', desc = 'Set a mob modifier on your cursor target mob.',
   args = { pick('Mob mod', 'mobmods', { req = true, send = 'name' }), int('Value', { req = true }) }, cursor = 'mob' }
C{ cmd = 'getmobmod', page = 'mobs', desc = 'Show a mob modifier on your cursor target.',
   args = { pick('Mob mod', 'mobmods', { req = true, send = 'name' }) }, cursor = 'mob' }
C{ cmd = 'getenmity', page = 'mobs', desc = 'Show your cursor target mob\'s enmity toward you (CE and VE).', cursor = 'mob' }
C{ cmd = 'getta', page = 'mobs', desc = 'Show who Trick Attack would pick against your cursor target.', cursor = 'mob' }
C{ cmd = 'mobsub', page = 'mobs', desc = 'Change a mob\'s sub-animation.',
   args = { entity('Mob id', { shift = true, hint = 'cursor target' }), int('Animation', { req = true, min = 0 }) } }
C{ cmd = 'provokeall', page = 'mobs', desc = 'Every mob in the zone targets you, at 3000 TP.', danger = true }
C{ cmd = 'fafnir', page = 'mobs', desc = 'Summon a fightable Fafnir (no loot).' }

-- NPCs & Entities -------------------------------------------------------------------------------------------------
C{ cmd = 'npchere', page = 'npcs', desc = 'Spawn an NPC if needed and bring it to you.',
   args = { entity('NPC id', { hint = 'cursor target', fill = 'target' }), choice('Keep spawned', { { '1', 'Yes' } }, { hint = 'no' }) } }
C{ cmd = 'animatenpc', page = 'npcs', desc = 'Change an NPC\'s animation.',
   args = { entity('NPC id', { shift = true, hint = 'cursor target' }), int('Animation', { req = true, min = 0 }) } }
C{ cmd = 'animatesubnpc', page = 'npcs', desc = 'Change an NPC\'s sub-animation.',
   args = { entity('NPC id', { shift = true, hint = 'cursor target' }), int('Animation', { req = true, min = 0 }) } }
C{ cmd = 'rename', page = 'npcs', desc = 'Rename an NPC or mob (16 characters, one word).',
   args = { word('Name', { req = true }), entity('NPC or mob id', { hint = 'cursor target' }) } }
C{ cmd = 'getid', cursor = 'any', page = 'npcs', desc = 'Show your cursor target\'s server id.' }
C{ cmd = 'getstats', cursor = 'any', page = 'npcs', desc = 'Show your cursor target\'s stats.', args = { choice('Stats', STATS, { hint = 'base' }) } }
C{ cmd = 'getlocalvars', cursor = 'any', page = 'npcs', desc = 'List your cursor target\'s local variables.' }

-- Appearance & World ----------------------------------------------------------------------------------------------
C{ cmd = 'hide', page = 'world', desc = 'Toggle GM hide: other players can\'t see you.', args = { choice('Mode', HIDE, { hint = 'toggle' }) } }
C{ cmd = 'togglegm', page = 'world', desc = 'Toggle your GM name flag and icon.' }
C{ cmd = 'wallhack', page = 'world', desc = 'Toggle walking through walls.', args = { player('you') } }
C{ cmd = 'speed', page = 'world', desc = 'Set your movement speed (0 back to normal, below 0 binds).',
   args = { int('Speed', { min = -1, max = 255, hint = 'show current' }) },
   presets = { { 'Normal', { '0' } }, { 'Fast', { '80' } }, { 'Very fast', { '150' } }, { 'Bind', { '-1' } } } }
C{ cmd = 'animation', page = 'world', desc = 'Set your current animation.', args = { pick('Animation', 'animations', { hint = 'show current' }) } }
C{ cmd = 'costume', page = 'world', desc = 'Wear a costume (0 takes it off).', args = { int('Costume id', { req = true, min = 0 }) } }
C{ cmd = 'costume2', page = 'world', desc = 'Wear a costume (costume2).', args = { int('Costume id', { req = true, min = 0 }) } }
C{ cmd = 'setplayermodel', page = 'world', desc = 'Change how a player looks, by model id and slot (testing).',
   args = { int('Model', { req = true, min = 0 }), int('Slot', { req = true, min = 0 }), player('you') } }
C{ cmd = 'entityvisual', page = 'world', desc = 'Play an entity visual (its 4-letter animation string).',
   args = { text('Visual', { req = true }) } }
C{ cmd = 'posemannequin', page = 'world', desc = 'Change a mannequin\'s pose.',
   args = { int('Race', { req = true, min = 0 }), int('Pose', { req = true, min = 0 }), player('cursor') } }
C{ cmd = 'setmusic', page = 'world', desc = 'Change your music for now.',
   args = { choice('Type', MUSIC_TYPES, { req = true }), int('Song id', { req = true, min = 0 }) } }
C{ cmd = 'setweather', page = 'world', desc = 'Set your zone\'s weather.', args = { pick('Weather', 'weather', { req = true }) } }
C{ cmd = 'time', page = 'world', desc = 'Show the time: Vana\'diel and Earth.' }

-- Variables -------------------------------------------------------------------------------------------------------
C{ cmd = 'checkvar', page = 'vars', desc = 'Show a character variable (or a server one: owner "server").',
   args = { word('Owner', { shift = true, hint = 'cursor player or you', target = 'name', cursor = true }), word('Variable', { req = true }) } }
C{ cmd = 'setplayervar', page = 'vars', desc = 'Set a character variable.',
   args = { player('none'), word('Variable', { req = true }), int('Value', { req = true }) } }
C{ cmd = 'checklocalvar', page = 'vars', desc = 'Show a local variable on a player, mob or NPC.',
   args = { word('Variable', { req = true }), choice('On', VAR_OWNERS, { req = true }), word('Name or id', { req = true, target = 'name_or_id' }) } }
C{ cmd = 'setlocalvar', page = 'vars', desc = 'Set a local variable on a player, mob or NPC.',
   args = { word('Variable', { req = true }), int('Value', { req = true }), choice('On', VAR_OWNERS, { req = true }),
            word('Name or id', { req = true, target = 'name_or_id' }) } }

-- Events & Debug --------------------------------------------------------------------------------------------------
local OPS = {}
for i = 1, 8 do OPS[i] = int('Param ' .. i, { fill = '0', adv = i > 2 }) end
C{ cmd = 'cs', page = 'debug', desc = 'Play a cutscene (event) for yourself.',
   args = with({ int('Cutscene id', { req = true, min = 0 }) }, with(OPS, { int('Text table', { adv = true }) })) }
do
    local strings = {}
    for i = 1, 4 do strings[i] = word('String ' .. i, { fill = '0', adv = i > 1 }) end
    C{ cmd = 'cs2', page = 'debug', desc = 'Play a cutscene with strings and params.',
       args = with({ int('Cutscene id', { req = true, min = 0 }) }, with(strings, OPS)) }
end
C{ cmd = 'menu', page = 'debug', desc = 'Show a test menu with three options.' }
C{ cmd = 'menu_paginated', page = 'debug', desc = 'Show a paginated test menu.' }
C{ cmd = 'minigame', page = 'debug', desc = 'Open the minigame test menu.' }
C{ cmd = 'chocoboraising', page = 'debug', desc = 'Open the chocobo raising debug menu.' }
C{ cmd = 'messagebasic', page = 'debug', desc = 'Inject a message basic packet.',
   args = { int('Message id', { req = true, min = 0 }), int('Param 1', { fill = '0' }), int('Param 2') } }
C{ cmd = 'messagespecial', page = 'debug', desc = 'Inject a message special packet.',
   args = { int('Message id', { req = true, min = 0 }), int('Param 1', { fill = '0' }), int('Param 2', { fill = '0' }),
            int('Param 3', { fill = '0', adv = true }), int('Param 4', { adv = true }) },
   note = 'The server reads four params (its usage lists five, but its parameters stop at the fourth).' }
C{ cmd = 'messagestandard', page = 'debug', desc = 'Inject a standard message packet.', args = { int('Message id', { req = true, min = 0 }) } }
C{ cmd = 'injectaction', page = 'debug', desc = 'Inject an action packet (action and animation id).',
   args = { int('Action id', { req = true, min = 0 }), int('Animation id', { req = true, min = 0 }), int('Info', { fill = '0' }),
            int('Reaction', { fill = '0' }), int('Message', { adv = true }) } }
C{ cmd = 'inject', page = 'debug', desc = 'Inject a packet from a file on the server.', args = { text('Packet file', { req = true }) } }
C{ cmd = 'exec', page = 'debug', desc = 'Run a line of Lua on the server: `player` is you, `target` your cursor target.',
   args = { text('Lua', { req = true }) }, note = 'One line. Mind the 120-byte limit.' }
C{ cmd = 'checkinstance', page = 'debug', desc = 'Show the progress and stage of your instance.' }
C{ cmd = 'setprogress', page = 'debug', desc = 'Set the progress of your instance.', args = { int('Progress', { req = true, min = 0 }) } }
C{ cmd = 'setstage', page = 'debug', desc = 'Set the stage of your instance.', args = { int('Stage', { req = true, min = 0 }) } }
C{ cmd = 'setbattlefieldtime', page = 'debug', desc = 'Set the time limit of your battlefield.', args = { int('Minutes', { req = true, min = 1 }) } }
C{ cmd = 'getfishers', page = 'debug', desc = 'List the players who fished lately.', args = { int('Minutes back', { req = true, min = 1 }) } }
C{ cmd = 'ah', page = 'debug', desc = 'Open the auction house menu anywhere.' }
C{ cmd = 'uptime', page = 'debug', desc = 'Show your zone\'s uptime.' }
C{ cmd = 'build', page = 'debug', desc = 'Show the server\'s build information.' }
C{ cmd = 'checkinteraction', page = 'debug', desc = 'Check the interaction framework (a handler, or all).',
   args = { word('Handler', { hint = 'all' }) } }

-- Moderation ------------------------------------------------------------------------------------------------------
C{ cmd = 'jail', page = 'moderation', desc = 'Send a player to jail (Mordion Gaol).',
   args = { player('none'), int('Cell', { min = 1, max = 32, fill = '0', hint = 'cell 1' }), word('Reason', { hint = 'Unspecified' }) },
   danger = true, note = 'The reason is one word: the server reads only the first.' }
C{ cmd = 'pardon', page = 'moderation', desc = 'Release a player from jail.', args = { player('none') } }
C{ cmd = 'yell', page = 'moderation', desc = 'Ban or unban a player from /yell.',
   args = { choice('Action', YELL, { req = true }), player('none'), int('Days', { min = 0, hint = 'forever' }) } }
C{ cmd = 'logoff', page = 'moderation', desc = 'Log a player off by force.', args = { player('you') }, danger = true }
C{ cmd = 'posfix', page = 'moderation', desc = 'Reset a player\'s session and warp them to Jeuno.', args = { player('none') }, danger = true }
C{ cmd = 'afkcheck', cursor = 'any', page = 'moderation', desc = 'Send an AFK check menu to your cursor target.' }
C{ cmd = 'promote', page = 'moderation', desc = 'Set a player\'s GM level.',
   args = { player('none'), int('GM level', { req = true, min = 0, max = 5 }) }, danger = true }
C{ cmd = 'racechange', page = 'moderation', desc = 'Make a player eligible for the race change service.',
   args = { player('cursor_pc') }, danger = true }
C{ cmd = 'breaklinkshell', page = 'moderation', desc = 'Break a linkshell, with all its pearls and sacks.',
   args = { text('Linkshell', { req = true }) }, danger = true }

-- Server ----------------------------------------------------------------------------------------------------------
C{ cmd = 'reloadglobal', page = 'server', desc = 'Reload a global Lua file without a restart.',
   args = { word('Global', { req = true }), word('Other', { adv = true }) } }
C{ cmd = 'reloadquest', page = 'server', desc = 'Reload a quest Lua file.', args = { text('Quest file', { req = true }) } }
C{ cmd = 'reloadbattlefield', page = 'server', desc = 'Reload a battlefield Lua file.', args = { text('Battlefield file', { req = true }) } }
C{ cmd = 'reloaddefaultactions', page = 'server', desc = 'Reload the default actions of your zone (or all zones).',
   args = { choice('Zones', { { 'true', 'All zones' } }, { hint = 'this zone' }) } }
C{ cmd = 'reloadinteraction', page = 'server', desc = 'Reload the interaction framework.',
   args = { choice('Data', { { 'true', 'Reload data too' } }, { hint = 'no' }) } }
C{ cmd = 'reloadmagians', page = 'server', desc = 'Reload the Magian listeners.' }
C{ cmd = 'reloadnavmesh', page = 'server', desc = 'Reload your zone\'s navmesh.' }
C{ cmd = 'reloadrecipes', page = 'server', desc = 'Reload the crafting recipes from the database.' }
C{ cmd = 'givebonanzapearl', page = 'server', desc = 'Give a Mog Bonanza pearl with a number.',
   args = { player('none'), int('Number', { req = true, min = 0, max = 99999 }), int('Event', { req = true, min = 0 }) } }
C{ cmd = 'addtime', page = 'server', desc = 'Reset the server\'s Earth clock and add an offset in seconds.',
   args = { int('Seconds', { req = true }) }, danger = true }
C{ cmd = 'packetmod', page = 'server', desc = 'Add a modifier for server-to-client packets.',
   args = { word('Operation', { req = true }), word('Packet id', { req = true }), word('Offset', { req = true }), word('Value', { req = true }) },
   danger = true }
C{ cmd = 'gc_step', page = 'server', desc = 'Run one Lua garbage collection step.' }
C{ cmd = 'gc_full', page = 'server', desc = 'Run a full Lua garbage collection.', danger = true }
C{ cmd = 'sleep', page = 'server', desc = 'Stall the server for a second (local performance tests only).', danger = true }
C{ cmd = 'crash', page = 'server', desc = 'Crash the map server.', danger = true }

-- Lookups ---------------------------------------------------------------------------------------------------------

-- Each command's key: its name, or name:title for a second form of one (Mob HP).
for _, c in ipairs(list) do
    c.key = c.title and (c.cmd .. ':' .. c.title) or c.cmd
    c.args = c.args or {}
    c.title = c.title or ('!' .. c.cmd)
end

catalog.by_key = {}
for _, c in ipairs(list) do catalog.by_key[c.key] = c end

catalog.page_of = {}
for _, p in ipairs(catalog.PAGES) do catalog.page_of[p[1]] = { id = p[1], title = p[2], blurb = p[3], commands = {} } end
for _, c in ipairs(list) do
    local p = catalog.page_of[c.page]
    assert(p, 'no page ' .. tostring(c.page) .. ' for ' .. c.key)
    p.commands[#p.commands + 1] = c
end

-- The window's pages that aren't a group of commands, by id, with the title the sidebar shows.
catalog.TOOL_PAGES = { { 'favorites', 'Favorites' }, { 'console', 'Console' }, { 'history', 'History' },
                       { 'settings', 'Settings' }, { 'target', 'Target' }, { 'players', 'Players' }, { 'nearby', 'Nearby' },
                       { 'zones', 'Zone Browser' }, { 'macros', 'Macros' }, { 'places', 'Places' } }

-- The page `s` names (/gmt page): its id or title, any case; a whole one first, else the first a prefix of fits, in
-- the order Favorites, Console, History, Settings, the command pages, then Target, Nearby, Zone Browser, Macros,
-- Places (so 'pl' is still Player, as before the last five could be named). Nil for none.
function catalog.page_named(s)
    s = util_trim(s):lower()
    if s == '' then return nil end
    local pages = {}
    for i = 1, 4 do pages[#pages + 1] = catalog.TOOL_PAGES[i] end
    for _, p in ipairs(catalog.PAGES) do pages[#pages + 1] = p end
    for i = 5, #catalog.TOOL_PAGES do pages[#pages + 1] = catalog.TOOL_PAGES[i] end
    for _, p in ipairs(pages) do
        if p[1] == s or p[2]:lower() == s then return p[1] end
    end
    for _, p in ipairs(pages) do
        if p[1]:sub(1, #s) == s or p[2]:lower():sub(1, #s) == s then return p[1] end
    end
end

-- The commands whose name, title, description or note holds every word of `q` (any case).
function catalog.search(q)
    local want = {}
    for w in tostring(q or ''):lower():gmatch('%S+') do want[#want + 1] = (w:gsub('^!', '')) end
    if #want == 0 then return {} end
    local out = {}
    for _, c in ipairs(list) do
        local hay = (c.cmd .. ' ' .. c.title .. ' ' .. (c.desc or '') .. ' ' .. (c.note or '')):lower()
        local all = true
        for _, w in ipairs(want) do if not hay:find(w, 1, true) then all = false break end end
        if all then out[#out + 1] = c end
    end
    -- A command whose name starts with the first word comes first.
    table.sort(out, function (a, b)
        local pa, pb = a.cmd:sub(1, #want[1]) == want[1], b.cmd:sub(1, #want[1]) == want[1]
        if pa ~= pb then return pa end
        return a.cmd < b.cmd
    end)
    return out
end

return catalog
