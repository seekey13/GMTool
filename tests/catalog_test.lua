-- core/catalog.lua against the server's own commands (data/server.lua, from scripts/commands).
local catalog = require('core.catalog')
local data = require('core.data')
local server = require('data.server')

local KINDS = { int = true, num = true, word = true, text = true, player = true, pick = true, choice = true,
                entity = true, item = true, spell = true }
local WHO = { you = true, cursor = true, cursor_pc = true, none = true }

test('every server command has a form', function ()
    local have = {}
    for _, c in ipairs(catalog.list) do have[c.cmd] = true end
    local missing = {}
    for name in pairs(server) do if not have[name] then missing[#missing + 1] = name end end
    table.sort(missing)
    eq(missing, {}, 'commands with no form')
end)

test('every form is a server command', function ()
    for _, c in ipairs(catalog.list) do assert(server[c.cmd], 'no server command !' .. c.cmd) end
end)

test('keys are unique and every page has commands', function ()
    local seen = {}
    for _, c in ipairs(catalog.list) do
        assert(not seen[c.key], 'repeated key ' .. c.key)
        seen[c.key] = true
        assert(catalog.page_of[c.page], c.key .. ': no page ' .. tostring(c.page))
        assert(type(c.desc) == 'string' and c.desc ~= '', c.key .. ': no description')
    end
    for _, p in ipairs(catalog.PAGES) do assert(#catalog.page_of[p[1]].commands > 0, 'empty page ' .. p[1]) end
end)

-- The arguments a command reads: one per parameter letter, any number for one that takes the whole line ('b') or
-- whose one parameter is text ('s').
local function rest_of_line(params) return params == 'b' or params == 's' end

test('no form gives more arguments than the server reads', function ()
    for _, c in ipairs(catalog.list) do
        local params = server[c.cmd].params
        if not rest_of_line(params) then
            assert(#c.args <= #params, ('!%s: %d arguments, the server reads %d (%s)'):format(c.cmd, #c.args, #params, params))
        end
    end
end)

test('text with spaces only where the server keeps it', function ()
    for _, c in ipairs(catalog.list) do
        for i, a in ipairs(c.args) do
            if a[2] == 'text' then
                assert(rest_of_line(server[c.cmd].params), ('!%s: text argument %s, but the server splits on spaces'):format(c.cmd, a[1]))
                assert(i == #c.args, ('!%s: text argument %s is not the last'):format(c.cmd, a[1]))
            end
        end
    end
end)

-- What a word of an argument can be: a number, for the server's 'i'.
local NUMERIC = { int = true, entity = true, item = true }
local function numeric(a)
    if NUMERIC[a[2]] then return true end
    if a[2] == 'pick' then return a.send ~= 'name' and a.send ~= 'lower' and a.set ~= 'currencies' end
    if a[2] == 'choice' then
        for _, o in ipairs(a.options) do if not tostring(o[1]):match('^%-?%d+$') then return false end end
        return true
    end
    return false
end

test('a number goes where the server reads one (atoi)', function ()
    for _, c in ipairs(catalog.list) do
        local params = server[c.cmd].params
        if not rest_of_line(params) then
            for i, a in ipairs(c.args) do
                if params:sub(i, i) == 'i' then
                    assert(numeric(a), ('!%s: argument %d (%s) is read as a number, but the form gives %s'):format(c.cmd, i, a[1], a[2]))
                end
            end
        end
    end
end)

test('every argument is well formed', function ()
    for _, c in ipairs(catalog.list) do
        for i, a in ipairs(c.args) do
            local where = ('!%s argument %d (%s)'):format(c.cmd, i, tostring(a[1]))
            assert(type(a[1]) == 'string' and a[1] ~= '', where .. ': a label')
            assert(KINDS[a[2]], where .. ': kind ' .. tostring(a[2]))
            if a[2] == 'player' then assert(WHO[a.who], where .. ': who ' .. tostring(a.who)) end
            if a[2] == 'choice' then assert(type(a.options) == 'table' and #a.options > 0, where .. ': options') end
            if a.shift then assert(i == 1, where .. ': only a leading argument can be left out') end
            if a.req and a.fill then error(where .. ': required, so never filled') end
            if a[2] == 'pick' then
                if a.log then
                    local l = c.args[a.log]
                    assert(l and l[2] == 'pick' and (l.set == 'questlogs' or l.set == 'missionlogs'), where .. ': its log')
                else
                    assert(#data.list(a) > 0, where .. ': an empty list ' .. a.set)
                end
            end
        end
    end
end)

test('a required argument never follows an optional one that can\'t be filled', function ()
    for _, c in ipairs(catalog.list) do
        local loose
        for _, a in ipairs(c.args) do
            if a.req and loose then
                error(('!%s: %s is required after %s, which has no fill'):format(c.cmd, a[1], loose))
            end
            if not a.req and not a.fill and not a.shift and a[2] ~= 'player' then loose = a[1] end
            if a[2] == 'player' and not a.req and not a.shift and not a.fill then loose = a[1] end
        end
    end
end)

test('the server\'s dangerous commands ask twice', function ()
    for _, name in ipairs({ 'crash', 'sleep', 'gc_full', 'addtime', 'packetmod', 'delallinventory', 'delcontaineritems',
                            'breaklinkshell', 'jail', 'logoff', 'promote', 'provokeall' }) do
        assert(catalog.by_key[name].danger, '!' .. name .. ' should confirm')
    end
end)

test('search finds by name, then by words', function ()
    local r = catalog.search('zone')
    eq(r[1].cmd, 'zone', 'the command named so first')
    local found = {}
    for _, c in ipairs(catalog.search('key item')) do found[c.cmd] = true end
    assert(found.addkeyitem and found.delkeyitem and found.haskeyitem, 'key item commands')
    eq(#catalog.search(''), 0, 'nothing for nothing')
    eq(catalog.search('!hp')[1].cmd, 'hp', 'a leading ! is ignored')
end)

test('/gmt page names: a whole name first, then a prefix, in the old order', function ()
    eq(catalog.page_named('player'), 'vitals', 'a title')
    eq(catalog.page_named('pl'), 'vitals', 'a prefix: Player before Places, as before')
    eq(catalog.page_named('places'), 'places')
    eq(catalog.page_named('Zone Browser'), 'zones')
    eq(catalog.page_named('zones'), 'zones')
    eq(catalog.page_named('nation'), 'nation', 'a whole id')
    eq(catalog.page_named('nearby'), 'nearby')
    eq(catalog.page_named('n'), 'nation', 'a prefix: the command pages first')
    eq(catalog.page_named('  HISTORY '), 'history', 'any case, trimmed')
    eq(catalog.page_named('nope'), nil)
    eq(catalog.page_named(''), nil)
end)
