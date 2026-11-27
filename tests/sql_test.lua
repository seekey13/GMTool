-- tools/sql.lua: the server's sql dump rows, as tools/gen_data.lua reads them.
local sql = require('tools.sql')

test('a row: numbers, strings, NULL, hex', function ()
    local r = sql.row("INSERT INTO `npc_list` VALUES (16781331,'Achieve_Master','Achieve Master',0,-1.500,NULL,0x0000320000,'SOA');")
    eq(r.n, 8)
    eq({ r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8] }, { 16781331, 'Achieve_Master', 'Achieve Master', 0, -1.5, nil, 0x0000320000, 'SOA' })
end)

test('quotes and commas inside a string', function ()
    local r = sql.row([[INSERT INTO `t` VALUES (1,'Ru\'Lude, Gardens','it''s',2);]])
    eq({ r[1], r[2], r[3], r[4], r.n }, { 1, 'Ru\'Lude, Gardens', 'it\'s', 2, 4 })
end)

test('a trailing comment, spaces after commas; other lines are none', function ()
    local r = sql.row("INSERT INTO `t` VALUES (5, 'a', 6); -- (NM) a note")
    eq({ r[1], r[2], r[3], r.n }, { 5, 'a', 6, 3 })
    eq(sql.row('-- INSERT INTO `t` VALUES (1);'), nil)
    eq(sql.row('CREATE TABLE `t` ('), nil)
    local n = 0
    sql.rows("INSERT INTO `t` VALUES (1);\r\n-- x\nINSERT INTO `t` VALUES (2);\n", function () n = n + 1 end)
    eq(n, 2)
end)
