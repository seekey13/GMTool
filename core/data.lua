--[[
    The lists a form picks from: the server's enums (data/*.lua, from tools/gen_data.lua), each loaded the first
    time it's wanted, and the client's own names for what the server lists by id alone (items, spells; a zone's
    name as the game spells it). Pure: the client's names come through data.res, which GMTool.lua sets in game
    and the tests fake.

    An entry is { id = number or nil, name = what goes in the line, label = what the list shows, low = label
    lowered for searching }.
]]--

local util = require('core.util')

local data = {}

-- The client's names: each takes an id, gives a name or nil. GMTool.lua points these at Ashita's resource manager.
data.res = {
    item = function () return nil end,
    spell = function () return nil end,
    zone = function () return nil end,
    keyitem = function () return nil end,
}

local loaded = {}

-- data/<name>.lua's table, loaded once.
local function raw(name)
    if loaded[name] == nil then
        local ok, t = pcall(require, 'data.' .. name)
        loaded[name] = ok and t or false
    end
    return loaded[name] or nil
end
data.raw = raw

-- The crafts !setcraftrank and !getcraftrank take: fishing to synergy (48 to 57).
local CRAFTS = { [48] = true, [49] = true, [50] = true, [51] = true, [52] = true, [53] = true, [54] = true,
                 [55] = true, [56] = true, [57] = true }

local function entry(id, name, label)
    label = label or name
    return { id = id, name = name, label = label, low = label:lower() }
end

