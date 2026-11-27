--[[
    What GM Tool keeps between loads, per character (Ashita's settings library: config/addons/GMTool/<character>/),
    and the pure rules for changing it: favorites, history, recent names, each form's last values, preferences.
    store.cfg is the live table; store.dirty() marks it for saving, GMTool.lua saves it once nothing is held.
]]--

local util = require('core.util')

local store = {}

store.HISTORY = 100  -- lines kept
store.NAMES = 20     -- recent player names kept

store.DEFAULTS = {
    ui = { open = true, bar = false, page = 'favorites', scale = 100, adv = false, show_server = false, list_rows = 10 },
    send = { mode = 'packet', echo = true, confirm = true },
    acting = { mode = 'target', name = '' },
    gm_level = 0,          -- 0: unknown, nothing dimmed; else commands above it are dimmed
    favorites = {},        -- command keys, in order
    history = {},          -- { line = '!hp 100 Name', t = os.time() }, newest first
    names = {},            -- recent player names, newest first
    forms = {},            -- [command key] = { [arg index] = value }
    macros = {},           -- { name, lines = { '!hp 99999 {who}', ... } } (core/macros.lua)
    places = {},           -- { name, x, y, z, zone }: where you stood, for !pos
    seq = 0,               -- the last stable id given (a macro's, a place's, a history line's `uid`)
}

store.cfg = util.copy(store.DEFAULTS)
local dirty = false

function store.dirty() dirty = true end
function store.is_dirty() return dirty end
function store.clean() dirty = false end

-- Fills in what `cfg` lacks from the defaults (a file from an older version), in place.
function store.complete(cfg, defaults)
    defaults = defaults or store.DEFAULTS
    for k, v in pairs(defaults) do
        if cfg[k] == nil then
            cfg[k] = util.copy(v)
        elseif type(v) == 'table' and type(cfg[k]) == 'table' and next(v) ~= nil and v[1] == nil then
            store.complete(cfg[k], v)
        end
    end
    return cfg
end

-- A new stable id: what a row's buttons are keyed by, so they don't move with the rows.
function store.uid()
    store.cfg.seq = (tonumber(store.cfg.seq) or 0) + 1
    dirty = true
    return store.cfg.seq
end

-- History -------------------------------------------------------------------------------------------------------

-- `line` at the top of the history (a repeat of the newest only updates its time), the oldest past HISTORY gone.
function store.remember(line, now)
    local h = store.cfg.history
    if h[1] and h[1].line == line then
        h[1].t = now
    else
        table.insert(h, 1, { line = line, t = now, uid = store.uid() })
        while #h > store.HISTORY do table.remove(h) end
    end
    dirty = true
end

-- A player name typed or sent: first in the recent names. `soft` (seen in a line) never moves one already there.
function store.name_used(name, soft)
    if type(name) ~= 'string' or not name:match('^%a+$') or #name < 3 or #name > 15 then return end
    local n = store.cfg.names
    for i, v in ipairs(n) do
        if v:lower() == name:lower() then
            if soft then return end
            table.remove(n, i)
            break
        end
    end
    if soft and #n >= store.NAMES then return end
    table.insert(n, 1, name)
    while #n > store.NAMES do table.remove(n) end
    dirty = true
end

-- Favorites -----------------------------------------------------------------------------------------------------

function store.is_favorite(key) return util.contains(store.cfg.favorites, key) end

function store.toggle_favorite(key)
    local f = store.cfg.favorites
    for i, k in ipairs(f) do
        if k == key then table.remove(f, i); dirty = true; return false end
    end
    f[#f + 1] = key
    dirty = true
    return true
end

-- Moves favorite `key` by `delta` places (-1 up, 1 down).
function store.move_favorite(key, delta)
    local f = store.cfg.favorites
    for i, k in ipairs(f) do
        if k == key then
            local j = util.clamp(i + delta, 1, #f)
            if j ~= i then
                f[i], f[j] = f[j], f[i]
                dirty = true
            end
            return
        end
    end
end

-- Forms ---------------------------------------------------------------------------------------------------------

local EMPTY = setmetatable({}, { __newindex = function () error('store.form: change a form with store.set_value', 2) end })

-- Command `key`'s box values, kept as typed: a table of strings by argument index, to read (an empty one for a form
-- never filled, so drawing a card writes nothing to the settings file).
function store.form(key) return store.cfg.forms[key] or EMPTY end

-- Sets box `i` of `key` to `v` ('' clears it).
function store.set_value(key, i, v)
    v = v ~= nil and tostring(v) or ''
    local f = store.cfg.forms[key]
    if (f and f[i] or '') == v then return end
    if not f then
        f = {}
        store.cfg.forms[key] = f
    end
    f[i] = v ~= '' and v or nil
    if next(f) == nil then store.cfg.forms[key] = nil end
    dirty = true
end

function store.clear_form(key)
    if store.cfg.forms[key] then dirty = true end
    store.cfg.forms[key] = nil
end

-- Ashita's settings library (in game only) ----------------------------------------------------------------------

local lib

-- `t` and every table in it as Ashita's T{} tables, as its library expects.
local function T_(t)
    for k, v in pairs(t) do if type(v) == 'table' then t[k] = T_(v) end end
    return T and T(t) or t
end

-- The library fills a key the file lacks with the defaults' own table, and keeps those defaults for the next
-- character's load: give it copies, so what's written into the settings (a favorite) stays out of them.
local function detach(defaults)
    for k, v in pairs(defaults) do
        if type(v) == 'table' then defaults[k] = T_(util.copy(v)) end
    end
end

local cached  -- the defaults the library holds

-- `s` with every table it shares with the library's defaults copied (each character its own), the defaults' tables
-- copied again for the next.
local function own(s)
    if cached then
        for k, v in pairs(cached) do
            if type(v) == 'table' and rawequal(s[k], v) then s[k] = T_(util.copy(v)) end
        end
        detach(cached)
    end
    return s
end

function store.load()
    lib = lib or require('settings')
    cached = T_(util.copy(store.DEFAULTS))
    store.cfg = store.complete(lib.load(cached))
    detach(cached)
    dirty = false
    return store.cfg
end

function store.save()
    if lib then lib.save() end
    dirty = false
end

-- The library loads a new table on a character switch: take it up.
function store.watch()
    if not lib then return end
    lib.register('settings', 'gmtool_settings_update', function (s)
        if s then store.cfg = store.complete(own(s)) end
    end)
end

return store
