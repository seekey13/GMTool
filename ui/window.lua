--[[
    The GM Tool window, in Sidekick Settings' look (ui/kit.lua, after VanaCore's /vana window): a sidebar listing
    the pages (Favorites, a page per group of commands, then Console, History and Settings), and the page shown.

    A command is a card: its name, GM level and what it does on one line, with its Send button and a star that
    makes it a favorite; a click on the name opens its form, a box per argument (a number, a word, a player, or a
    pick from the server's own lists), its presets, and the line it will send, checked as it's typed
    (core/build.lua). Everything said to the server goes through `act` (GMTool.lua), never from here.

    ImGui only: what it shows of the game comes in `view`, rebuilt each frame. The form's values and the settings
    live in core/store.lua's cfg, which this changes through store's own functions.

    Ashita's binding: widget values are one-element tables ({ 'text' }); Text takes a printf format. Everything here
    is drawn on draw lists (no '%' doubling) or with TextUnformatted.
]]--

local imgui = require('imgui')
local actions = require('core.actions')
local build = require('core.build')
local catalog = require('core.catalog')
local data = require('core.data')
local kit = require('ui.kit')
local macros = require('core.macros')
local replies = require('core.replies')
local spawns = require('core.spawns')
local store = require('core.store')
local util = require('core.util')

local window = {}

local P, S = kit.P, kit.S
local BODY, SMALL = kit.BODY, kit.SMALL

-- Unscaled sizes, as every size here.
local SIDE_W, PAGE_W, WIN_H, MARGIN = 184, 540, 640, 6
local TITLE_H, ACT_H, HEAD_H, ROW_H, NAV_H, TOAST_H = 44, 40, 32, 30, 25, 26
local LEFT, PAD, GUTTER = 24, 18, 12
local FIELD_W = 250

local act, view   -- this frame's
local state = {
    page = nil,          -- the page shown (its id)
    open = {},           -- [command key] = true: its form is open
    more = {},           -- [command key] = true: its advanced fields are shown too
    bufs = {},           -- [id] = { text }: each text box's buffer
    filter = {},         -- [popup id] = { text }: a list's filter
    search = { '' },     -- the sidebar's search
    console = { '' },    -- the console's line
    armed = {},          -- [id] = time: a danger button pressed once, till ARMED seconds pass
}
window.state = state
local ARMED = 5

-- Helpers ---------------------------------------------------------------------------------------------------------

local function dl() return imgui.GetWindowDrawList() end

