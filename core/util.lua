--[[
    Small helpers more than one module needs. Pure: no game client.
]]--

local util = {}

function util.clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end

function util.round(x) return math.floor(x + 0.5) end

-- A deep copy of `v`.
function util.copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = util.copy(x) end
    return out
end

-- `s` without the spaces at either end; '' for nil.
function util.trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- `s` split on runs of spaces: its words.
function util.words(s)
    local out = {}
    for w in tostring(s or ''):gmatch('%S+') do out[#out + 1] = w end
    return out
end

-- 'SOUTHERN_SAN_DORIA' as 'Southern San Doria'.
function util.pretty(name)
    return (tostring(name):lower():gsub('_', ' '):gsub('(%a)([%w\']*)', function (a, b) return a:upper() .. b end))
end

-- Whether `s` is a whole number, written plainly (an optional minus, then digits).
function util.is_int(s) return type(s) == 'string' and s:match('^%-?%d+$') ~= nil end

-- Whether `s` is a number, written plainly ('-12', '3.5', '-0.25').
function util.is_num(s) return type(s) == 'string' and (s:match('^%-?%d+%.?%d*$') ~= nil or s:match('^%-?%.%d+$') ~= nil) end

-- Whether `list` holds `x`.
function util.contains(list, x)
    for _, v in ipairs(list or {}) do if v == x then return true end end
    return false
end

-- Seconds as '12s', '4m', '3h'.
function util.ago(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return seconds .. 's' end
    if seconds < 3600 then return math.floor(seconds / 60) .. 'm' end
    if seconds < 86400 then return math.floor(seconds / 3600) .. 'h' end
    return math.floor(seconds / 86400) .. 'd'
end

return util
