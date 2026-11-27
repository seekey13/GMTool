--[[
    Macros and places. Pure: what it knows of the game comes in `ctx` (core/build.lua's, plus `pos`).

    A macro is { name, lines = { '!hp 99999 {who}', ... } }: its lines sent in order through the one queue, each
    {word} first replaced:
        {who}     whom an empty player box means now (Acting on: you, your target, the typed name)
        {me}      your name
        {target}  your target's name (a player)
        {tid}     your target's server id (a mob or NPC: what !gotoid, !despawnmob take)
        {x} {y} {z} {zone}  where you stand, as the server reads it, and your zone's id
    A line that can't be made (no target for {target}, say) stops the whole macro before anything goes.

    A place is { name, x, y, z, zone }: where you stood when you saved it, to !pos yourself or a player back to.
]]--

local build = require('core.build')
local util = require('core.util')

local macros = {}

macros.MAX_LINES = 20

-- A coordinate as !pos takes it: up to 3 decimals, no trailing zeros.
function macros.coord(n)
    local s = ('%.3f'):format(n):gsub('0+$', ''):gsub('%.$', '')
    if s == '-0' then s = '0' end
    return s
end

-- The value of {word} now, or nil and why.
local function value(word, ctx)
    local t = ctx.target
    if word == 'me' then
        if ctx.me then return ctx.me end
        return nil, 'you aren\'t logged in'
    elseif word == 'who' then
        local mode = ctx.mode or 'target'
        if mode == 'none' then return nil, 'Acting on: None names no one: use {me}, or pick a mode' end
        if mode == 'party' then return nil, 'Acting on: Party: run the macro (each member gets its {who} lines)' end
        if mode == 'me' then return ctx.me or nil, 'you aren\'t logged in' end
        if mode == 'name' then
            local n = util.trim(ctx.name)
            if n ~= '' then return n end
            return nil, 'type a name in Acting on'
        end
        if t and t.kind == 'pc' then return t.name end
        return nil, 'target a player for {who} (Acting on: Target)'
    elseif word == 'target' then
        if t and t.kind == 'pc' then return t.name end
        return nil, 'target a player for {target}'
    elseif word == 'tid' then
        if t and t.sid then return tostring(t.sid) end
        return nil, 'target something for {tid}'
    elseif word == 'x' or word == 'y' or word == 'z' then
        local p = ctx.pos
        if p and p[word] then return macros.coord(p[word]) end
        return nil, 'your position isn\'t known yet (move a step)'
    elseif word == 'zone' then
        if ctx.zone then return tostring(ctx.zone) end
        return nil, 'your zone isn\'t known'
    end
    return nil, ('no {%s}: use {who} {me} {target} {tid} {x} {y} {z} {zone}'):format(word)
end
macros.value = value

-- `line` with its {words} replaced, tidied and checked: the line, or nil and why.
function macros.expand(line, ctx)
    local why
    local out = tostring(line or ''):gsub('{(%a+)}', function (w)
        if why then return '' end
        local v, err = value(w:lower(), ctx)
        if not v then why = err return '' end
        return v
    end)
    if why then return nil, why end
    if util.trim(out) == '' then return nil, 'an empty line' end
    return build.tidy(out)
end

-- Every line of macro `m` expanded: the lines, or nil and why (the line it failed on, from 1).
-- Whether `line` is one of the commands that ask twice (core/catalog.lua's danger).
function macros.risky(line)
    local name = (tostring(line):match('^!?(%S+)') or ''):lower()
    for _, c in ipairs(require('core.catalog').list) do
        if c.cmd == name and c.danger then return true end
    end
    return false
end

local function has_who(l) return l:lower():find('{who}', 1, true) ~= nil end

-- The lines of `m` that `keep(i, l)` keeps (every one, for none), expanded: lines, risky; or nil, why, line number.
local function expand_all(m, ctx, keep)
    local out, risky = {}, false
    for i, l in ipairs(m.lines or {}) do
        if util.trim(l) ~= '' then
            if macros.risky(util.trim(l)) then
                risky = true
                if has_who(l) or l:lower():find('{target}', 1, true) then
                    return nil, ('line %d: a risky command never takes its name from {who} or {target}: type it'):format(i), i
                end
            end
            if not keep or keep(i, l) then
                local line, why = macros.expand(l, ctx)
                if not line then return nil, ('line %d: %s'):format(i, why), i end
                out[#out + 1] = line
            end
        end
    end
    return out, risky
end

-- Every line of macro `m` expanded: lines, risky (one is: its Run asks twice, and /gmt macro won't run it), fans (it
-- goes to more than one member of a party: its Run asks twice too); or nil, why and the line it failed on (from 1).
-- A risky command never takes its name from {who} or {target}: the macro must spell it.
-- Under Acting on: Party (ctx.party: you, then your party), the lines from its first {who} line to its last go for
-- each member in turn, with their name in {who}; those of them without {who} go with the first member only, so a
-- toggle (!hide) isn't flipped back. The lines before go once first, the lines after once last. A `notself`
-- command (!bring {who}) leaves you out; a `one` (!goto {who}) can't go to a party: type the name.
function macros.lines(m, ctx)
    local first, last
    for i, l in ipairs(m.lines or {}) do
        if has_who(l) then first, last = first or i, i end
    end
    if ctx.mode ~= 'party' or not first then
        local out, risky, at = expand_all(m, ctx)
        if not out then return nil, risky, at end
        if #out == 0 then return nil, 'no lines' end
        return out, risky, false
    end
    for i = first, last do
        local l = util.trim(m.lines[i])
        if has_who(l) and build.flag(l, 'one') then
            return nil, ('line %d: %s goes to one player: type the name, not {who}'):format(i, l:match('^!?%S+')), i
        end
    end
    if #(ctx.party or {}) == 0 then return nil, 'Acting on: Party has no one in it (log in)' end
    local me = ctx.me and ctx.me:lower()
    local out, risky, members = {}, false, 0
    local function run(c, keep, who)
        local lines, r, at = expand_all(m, c, keep)
        if not lines then return nil, who and ('%s (for %s)'):format(r, who) or r, at end
        risky = risky or r
        for _, x in ipairs(lines) do out[#out + 1] = x end
        return #lines
    end
    local ok, why, at = run(ctx, function (i) return i < first end)
    if not ok then return nil, why, at end
    for k, n in ipairs(ctx.party) do
        local one = {}
        for key, v in pairs(ctx) do one[key] = v end
        one.mode, one.name = 'name', n
        local mine = me ~= nil and n:lower() == me
        local got
        got, why, at = run(one, function (i, l)
            if i < first or i > last then return false end
            if not has_who(l) then return k == 1 end
            return not (mine and build.flag(util.trim(l), 'notself'))
        end, n)
        if not got then return nil, why, at end
        local named = false
        for i = first, last do
            if has_who(m.lines[i]) and not (mine and build.flag(util.trim(m.lines[i]), 'notself')) then named = true end
        end
        if named then members = members + 1 end
    end
    ok, why, at = run(ctx, function (i) return i > last end)
    if not ok then return nil, why, at end
    if #out == 0 then return nil, 'no lines' end
    return out, risky, members > 1
end

-- The macro named `name` (any case) in `list`, and its index.
function macros.find(list, name)
    name = util.trim(name):lower()
    for i, m in ipairs(list or {}) do
        if util.trim(m.name):lower() == name then return m, i end
    end
end

-- A name not yet in `list`: `base`, else 'base 2', 'base 3'...
function macros.fresh_name(list, base)
    if not macros.find(list, base) then return base end
    local n = 2
    while macros.find(list, base .. ' ' .. n) do n = n + 1 end
    return base .. ' ' .. n
end

macros.EXAMPLES = {
    { name = 'Restore', lines = { '!hp 99999 {who}', '!mp 99999 {who}', '!tp 3000 {who}' } },
    { name = 'Revive here', lines = { '!raise 3 {who}' } },
    { name = 'Bring and restore', lines = { '!bring {who}', '!hp 99999 {who}', '!mp 99999 {who}' } },
    { name = 'Go incognito', lines = { '!hide', '!togglegm' } },
    { name = 'Punching bag', lines = { '!setmoblevel 1', '!hp 99999' } },
}

-- Places ----------------------------------------------------------------------------------------------------

-- The line that puts `who` (nil: you) at place `p`. `here`: the zone they are in now, when known: the same zone
-- as the place's leaves the zone out, as !pos with a zone always zones them in (a loading screen, trusts gone).
function macros.place_line(p, who, here)
    local line = ('!pos %s %s %s'):format(macros.coord(p.x), macros.coord(p.y), macros.coord(p.z))
    if here ~= p.zone then line = line .. ' ' .. p.zone end
    if who and who ~= '' then line = line .. ' ' .. who end
    return line
end

-- A place where you stand: { name, x, y, z, zone }, or nil and why.
function macros.here(name, ctx)
    local p = ctx.pos
    if not (p and p.x and p.y and p.z) then return nil, 'your position isn\'t known yet (move a step)' end
    if not ctx.zone then return nil, 'your zone isn\'t known' end
    name = util.trim(name)
    if name == '' then return nil, 'name the place' end
    return { name = name, x = p.x, y = p.y, z = p.z, zone = ctx.zone }
end

-- Sharing ---------------------------------------------------------------------------------------------------
-- Macros and places as text, to copy and paste (to another character, another GM, a message):
--     [Restore]
--     !hp 99999 {who}
--     !mp 99999 {who}
--     @ Jeuno AH: -12.5 0 33.25 246
-- A [name] line starts a macro, and the lines after it are its own; an @ line is a place: its name, then after a
-- colon x y z and its zone. Blank lines and # comments are left out.

function macros.export(ms, ps)
    local out = { '# GM Tool: macros ([name], then its lines) and places (@ name: x y z zone)' }
    for _, m in ipairs(ms or {}) do
        out[#out + 1] = '[' .. util.trim(m.name) .. ']'
        for _, l in ipairs(m.lines or {}) do
            if util.trim(l) ~= '' then out[#out + 1] = util.trim(l) end
        end
    end
    for _, p in ipairs(ps or {}) do
        out[#out + 1] = ('@ %s: %s %s %s %d'):format(util.trim(p.name), macros.coord(p.x), macros.coord(p.y), macros.coord(p.z),
            p.zone)
    end
    return table.concat(out, '\n')
end

-- What text `s` holds: macros, places, and the lines it couldn't read ({ line number, why }). Each macro line is
-- checked as a typed line would be (ASCII, within the server's length...), placeholders and all.
function macros.import(s)
    local ms, ps, bad = {}, {}, {}
    local cur
    local n = 0
    for raw in (tostring(s or '') .. '\n'):gmatch('([^\n]*)\n') do
        n = n + 1
        local l = util.trim(raw:gsub('\r$', ''))
        if l == '' or l:sub(1, 1) == '#' then  -- luacheck: ignore 542 (nothing to do)
        elseif l:match('^%[.*%]$') then
            local name = util.trim(l:sub(2, -2))
            if name == '' then bad[#bad + 1] = { n, 'a macro needs a name' } cur = nil
            else
                cur = { name = name, lines = {} }
                ms[#ms + 1] = cur
            end
        elseif l:sub(1, 1) == '@' then
            local name, x, y, z, zone = l:match('^@%s*(.-)%s*:%s*(%S+)%s+(%S+)%s+(%S+)%s+(%d+)$')
            x, y, z, zone = tonumber(x), tonumber(y), tonumber(z), tonumber(zone)
            if name and name ~= '' and x and y and z and zone then
                ps[#ps + 1] = { name = name, x = x, y = y, z = z, zone = zone }
            else
                bad[#bad + 1] = { n, 'a place is "@ name: x y z zone"' }
            end
        elseif not cur then
            bad[#bad + 1] = { n, 'a line before any [macro name]' }
        elseif #cur.lines >= macros.MAX_LINES then
            bad[#bad + 1] = { n, ('a macro holds %d lines at most'):format(macros.MAX_LINES) }
        else
            local line, why = build.tidy(l)
            if line then cur.lines[#cur.lines + 1] = line else bad[#bad + 1] = { n, why } end
        end
    end
    local kept = {}
    for _, m in ipairs(ms) do if #m.lines > 0 then kept[#kept + 1] = m end end
    return kept, ps, bad
end

-- Adds `incoming` (macros or places) to `list`: one the same as one there (name and all) is skipped, one whose name
-- is taken gets 'name 2'. `same(a, b)` says whether two are the same. Returns how many were added and skipped.
function macros.merge(list, incoming, same)
    local added, skipped = 0, 0
    for _, x in ipairs(incoming) do
        local have = macros.find(list, x.name)
        if have and same(have, x) then
            skipped = skipped + 1
        else
            if have then x.name = macros.fresh_name(list, x.name) end
            list[#list + 1] = x
            added = added + 1
        end
    end
    return added, skipped
end

function macros.same_macro(a, b)
    if #a.lines ~= #b.lines then return false end
    for i = 1, #a.lines do if util.trim(a.lines[i]) ~= util.trim(b.lines[i]) then return false end end
    return true
end

function macros.same_place(a, b)
    return a.zone == b.zone and macros.coord(a.x) == macros.coord(b.x) and macros.coord(a.y) == macros.coord(b.y)
        and macros.coord(a.z) == macros.coord(b.z)
end
return macros