-- A list from an enum's { id, NAME } pairs: labelled 'Name (id)' unless `plain`.
local function enum(name, o)
    local out = {}
    for _, e in ipairs(raw(name) or {}) do
        local id, n = e[1], e[2]
        if not (o and o.skip and o.skip[id]) and not (o and o.keep and not o.keep[id]) then
            local label = util.pretty(n) .. ' (' .. id .. ')'
            if o and o.label then label = o.label(id, n) or label end
            out[#out + 1] = entry(id, n, label)
        end
    end
    return out
end

local cache = {}

-- The quest or mission logs, as a pick: { id = log id, name = its NAME }.
local function logs(name)
    local out = {}
    for _, l in ipairs(raw(name) or {}) do out[#out + 1] = entry(l.log, l.name, util.pretty(l.name) .. ' (' .. l.log .. ')') end
    return out
end

-- The entries of quest or mission log `log`.
local function in_log(name, log)
    for _, l in ipairs(raw(name) or {}) do
        if l.log == log then
            local out = {}
            for _, e in ipairs(l.entries) do out[#out + 1] = entry(e[1], e[2], util.pretty(e[2]) .. ' (' .. e[1] .. ')') end
            return out
        end
    end
    return {}
end

local BUILDERS = {
    effects = function () return enum('effects') end,
    mods = function () return enum('mods') end,
    mobmods = function () return enum('mobmods') end,
    zones = function ()
        return enum('zones', { label = function (id, n)
            local shown = data.res.zone(id)
            if shown and shown ~= '' then return ('%s (%d)'):format(shown, id) end
            return util.pretty(n) .. ' (' .. id .. ')'
        end })
    end,
    skills = function () return enum('skills', { skip = { [0] = true } }) end,
    crafts = function () return enum('skills', { keep = CRAFTS }) end,
    weather = function () return enum('weather') end,
    keyitems = function ()
        return enum('keyitems', { label = function (id, n)
            local shown = data.res.keyitem(id)
            if shown and shown ~= '' then return ('%s (%d)'):format(shown, id) end
            return util.pretty(n) .. ' (' .. id .. ')'
        end })
    end,
    titles = function () return enum('titles') end,
    mounts = function () return enum('mounts') end,
    nations = function () return enum('nations') end,
    allegiances = function () return enum('allegiances') end,
    animations = function () return enum('animations') end,
    jobs = function ()
        -- not NONE, nor MON (Monstrosity's, not a job a character takes)
        return enum('jobs', { skip = { [0] = true, [23] = true }, label = function (id, n) return n .. ' (' .. id .. ')' end })
    end,
    containers = function () return enum('containers') end,
    fame = function () return enum('fame') end,
    craftranks = function () return enum('craftranks') end,
    currencies = function ()
        local out = {}
        for _, n in ipairs(raw('currencies') or {}) do out[#out + 1] = entry(nil, n, util.pretty(n)) end
        return out
    end,
    questlogs = function () return logs('quests') end,
    missionlogs = function () return logs('missions') end,
}

-- The list for argument `a` (a catalog pick); `log` is the log id a quest or mission list is for.
function data.list(a, log)
    local set = a.set
    if set == 'skills' and a.crafts then set = 'crafts' end
    if set == 'quests' or set == 'missions' then
        local key = set .. ':' .. tostring(log)
        if not cache[key] then cache[key] = log and in_log(set, log) or {} end
        return cache[key]
    end
    if not cache[set] then
        local b = BUILDERS[set]
        cache[set] = b and b() or {}
    end
    return cache[set]
end

-- What a pick of `a` sends for entry `e`: its id, or its name (lower case for 'lower').
function data.value(a, e)
    if a.send == 'name' then return e.name end
    if a.send == 'lower' then return e.name:lower() end
    return e.id and tostring(e.id) or e.name
end

local by_value = setmetatable({}, { __mode = 'k' })  -- [list] = { [send] = { [value] = entry } }

-- The entry of `a`'s list whose value is `v`, or nil. (Looked up in a map made once per list: a pick box asks every
-- frame, and a list may hold thousands.)
function data.find(a, v, log)
    if v == nil or v == '' then return nil end
    local list = data.list(a, log)
    local maps = by_value[list]
    if not maps then maps = {} by_value[list] = maps end
    local key = a.send or 'id'
    local map = maps[key]
    if not map then
        map = {}
        for _, e in ipairs(list) do
            local k = data.value(a, e)
            if map[k] == nil then map[k] = e end
        end
        maps[key] = map
    end
    return map[v]
end

-- At most `limit` entries of `list` whose label holds every word of `q` (any case); every one for an empty q.
-- A number typed alone also finds the entry with that id.
function data.filter(list, q, limit)
    local want = util.words(tostring(q or ''):lower())
    local out, id = {}, tonumber(q)
    limit = limit or 200
    for _, e in ipairs(list) do
        local ok = true
        if id and e.id == id then
            ok = true
        else
            for _, w in ipairs(want) do if not e.low:find(w, 1, true) then ok = false break end end
        end
        if ok then
            out[#out + 1] = e
            if #out >= limit then break end
        end
    end
    return out
end

-- Names by id the client knows: items and spells, indexed a few thousand ids a frame (index.step) so a search
-- never stalls the game. index.items, index.spells: { entries, next = the next id to look at, done }.
data.index = {
    items = { entries = {}, next = 1, last = 65535, res = 'item' },
    spells = { entries = {}, next = 1, last = 1023, res = 'spell' },
}

-- Looks at up to `budget` more ids of index `which`. Returns whether it's done.
function data.step(which, budget)
    local ix = data.index[which]
    if ix.done then return true end
    local stop = math.min(ix.last, ix.next + (budget or 2000) - 1)
    local get = data.res[ix.res]
    for id = ix.next, stop do
        local ok, n = pcall(get, id)
        if ok and type(n) == 'string' and n ~= '' and n ~= '.' then
            ix.entries[#ix.entries + 1] = entry(id, tostring(id), ('%s (%d)'):format(n, id))
        end
    end
    ix.next = stop + 1
    ix.done = ix.next > ix.last
    return ix.done
end

-- The name the client gives item or spell `id`, or nil.
function data.name_of(which, id)
    local ok, n = pcall(data.res[which == 'items' and 'item' or 'spell'], tonumber(id) or -1)
    if ok and type(n) == 'string' and n ~= '' then return n end
end

-- Zone `id`'s name: the client's, else the server's enum name; nil for no such zone.
function data.zone_name(id)
    id = tonumber(id)
    if not id then return nil end
    local ok, n = pcall(data.res.zone, id)
    if ok and type(n) == 'string' and n ~= '' then return n end
    for _, e in ipairs(raw('zones') or {}) do
        if e[1] == id then return util.pretty(e[2]) end
    end
end

-- Forget every list built (the client's names may have changed: a language switch, a test).
function data.reset()
    cache = {}
    for _, ix in pairs(data.index) do ix.entries, ix.next, ix.done = {}, 1, nil end
end

return data
