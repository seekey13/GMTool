--[[
    The Setup page: a test character made in one go, for yourself. Its choices (store.cfg.setup) as the lines that
    make it, in the order they must go: the main job and level first (!capallskills caps for the job and level you
    have when it runs), then the sub job, then skills, spells and the rest. Pure. (Its defaults: core/store.lua.)

    !changejob, !changesjob, !capallskills and !setgil act on you alone; the rest are given your name.
]]--

local build = require('core.build')
local util = require('core.util')

local setup = {}

-- The switches, in the order their lines go: { key, label, help, line(me) }.
setup.SWITCHES = {
    { 'skills', 'Cap every skill', 'Every combat and magic skill capped for the job and level set above (!capallskills)',
      function () return '!capallskills' end },
    { 'spells', 'Learn every spell', 'Every valid spell but the trusts (!addallspells)', function (me) return '!addallspells ' .. me end },
    { 'ws', 'Every quest weapon skill', 'Every weapon skill learned by quest (!addallweaponskills)',
      function (me) return '!addallweaponskills ' .. me end },
    { 'trusts', 'Every trust', 'Every trust (!addalltrusts)', function (me) return '!addalltrusts ' .. me end },
    { 'maps', 'Every map', 'Every map (!addallmaps)', function (me) return '!addallmaps ' .. me end },
    { 'mounts', 'Every mount', 'Every mount key item (!addallmounts)', function (me) return '!addallmounts ' .. me end },
    { 'attachments', 'Every automaton attachment', 'Every attachment, for a puppetmaster (!addallattachments)',
      function (me) return '!addallattachments ' .. me end },
}

local function level(v, what, optional)
    v = util.trim(v)
    if v == '' and optional then return '' end
    if not util.is_int(v) then return nil, ('%s: a level, 1 to 99'):format(what) end
    local n = tonumber(v)
    if n < 1 or n > 99 then return nil, ('%s: 1 to 99'):format(what) end
    return tostring(n)
end

-- The lines setup `o` sends for you (`me`, your name): lines, or nil and why.
function setup.lines(o, me)
    if not me or me == '' then return nil, 'you aren\'t logged in' end
    o = o or {}
    local out = {}
    if util.trim(o.job) ~= '' then
        local lv, why = level(o.level, 'Main job level')
        if not lv then return nil, why end
        out[#out + 1] = ('!changejob %s %s%s'):format(o.job, lv, o.master and ' 1' or '')
    elseif o.master then
        return nil, 'pick a main job to master'
    end
    if util.trim(o.sub) ~= '' then
        local lv, why = level(o.sub_level, 'Sub job level', true)
        if not lv then return nil, why end
        out[#out + 1] = ('!changesjob %s%s'):format(o.sub, lv ~= '' and (' ' .. lv) or '')
    end
    for _, s in ipairs(setup.SWITCHES) do
        if o[s[1]] then out[#out + 1] = s[4](me) end
    end
    local gil = util.trim(o.gil)
    if gil ~= '' then
        if not util.is_int(gil) or tonumber(gil) < 0 then return nil, 'Gil: a whole number, 0 or more' end
        out[#out + 1] = '!setgil ' .. tonumber(gil)
    end
    if o.restore then
        out[#out + 1] = '!hp 99999 ' .. me
        out[#out + 1] = '!mp 99999 ' .. me
    end
    if #out == 0 then return nil, 'choose something to set' end
    for _, l in ipairs(out) do
        local ok, why = build.check(l)
        if not ok then return nil, ('%s: %s'):format(l, why) end
    end
    return out
end

-- A name for a macro of setup `o`: 'Setup WHM 75/BLM 37'.
function setup.name(o)
    local s = 'Setup'
    if util.trim(o.job) ~= '' then s = s .. ' ' .. o.job .. ' ' .. util.trim(o.level) end
    if util.trim(o.sub) ~= '' then s = s .. '/' .. o.sub .. (util.trim(o.sub_level) ~= '' and (' ' .. util.trim(o.sub_level)) or '') end
    return s
end

return setup
