--[[
    Reading the server's sql dumps (sql/*.sql): one `INSERT INTO ... VALUES (...);` a line, as LandSandBoat writes
    them. Used by tools/gen_data.lua; tests/sql_test.lua runs it. Pure.
]]--

local sql = {}

-- The values of one `INSERT INTO ... VALUES (...);` line, by column: numbers as numbers (hex too), strings unquoted
-- (\' and '' read as '), NULL as nil, `out.n` the column count. Nil for any other line (a comment, a CREATE).
function sql.row(line)
    local body = line:match('^INSERT INTO [^(]*VALUES%s*%((.*)%)%s*;')
    if not body then return nil end
    local out, n, i, len = {}, 0, 1, #body
    while i <= len do
        local c = body:sub(i, i)
        if c == ' ' then
            i = i + 1
        elseif c == '\'' then
            local j, parts = i + 1, {}
            while j <= len do
                local ch = body:sub(j, j)
                if ch == '\\' then
                    parts[#parts + 1] = body:sub(j + 1, j + 1)
                    j = j + 2
                elseif ch == '\'' then
                    if body:sub(j + 1, j + 1) ~= '\'' then break end
                    parts[#parts + 1] = '\''
                    j = j + 2
                else
                    parts[#parts + 1] = ch
                    j = j + 1
                end
            end
            n = n + 1
            out[n] = table.concat(parts)
            local comma = body:find(',', j + 1, true)
            i = comma and comma + 1 or len + 1
        else
            local comma = body:find(',', i, true) or (len + 1)
            local tok = body:sub(i, comma - 1):match('^%s*(.-)%s*$')
            n = n + 1
            if tok ~= 'NULL' then out[n] = tonumber(tok) or tok end
            i = comma + 1
        end
    end
    out.n = n
    return out
end

-- fn(row) for each row of sql text `s`.
function sql.rows(s, fn)
    for line in s:gmatch('[^\r\n]+') do
        local r = sql.row(line)
        if r then fn(r) end
    end
end

return sql
