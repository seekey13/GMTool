--[[
    A command's form, as filled in, made into the line the server reads ('!hp 100 Kupipi'), or why it can't be.
    Pure: what it knows of the game comes in `ctx`. tests/build_test.lua runs it.

    ctx = {
        me     = your name,
        target = your target or nil: { name, kind = 'pc' | 'npc' | 'mob' | 'other', sid = server id, index },
        mode   = whom an empty player box means:
                   'target'  your target if it's a player; a mob or pet for the commands that act on the cursor
                             target; else you, by name
                   'me'      you, by name
                   'name'    ctx.name
                   'none'    no name: the server's own default (your cursor target, or you)
                   'party'   each of ctx.party, a line apiece (build.lines)
        name   = the name for mode 'name',
        party  = for mode 'party': you, then your party and alliance, by name
    }
    A command that needs a name (who 'none': !goto, !giveitem...) takes it from your player target or the typed
    name, never from 'me'; a risky one (c.danger: !jail, !promote, delete inventory...) only from its own box.

    What the server reads (src/map/command_handler.cpp): words split on spaces, by position; a number with atoi.
    So every word here is checked before anything goes: a number is a number, a word has no space, a name is a
    name, the line is ASCII, single-spaced, without a trailing space (the server's reader would repeat the last
    word), and within MAX bytes (the chat packet keeps 128).

    The cursor: a command that reads your cursor target acts on the one the server last heard of (core/game.lua),
    so build says so (info.cursor) and core/send.lua sends the line only while the server has the target you had
    when you clicked.
]]--

local util = require('core.util')

local build = {}

build.MAX = 120

local function fail(fmt, ...) return nil, fmt:format(...) end

-- Whether `s` looks like a character's name: 3 to 15 letters (the server matches any case).
function build.is_name(s) return type(s) == 'string' and #s >= 3 and #s <= 15 and s:match('^%a+$') ~= nil end

-- Whether argument `a`, left out, has the server read your cursor target instead.
function build.reads_cursor_arg(a)
    if a.cursor then return true end
    if a[2] == 'player' then return a.who == 'cursor' or a.who == 'cursor_pc' end
    return a[2] == 'entity' and a.hint == 'cursor target'
end