-- A text box's buffer `id`, holding `value` unless it's being typed in (then the box's own).
local function buf(id, value)
    local b = state.bufs[id]
    value = value or ''
    if not b then
        b = { value }
        state.bufs[id] = b
    elseif b.shown ~= value and not b.active then
        b[1] = value
    end
    b.shown = value
    return b
end

-- A stable id for a macro, place or history line (its `uid`, given the first time it's drawn): the ids of its
-- buttons don't move to another row when rows above it come and go.
local function uid_of(t)
    if not t.uid then t.uid = store.uid() end
    return t.uid
end

-- A five-pointed star `r` across centred on (cx, cy): filled, or its outline.
local function star(d, cx, cy, r, color, filled, alpha)
    local pts = {}
    for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5
        local rr = i % 2 == 0 and r or r * 0.45
        pts[#pts + 1] = { cx + math.cos(a) * rr, cy + math.sin(a) * rr }
    end
    if filled then
        for i = 1, 10 do kit.tri(d, { cx, cy }, pts[i], pts[i % 10 + 1], color, alpha) end
    else
        for i = 1, 10 do kit.line(d, pts[i][1], pts[i][2], pts[i % 10 + 1][1], pts[i % 10 + 1][2], color, alpha, math.max(1, S(1.2))) end
    end
end

-- An icon button `box` across centred on (cx, cy): `draw(color)` in `base`, `hot` under the mouse. Returns clicked.
local function icon_button(id, cx, cy, box, draw, base, hot)
    local hovered, clicked = kit.hit(id, cx - box / 2, cy - box / 2, box, box)
    draw(hovered and (hot or P.text) or (base or P.dim))
    return clicked, hovered
end

-- The GM level's pill colour: green for 0-1, the accent for 2-3, amber 4, rose 5.
local function level_tint(lv)
    if lv >= 5 then return P.rose end
    if lv >= 4 then return P.amber end
    if lv >= 2 then return P.accent end
    return P.teal
end

local function level_of(c)
    local s = data.raw('server')
    local e = s and s[c.cmd]
    return e and e.level or 0
end

-- Whether the server's own usage text exists for `c`.
local function usage_of(c)
    local s = data.raw('server')
    local e = s and s[c.cmd]
    return e and e.usage
end

-- A labelled line `h` tall: its hover band, `label` at the left, `help` over its left half. Returns its middle.
local function line(pg, label, help, h, color)
    h = h or S(ROW_H)
    local y = pg.y
    pg.y = y + h
    if kit.over(pg.x + S(4), y, pg.w - S(8), h) then kit.fill(pg.dl, pg.x + S(4), y, pg.w - S(8), h, P.hover, S(3), 0.8) end
    local cy = y + h / 2
    if label then
        local room = pg.right - S(FIELD_W) - S(10) - pg.lx
        kit.text_mid(pg.dl, pg.lx, cy, kit.fit(label, room, kit.fonts.text, S(BODY - 1)), color or P.text, kit.fonts.text, S(BODY - 1), pg.alpha)
    end
    if help and kit.over(pg.x, y, pg.w / 2, h) then kit.tooltip(help) end
    return cy
end

-- Wrapped text across the page.
local function note(pg, s, color, px)
    px = px or S(SMALL + 0.5)
    for _, l in ipairs(kit.wrap(s, kit.fonts.text, px, pg.right - pg.lx)) do
        kit.text_mid(pg.dl, pg.lx, pg.y + S(10), l, color or P.dim, kit.fonts.text, px, pg.alpha)
        pg.y = pg.y + S(20)
    end
end

-- A group's heading inside a page: small spaced capitals, a line after.
local function subheader(pg, s, color)
    pg.y = pg.y + S(6)
    local cy = pg.y + S(12)
    local font, px, spacing = kit.fonts.semi_italic, S(SMALL), math.max(1, S(1.2))
    local tw = kit.text_spaced(pg.dl, pg.lx, cy, s:upper(), color or P.teal, font, px, spacing, pg.alpha)
    local tx = pg.lx + tw + S(10)
    if pg.right > tx then kit.line(pg.dl, tx, cy, pg.right, cy, color or P.teal, 0.35 * pg.alpha) end
    pg.y = pg.y + S(26)
end

-- A danger button: the first press arms it (red, "Sure?"), the second within ARMED seconds goes. Returns clicked.
-- `right`: x is the button's right edge (it grows leftwards as it arms, and stays inside the page).
local function guarded(id, x, cy, label, kind, enabled, right)
    local armed = state.armed[id] and view.now - state.armed[id] < ARMED
    local shown = armed and 'Sure? Click again' or label
    if right then x = x - kit.button_width(shown) end
    local clicked, w = kit.button(id, x, cy, shown, armed and 'danger' or kind, enabled)
    if clicked then
        if armed or view.cfg.send.confirm == false then
            state.armed[id] = nil
            return true, w
        end
        state.armed[id] = view.now
    end
    return false, w
end

-- You, then your party and alliance, by name: whom Acting on: Party means.
local function party_names()
    local out = {}
    if view.me and view.me.name then out[1] = view.me.name end
    for _, p in ipairs(view.players or {}) do if p.party then out[#out + 1] = p.name end end
    return out
end

-- The context build.line takes: you, your target and the "acting on" choice.
local function ctx()
    local a, me = view.cfg.acting, view.me
    return { me = me and me.name, target = view.target, mode = a.mode, name = a.name, party = party_names(),
             pos = me and me.x and { x = me.x, y = me.y, z = me.z } or nil, zone = me and me.zone }
end
window.ctx = ctx

-- Lists that pop up --------------------------------------------------------------------------------------------

-- A filter box at the top of a popup, focused as it opens. Returns its text, lowered.
local function filter_box(id, w)
    local f = state.filter[id]
    if not f then f = { '' }; state.filter[id] = f end
    if imgui.IsWindowAppearing() then
        f[1] = ''
        imgui.SetKeyboardFocusHere()
    end
    imgui.PushItemWidth(w)
    imgui.InputText('##filter' .. id, f, 64)
    imgui.PopItemWidth()
    return f[1]
end

-- A list of `entries` to pick from inside a popup, `height` tall: `pick(e)` on a click. Shows at most 200.
local function pick_list(id, entries, selected, pick, height)
    local open = kit.child('##list' .. id, 0, height)
    if open then
        for i, e in ipairs(entries) do
            if kit.selectable(e.label .. '##' .. id .. i, selected == e) then pick(e) imgui.CloseCurrentPopup() end
        end
        if #entries == 0 then imgui.TextDisabled('Nothing matches.') end
    end
    imgui.EndChild()
end

-- Arguments ---------------------------------------------------------------------------------------------------

-- The id of argument `i`'s widgets on card `key`.
local function aid(key, i, part) return ('##gm_%s_%d_%s'):format(key, i, part or 'v') end

-- A text box for argument `i` of `c`, `w` wide at x: its value saved in the form as typed.
-- Enter in one sends its card (card(), once the form is drawn): state.enter holds the card's key till then.
local function text_box(c, i, x, cy, w, hint, max)
    local id = aid(c.key, i)
    local form = store.form(c.key)
    local b = buf(id, form[i] or '')
    local entered = kit.input(id, x, cy, w, b, max or 100, hint, ImGuiInputTextFlags_EnterReturnsTrue)
    b.active = imgui.IsItemActive()
    if b[1] ~= (form[i] or '') then store.set_value(c.key, i, b[1]) end
    if entered then state.enter = c.key end
    return store.form(c.key)[i] or ''
end

-- A small button at the right of a box: `label`, returns clicked.
local function side_button(id, right, cy, label, tip, enabled)
    local w = kit.button_width(label)
    local clicked = kit.button(id, right - w, cy, label, 'ghost', enabled)
    kit.tip(tip)
    return clicked, w
end

-- The names a player box offers: your target (a player), the party and players near you, then the recent ones.
local function name_choices()
    local out, seen = {}, {}
    local function add(n, tag)
        if n and n ~= '' and not seen[n:lower()] then
            seen[n:lower()] = true
            out[#out + 1] = { name = n, label = tag and (n .. '  ' .. tag) or n }
        end
    end
    if view.me then add(view.me.name, '(you)') end
    if view.target and view.target.kind == 'pc' then add(view.target.name, '(target)') end
    for _, p in ipairs(view.players or {}) do add(p.name, p.party and '(party)' or ('(%.0fy)'):format(p.dist or 0)) end
    for _, n in ipairs(view.cfg.names or {}) do add(n, '(recent)') end
    return out
end

-- A popup of names; `pick(name)` on a click.
local function names_popup(id, x, y, w, pick)
    imgui.SetNextWindowPos({ x, y })
    kit.list_size(S(BODY - 1), w, math.max(w, S(300)))
    kit.popup(id, S(BODY - 1), function ()
        local q = filter_box(id, w - S(20)):lower()
        local list = {}
        for _, n in ipairs(name_choices()) do
            if q == '' or n.label:lower():find(q, 1, true) then list[#list + 1] = { label = n.label, name = n.name } end
        end
        pick_list(id, list, nil, function (e) pick(e.name) end, S(220))
    end)
end

-- What an empty player box sends: shown as its hint.
-- (core/build.lua's own rule, so the hint and the line never disagree.)
local function player_hint(c, a)
    if view.cfg.acting.mode == 'party' and not c.danger then
        local n = #party_names()
        if a.who == 'none' then n = n - 1 end
        return n > 0 and ('each of your party (%d)'):format(n) or 'no one in your party'
    end
    local d, why = build.default_player(c, a, ctx())
    if not d then return c.danger and 'type the name' or why end
    if d == '' then
        if view.cfg.acting.mode == 'target' and view.target then return view.target.name .. ' (cursor)' end
        if a.who == 'none' then return 'a name is needed' end
        return a.who == 'cursor' and 'server: cursor target, else you' or a.who == 'cursor_pc' and 'server: cursor player, else you'
            or 'server: you'
    end
    local t = view.target
    if view.me and d == view.me.name then return d .. ' (you)' end
    if t and d == t.name then return d .. ' (target)' end
    return d
end

-- The shown label of a pick's value, or its hint.
local function pick_shown(a, v, log)
    if v == '' then return nil end
    local e = data.find(a, v, log)
    return e and e.label or v
end

-- A drop-down for pick argument `i` of `c`, `w` wide.
local function pick_box(c, i, a, x, cy, w, values)
    local log
    if a.log then
        log = tonumber(values[a.log] or '')
        if not log then
            kit.dropdown(aid(c.key, i), x, cy, w, 'pick the log first', false, 1, function () end)
            return
        end
    end
    local v = values[i] or ''
    local shown = pick_shown(a, v, log) or (a.hint and ('(' .. a.hint .. ')')) or '(pick one)'
    local id = aid(c.key, i)
    kit.dropdown(id, x, cy, w, shown, true, 1, function ()
        local q = filter_box(id, math.max(w, S(300)) - S(20))
        local list = data.filter(data.list(a, log), q, 300)
        if not a.req and v ~= '' then
            if kit.selectable('(clear)##' .. id .. '_clear', false) then store.set_value(c.key, i, '') end
        end
        pick_list(id, list, data.find(a, v, log), function (e) store.set_value(c.key, i, data.value(a, e)) end, S(240))
    end)
end

-- A choice argument: segments when its options fit, else a drop-down. A click on the chosen one of an optional
-- choice clears it.
local function choice_box(c, i, a, x, cy, w, values)
    local v = values[i] or ''
    local labels, index = {}, 0
    for j, o in ipairs(a.options) do
        labels[j] = o[2]
        if o[1] == v then index = j end
    end
    local px = S(BODY - 2)
    local total = kit.segments_width(labels, px)
    if total <= w and #labels <= 4 then
        local ids = {}
        for j = 1, #labels do ids[j] = aid(c.key, i, 's' .. j) end
        local picked, changed, _, again = kit.segments(ids, x + w - total, cy, labels, index, true, 1, px)
        if changed then store.set_value(c.key, i, a.options[picked][1])
        elseif again and not a.req then store.set_value(c.key, i, '') end  -- the chosen one again: none
        if not a.req and index > 0 then kit.tip('Click it again to leave it empty') end
        if a.hint and index == 0 then
            kit.text_right(dl(), x + w - total - S(8), cy, '(' .. a.hint .. ')', P.faint, kit.fonts.text, S(SMALL))
        end
        return
    end
    local shown = index > 0 and labels[index] or (a.hint and ('(' .. a.hint .. ')')) or '(pick one)'
    local id = aid(c.key, i)
    kit.dropdown(id, x, cy, w, shown, true, 1, function ()
        if not a.req and v ~= '' then
            if kit.selectable('(clear)##' .. id .. '_clear', false) then store.set_value(c.key, i, '') end
        end
        for j, o in ipairs(a.options) do
            if kit.selectable(o[2] .. '##' .. id .. j, j == index) then store.set_value(c.key, i, o[1]) end
        end
    end)
end

-- An item or spell box: the id typed, or found by name in a list the client's names fill (indexed as it's open).
local function named_id_box(c, i, a, x, cy, w)
    local which = a[2] == 'item' and 'items' or 'spells'
    local find_w = kit.button_width('Find')
    text_box(c, i, x, cy, w - find_w - S(6), a.hint or (which == 'items' and 'item id' or 'spell id or NAME'))
    local id = aid(c.key, i, 'find')
    local clicked = side_button(id, x + w, cy, 'Find', 'Search by name')
    if clicked then imgui.OpenPopup(id .. '.list') end
    imgui.SetNextWindowPos({ x, cy + S(14) })
    kit.list_size(S(BODY - 1), w, math.max(w, S(340)))
    kit.popup(id .. '.list', S(BODY - 1), function ()
        local q = filter_box(id, math.max(w, S(340)) - S(20))
        local ix = data.index[which]
        if not ix.done then
            data.step(which, which == 'items' and 4000 or 1024)
            imgui.TextDisabled(('Reading names... %d of %d'):format(ix.next - 1, ix.last))
        end
        local list = q ~= '' and data.filter(ix.entries, q, 200) or {}
        if q == '' then imgui.TextDisabled('Type part of a name.') end
        pick_list(id, list, nil, function (e) store.set_value(c.key, i, tostring(e.id)) end, S(220))
    end)
end

-- A player box: a name typed, or picked from the names near you and recent ones.
local function player_box(c, i, a, x, cy, w)
    local pick_w = S(26)
    text_box(c, i, x, cy, w - pick_w - S(4), player_hint(c, a), 16)
    local id = aid(c.key, i, 'names')
    local bx = x + w - pick_w
    local hovered, clicked = kit.hit(id, bx, cy - S(13), pick_w, S(26))
    kit.fill(dl(), bx, cy - S(13), pick_w, S(26), hovered and P.hover or P.well, S(5))
    kit.outline(dl(), bx, cy - S(13), pick_w, S(26), hovered and P.accent_lo or P.well_edge, S(5))
    kit.icon(dl(), 'down', bx + pick_w / 2, cy, S(11), P.dim)
    kit.tip('Pick a player: your target, party, players nearby, recent names')
    if clicked then imgui.OpenPopup(id .. '.list') end
    names_popup(id .. '.list', x, cy + S(14), w, function (n)
        store.set_value(c.key, i, n)
        store.name_used(n)
    end)
end

-- An entity (or name-or-id) box, with a button that fills your target in.
local function target_box(c, i, a, x, cy, w)
    local label = 'Target'
    local bw = kit.button_width(label)
    text_box(c, i, x, cy, w - bw - S(6), a.hint or '', 40)
    local t = view.target
    local usable
    if a[2] == 'entity' then usable = t and t.kind ~= 'pc' and t.sid
    elseif a.target == 'name' then usable = t and t.name
    else usable = t and (t.kind == 'pc' and t.name or t.sid) end
    local tip = t and (a[2] == 'entity' and t.kind == 'pc' and 'Your target is a player, not a mob or NPC' or
        ('Fill in %s (%s)'):format(t.name, t.kind)) or 'Target something first'
    local clicked = side_button(aid(c.key, i, 'tgt'), x + w, cy, label, tip, usable ~= nil and usable ~= false)
    if clicked and usable then
        local v = a[2] == 'entity' and tostring(t.sid) or a.target == 'name' and t.name or (t.kind == 'pc' and t.name or tostring(t.sid))
        store.set_value(c.key, i, (v:gsub(' ', '_')))
    end
end

-- Argument `i` of `c`: a row, its label at the left (`*` when it must be given), its box at the right.
local function arg_row(pg, c, i, a, values)
    local label = a[1] .. (a.req and ' *' or '')
    if a[2] == 'item' or a[2] == 'spell' then  -- the client's name for the id typed
        local v = values[i] or ''
        local n = util.is_int(v) and data.name_of(a[2] == 'item' and 'items' or 'spells', v)
        if n then label = label .. ': ' .. n end
    end
    local cy = line(pg, label, a.hint and ('Empty: ' .. a.hint) or nil)
    if pg.skip then return end
    local w = S(FIELD_W)
    local x = pg.right - w
    local kind = a[2]
    if kind == 'player' then player_box(c, i, a, x, cy, w)
    elseif kind == 'pick' then pick_box(c, i, a, x, cy, w, values)
    elseif kind == 'choice' then choice_box(c, i, a, x, cy, w, values)
    elseif kind == 'item' or kind == 'spell' then named_id_box(c, i, a, x, cy, w)
    elseif kind == 'entity' or a.target then target_box(c, i, a, x, cy, w)
    else
        local hint = a.hint or (kind == 'int' and (a.min and a.max and ('%d to %d'):format(a.min, a.max) or 'a number')) or ''
        text_box(c, i, x, cy, w, hint, kind == 'text' and 120 or 60)
    end
end

-- Cards ---------------------------------------------------------------------------------------------------------

-- Sends `c` with `values`: built, then handed to act. Opens the card to show why when it can't go. Under Acting on:
-- Party, a line apiece goes, all or none.
local function send_card(c, values)
    local lines, info = build.lines(c, values, ctx())
    if not lines then
        state.open[c.key] = true
        act.toast(info, 'error')
        return
    end
    if #lines == 1 then act.send(lines[1], info) else act.send_lines(lines, c.title) end
end

-- The lines a card would send now, for its preview: lines, info or nil, why.
local function preview(c)
    return build.lines(c, store.form(c.key), ctx())
end

-- A card's lines as one to show: the first, and how many more go with it.
local function first_of(lines)
    if not lines then return nil end
    if #lines == 1 then return lines[1] end
    return ('%s  (+%d more)'):format(lines[1], #lines - 1)
end

-- Its lines for a tooltip: 'Sends ...', one a row, at most 10.
local function sends_tip(lines)
    if #lines == 1 then return 'Sends ' .. lines[1] end
    local shown = {}
    for i = 1, math.min(#lines, 10) do shown[i] = lines[i] end
    if #lines > 10 then shown[#shown + 1] = ('and %d more'):format(#lines - 10) end
    return ('Sends %d lines, one after another:\n'):format(#lines) .. table.concat(shown, '\n')
end

-- A card's heading: fold chevron, title, level pill, what it does; its star and Send at the right. Returns its
-- height.
local function card_head(pg, c, tag)
    local y, h = pg.y, S(HEAD_H)
    pg.y = y + h
    if pg.skip then return end
    local d, cy = pg.dl, y + h / 2
    local hovered_row = kit.over(pg.x + S(4), y, pg.w - S(8), h)
    if hovered_row then kit.fill(d, pg.x + S(4), y, pg.w - S(8), h, P.hover, S(3), 0.8) end
    local lv = level_of(c)
    local dimmed = view.cfg.gm_level > 0 and lv > view.cfg.gm_level
    local a = dimmed and 0.5 or 1
    -- right side: Send (its tooltip the line it sends, or why it can't), then the star
    local right = pg.right
    local values = store.form(c.key)
    local lines, why = build.lines(c, values, ctx())
    local line_ = first_of(lines)
    local clicked, bw
    if c.danger then
        clicked, bw = guarded('##gm_send_' .. c.key, right, cy, 'Send', 'danger', true, true)
    else
        clicked, bw = kit.button('##gm_send_' .. c.key, right - kit.button_width('Send'), cy, 'Send', 'accent')
    end
    kit.tip(lines and sends_tip(lines) or ('Can\'t send yet: ' .. tostring(why)))
    local sx = right - bw
    if clicked then send_card(c, values) end
    local fav = store.is_favorite(c.key)
    local scx = sx - S(16)
    local sclick = icon_button('##gm_fav_' .. c.key, scx, cy, S(20), function (col)
        star(d, scx, cy, S(7), fav and P.amber or col, fav, a)
    end, P.faint, P.amber)
    kit.tip(fav and 'Remove from Favorites' or 'Add to Favorites')
    if sclick then store.toggle_favorite(c.key) end
    local text_right = scx - S(14)
    -- left: chevron and title, a click folds
    local has_form = #c.args > 0 or c.note or c.presets
    local title_px = S(BODY)
    local tw = kit.measure(c.title, kit.fonts.semi, title_px)
    local fold_w = S(LEFT) + tw + S(2)
    local fh, fclick = kit.hit('##gm_fold_' .. c.key, pg.x + S(4), y + S(2), fold_w, h - S(4))
    if fclick then state.open[c.key] = not state.open[c.key] or nil end
    if has_form then
        kit.icon(d, state.open[c.key] and 'down' or 'right', pg.x + S(GUTTER), cy, S(10), fh and P.teal or P.faint, a)
    end
    kit.text_mid(d, pg.lx, cy, c.title, kit.mix(P.white, P.accent2, fh and 0.35 or 0), kit.fonts.semi, title_px, a)
    local x = pg.lx + tw + S(8)
    local pill = 'GM' .. lv
    local pw = kit.pill_width(pill)
    kit.pill('##gm_lv_' .. c.key, x, cy, pill, level_tint(lv), true, false, a * 0.9)
    kit.tip(('Needs GM level %d%s'):format(lv, dimmed and (' (yours: ' .. view.cfg.gm_level .. ')') or ''))
    x = x + pw + S(8)
    if c.danger then
        kit.text_mid(d, x, cy, '!', P.rose, kit.fonts.semi, S(BODY), a)
        x = x + S(10)
    end
    -- what it does; or, folded with boxes filled in, the line Send would send (or why it can't), so a value
    -- typed last week never goes unseen
    local desc, color = c.desc or '', P.dim
    if tag then desc = tag .. ' \194\183 ' .. desc end
    if next(values) ~= nil and not state.open[c.key] then
        desc, color = line_ and ('\226\134\146 ' .. line_) or tostring(why), line_ and P.accent2 or kit.mix(P.rose, P.dim, 0.3)
        if not kit.custom or not kit.dynamic then desc = desc:gsub('^\226\134\146', '->') end
    end
    local room = text_right - x
    if room > S(30) then
        local fitted = kit.fit(desc, room, kit.fonts.text, S(SMALL))
        kit.text_mid(d, x, cy, fitted, color, kit.fonts.text, S(SMALL), a)
        if fitted ~= desc and kit.over(x, y, room, h) then kit.tooltip(desc) end
    end
end

-- A card's form, under its heading while open.
local function card_body(pg, c)
    local values = store.form(c.key)
    local adv_count = 0
    for _, a in ipairs(c.args) do if a.adv then adv_count = adv_count + 1 end end
    local show_adv = state.more[c.key] or view.cfg.ui.adv
    pg.y = pg.y + S(2)
    if c.desc and not pg.skip then note(pg, c.desc, P.text2) end
    if c.note and not pg.skip then note(pg, c.note, P.amber) end
    local u = usage_of(c)
    if u and not pg.skip then note(pg, 'Server: ' .. u, P.faint, S(SMALL - 0.5)) end
    for i, a in ipairs(c.args) do
        if not a.adv or show_adv then arg_row(pg, c, i, a, values) end
    end
    -- presets, more fields, clear
    local cy = pg.y + S(ROW_H) / 2
    pg.y = pg.y + S(ROW_H)
    if not pg.skip then
        local x = pg.lx
        for j, p in ipairs(c.presets or {}) do
            local w = kit.chip_width(p[1]) + S(6)
            if kit.chip(('##gm_pre_%s_%d'):format(c.key, j), x, cy, w, p[1], 'on') then
                local v = {}
                for k = 1, #c.args do v[k] = values[k] end
                for k, pv in ipairs(p[2]) do v[k] = pv end
                send_card(c, v)
            end
            kit.tip(('Send with %s'):format(table.concat(p[2], ' ')))
            x = x + w + S(6)
        end
        local rx = pg.right
        local cw = kit.button_width('Clear')
        if kit.button('##gm_clear_' .. c.key, rx - cw, cy, 'Clear', 'ghost', next(values) ~= nil) then
            store.clear_form(c.key)
            for k in pairs(state.bufs) do if k:find('##gm_' .. c.key .. '_', 1, true) == 1 then state.bufs[k] = nil end end
        end
        kit.tip('Empty every box')
        rx = rx - cw - S(6)
        if adv_count > 0 and not view.cfg.ui.adv then
            local label = state.more[c.key] and 'Fewer fields' or ('More fields (' .. adv_count .. ')')
            local mw = kit.button_width(label)
            if kit.button('##gm_more_' .. c.key, rx - mw, cy, label, 'ghost') then state.more[c.key] = not state.more[c.key] or nil end
        end
    end
    -- the line it sends (the first of a party's, and how many more)
    local lines, info = preview(c)
    local line_ = first_of(lines)
    local h = S(28)
    local y = pg.y
    pg.y = pg.y + h + S(8)
    if pg.skip then return end
    local d = pg.dl
    local bx, bw = pg.lx - S(6), pg.right - pg.lx + S(6)
    kit.fill(d, bx, y, bw, h, P.well, S(4), 0.8)
    kit.outline(d, bx, y, bw, h, line_ and P.line or kit.mix(P.well, P.rose, 0.5), S(4))
    local px = S(SMALL + 0.5)
    if line_ then
        local waits = info.cursor and not view.ready
        kit.text_mid(d, pg.lx, y + h / 2, kit.fit(line_, bw - S(110), kit.fonts.text, px), P.accent2, kit.fonts.text, px)
        local tag = info.cursor and (waits and 'waits for target' or 'cursor target')
            or (#lines > 1 and (#lines .. ' lines')) or (#lines[1] .. ' bytes')
        kit.text_right(d, pg.right - S(4), y + h / 2, tag, waits and P.amber or P.faint, kit.fonts.text, S(SMALL - 1))
        if info.cursor and kit.over(bx, y, bw, h) then
            kit.tooltip('Acts on your cursor target, as the server last heard it. GM Tool sends it once the server '
                .. 'has your current target (a moment after you target something).')
        elseif #lines > 1 and kit.over(bx, y, bw, h) then
            kit.tooltip(sends_tip(lines))
        end
    else
        kit.text_mid(d, pg.lx, y + h / 2, kit.fit(info or '', bw - S(12), kit.fonts.text, px), P.rose, kit.fonts.text, px)
    end
end

-- A card: its heading, and its form while open.
local function card(pg, c, tag)
    local top = pg.y
    -- a card scrolled out of sight is measured, not drawn
    pg.skip = top > pg.bottom or top + S(HEAD_H) < pg.top
    card_head(pg, c, tag)
    if state.open[c.key] then
        local was = pg.skip
        pg.skip = false  -- a form's own boxes keep their state even half out of sight
        card_body(pg, c)
        pg.skip = was
        kit.line(pg.dl, pg.x + S(PAD), pg.y - S(4), pg.right, pg.y - S(4), P.line, 0.6)
        if state.enter == c.key then  -- Enter in one of its boxes: as its Send (a risky one still asks twice)
            state.enter = nil
            if c.danger and view.cfg.send.confirm ~= false then
                act.toast('A risky command: press its Send.', 'warn')
            else
                send_card(c, store.form(c.key))
            end
        end
    end
    pg.skip = false
end

-- The "acting on" strip: whom an empty player box means.
local MODES = { { 'me', 'Me' }, { 'target', 'Target' }, { 'name', 'Name' }, { 'party', 'Party' }, { 'none', 'None' } }
local MODE_TIP = {
    party = 'Empty player boxes send a line for each of you and your party and alliance, one after another. A command '
        .. 'that needs another player (go to, bring...) leaves you out; a risky one still takes only the name typed '
        .. 'in its own box. A macro runs its {who} lines for each member, and the rest once.',
    me = 'Empty player boxes send your own name.',
    target = 'Empty player boxes send your target\'s name when it\'s a player, else yours. A command that acts on the '
        .. 'cursor target takes a targeted mob or pet with no name. A command that needs a name takes only a player '
        .. 'target\'s, and a risky one only the name typed in its own box.',
    name = 'Empty player boxes send the name typed here.',
    none = 'Empty player boxes send no name: the server picks (your cursor target, or you).',
}

local function acting_strip(x, y, w)
    local d = dl()
    local h = S(ACT_H)
    kit.fill(d, x, y, w, h, P.side, 0, 0.6)
    kit.line(d, x, y + h, x + w, y + h, P.border)
    local cy = y + h / 2
    local lx = x + S(LEFT)
    local font, px, spacing = kit.fonts.semi_italic, S(SMALL - 1), math.max(1, S(1))
    local tw = kit.text_spaced(d, lx, cy, 'ACTING ON', P.teal, font, px, spacing)
    local labels, ids, index = {}, {}, 1
    local a = view.cfg.acting
    for j, m in ipairs(MODES) do
        labels[j], ids[j] = m[2], '##gm_mode_' .. m[1]
        if m[1] == a.mode then index = j end
    end
    local sx = lx + tw + S(12)
    local picked, changed, over = kit.segments(ids, sx, cy, labels, index, true, 1, S(BODY - 2))
    if over then kit.tooltip(MODE_TIP[MODES[over][1]]) end
    if changed then
        a.mode = MODES[picked][1]
        store.dirty()
    end
    local rx = sx + kit.segments_width(labels, S(BODY - 2)) + S(12)
    local right = x + w - S(PAD)
    local small = S(SMALL)
    if a.mode == 'name' then
        local pick_w = S(26)
        local fw = right - rx - pick_w - S(4)
        local b = buf('##gm_acting_name', a.name or '')
        if kit.input('##gm_acting_name', rx, cy, fw, b, 16, 'a player\'s name') then
            a.name = b[1]
            store.dirty()
        end
        b.active = imgui.IsItemActive()
        local bx = right - pick_w
        local hovered, clicked = kit.hit('##gm_acting_names', bx, cy - S(13), pick_w, S(26))
        kit.fill(d, bx, cy - S(13), pick_w, S(26), hovered and P.hover or P.well, S(5))
        kit.outline(d, bx, cy - S(13), pick_w, S(26), hovered and P.accent_lo or P.well_edge, S(5))
        kit.icon(d, 'down', bx + pick_w / 2, cy, S(11), P.dim)
        if clicked then imgui.OpenPopup('##gm_acting_names.list') end
        names_popup('##gm_acting_names.list', rx, cy + S(14), right - rx, function (n)
            a.name = n
            store.name_used(n)
            store.dirty()
        end)
        return
    end
    local s, color
    if a.mode == 'me' then
        s, color = view.me and view.me.name or 'you', P.white
    elseif a.mode == 'party' then
        local names = party_names()
        if #names <= 1 then s, color = 'you alone: no party', P.amber
        else
            s, color = ('%d: %s'):format(#names, table.concat(names, ', ')), P.white
            if kit.over(rx, y, right - rx, h) then kit.tooltip('A line apiece for:\n' .. table.concat(names, '\n')) end
        end
    elseif a.mode == 'target' then
        local t = view.target
        if not t then s, color = 'nothing targeted', P.dim
        elseif t.kind == 'pc' then s, color = t.name, P.white
        else s, color = ('%s (%s: cursor commands only)'):format(t.name, t.kind), P.amber end
    else
        s, color = 'the server\'s default', P.dim
    end
    local dot = view.ready and P.teal or P.amber
    kit.circle(d, rx + S(3), cy, S(3), dot)
    if kit.over(rx - S(4), y, S(14), h) then
        kit.tooltip(view.ready and 'The server has your current target.' or 'The server hasn\'t heard of your current target yet.')
    end
    kit.text_mid(d, rx + S(12), cy, kit.fit(s, right - rx - S(12), kit.fonts.text, small), color, kit.fonts.text, small)
end

-- Pages ---------------------------------------------------------------------------------------------------------

-- The commands shown on page `id` (the server's hidden unless Settings shows them).
local function commands_of(id)
    if id == 'favorites' then
        local out = {}
        for _, k in ipairs(view.cfg.favorites) do
            local c = catalog.by_key[k]
            if c then out[#out + 1] = c end
        end
        return out
    end
    local p = catalog.page_of[id]
    return p and p.commands or {}
end

local SUGGESTED = { 'hp', 'mp', 'tp', 'raise', 'zone', 'goto', 'bring', 'pos', 'additem', 'addeffect', 'hide', 'speed' }

local function favorites_page(pg)
    local list = commands_of('favorites')
    if #list == 0 then
        note(pg, 'Star a command (the star by its Send button) to keep it here, on top of every other page.', P.text2)
        pg.y = pg.y + S(6)
        local cy = pg.y + S(14)
        pg.y = pg.y + S(30)
        if kit.button('##gm_suggest', pg.lx, cy, 'Add a starter set', 'accent') then
            for _, k in ipairs(SUGGESTED) do if not store.is_favorite(k) then store.toggle_favorite(k) end end
        end
        kit.tip(table.concat(SUGGESTED, ', '))
        return
    end
    for _, c in ipairs(list) do
        local p = catalog.page_of[c.page]
        card(pg, c, p and p.title)
    end
end

local function commands_page(pg, id)
    local p = catalog.page_of[id]
    if p and p.blurb then note(pg, p.blurb, P.dim) pg.y = pg.y + S(2) end
    if id == 'server' then note(pg, 'These act on the whole server. Most need GM level 5.', P.rose) end
    for _, c in ipairs(commands_of(id)) do card(pg, c) end
end

local function search_page(pg)
    local q = state.search[1]
    local found = catalog.search(q)
    note(pg, ('%d command%s for "%s"'):format(#found, #found == 1 and '' or 's', q), P.dim)
    for _, c in ipairs(found) do
        if c.page ~= 'server' or view.cfg.ui.show_server then
            local p = catalog.page_of[c.page]
            card(pg, c, p and p.title)
        end
    end
end

-- Console: a line typed by hand, the commands it could be, their usage.
local function console_page(pg)
    note(pg, 'Type any GM command, with or without its !, and press Enter. It goes as it is, through the same queue.', P.text2)
    local cy = pg.y + S(18)
    pg.y = pg.y + S(36)
    local sw = kit.button_width('Send')
    local b = state.console
    local enter = kit.input('##gm_console', pg.lx, cy, pg.right - pg.lx - sw - S(8), b, 120, '!command arguments',
        ImGuiInputTextFlags_EnterReturnsTrue)
    local typed = util.trim(b[1])
    local clicked = kit.button('##gm_console_send', pg.right - sw, cy, 'Send', 'accent', typed ~= '')
    if (clicked or enter) and typed ~= '' then
        local l, why = build.tidy(typed, ctx())
        if l then
            act.send(l, { cursor = build.reads_cursor(l) })
            b[1] = ''
        else
            act.toast(why, 'error')
        end
    end
    -- what it could be
    local first = typed:gsub('^!', ''):match('^(%S*)') or ''
    if first ~= '' then
        local server = data.raw('server') or {}
        local shown = 0
        subheader(pg, 'Matches')
        local names = {}
        for name in pairs(server) do if name:sub(1, #first):lower() == first:lower() then names[#names + 1] = name end end
        table.sort(names)
        for _, name in ipairs(names) do
            if shown >= 12 then break end
            shown = shown + 1
            local e = server[name]
            local ly = pg.y
            local lcy = line(pg, nil, e.desc)
            local hovered, clicked2 = kit.hit('##gm_con_' .. name, pg.x + S(4), ly, pg.w - S(8), S(ROW_H))
            local d = pg.dl
            kit.text_mid(d, pg.lx, lcy, '!' .. name, hovered and P.accent2 or P.white, kit.fonts.semi, S(BODY - 1))
            local nx = pg.lx + kit.measure('!' .. name, kit.fonts.semi, S(BODY - 1)) + S(8)
            kit.pill('##gm_conlv_' .. name, nx, lcy, 'GM' .. e.level, level_tint(e.level), true, false)
            nx = nx + kit.pill_width('GM' .. e.level) + S(8)
            local u = e.usage or e.desc or ''
            kit.text_mid(d, nx, lcy, kit.fit(u, pg.right - nx, kit.fonts.text, S(SMALL)), P.dim, kit.fonts.text, S(SMALL))
            if clicked2 then b[1] = '!' .. name .. ' ' end
        end
        if shown == 0 then note(pg, 'No command starts with "' .. first .. '".', P.amber) end
    end
end

-- Whether a typed or remembered line is one of the commands that ask twice.
local function risky(l)
    local name = (l:match('^!(%S+)') or ''):lower()
    for _, c in ipairs(catalog.list) do
        if c.cmd == name and c.danger then return true end
    end
    return false
end

local function history_page(pg)
    local h = view.cfg.history
    if #h == 0 then note(pg, 'Nothing sent yet. Every line GM Tool sends is kept here, newest first.', P.text2) return end
    local cy = pg.y + S(14)
    pg.y = pg.y + S(30)
    local clicked = guarded('##gm_hist_clear', pg.lx, cy, 'Clear history', 'danger')
    if clicked then act.clear_history() end
    for _, e in ipairs(h) do
        local y = pg.y
        local lcy = line(pg, nil, nil)
        if y < pg.bottom and y + S(ROW_H) > pg.top then
            local d = pg.dl
            local ago = util.ago((view.time or 0) - (e.t or 0))
            kit.text_mid(d, pg.lx, lcy, ago, P.faint, kit.fonts.text, S(SMALL))
            local sw = kit.button_width('Send')
            local ew = kit.button_width('Edit')
            local lx = pg.lx + S(40)
            kit.text_mid(d, lx, lcy, kit.fit(e.line, pg.right - sw - ew - S(16) - lx, kit.fonts.text, S(SMALL + 0.5)), P.text,
                kit.fonts.text, S(SMALL + 0.5))
            local again
            local key = uid_of(e)
            if risky(e.line) then again = guarded('##gm_hist_send_' .. key, pg.right, lcy, 'Send', 'danger', true, true)
            else again = kit.button('##gm_hist_send_' .. key, pg.right - sw, lcy, 'Send', 'accent') end
            if again then act.send(e.line, { cursor = build.reads_cursor(e.line) }) end
            if kit.button('##gm_hist_edit_' .. key, pg.right - sw - ew - S(6), lcy, 'Edit', 'ghost') then
                state.console[1] = e.line
                state.page = 'console'
            end
            kit.tip('Copy it into the Console')
        end
        -- what the server said back (this session's sends only)
        local said = replies.of(e)
        if said then
            local px, shown = S(SMALL - 0.5), math.min(#said, 4)
            local top = pg.y
            for j = 1, shown do
                local ry = pg.y
                pg.y = pg.y + S(22)
                if ry < pg.bottom and ry + S(22) > pg.top then
                    local rcy = ry + S(11)
                    -- what to do with it: copy it; a position (!pos) saved as a place
                    local right = pg.right
                    local cw = kit.button_width('Copy')
                    if kit.button(('##gm_hist_copy_%d_%d'):format(uid_of(e), j), right - cw, rcy, 'Copy', 'ghost') then
                        imgui.SetClipboardText(said[j])
                        act.toast('Copied: ' .. said[j])
                    end
                    right = right - cw - S(6)
                    local p = replies.position(said[j])
                    if p then
                        local pw_ = kit.button_width('Save place')
                        if kit.button(('##gm_hist_place_%d_%d'):format(uid_of(e), j), right - pw_, rcy, 'Save place', 'ghost') then
                            local list = view.cfg.places
                            local name = macros.fresh_name(list, ('%s %s'):format(p.name, data.zone_name(p.zone) or p.zone))
                            list[#list + 1] = { name = name, x = p.x, y = p.y, z = p.z, zone = p.zone }
                            store.dirty()
                            act.toast(('Saved %s (Places).'):format(name))
                        end
                        kit.tip('Keep it on the Places page, to put anyone there later')
                        right = right - pw_ - S(6)
                    end
                    local s = j == shown and #said > shown and (said[j] .. ('  (+%d more)'):format(#said - shown)) or said[j]
                    kit.text_mid(pg.dl, pg.lx + S(40), rcy, kit.fit(s, right - S(8) - pg.lx - S(40), kit.fonts.text, px),
                        P.text2, kit.fonts.text, px, 0.85)
                end
            end
            if kit.over(pg.x, top, pg.w, pg.y - top) then kit.tooltip(table.concat(said, '\n')) end
            pg.y = pg.y + S(4)
        end
    end
end

-- Macros and places -------------------------------------------------------------------------------------------

local macro_open = setmetatable({}, { __mode = 'k' })  -- [macro] = true: its editor is open


-- The zone player `name` is in, when it can be told (you; your party; drawn near you): nil when not.
local function zone_of(name)
    if not name then return nil end
    if view.me and view.me.name:lower() == name:lower() then return view.me.zone end
    for _, p in ipairs(view.players or {}) do
        if p.name:lower() == name:lower() then return p.zone end
    end
end

-- Forget the text boxes whose ids start with `prefix` (their rows moved: each takes its value again).
local function forget(prefix)
    for k in pairs(state.bufs) do if k:sub(1, #prefix) == prefix then state.bufs[k] = nil end end
    state.armed = {}
end

-- A small round mark that deletes, after a second click within ARMED seconds (rose while armed). Returns clicked.
local function delete_mark(id, cx, cy)
    local armed = state.armed[id] and view.now - state.armed[id] < ARMED
    local d = dl()
    local hovered, clicked = kit.hit(id, cx - S(10), cy - S(10), S(20), S(20))
    if armed then kit.circle(d, cx, cy, S(9), P.rose, 0.25) end
    kit.icon(d, 'close', cx, cy, S(12), (armed or hovered) and P.rose or P.faint)
    kit.tip(armed and 'Click again to delete' or 'Delete')
    if not clicked then return false end
    if armed or view.cfg.send.confirm == false then
        state.armed[id] = nil
        return true
    end
    state.armed[id] = view.now
    return false
end

-- A one-line text box `w` wide for a value held outside the form store; `set(text)` as it's typed.
local function plain_box(id, x, cy, w, value, hint, max, set)
    local b = buf(id, value or '')
    local edited = kit.input(id, x, cy, w, b, max or 120, hint)
    b.active = imgui.IsItemActive()
    if edited then set(b[1]) end
end

local PLACEHOLDERS = '{who} is whom Acting on means, {me} you, {target} your target (a player), {tid} your target\'s id, '
    .. '{x} {y} {z} {zone} where you stand.'

local function macro_editor(pg, m, i)
    local d = pg.dl
    local fw = pg.right - pg.lx - S(70)
    local cy = line(pg, 'Name')
    plain_box(('##gm_mac_%d_name'):format(i), pg.right - fw, cy, fw, m.name, 'its name', 40, function (s)
        m.name = s
        store.dirty()
    end)
    local drop
    for j = 1, #m.lines do
        local lcy = line(pg, nil)
        local ok_line, why = true, nil
        if util.trim(m.lines[j]) ~= '' then ok_line, why = macros.expand(m.lines[j], ctx()) end
        kit.circle(d, pg.lx + S(4), lcy, S(3), ok_line and P.teal or P.rose)
        if not ok_line and kit.over(pg.lx - S(4), lcy - S(10), S(16), S(20)) then kit.tooltip(why) end
        plain_box(('##gm_mac_%d_l%d'):format(i, j), pg.lx + S(16), lcy, pg.right - pg.lx - S(44), m.lines[j],
            '!command {who}', 120, function (s)
                m.lines[j] = s
                store.dirty()
            end)
        if delete_mark(('##gm_mac_%d_drop%d'):format(i, j), pg.right - S(10), lcy) then drop = j end
    end
    if drop then
        table.remove(m.lines, drop)
        forget(('##gm_mac_%d_'):format(i))
        store.dirty()
    end
    local bcy = pg.y + S(ROW_H) / 2
    pg.y = pg.y + S(ROW_H)
    local x = pg.lx + S(16)
    local added, aw = kit.button(('##gm_mac_%d_add'):format(i), x, bcy, '+ Line', 'ghost', #m.lines < macros.MAX_LINES)
    if added then
        m.lines[#m.lines + 1] = ''
        store.dirty()
    end
    x = x + aw + S(6)
    local list = view.cfg.macros
    local up, uw = kit.button(('##gm_mac_%d_up'):format(i), x, bcy, 'Move up', 'ghost', i > 1)
    x = x + uw + S(6)
    local down = kit.button(('##gm_mac_%d_down'):format(i), x, bcy, 'Move down', 'ghost', i < #list)
    if up or down then
        local j = up and i - 1 or i + 1
        list[i], list[j] = list[j], list[i]
        forget('##gm_mac_')
        store.dirty()
    end
    pg.y = pg.y + S(6)
end

local function macros_page(pg)
    local list = view.cfg.macros
    note(pg, 'A macro sends its lines in order, through the same queue as everything else. In a line, ' .. PLACEHOLDERS,
        P.text2)
    local cy = pg.y + S(16)
    pg.y = pg.y + S(34)
    local clicked, w = kit.button('##gm_mac_new', pg.lx, cy, 'New macro', 'accent')
    if clicked then
        local m = { name = macros.fresh_name(list, 'Macro'), lines = { '' } }
        list[#list + 1] = m
        macro_open[m] = true
        store.dirty()
    end
    if kit.button('##gm_mac_examples', pg.lx + w + S(8), cy, 'Add examples', 'ghost') then
        for _, e in ipairs(macros.EXAMPLES) do
            if not macros.find(list, e.name) then list[#list + 1] = util.copy(e) end
        end
        store.dirty()
    end
    kit.tip('Restore, Revive here, Bring and restore, Go incognito, Punching bag')
    if #list == 0 then note(pg, 'No macros yet. /gmt macro <name> runs one from chat or a game macro.', P.dim) return end
    local remove
    for i, m in ipairs(list) do
        local y, h = pg.y, S(HEAD_H)
        pg.y = y + h
        local d, hcy = pg.dl, y + h / 2
        if kit.over(pg.x + S(4), y, pg.w - S(8), h) then kit.fill(d, pg.x + S(4), y, pg.w - S(8), h, P.hover, S(3), 0.8) end
        local rw = kit.button_width('Run')
        local rx = pg.right - rw
        local lines, why = macros.lines(m, ctx())
        local run
        if why == true then  -- risky: two clicks
            run = guarded('##gm_mac_run_' .. uid_of(m), pg.right, hcy, 'Run', 'danger', true, true)
        else
            run = kit.button('##gm_mac_run_' .. uid_of(m), rx, hcy, 'Run', 'accent')
        end
        kit.tip(lines and table.concat(lines, '\n') or tostring(why))
        if run then
            if lines then act.send_lines(lines, m.name) else
                act.toast(('%s: %s'):format(m.name, why), 'error')
                macro_open[m] = true
            end
        end
        if delete_mark('##gm_mac_del_' .. uid_of(m), rx - S(16), hcy) then remove = i end
        local title = util.trim(m.name) ~= '' and m.name or '(no name)'
        local tw = kit.measure(title, kit.fonts.semi, S(BODY))
        local fh, fclick = kit.hit('##gm_mac_fold_' .. i, pg.x + S(4), y + S(2), S(LEFT) + tw + S(2), h - S(4))
        if fclick then macro_open[m] = not macro_open[m] or nil end
        kit.icon(d, macro_open[m] and 'down' or 'right', pg.x + S(GUTTER), hcy, S(10), fh and P.teal or P.faint)
        kit.text_mid(d, pg.lx, hcy, title, kit.mix(P.white, P.accent2, fh and 0.35 or 0), kit.fonts.semi, S(BODY))
        local n = 0
        for _, l in ipairs(m.lines) do if util.trim(l) ~= '' then n = n + 1 end end
        local first = m.lines[1] and util.trim(m.lines[1]) or ''
        local sub = ('%d line%s%s'):format(n, n == 1 and '' or 's', first ~= '' and (' \194\183 ' .. first) or '')
        local sx = pg.lx + tw + S(10)
        kit.text_mid(d, sx, hcy, kit.fit(sub, rx - S(30) - sx, kit.fonts.text, S(SMALL)), P.dim, kit.fonts.text, S(SMALL))
        if macro_open[m] then macro_editor(pg, m, i) end
    end
    if remove then
        table.remove(list, remove)
        forget('##gm_mac_')
        store.dirty()
    end
end

local function places_page(pg)
    local list = view.cfg.places
    local c = ctx()
    note(pg, 'Save where you stand, then put yourself, or whoever Acting on means, back there with one click (!pos).', P.text2)
    -- here
    local d = pg.dl
    local cy = line(pg, 'Here')
    local here
    if c.pos and c.zone then
        local zn = view.zone_name or ('zone ' .. c.zone)
        here = ('%s  %s %s %s'):format(zn, macros.coord(c.pos.x), macros.coord(c.pos.y), macros.coord(c.pos.z))
    end
    kit.text_right(d, pg.right, cy, kit.fit(here or 'not known yet: move a step', S(FIELD_W) + S(80), kit.fonts.text, S(SMALL)),
        here and P.text2 or P.amber, kit.fonts.text, S(SMALL))
    local ncy = line(pg, 'Save as')
    local sw = kit.button_width('Save here')
    local fw = S(FIELD_W) - sw - S(6)
    state.place_name = state.place_name or { '' }
    kit.input('##gm_place_name', pg.right - S(FIELD_W), ncy, fw, state.place_name, 40, view.zone_name or 'a name')
    if kit.button('##gm_place_save', pg.right - sw, ncy, 'Save here', 'accent', here ~= nil) then
        local name = util.trim(state.place_name[1]) ~= '' and state.place_name[1] or (view.zone_name or 'Place')
        local p, why = macros.here(macros.fresh_name(list, util.trim(name)), c)
        if p then
            list[#list + 1] = p
            state.place_name[1] = ''
            store.dirty()
            act.toast(('Saved %s.'):format(p.name))
        else
            act.toast(why, 'error')
        end
    end
    if #list == 0 then note(pg, 'No places saved. /gmt place <name> [player] goes to one from chat.', P.dim) return end
    subheader(pg, 'Saved')
    local remove
    local who = macros.value('who', c)
    for i, p in ipairs(list) do
        local y = pg.y
        local lcy = line(pg, nil)
        if y < pg.bottom and y + S(ROW_H) > pg.top then
            local gw = kit.button_width('Go')
            local tw_ = kit.button_width('Send')
            if kit.button('##gm_place_go_' .. uid_of(p), pg.right - gw, lcy, 'Go', 'accent') then
                act.send(macros.place_line(p, nil, c.zone), { cursor = false })
            end
            kit.tip('Put yourself here')
            local tx = pg.right - gw - S(6) - tw_
            if kit.button('##gm_place_send_' .. uid_of(p), tx, lcy, 'Send', 'ghost', who ~= nil) then
                act.send(macros.place_line(p, who, zone_of(who)), { cursor = false })
            end
            kit.tip(who and ('Put %s here'):format(who) or 'Acting on names no player now')
            if delete_mark('##gm_place_del_' .. uid_of(p), tx - S(16), lcy) then remove = i end
            kit.text_mid(d, pg.lx, lcy, kit.fit(p.name, S(150), kit.fonts.semi, S(BODY - 1)), P.white, kit.fonts.semi, S(BODY - 1))
            local info = ('%s  %s %s %s'):format(data.zone_name(p.zone) or ('zone ' .. p.zone), macros.coord(p.x),
                macros.coord(p.y), macros.coord(p.z))
            local ix = pg.lx + S(160)
            kit.text_mid(d, ix, lcy, kit.fit(info, tx - S(30) - ix, kit.fonts.text, S(SMALL)), P.dim, kit.fonts.text, S(SMALL))
        end
    end
    if remove then
        table.remove(list, remove)
        state.armed = {}
        store.dirty()
    end
end

-- Target ------------------------------------------------------------------------------------------------------

local KIND = { pc = { 'PLAYER', P.teal }, mob = { 'MOB', P.rose }, npc = { 'NPC', P.amber }, other = { 'PET / TRUST', P.accent } }

-- Job ids to their names (WAR, MNK...), for what the database says of a mob.
local job_names
local function jobs()
    if not job_names then
        job_names = {}
        for _, j in ipairs(data.raw('jobs') or {}) do job_names[j[1]] = j[2] end
    end
    return job_names
end

local function target_page(pg)
    local t = view.target
    if not t then
        note(pg, 'Target a player, mob or NPC: what you can do to it in one click shows here.', P.text2)
        return
    end
    local d = pg.dl
    -- what the server's database says of a mob or NPC (core/spawns.lua)
    local known = t.kind ~= 'pc' and t.sid and spawns.find(t.sid, t.kind)
    local y, h = pg.y, S(known and 76 or 58)
    local bx, bw = pg.lx - S(8), pg.right - pg.lx + S(16)
    kit.fill(d, bx, y, bw, h, P.well, S(5), 0.7)
    kit.outline(d, bx, y, bw, h, P.line, S(5))
    if known then
        local desc = spawns.describe(known, jobs())
        table.remove(desc)  -- its ids: the line above has it
        table.remove(desc, 1)  -- its name: the title has it
        local tags = spawns.tags(known)
        if #tags > 0 then table.insert(desc, 1, table.concat(tags, ', ')) end
        local s = #desc > 0 and table.concat(desc, '  \194\183  ') or 'In the server\'s database.'
        kit.text_mid(d, pg.lx, y + S(60), kit.fit(s, bw - S(16), kit.fonts.text, S(SMALL)), known.nm and P.amber or P.text2,
            kit.fonts.text, S(SMALL))
        if kit.over(bx, y + S(50), bw, S(20)) then kit.tooltip(table.concat(spawns.describe(known, jobs()), '\n')) end
    end
    local name_px = S(BODY + 2)
    local tw = kit.measure(t.name, kit.fonts.semi, name_px)
    kit.text_mid(d, pg.lx, y + S(19), kit.fit(t.name, S(260), kit.fonts.semi, name_px), P.white, kit.fonts.semi, name_px)
    local k = KIND[t.kind] or KIND.other
    kit.pill('##gm_tkind', pg.lx + math.min(tw, S(260)) + S(10), y + S(19), k[1], k[2], true, false)
    local info = ('Server id %d  \194\183  index %d  \194\183  HP %d%%  \194\183  %.1f yalms'):format(t.sid or 0, t.index or 0,
        t.hpp or 0, t.dist or 0)
    kit.text_mid(d, pg.lx, y + S(41), kit.fit(info, bw - S(16), kit.fonts.text, S(SMALL)), P.dim, kit.fonts.text, S(SMALL))
    local heard = view.ready and 'server has it' or 'server hasn\'t heard yet'
    kit.circle(d, pg.right - kit.measure(heard, kit.fonts.text, S(SMALL - 1)) - S(10), y + S(19), S(3), view.ready and P.teal or P.amber)
    kit.text_right(d, pg.right, y + S(19), heard, view.ready and P.teal or P.amber, kit.fonts.text, S(SMALL - 1))
    pg.y = y + h + S(4)
    -- its actions, by group, laid out in rows
    local groups, order = {}, {}
    for _, a in ipairs(actions.for_target(t, view.me and view.me.name)) do
        if not groups[a.group] then groups[a.group], order[#order + 1] = {}, a.group end
        table.insert(groups[a.group], a)
    end
    for _, g in ipairs(order) do
        subheader(pg, g)
        local x, cy = pg.lx, pg.y + S(13)
        for _, a in ipairs(groups[g]) do
            local w = kit.button_width(a.label)
            if x + w > pg.right and x > pg.lx then
                x, pg.y = pg.lx, pg.y + S(30)
                cy = pg.y + S(13)
            end
            local id = ('##gm_tact_%s_%d_%s'):format(t.kind, t.index or 0, a.label)
            local clicked, bw_
            if a.danger then clicked, bw_ = guarded(id, x, cy, a.label, 'danger')
            else clicked, bw_ = kit.button(id, x, cy, a.label, 'ghost') end
            kit.tip(a.tip .. '\n' .. table.concat(a.lines, '\n') .. (a.cursor and '\n(waits for the server to have your target)' or ''))
            if clicked then act.send_lines(a.lines, a.label) end
            x = x + (bw_ or w) + S(6)
        end
        pg.y = pg.y + S(32)
    end
end

-- Nearby ------------------------------------------------------------------------------------------------------

local NEAR_KINDS = { { 'all', 'All' }, { 'pc', 'Players' }, { 'mob', 'Mobs' }, { 'npc', 'NPCs' } }

-- What a row of the Nearby page offers for entity `e`: { label, line, tip, asks twice }.
local function near_buttons(e)
    if e.kind == 'pc' then
        return { { 'Go to', '!goto ' .. e.name, 'Go to them' }, { 'Bring', '!bring ' .. e.name, 'Bring them to you', true } }
    elseif e.kind == 'mob' then
        return { { 'Go to', '!gotoid ' .. e.sid, 'Go to it' }, { 'Bring', '!mobhere ' .. e.sid, 'Move it to you', true },
                 { 'Despawn', '!despawnmob ' .. e.sid, 'Despawn it', true } }
    elseif e.kind == 'npc' then
        return { { 'Go to', '!gotoid ' .. e.sid, 'Go to it' },
                 { 'Bring', '!npchere ' .. e.sid, 'Move it to you (for everyone in the zone)', true } }
    end
    return { { 'Go to', '!gotoid ' .. e.sid, 'Go to it' } }
end

local function nearby_page(pg)
    state.near = state.near or { kind = 1, q = { '' } }
    local near = state.near
    local cy = pg.y + S(15)
    pg.y = pg.y + S(34)
    local labels, ids = {}, {}
    for j, k in ipairs(NEAR_KINDS) do labels[j], ids[j] = k[2], '##gm_near_kind_' .. k[1] end
    local px = S(BODY - 2)
    local picked, changed = kit.segments(ids, pg.lx, cy, labels, near.kind, true, 1, px)
    if changed then near.kind = picked end
    local fx = pg.lx + kit.segments_width(labels, px) + S(10)
    kit.input('##gm_near_q', fx, cy, pg.right - fx, near.q, 40, 'filter by name')
    local want, q = NEAR_KINDS[near.kind][1], util.trim(near.q[1]):lower()
    local list = {}
    for _, e in ipairs(view.entities or {}) do
        if (want == 'all' or e.kind == want) and (q == '' or e.name:lower():find(q, 1, true)) then list[#list + 1] = e end
    end
    -- nearest first, but held still while the pointer is over the list: a row never moves under a click
    if kit.over(pg.x, pg.top, pg.w, pg.bottom - pg.top) and near.order then
        local at = {}
        for n, index in ipairs(near.order) do at[index] = n end
        table.sort(list, function (a, b)
            local x, y = at[a.index] or math.huge, at[b.index] or math.huge
            if x ~= y then return x < y end
            return a.dist < b.dist
        end)
    end
    near.order = {}
    for n, e in ipairs(list) do near.order[n] = e.index end
    if #list == 0 then
        note(pg, view.entities and #view.entities > 0 and 'Nothing near you matches.' or 'Nothing near you.', P.dim)
        return
    end
    local d = pg.dl
    for _, e in ipairs(list) do
        local y = pg.y
        local lcy = line(pg, nil)
        if y < pg.bottom and y + S(ROW_H) > pg.top then
            local k = KIND[e.kind] or KIND.other
            kit.circle(d, pg.lx + S(3), lcy, S(3.5), k[2])
            local nx = pg.lx + S(14)
            kit.text_mid(d, nx, lcy, kit.fit(e.name, S(150), kit.fonts.text, S(BODY - 1)), P.white, kit.fonts.text, S(BODY - 1))
            local idx = pg.lx + S(170)
            local shown = e.kind == 'pc' and ('%.1fy'):format(e.dist) or ('%d  \194\183  %.1fy'):format(e.sid or 0, e.dist)
            local hovered, clicked = kit.hit(('##gm_near_%d_id'):format(e.index), idx - S(2), y + S(4),
                kit.measure(shown, kit.fonts.text, S(SMALL)) + S(4), S(ROW_H) - S(8))
            kit.text_mid(d, idx, lcy, shown, hovered and e.kind ~= 'pc' and P.accent2 or P.dim, kit.fonts.text, S(SMALL))
            if e.kind ~= 'pc' then
                kit.tip(('Server id %d, index %d, HP %d%%. Click to copy the id.'):format(e.sid or 0, e.index, e.hpp or 0))
                if clicked then
                    imgui.SetClipboardText(tostring(e.sid))
                    act.toast(('Copied %d (%s).'):format(e.sid or 0, e.name))
                end
            end
            local x = pg.right
            local buttons = near_buttons(e)
            for j = #buttons, 1, -1 do
                local b = buttons[j]
                local id = ('##gm_near_%d_%d_%s'):format(e.index, e.sid or 0, b[1])
                local pressed, w
                if b[4] then
                    pressed, w = guarded(id, x, lcy, b[1], 'ghost', true, true)
                else
                    pressed, w = kit.button(id, x - kit.button_width(b[1]), lcy, b[1], 'accent')
                end
                kit.tip(('%s (%s): %s'):format(b[3], e.name, b[2]))
                if pressed then act.send(b[2], { cursor = false }) end
                x = x - (w or kit.button_width(b[1])) - S(6)
            end
        end
    end
end

-- Zone Browser ------------------------------------------------------------------------------------------------
-- Every mob and NPC of a zone, from the server's database (core/spawns.lua): a row per mob group or NPC name; one
-- with several ids opens to a row per id. Bring only in your own zone (the server moves a mob only into it).

local ZB_KINDS = { { 'all', 'All' }, { 'nm', 'NMs' }, { 'mob', 'Mobs' }, { 'npc', 'NPCs' } }
local ZONES = { set = 'zones' }

-- How wide an id's buttons are (unarmed).
local function zb_buttons_width(e, here)
    local w = 0
    for _, b in ipairs(spawns.buttons(e, 0, here)) do w = w + kit.button_width(b[1]) + S(6) end
    return w
end

-- Id `id`'s buttons, right to left from `x`.
local function zb_buttons(e, id, here, x, cy)
    local list = spawns.buttons(e, id, here)
    for j = #list, 1, -1 do
        local b = list[j]
        local bid = ('##gm_zb_%s_%d_%s'):format(e.key, id, b[1])  -- a few ids are a mob and an NPC: by row too
        local pressed, w
        if b[4] then
            pressed, w = guarded(bid, x, cy, b[1], 'ghost', true, true)
        else
            w = kit.button_width(b[1])
            pressed = kit.button(bid, x - w, cy, b[1], j == 1 and 'accent' or 'ghost')
        end
        kit.tip(('%s (%s, %d): %s'):format(b[3], e.name, id, b[2]))
        if pressed then act.send(b[2], { cursor = false }) end
        x = x - (w or kit.button_width(b[1])) - S(6)
    end
end

local function copy_id(id, name)
    imgui.SetClipboardText(tostring(id))
    act.toast(('Copied %d (%s).'):format(id, name))
end

-- A row's words after the name: its tags (NM in amber), levels, and count or id. Returns the x after them.
local function zb_info(d, x, cy, room, e, nup)
    local px = S(SMALL)
    local tags = spawns.tags(e)
    if e.nm and room > S(30) then
        kit.text_mid(d, x, cy, 'NM', P.amber, kit.fonts.semi, px)
        local w = kit.measure('NM', kit.fonts.semi, px) + S(8)
        x, room = x + w, room - w
        table.remove(tags, 1)
    end
    local bits = {}
    for _, t in ipairs(tags) do bits[#bits + 1] = t end
    if spawns.levels(e) ~= '' then bits[#bits + 1] = spawns.levels(e) end
    bits[#bits + 1] = #e.ids > 1 and ('\195\151' .. #e.ids) or tostring(e.ids[1])
    if nup > 0 then bits[#bits + 1] = #e.ids > 1 and (nup .. ' up near you') or 'up near you' end
    if room > S(20) then
        kit.text_mid(d, x, cy, kit.fit(table.concat(bits, '  \194\183  '), room, kit.fonts.text, px), nup > 0 and P.teal or P.dim,
            kit.fonts.text, px)
    end
end

local function zones_page(pg)
    state.zb = state.zb or { kind = 1, q = { '' }, open = {} }
    local zb = state.zb
    local mine = view.me and view.me.zone
    local zone = zb.zone or mine
    local here = zone ~= nil and zone == mine
    -- the zone, and which kind
    local cy = pg.y + S(15)
    pg.y = pg.y + S(34)
    local labels, ids = {}, {}
    for j, k in ipairs(ZB_KINDS) do labels[j], ids[j] = k[2], '##gm_zb_kind_' .. k[1] end
    local px = S(BODY - 2)
    local sw = kit.segments_width(labels, px)
    local picked, changed = kit.segments(ids, pg.right - sw, cy, labels, zb.kind, true, 1, px)
    if changed then zb.kind = picked end
    local away = zb.zone ~= nil and mine ~= nil and zb.zone ~= mine
    local mine_w = kit.button_width('Mine')
    local zw = pg.right - sw - S(10) - pg.lx - (away and (mine_w + S(6)) or 0)
    local ze = zone and data.find(ZONES, tostring(zone))
    local shown = ze and ze.label or (zone and ('Zone ' .. zone)) or '(pick a zone)'
    kit.dropdown('##gm_zb_zone', pg.lx, cy, zw, shown, true, 1, function ()
        local q = filter_box('##gm_zb_zone', math.max(zw, S(360)) - S(20))
        pick_list('##gm_zb_zone', data.filter(data.list(ZONES), q, 300), ze, function (e)
            zb.zone = e.id ~= mine and e.id or nil
            zb.open = {}
        end, S(240))
    end)
    if away then
        if kit.button('##gm_zb_mine', pg.lx + zw + S(6), cy, 'Mine', 'ghost') then zb.zone, zb.open = nil, {} end
        kit.tip('Back to the zone you are in')
    end
    -- the filter
    cy = pg.y + S(13)
    pg.y = pg.y + S(32)
    kit.input('##gm_zb_q', pg.lx, cy, pg.right - pg.lx, zb.q, 40, 'filter by name, server id or index')
    if not zone then
        note(pg, 'Pick a zone: every mob and NPC in it, from the server\'s database.', P.text2)
        return
    end
    local all = spawns.zone(zone)
    if #all == 0 then
        note(pg, 'The server\'s database has no mobs or NPCs in this zone.', P.dim)
        return
    end
    local list = spawns.filter(all, ZB_KINDS[zb.kind][1], util.trim(zb.q[1]))
    local c = spawns.counts(all)
    local function plural(n, s) return ('%d %s%s'):format(n, s, n == 1 and '' or 's') end
    note(pg, ('%s, %s and %s in the server\'s database.%s'):format(plural(c.nm, 'NM'), plural(c.mob, 'mob'),
        plural(c.npc, 'NPC'), here and '' or ' Go to zones you there; Bring is for your own zone.'), P.dim)
    if #list == 0 then
        note(pg, 'Nothing in this zone matches.', P.dim)
        return
    end
    -- what's up near you (your zone only: what the client draws)
    local up = {}
    if here then for _, x in ipairs(view.entities or {}) do if x.sid then up[x.sid] = true end end end
    local d = pg.dl
    local function visible(y) return y < pg.bottom and y + S(ROW_H) > pg.top end
    for _, e in ipairs(list) do
        local y = pg.y
        local lcy = line(pg, nil)
        local single = #e.ids == 1
        local open = not single and zb.open[e.key]
        if visible(y) then
            local nup = 0
            for _, id in ipairs(e.ids) do if up[id] then nup = nup + 1 end end
            kit.circle(d, pg.lx + S(3), lcy, S(3.5), e.kind == 'npc' and P.amber or P.rose)
            if nup > 0 then kit.ring(d, pg.lx + S(3), lcy, S(6), P.teal) end
            local right = single and (pg.right - zb_buttons_width(e, here)) or (pg.right - S(20))
            local nx = pg.lx + S(14)
            local room = right - nx - S(8)
            local name_px = S(BODY - 1)
            local name = kit.fit(e.name, room * 0.62, kit.fonts.text, name_px)
            kit.text_mid(d, nx, lcy, name, P.white, kit.fonts.text, name_px)
            local nw = kit.measure(name, kit.fonts.text, name_px) + S(10)
            zb_info(d, nx + nw, lcy, room - nw, e, nup)
            local hovered, clicked = kit.hit('##gm_zb_row_' .. e.key, nx - S(2), y + S(3), room + S(6), S(ROW_H) - S(6))
            if hovered then
                kit.tooltip(table.concat(spawns.describe(e, jobs()), '\n') .. (single and '\nClick to copy the id.'
                    or '\nClick to list each id.'))
            end
            if clicked then
                if single then copy_id(e.ids[1], e.name) else zb.open[e.key] = not open or nil end
            end
            if single then
                zb_buttons(e, e.ids[1], here, pg.right, lcy)
            else
                kit.icon(d, open and 'down' or 'right', pg.right - S(8), lcy, S(11), hovered and P.text or P.dim)
            end
        end
        if open then
            for _, id in ipairs(e.ids) do
                local sy = pg.y
                local scy = line(pg, nil)
                if visible(sy) then
                    local ix = pg.lx + S(28)
                    if up[id] then kit.circle(d, ix - S(8), scy, S(3), P.teal) end
                    local s = ('%d  \194\183  index %d%s'):format(id, id - spawns.id(e.zone, 0), up[id] and '  \194\183  up near you' or '')
                    local tw = kit.measure(s, kit.fonts.text, S(SMALL))
                    local hovered, clicked = kit.hit(('##gm_zb_id_%s_%d'):format(e.key, id), ix - S(2), sy + S(4), tw + S(4), S(ROW_H) - S(8))
                    kit.text_mid(d, ix, scy, s, hovered and P.accent2 or (up[id] and P.teal or P.text2), kit.fonts.text, S(SMALL))
                    kit.tip('Click to copy the id')
                    if clicked then copy_id(id, e.name) end
                    zb_buttons(e, id, here, pg.right, scy)
                end
            end
        end
    end
end

local SEND_MODES = { { 'packet', 'Packet' }, { 'typed', 'Typed' } }
local LEVELS = { 'Any', '1', '2', '3', '4', '5' }

local function settings_page(pg)
    local cfg = view.cfg
    local function switch(label, on, help, set)
        local cy = line(pg, label, help)
        local v, flipped = kit.switch('##gm_set_' .. label, pg.right - S(kit.SW_W), cy, on, true)
        kit.tip(help)
        if flipped then set(v) store.dirty() end
    end
    local function segs(label, labels, index, help, set)
        local cy = line(pg, label, help)
        local ids = {}
        for j = 1, #labels do ids[j] = '##gm_set_' .. label .. j end
        local px = S(BODY - 2)
        local picked, changed = kit.segments(ids, pg.right - kit.segments_width(labels, px), cy, labels, index, true, 1, px)
        if changed then set(picked) store.dirty() end
    end
    subheader(pg, 'Sending')
    local mi = cfg.send.mode == 'typed' and 2 or 1
    segs('Send as', { 'Packet', 'Typed' }, mi, 'Packet: the line goes as a chat packet, at once, as fast as you send. '
        .. 'Typed: through the chat box (/say), 1.6 seconds apart, as the client throttles typed lines.', function (j)
        cfg.send.mode = SEND_MODES[j][1]
    end)
    switch('Echo each line in chat', cfg.send.echo ~= false, 'An injected line doesn\'t show in your own chat log: '
        .. 'GM Tool prints it there.', function (v) cfg.send.echo = v end)
    switch('Confirm risky commands', cfg.send.confirm ~= false, 'Commands that remove things or act on everyone '
        .. '(jail, delete inventory, crash...) ask for a second click.', function (v) cfg.send.confirm = v end)
    subheader(pg, 'Showing')
    local li = (cfg.gm_level or 0) + 1
    segs('My GM level', LEVELS, li, 'Commands above your level are dimmed (the server ignores them). Any shows all '
        .. 'as they are.', function (j) cfg.gm_level = j - 1 end)
    switch('GM Bar', cfg.ui.bar == true, 'A strip of your favorites as buttons, up with this window closed too '
        .. '(/gmt bar). A click sends one with its form as it is.', function (v) cfg.ui.bar = v end)
    switch('Server page', cfg.ui.show_server == true, 'List the server-wide commands (reloads, the clock, '
        .. 'garbage collection, crash): GM level 4 and 5.', function (v) cfg.ui.show_server = v end)
    switch('Every field', cfg.ui.adv == true, 'Show every argument of every form (augments, cutscene params...), '
        .. 'not just the usual ones.', function (v) cfg.ui.adv = v end)
    do
        local cy = line(pg, 'Size', 'The window\'s size, in percent.')
        local v, moved = kit.slider('##gm_set_scale', pg.right - S(200), cy, S(200), cfg.ui.scale or 100, 50, 200, true, 1, '%')
        if moved then cfg.ui.scale = v store.dirty() end
    end
    do
        local cy = line(pg, 'List rows', 'How many choices a drop-down shows before it scrolls.')
        local v, moved = kit.slider('##gm_set_rows', pg.right - S(200), cy, S(200), cfg.ui.list_rows or 10, 3, 30, true, 1)
        if moved then cfg.ui.list_rows = v store.dirty() end
    end
    subheader(pg, 'Good to know', P.amber)
    note(pg, 'Only a GM\'s ! lines are read by the server. A player\'s that no command takes are said aloud, as /say, '
        .. 'to everyone near: use GM Tool only on a GM character.', P.text2)
    note(pg, 'A command above your GM level, or one the server doesn\'t have, gets no answer at all.', P.text2)
    note(pg, ('Queued: %d line%s.'):format(view.pending or 0, view.pending == 1 and '' or 's'), P.dim)
end

-- Sidebar -------------------------------------------------------------------------------------------------------

local FOOT = { { 'console', 'Console' }, { 'history', 'History' }, { 'macros', 'Macros' }, { 'places', 'Places' },
               { 'settings', 'Settings' } }

local function nav_item(id, title, x, y, w, count)
    local d, ih = dl(), S(NAV_H)
    local hovered, clicked = kit.hit('##gm_page_' .. id, x, y, w, ih)
    if clicked then
        state.page = id
        state.search[1] = ''
        view.cfg.ui.page = id
        store.dirty()
    end
    local active = state.page == id
    local lit = kit.ease('nav.' .. id, active and 1 or 0, 20)
    if lit > 0.01 then
        kit.fill(d, x, y, w, ih, P.accent_bg, 0, 0.9 * lit)
        kit.fill(d, x, y, S(2), ih, P.accent, 0, lit)
    end
    if hovered and not active then kit.fill(d, x, y, w, ih, P.hover, 0, 0.7) end
    local cy = y + ih / 2
    local dx = x + S(PAD) + S(2)
    if id == 'favorites' then
        star(d, dx, cy, S(5), active and P.amber or P.faint, true)
    else
        kit.circle(d, dx, cy, S(3), active and P.accent or P.faint)
    end
    kit.text_mid(d, x + S(PAD) + S(14), cy, title, active and P.white or P.text, kit.fonts.text, S(BODY - 0.5))
    if count then kit.text_right(d, x + w - S(PAD), cy, tostring(count), P.faint, kit.fonts.text, S(SMALL - 1)) end
    return ih
end

local function sidebar(x, y, w, h)
    local d = dl()
    local pad = S(PAD)
    kit.text_mid(d, x + pad, y + S(24), 'GM Tool', P.white, kit.fonts.semi, S(BODY + 1))
    -- you and your target
    local small = S(SMALL - 0.5)
    local me = view.me
    local where = me and me.zone and (view.zone_name or ('zone ' .. me.zone)) or 'not logged in'
    kit.text_mid(d, x + pad, y + S(44), kit.fit(where, w - pad * 2, kit.fonts.text, small), P.dim, kit.fonts.text, small)
    local t = view.target
    local ts = t and ('%s %s \194\183 %d'):format(t.kind:upper(), t.name, t.sid or 0) or 'no target'
    kit.circle(d, x + pad + S(3), y + S(62), S(3), t and (view.ready and P.teal or P.amber) or P.faint)
    kit.text_mid(d, x + pad + S(12), y + S(62), kit.fit(ts, w - pad * 2 - S(12), kit.fonts.text, small), t and P.text2 or P.faint,
        kit.fonts.text, small)
    if kit.over(x, y + S(52), w, S(20)) and t then
        kit.tooltip(('%s (%s)\nServer id %d, index %d\n%s'):format(t.name, t.kind, t.sid or 0, t.index or 0,
            view.ready and 'The server has this target.' or 'The server hasn\'t heard of this target yet.'))
    end
    -- search
    local sy = y + S(88)
    local sw = w - pad * 2
    kit.fill(d, x + pad, sy - S(13) + S(2), sw, S(26), '#000000', S(6), 0.3)
    if kit.input('##gm_search', x + pad, sy, sw, state.search, 40, 'Search commands') then
        if util.trim(state.search[1]) ~= '' then state.page = 'search' end
    end
    if state.page == 'search' and util.trim(state.search[1]) == '' then state.page = view.cfg.ui.page or 'favorites' end
    -- the pages, scrolling
    local top = y + S(110)
    local foot_h = #FOOT * S(NAV_H) + S(34)
    local list_h = h - (top - y) - foot_h
    kit.line(d, x + pad, top - S(4), x + w - pad, top - S(4), P.border, 0.8)
    imgui.SetCursorScreenPos({ x, top })
    local ok, err = true, nil
    if kit.child('##gm_nav', w, list_h) then
        ok, err = pcall(function ()
            local cx, cy = imgui.GetCursorScreenPos()
            local ny = cy + S(2)
            ny = ny + nav_item('favorites', 'Favorites', cx, ny, w, #view.cfg.favorites > 0 and #view.cfg.favorites or nil)
            ny = ny + nav_item('target', 'Target', cx, ny, w)
            ny = ny + nav_item('nearby', 'Nearby', cx, ny, w)
            ny = ny + nav_item('zones', 'Zone Browser', cx, ny, w)
            for _, p in ipairs(catalog.PAGES) do
                if p[1] ~= 'server' or view.cfg.ui.show_server then
                    ny = ny + nav_item(p[1], p[2], cx, ny, w, #catalog.page_of[p[1]].commands)
                end
            end
            imgui.SetCursorScreenPos({ cx, ny })
            imgui.Dummy({ 1, S(4) })
        end)
    end
    imgui.EndChild()
    if not ok then error(err, 0) end
    local fy = y + h - foot_h
    kit.line(d, x + pad, fy + S(6), x + w - pad, fy + S(6), P.border, 0.8)
    kit.text_mid(d, x + pad, fy + S(20), 'TOOLS', P.faint, kit.fonts.semi, S(SMALL - 1.5))
    fy = fy + S(32)
    for _, f in ipairs(FOOT) do fy = fy + nav_item(f[1], f[2], x, fy, w) end
end

-- The page ------------------------------------------------------------------------------------------------------

local function close_mark(id, cx, cy, box)
    local hovered, clicked = kit.hit(id, cx - box / 2, cy - box / 2, box, box)
    kit.icon(dl(), 'close', cx, cy, box * 0.72, hovered and P.rose or P.dim)
    return clicked
end

local TITLES = { favorites = 'Favorites', target = 'Target', nearby = 'Nearby', zones = 'Zone Browser', console = 'Console',
                 history = 'History', settings = 'Settings', search = 'Search', macros = 'Macros', places = 'Places' }

local function page_title(id)
    if TITLES[id] then return TITLES[id] end
    local p = catalog.page_of[id]
    return p and p.title or id
end

local COMMAND_PAGES = { favorites = true, search = true, macros = true, places = true }

local function page(x, y, w, h)
    local d = dl()
    local id = state.page
    local cy = y + S(TITLE_H) / 2
    kit.text_mid(d, x + S(LEFT), cy, page_title(id), P.white, kit.fonts.semi, S(BODY + 1))
    if view.pending and view.pending > 0 then
        local cw = kit.button_width('Clear')
        local cx_ = x + w - S(PAD) - S(30) - cw
        if kit.button('##gm_queue_clear', cx_, cy, 'Clear', 'ghost') then act.clear_queue() end
        local lines = {}
        for _, q in ipairs(view.queued or {}) do lines[#lines + 1] = q.line .. (q.cursor and '  (waits for its target)' or '') end
        kit.tip('Drop every line still waiting:\n' .. table.concat(lines, '\n'))
        kit.text_right(d, cx_ - S(8), cy, ('%d queued'):format(view.pending), P.amber, kit.fonts.text, S(SMALL))
    end
    if close_mark('##gm_close', x + w - S(PAD) - S(10), cy, S(21)) then act.close() end
    kit.tip('Close (/gmt opens it again)')
    kit.line(d, x, y + S(TITLE_H), x + w, y + S(TITLE_H), P.border)
    local body_y = y + S(TITLE_H) + 1
    local commands = COMMAND_PAGES[id] or catalog.page_of[id] ~= nil
    if commands then
        acting_strip(x, body_y, w)
        body_y = body_y + S(ACT_H) + 1
    end
    local body_h = y + h - body_y - S(TOAST_H)
    imgui.SetCursorScreenPos({ x, body_y })
    local ok, err = true, nil
    if kit.child('##gm_pane_' .. id, w, body_h) then
        ok, err = pcall(function ()
            local cx, ccy = imgui.GetCursorScreenPos()
            local pg = { dl = imgui.GetWindowDrawList(), x = cx, w = w, y = ccy + S(8), lx = cx + S(LEFT),
                         right = cx + w - S(PAD), alpha = 1, top = body_y, bottom = body_y + body_h }
            if id == 'favorites' then favorites_page(pg)
            elseif id == 'target' then target_page(pg)
            elseif id == 'nearby' then nearby_page(pg)
            elseif id == 'zones' then zones_page(pg)
            elseif id == 'search' then search_page(pg)
            elseif id == 'console' then console_page(pg)
            elseif id == 'history' then history_page(pg)
            elseif id == 'settings' then settings_page(pg)
            elseif id == 'macros' then macros_page(pg)
            elseif id == 'places' then places_page(pg)
            else commands_page(pg, id) end
            imgui.SetCursorScreenPos({ cx, pg.y })
            imgui.Dummy({ 1, S(12) })  -- drawn content has no item: this tells the child how far it scrolls
        end)
    end
    imgui.EndChild()
    if not ok then error(err, 0) end
    -- the last thing said
    local ty = y + h - S(TOAST_H)
    kit.line(d, x, ty, x + w, ty, P.border, 0.8)
    local toast = view.toast
    if toast and view.now - toast.at < 8 then
        local color = toast.kind == 'error' and P.rose or toast.kind == 'warn' and P.amber
            or toast.kind == 'reply' and P.accent2 or P.teal
        local a = util.clamp(8 - (view.now - toast.at), 0, 1)
        kit.text_mid(d, x + S(LEFT), ty + S(TOAST_H) / 2, kit.fit(toast.text, w - S(LEFT) - S(PAD), kit.fonts.text, S(SMALL)),
            color, kit.fonts.text, S(SMALL), a)
    end
end

-- The window ----------------------------------------------------------------------------------------------------

local FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoNavInputs  -- Tab is the game's (target cycling), not ImGui's
local COLOURS = {
    { ImGuiCol_ChildBg, { 0, 0, 0, 0 } }, { ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 } },
    { ImGuiCol_ScrollbarGrab, kit.rgba('#3A4158') }, { ImGuiCol_ScrollbarGrabHovered, kit.rgba('#4A5270') },
    { ImGuiCol_ScrollbarGrabActive, kit.rgba(P.accent_lo) },
}

local user_scale = 1

-- Once, at load, before any frame: Segoe UI, which ImGui 1.81 (Ashita 4.16) takes only then.
function window.load() kit.bake() end

-- The main window. Returns the error its inside raised.
local function main_window()
    local m, side = S(MARGIN), S(SIDE_W)
    local pw, ph = side + S(PAGE_W), S(WIN_H)
    local sw, sh = kit.screen()
    imgui.SetNextWindowPos({ sw / 2, sh / 2 }, ImGuiCond_FirstUseEver, { 0.5, 0.5 })
    imgui.SetNextWindowSize({ pw + m * 2, ph + m * 2 }, ImGuiCond_Always)
    local vars = kit.push_style(COLOURS, ImGuiStyleVar_WindowPadding, { 0, 0 }, ImGuiStyleVar_WindowBorderSize, 0,
        ImGuiStyleVar_ItemSpacing, { 0, 0 }, ImGuiStyleVar_ScrollbarSize, S(6), ImGuiStyleVar_ScrollbarRounding, S(3))
    local open = { true }
    local ok, err = true, nil
    if imgui.Begin('GM Tool###gmtool', open, FLAGS) then
        local x, y = imgui.GetCursorScreenPos()
        x, y = x + m, y + m
        local d = dl()
        kit.fill(d, x - 1, y, pw + 2, ph + 2, '#000000', S(6), 0.35)  -- its shadow
        kit.fill(d, x, y, pw, ph, P.bg, S(5))
        kit.fill(d, x, y, side, ph, P.side, S(5), 1, kit.LEFT_CORNERS)
        kit.line(d, x + side, y, x + side, y + ph, P.border)
        kit.outline(d, x, y, pw, ph, P.border, S(5))
        ok, err = pcall(function ()
            sidebar(x, y, side, ph)
            page(x + side + 1, y, pw - side - 1, ph)
        end)
    end
    imgui.End()
    kit.pop_style(COLOURS, vars)
    if not open[1] then act.close() end
    if not ok then return err end
end

-- The GM Bar: your favorites as buttons in a strip of their own (cfg.ui.bar), up with the main window closed too.
-- A click sends the favorite with its form's values as they are (the tooltip shows the line); one that can't go
-- yet opens its card in the main window instead. GM opens and closes the main window.
local BAR_FLAGS = ImGuiWindowFlags_NoTitleBar + ImGuiWindowFlags_NoResize + ImGuiWindowFlags_NoScrollbar
    + ImGuiWindowFlags_NoScrollWithMouse + ImGuiWindowFlags_NoCollapse + ImGuiWindowFlags_NoBackground
    + ImGuiWindowFlags_NoNavInputs + ImGuiWindowFlags_AlwaysAutoResize + ImGuiWindowFlags_NoFocusOnAppearing

local function open_card(c)
    view.cfg.ui.open = true
    state.page, state.open[c.key] = 'favorites', true
    store.dirty()
end

local function bar_body()
    local x0, y0 = imgui.GetCursorScreenPos()
    local pad, gap, h = S(6), S(5), S(34)
    local list = commands_of('favorites')
    local items = { { label = 'GM', lead = true } }
    for _, c in ipairs(list) do items[#items + 1] = { label = c.title, c = c } end
    local total = pad
    for _, it in ipairs(items) do
        it.w = kit.button_width(it.label)
        total = total + it.w + gap
    end
    local hint = #list == 0 and 'Star commands to put them here' or nil
    if hint then total = total + kit.measure(hint, kit.fonts.text, S(SMALL)) + gap end
    total = total - gap + pad
    local d = dl()
    kit.fill(d, x0, y0, total, h, P.bg, S(6), 0.94)
    kit.outline(d, x0, y0, total, h, P.border, S(6))
    local x, cy = x0 + pad, y0 + h / 2
    for _, it in ipairs(items) do
        if it.lead then
            local open = view.cfg.ui.open ~= false
            if kit.button('##gmbar_open', x, cy, it.label, open and 'accent' or 'ghost') then
                view.cfg.ui.open = not open
                store.dirty()
            end
            kit.tip(open and 'Close GM Tool' or 'Open GM Tool')
            x = x + it.w + gap
        else
            local c = it.c
            local values = store.form(c.key)
            local lines, why = build.lines(c, values, ctx())
            local id = '##gmbar_' .. c.key
            local clicked, w
            if c.danger then clicked, w = guarded(id, x, cy, it.label, 'danger')
            else clicked, w = kit.button(id, x, cy, it.label, 'ghost') end
            kit.tip(lines and sends_tip(lines) or ('Can\'t send yet (' .. tostring(why) .. '): a click opens its form'))
            if clicked then
                if lines then send_card(c, values) else open_card(c) end
            end
            x = x + math.max(w or it.w, it.w) + gap
        end
    end
    if hint then kit.text_mid(d, x, cy, hint, P.dim, kit.fonts.text, S(SMALL)) end
    imgui.SetCursorScreenPos({ x0, y0 })
    imgui.Dummy({ total, h })  -- the strip's size, for the auto-size
end

local function bar_window()
    local sw = kit.screen()
    imgui.SetNextWindowPos({ sw / 2, S(60) }, ImGuiCond_FirstUseEver, { 0.5, 0 })
    local vars = kit.push_style(COLOURS, ImGuiStyleVar_WindowPadding, { 0, 0 }, ImGuiStyleVar_WindowBorderSize, 0,
        ImGuiStyleVar_ItemSpacing, { 0, 0 })
    local ok, err = true, nil
    if imgui.Begin('GM Bar###gmtool_bar', true, BAR_FLAGS) then ok, err = pcall(bar_body) end
    imgui.End()
    kit.pop_style(COLOURS, vars)
    if not ok then return err end
end

-- One frame: the main window while cfg.ui.open, the bar while cfg.ui.bar. A Lua error raised while drawing is
-- raised again after the windows are ended, so ImGui stays balanced.
function window.render(view_, act_)
    view, act = view_, act_
    if not imgui.IsAnyItemActive() then user_scale = util.clamp(tonumber(view.cfg.ui.scale) or 100, 50, 200) / 100 end
    kit.frame(user_scale, false)
    kit.list_rows = kit.rows(view.cfg.ui.list_rows)
    if not state.page then state.page = view.cfg.ui.page or 'favorites' end
    if state.page == 'server' and not view.cfg.ui.show_server then state.page = 'favorites' end
    if not (TITLES[state.page] or catalog.page_of[state.page]) then state.page = 'favorites' end
    -- whatever was armed was for the target you had: another (or none) disarms it all
    local tindex = view.target and view.target.index or 0
    if tindex ~= state.target_index then state.armed, state.target_index = {}, tindex end
    local err
    if view.cfg.ui.open ~= false then err = main_window() end
    if view.cfg.ui.bar then err = bar_window() or err end
    kit.tooltips()
    if err then error(err, 0) end
end

return window
