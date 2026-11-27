--[[
    What GM Tool reads of the game: you, your target, the players around you, and what the server last heard of your
    position and target. In game only (AshitaCore); each read guarded, so a load before login reads nothing.

    The cursor race: a command that acts on your cursor target (a mob's !hp, !getid, !setmoblevel...) acts on the
    target the server last heard of, from your position packet (0x015, its target index at 0x16) a few times a
    second, not the one you see. game.ready() says when the two agree; core/send.lua holds such a line till then.
    Your position comes from the same packet, as the server reads it (x, then y the height, then z), so a bookmark
    is exactly what !pos takes.
]]--

local game = {}

local PC_FIRST, PC_LAST = 0x400, 0x6FF  -- players' entity indexes
local MOB_FLAG = 0x10                   -- spawn flag of a mob
local ENTITY_IDS = 0x1000000            -- a mob's, NPC's, pet's or trust's server id is this or more; a player's less

-- The last 0x015 the client sent: { index = its target, x, y, z = your position as the server reads it }.
game.heard = { index = nil, x = nil, y = nil, z = nil }

-- A little-endian IEEE 754 single from 4 bytes of `s` at `at` (1-based). Pure Lua: no struct, no ffi.
function game.float(s, at)
    local b1, b2, b3, b4 = s:byte(at, at + 3)
    if not b4 then return nil end
    local sign = b4 >= 128 and -1 or 1
    local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
    local mant = (b3 % 128) * 65536 + b2 * 256 + b1
    if exp == 0 then
        if mant == 0 then return 0 end
        return sign * mant * 2 ^ -149
    end
    if exp == 255 then return nil end  -- infinity or NaN: no position
    return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

-- Zoning (packet_in 0x00A in, 0x00B out): what was heard is the last zone's. Forgotten till the next 0x015.
function game.on_packet_in(id)
    if id == 0x00A or id == 0x00B then game.heard = { index = nil, x = nil, y = nil, z = nil } end
end

-- Ashita's packet_out for 0x015: its target index and your position, as the server reads them.
function game.on_packet_out(id, data)
    if id ~= 0x015 or type(data) ~= 'string' or #data < 0x18 then return end
    game.heard.index = data:byte(0x16 + 1) + data:byte(0x16 + 2) * 256
    local x, y, z = game.float(data, 0x04 + 1), game.float(data, 0x08 + 1), game.float(data, 0x0C + 1)
    if x and y and z then game.heard.x, game.heard.y, game.heard.z = x, y, z end
end

local function mm()
    local ok, m = pcall(function () return AshitaCore:GetMemoryManager() end)
    return ok and m or nil
end

-- Whether entity `i` is drawn: spawned near you, not hidden.
-- (Called only inside a scan that is itself under pcall: none of its own, as it runs for every index.)
local function present(em, i)
    if em:GetRawEntity(i) == nil then return false end  -- an empty slot: most of them
    local flags = em:GetRenderFlags0(i)
    return bit.band(flags, 0x200) ~= 0 and bit.band(flags, 0x4000) == 0
end

-- An entity's kind by its index and flags: 'pc', 'mob', 'npc' or 'other' (a pet, a trust).
local function kind_of(em, i)
    if i >= PC_FIRST and i <= PC_LAST then return 'pc' end
    if i < PC_FIRST then return bit.band(em:GetSpawnFlags(i), MOB_FLAG) ~= 0 and 'mob' or 'npc' end
    return 'other'
end

-- You: { name, sid, index, zone, x, y, z (the server's, once a position packet has gone) }, or nil.
function game.me()
    local m = mm()
    if not m then return nil end
    local ok, me = pcall(function ()
        local p = m:GetParty()
        local name = p:GetMemberName(0)
        if not name or name == '' then return nil end
        return { name = name, sid = p:GetMemberServerId(0), index = p:GetMemberTargetIndex(0), zone = p:GetMemberZone(0),
                 x = game.heard.x, y = game.heard.y, z = game.heard.z }
    end)
    return ok and me or nil
end

-- Your target: { index, name, kind, sid, hpp, dist, sub }, or nil. While a sub-target is being picked (`sub`), the
-- one in its slot (the server hears of neither till it's picked: game.ready waits).
function game.target()
    local m = mm()
    if not m then return nil end
    local ok, t = pcall(function ()
        local tg, em = m:GetTarget(), m:GetEntity()
        local sub = tg:GetIsSubTargetActive() ~= 0
        local i = tg:GetTargetIndex(sub and 1 or 0)
        if not i or i == 0 then return nil end
        local name = em:GetName(i)
        if not name or name == '' then return nil end
        return { index = i, name = name, kind = kind_of(em, i), sid = em:GetServerId(i), hpp = em:GetHPPercent(i),
                 dist = math.sqrt(em:GetDistance(i)), sub = sub }
    end)
    return ok and t or nil
end

-- Whether the server has heard of your current target (or of none, with none): a cursor command acts on it then.
function game.ready(t)
    local want = t and t.index or 0
    local heard = game.heard.index
    if heard == nil then return want == 0 end
    return heard == want and not (t and t.sub)
end

-- For core/send.lua: the target the server last heard of (nil before any position packet), your target now (0 for
-- none), and whether you are picking a sub-target.
function game.probe()
    local t = game.target()
    return game.heard.index, t and t.index or 0, t and t.sub or false
end

-- The players near you, nearest first, and your party and alliance: { name, dist, party = true }, you and trusts
-- left out.
function game.players()
    local m = mm()
    if not m then return {} end
    local ok, out = pcall(function ()
        local em, p = m:GetEntity(), m:GetParty()
        local me, here = p:GetMemberName(0), p:GetMemberZone(0)
        local seen, list = {}, {}
        for i = 1, 17 do
            if p:GetMemberIsActive(i) == 1 then
                local n = p:GetMemberName(i)
                -- a trust holds a party slot too: its server id is a zone entity's (0x1000000 up), a player's isn't
                local sid = tonumber(p:GetMemberServerId(i)) or 0
                if n and n ~= '' and not seen[n] and sid < ENTITY_IDS then
                    seen[n] = true
                    list[#list + 1] = { name = n, dist = 0, party = true, zone = p:GetMemberZone(i) }
                end
            end
        end
        for i = PC_FIRST, PC_LAST do
            if present(em, i) then
                local n = em:GetName(i)
                if n and n ~= '' and n ~= me and not seen[n] then
                    seen[n] = true
                    list[#list + 1] = { name = n, dist = math.sqrt(em:GetDistance(i)), zone = here }
                end
            end
        end
        table.sort(list, function (a, b)
            if (a.party == true) ~= (b.party == true) then return a.party == true end
            if a.dist ~= b.dist then return a.dist < b.dist end
            return a.name < b.name
        end)
        return list
    end)
    return ok and out or {}
end

-- Every entity drawn near you but you, nearest first, at most `limit`: { index, name, kind, sid, hpp, dist }.
function game.entities(limit)
    local m = mm()
    if not m then return {} end
    local ok, out = pcall(function ()
        local em, me = m:GetEntity(), m:GetParty():GetMemberTargetIndex(0)
        local list = {}
        for i = 1, 0x8FF do
            if i ~= me and present(em, i) then
                local n = em:GetName(i)
                if n and n ~= '' then
                    list[#list + 1] = { index = i, name = n, kind = kind_of(em, i), sid = em:GetServerId(i),
                                        hpp = em:GetHPPercent(i), dist = math.sqrt(em:GetDistance(i)) }
                end
            end
        end
        table.sort(list, function (a, b) if a.dist ~= b.dist then return a.dist < b.dist end return a.index < b.index end)
        while limit and #list > limit do table.remove(list) end
        return list
    end)
    return ok and out or {}
end

-- The zone player `name` is in, when GM Tool can tell (your party, or drawn near you): you are in yours.
function game.zone_of(name, players)
    if not name then return nil end
    local me = game.me()
    if me and me.name:lower() == name:lower() then return me.zone end
    for _, pl in ipairs(players or game.players()) do
        if pl.name:lower() == name:lower() then return pl.zone end
    end
end

-- The client's name for zone `id`, or nil.
function game.zone_name(id)
    local ok, n = pcall(function () return AshitaCore:GetResourceManager():GetString('zones.names', id) end)
    if ok and type(n) == 'string' and n ~= '' then return n end
end

return game