-- The name an empty player box of command `c` takes from Acting on: a name, '' for none (the server's default),
-- or nil and why.
function build.default_player(c, a, ctx)
    if c.danger then return nil, 'type the name: a risky command never takes it from Acting on' end
    local mode = ctx.mode or 'target'
    local t = ctx.target
    if mode == 'name' then
        local n = util.trim(ctx.name)
        if n == '' then return nil, 'type a name in Acting on' end
        return n
    end
    if mode == 'none' then return '' end
    if mode == 'party' then  -- a line apiece: build.lines; build.line alone never picks one of them
        return nil, ('each of your party, a line apiece (%d)'):format(#(ctx.party or {}))
    end
    if mode == 'target' and t and t.kind == 'pc' and t.name then return t.name end
    if a.who == 'none' then
        if mode == 'me' then return nil, 'type a name: this command needs one (Acting on: Me never names you here)' end
        return nil, t and ('your target (%s) isn\'t a player: type a name'):format(t.name or '?') or 'target a player or type a name'
    end
    if mode == 'target' and t and a.who == 'cursor' then
        -- a mob or pet goes as your cursor target, with no name; an NPC the server would skip, acting on you
        if t.kind == 'npc' then return nil, ('your target (%s) is an NPC: the server would act on you'):format(t.name or '?') end
        return ''
    end
    -- 'me', or 'target' with no player target: you, by name
    if ctx.me then return ctx.me end
    return nil, 'you aren\'t logged in'
end

-- `<t>`, `<me>`: your target's name (a player), yours; nil for a `<t>` that isn't a player.
local function substitute(v, ctx)
    local low = v:lower()
    if low == '<me>' then return ctx.me end
    if low == '<t>' then
        local t = ctx.target
        if t and t.kind == 'pc' then return t.name end
        return nil
    end
    return v
end

-- `a`'s word from box value `v` (trimmed, possibly ''), or nil and why.
local function word_of(a, v, ctx)
    local kind = a[2]
    if v == '' then return '' end
    if v == '<t>' or v == '<me>' or v:lower() == '<t>' or v:lower() == '<me>' then
        local s = substitute(v, ctx)
        if not s then return fail('%s: <t> is not a player', a[1]) end
        v = s
    end
    if kind == 'player' then
        if not build.is_name(v) then return fail('%s: "%s" is not a character name (3 to 15 letters)', a[1], v) end
        return v
    end
    if kind == 'int' or kind == 'entity' or kind == 'item' or (kind == 'pick' and a.send ~= 'name' and a.send ~= 'lower' and a.set ~= 'currencies') then
        if not util.is_int(v) then return fail('%s: a whole number, not "%s"', a[1], v) end
        local n = tonumber(v)
        if a.min and n < a.min then return fail('%s: %d or more', a[1], a.min) end
        if a.max and n > a.max then return fail('%s: %d or less', a[1], a.max) end
        if a.step and (n - (a.min or 0)) % a.step ~= 0 then return fail('%s: a multiple of %d', a[1], a.step) end
        return tostring(n)
    end
    if kind == 'num' then
        if not util.is_num(v) then return fail('%s: a number, not "%s"', a[1], v) end
        return v
    end
    if kind == 'text' then return v end
    -- word, choice, spell, a pick sent by name
    if v:find('%s') then return fail('%s: one word (the server reads only up to a space)', a[1]) end
    return v
end

-- The value `a` takes when it's left empty but a later one is given: its `fill`, or nil.
local function filled(a, ctx)
    if a.fill == 'me' then return ctx.me end
    if a.fill == 'target' then
        local t = ctx.target
        if t and t.sid and t.kind ~= 'pc' then return tostring(t.sid) end
        return nil
    end
    return a.fill
end

-- The kinds of target a command that acts on your cursor's mob takes (c.cursor == 'mob').
local MOBLIKE = { mob = true, other = true }

--[[ The line for command `c` (a catalog entry) with its boxes' `values` (strings, by argument; nil or '' for empty).
     Returns line, info: info.cursor is true when the server will read your cursor target (a command that acts on it,
     or an argument left for it), so the line should go only while the server has your target; info.names, the
     player names in it. Or nil and why. ]]--
function build.line(c, values, ctx)
    values, ctx = values or {}, ctx or {}
    local args = c.args or {}
    local words, info = {}, { cursor = c.cursor ~= nil, names = {} }
    if c.cursor == 'mob' then
        local t = ctx.target
        if not t then return fail('target a mob first: this acts on your cursor target') end
        if not MOBLIKE[t.kind] then return fail('your target (%s) isn\'t a mob: this acts on your cursor target', t.name or '?') end
    end
    -- Each box's word, a player's default put in.
    for i, a in ipairs(args) do
        local raw = util.trim(values[i])
        if raw == '' and a[2] == 'player' then
            local d, why = build.default_player(c, a, ctx)
            if not d then
                -- an optional player with no default may be left to the server, but never for a risky command
                if a.req or c.danger or ctx.mode ~= 'none' then return fail('%s: %s', a[1], why) end
                d = ''
            end
            raw = d
        end
        local w, why = word_of(a, raw, ctx)
        if not w then return nil, why end
        words[i] = w
        if a[2] == 'player' and w ~= '' then info.names[#info.names + 1] = w end
    end
    if c.pos then
        local x, y, z = words[1] ~= '', words[2] ~= '', words[3] ~= ''
        if (x or y or z) and not (x and y and z) then return fail('X, Y and Z go together') end
        if not x and words[4] ~= '' then return fail('a zone needs X, Y and Z') end
    end
    -- Required ones.
    for i, a in ipairs(args) do
        if a.req and words[i] == '' then return fail('%s is needed', a[1]) end
    end
    -- By position: up to the last given, each empty one is filled, or left out where the server can tell.
    local last = 0
    for i = 1, #args do if words[i] ~= '' then last = i end end
    -- !pos reads its words by how many there are: a name alone prints theirs, x y z [zone] [name] moves them.
    local omit = {}
    if c.pos then
        if words[1] == '' then omit[1], omit[2], omit[3], omit[4] = true, true, true, true
        elseif words[4] == '' then omit[4] = true end
    end
    local out, left = {}, {}
    for i = 1, #args do
        local a, w = args[i], words[i]
        if i > last then
            left[i] = true
        elseif w == '' then
            if a.shift or omit[i] then
                w, left[i] = nil, true
            else
                w = filled(a, ctx)
                if not w or w == '' then
                    local later
                    for j = i + 1, last do if words[j] ~= '' then later = args[j][1] break end end
                    return fail('%s is needed to give %s', a[1], later or 'what follows')
                end
            end
        end
        if w and i <= last then out[#out + 1] = w end
    end
    -- What reads the cursor: an argument left out that the server then takes from it.
    for i, a in ipairs(args) do
        if left[i] and build.reads_cursor_arg(a) then info.cursor = true end
    end
    local line = '!' .. c.cmd .. (#out > 0 and (' ' .. table.concat(out, ' ')) or '')
    local ok, why = build.check(line)
    if not ok then return nil, why end
    return line, info
end

-- Whether command `name` (a line's first word, '!' or not) needs another player named: a form of it has a player
-- box that never means you (who 'none': !goto, !bring, !send...).
function build.needs_name(name)
    name = (tostring(name or ''):match('^!?(%S+)') or ''):lower()
    for _, c in ipairs(require('core.catalog').list) do
        if c.cmd == name then
            for _, a in ipairs(c.args) do if a[2] == 'player' and a.who == 'none' then return true end end
        end
    end
    return false
end

--[[ The lines command `c` sends with `values`: build.line's one, or under Acting on: Party, a line apiece for each
     of ctx.party when a player box is empty (you left out for a command that needs another player; one name the
     same twice, once). A risky command never takes names from Party. Returns lines, info (info.names every name
     in them), or nil and why. ]]--
function build.lines(c, values, ctx)
    values, ctx = values or {}, ctx or {}
    local empty
    if ctx.mode == 'party' then
        for i, a in ipairs(c.args or {}) do
            if a[2] == 'player' and util.trim(values[i]) == '' then empty = a break end
        end
    end
    if not empty then
        local l, info = build.line(c, values, ctx)
        if not l then return nil, info end
        return { l }, info
    end
    if c.danger then return fail('%s: type the name: a risky command never takes it from Acting on', empty[1]) end
    local me = ctx.me and ctx.me:lower()
    local out, seen, info = {}, {}, { cursor = c.cursor ~= nil, names = {}, party = true }
    for _, n in ipairs(ctx.party or {}) do
        if not (empty.who == 'none' and me and n:lower() == me) then
            local one = {}
            for k, v in pairs(ctx) do one[k] = v end
            one.mode, one.name = 'name', n
            local l, why = build.line(c, values, one)
            if not l then return fail('for %s, %s', n, why) end
            if not seen[l] then
                seen[l] = true
                out[#out + 1] = l
                info.names[#info.names + 1] = n
            end
        end
    end
    if #out == 0 then
        return fail('%s: Acting on: Party has no one %s', empty[1], empty.who == 'none' and 'in it but you' or 'in it (log in)')
    end
    return out, info
end

-- Whether `line` can go as it is: ASCII, no line breaks, within MAX bytes, starting with '!'.
function build.check(line)
    if type(line) ~= 'string' or line == '' then return false, 'nothing to send' end
    if line:sub(1, 1) ~= '!' or #line < 2 or line:sub(2, 2):find('%s') then return false, 'a GM command starts with ! and its name' end
    if line:find('[\r\n]') then return false, 'one line only' end
    if line:find('[^\32-\126]') then return false, 'ASCII only (the server reads bytes, not your client\'s text)' end
    if #line > build.MAX then return false, ('%d bytes: the server keeps %d of a line'):format(#line, build.MAX) end
    return true
end

-- Whether a typed `line` acts on your cursor target: a form of its command that could be it (no more words than
-- it takes) does so always, or leaves out an argument the server then takes from the cursor. A leading argument
-- the server can do without (`shift`) counts as the one left out first.
function build.reads_cursor(line)
    local words = util.words(line)
    local name = (words[1] or ''):gsub('^!', ''):lower()
    local given = #words - 1
    for _, c in ipairs(require('core.catalog').list) do
        if c.cmd == name and #c.args >= given then
            if c.cursor then return true end
            local missing = #c.args - given
            local first = 1
            if missing > 0 and c.args[1] and c.args[1].shift then
                if build.reads_cursor_arg(c.args[1]) then return true end
                missing, first = missing - 1, 2
            end
            for i = #c.args - missing + 1, #c.args do
                if i >= first and build.reads_cursor_arg(c.args[i]) then return true end
            end
        end
    end
    return false
end

-- Whether a line that isn't from a form (typed, a macro's, History's, a Target action's) may go with `target` (as
-- core/build.lua's ctx.target): one that reads the cursor in the form of a mob command (Mob HP: a bare !hp) needs a
-- mob or pet there, and one that leaves out a player the server takes from the cursor never goes at an NPC (the
-- server would act on you). Returns true, or false and why.
function build.cursor_check(line, target)
    if not build.reads_cursor(line) then return true end
    local words = util.words(line)
    local name = (words[1] or ''):gsub('^!', ''):lower()
    local given = #words - 1
    for _, c in ipairs(require('core.catalog').list) do
        if c.cmd == name and #c.args == given and c.cursor == 'mob' then
            if not target then return false, ('%s acts on your cursor target: target a mob first'):format(line) end
            if not MOBLIKE[target.kind] then
                return false, ('%s acts on your cursor target, %s, which isn\'t a mob'):format(line, target.name or '?')
            end
            return true
        end
    end
    if target and target.kind == 'npc' then
        for _, c in ipairs(require('core.catalog').list) do
            if c.cmd == name and #c.args > given then
                for i = given + 1, #c.args do
                    local a = c.args[i]
                    if a[2] == 'player' and (a.who == 'cursor' or a.who == 'cursor_pc') then
                        return false, ('%s: your target is an NPC, so the server would act on you'):format(line)
                    end
                end
            end
        end
    end
    return true
end

-- `<t>` and `<me>` in a typed line made your target's name and yours, as the chat box would (a line sent as a
-- packet skips it). Returns the line, or nil and why.
function build.substitute(line, ctx)
    ctx = ctx or {}
    local why
    local out = tostring(line):gsub('<(%a+)>', function (w)
        local low = w:lower()
        if low == 'me' then
            if ctx.me then return ctx.me end
            why = 'you aren\'t logged in'
        elseif low == 't' then
            local t = ctx.target
            if t and t.kind == 'pc' then return t.name end
            why = t and ('<t> is %s, not a player: give its id'):format(t.name or '?') or '<t>: you have no target'
        end
    end)
    if why then return nil, why end
    return out
end

-- A line typed by hand ('!hp 5', 'hp 5', '  !where '), tidied: '!' first, single spaces, no ends; `<t>` and `<me>`
-- filled in when `ctx` is given. Or nil and why.
function build.tidy(s, ctx)
    s = util.trim(s)
    if s == '' then return nil, 'nothing to send' end
    if s:sub(1, 1) ~= '!' then s = '!' .. s end
    s = s:gsub('%s+', ' '):gsub('^! ', '!')
    if ctx then
        local why
        s, why = build.substitute(s, ctx)
        if not s then return nil, why end
    end
    local ok, why = build.check(s)
    if not ok then return nil, why end
    return s
end

return build
