-- core/game.lua against a fake AshitaCore: what it reads of your party.
local game = require('core.game')

-- A party of `members` ({ name, server id }, the first you) and no entities drawn near you.
local function party(members)
    local p = {
        GetMemberName = function (_, i) return members[i + 1] and members[i + 1][1] or '' end,
        GetMemberServerId = function (_, i) return members[i + 1] and members[i + 1][2] or 0 end,
        GetMemberIsActive = function (_, i) return members[i + 1] and 1 or 0 end,
        GetMemberZone = function (_, i) return members[i + 1] and members[i + 1][3] or 230 end,
        GetMemberTargetIndex = function (_, i) return members[i + 1] and members[i + 1][4] or 0 end,
    }
    local em = { GetRawEntity = function (_, i) return i == 0x401 and {} or nil end,
                 GetRenderFlags0 = function () return 0x200 end, GetDistance = function () return 25 end,
                 GetName = function () return '' end }
    rawset(_G, 'AshitaCore', { GetMemoryManager = function ()
        return { GetParty = function () return p end, GetEntity = function () return em end }
    end })
end

test('players: your party and alliance, you and trusts left out', function ()
    party({ { 'Seekey', 101 }, { 'Ajido', 102 }, { 'Kupipi', 0x1000000 + 230 * 4096 + 0x700 }, { 'Trion', 103 } })
    local names = {}
    for _, p in ipairs(game.players()) do names[#names + 1] = p.name .. (p.party and '+' or '') end
    eq(names, { 'Ajido+', 'Trion+' })
    rawset(_G, 'AshitaCore', nil)
end)

test('players: nothing before login', function ()
    rawset(_G, 'AshitaCore', nil)
    eq(game.players(), {})
    eq(game.me(), nil)
end)

test('players: a party member\'s distance, only when they are in your zone', function ()
    party({ { 'Seekey', 101, 230, 0x400 }, { 'Ajido', 102, 230, 0x401 }, { 'Trion', 103, 100, 0x401 } })
    local d = {}
    for _, p in ipairs(game.players()) do d[p.name] = p.dist end
    eq(d.Ajido, 5, 'drawn near you')
    eq(d.Trion, 0, 'another zone: its index is someone else\'s here')
    rawset(_G, 'AshitaCore', nil)
end)
