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

-- The lines of `m` that `keep(l)` keeps (every one, for none), expanded: lines, risky; or nil, why, line number.
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
            if not keep or keep(l) then
                local line, why = macros.expand(l, ctx)
                if not line then return nil, ('line %d: %s'):format(i, why), i end
                out[#out + 1] = line
            end
        end
    end
    return out, risky
end

-- Every line of macro `m` expanded: the lines and whether any is risky (its Run asks twice, and /gmt macro won't
-- run it); or nil, why and the line it failed on (from 1). A risky command never takes its name from {who} or
-- {target}: the macro must spell it.
-- Under Acting on: Party (ctx.party: you, then your party), each member in turn gets the {who} lines, with its
-- name; a line without {who} goes once, with the first (so a toggle, !hide, isn't flipped back), and a command
-- that needs another player (!bring {who}) leaves you out.
function macros.lines(m, ctx)
    local out, risky
    local fans = false
    for _, l in ipairs(m.lines or {}) do if has_who(l) then fans = true end end
    if ctx.mode == 'party' and fans then
        if #(ctx.party or {}) == 0 then return nil, 'Acting on: Party has no one in it (log in)' end
        out, risky = {}, false
        local me = ctx.me and ctx.me:lower()
        for k, n in ipairs(ctx.party) do
            local one = {}
            for key, v in pairs(ctx) do one[key] = v end
            one.mode, one.name = 'name', n
            local mine = me ~= nil and n:lower() == me
            local lines, r, at = expand_all(m, one, function (l)
                if not has_who(l) then return k == 1 end
                return not (mine and build.needs_name(util.trim(l)))
            end)
            if not lines then return nil, ('%s (for %s)'):format(r, n), at end
            risky = risky or r
            for _, x in ipairs(lines) do out[#out + 1] = x end
        end
    else
        local at
        out, risky, at = expand_all(m, ctx)
        if not out then return nil, risky, at end
    end
    if #out == 0 then return nil, 'no lines' end
    return out, risky
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

return macros
