-- core/game.lua against a fake AshitaCore: what it reads of your party.
local game = require('core.game')

-- A party of `members` ({ name, server id }, the first you) and no entities drawn near you.
local function party(members)
    local p = {
        GetMemberName = function (_, i) return members[i + 1] and members[i + 1][1] or '' end,
        GetMemberServerId = function (_, i) return members[i + 1] and members[i + 1][2] or 0 end,
        GetMemberIsActive = function (_, i) return members[i + 1] and 1 or 0 end,
        GetMemberZone = function () return 230 end,
        GetMemberTargetIndex = function () return 0 end,
    }
    local em = { GetRawEntity = function () return nil end }
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
