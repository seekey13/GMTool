--[[
GM Tool - every GM command of a LandSandBoat server, a click away
Copyright (c) 2026 Seekey

This addon is designed for Ashita v4 and the CatsEyeXI private server.

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version. It is
distributed WITHOUT ANY WARRANTY; see LICENSE for the details.
SPDX-License-Identifier: GPL-3.0-or-later
]]--

addon.name    = 'GMTool'
addon.author  = 'Seekey'
addon.version = '1.0.0'
addon.desc    = 'Buttons and forms for every GM command'
addon.link    = 'https://github.com/seekey13/GMTool'

require('common')
local chat = require('chat')
local imgui = require('imgui')
local build = require('core.build')
local catalog = require('core.catalog')
local data = require('core.data')
local game = require('core.game')
local macros = require('core.macros')
local replies = require('core.replies')
local send = require('core.send')
local store = require('core.store')
local window = require('ui.window')

local function say(style, fmt, ...)
    print(chat.header(addon.name) .. style(fmt:format(...)))
end
local function printf(fmt, ...) say(chat.message, fmt, ...) end

-- The client's names for what the server lists by id (core/data.lua).
local function res() return AshitaCore:GetResourceManager() end
data.res.item = function (id)
    local it = res():GetItemById(id)
    return it and it.Name and it.Name[1] or nil
end
data.res.spell = function (id)
    local sp = res():GetSpellById(id)
    return sp and sp.Name and sp.Name[1] or nil
end
data.res.zone = function (id) return res():GetString('zones.names', id) end
data.res.keyitem = function (id) return res():GetString('keyitems.names', id) end

-- Saying lines to the server (core/send.lua).
local toast
local function notify(text, kind) toast = { text = text, kind = kind or 'info', at = os.clock() } end

send.out.packet = function (line) AshitaCore:GetPacketManager():AddOutgoingPacket(0xB5, send.packet_bytes(line)) end
send.out.typed = function (line) AshitaCore:GetChatManager():QueueCommand(1, '/say ' .. line) end
send.out.echo = function (line) print(chat.header(addon.name) .. chat.color1(82, line)) end
send.out.said = function (fmt, ...)
    say(chat.warning, fmt, ...)
    notify(fmt:format(...), 'warn')
end
send.out.sent = function (line)
    store.remember(line, os.time())
    replies.sent(store.cfg.history[1], os.clock())
end

-- What the window may do (ui/window.lua).
local act = {
    -- Queues a built line. `info.cursor`: it acts on your cursor target, so it goes only while the server has the
    -- target you have now (sent with its index), and is dropped if you target something else first.
    -- `info.names`: the player names in it, for the pickers' recent names.
    send = function (line, info)
        local cursor = info and info.cursor
        local t = game.target()
        local fits, bad = build.cursor_check(line, t)  -- a typed or remembered line: never a mob's command at a player
        if not fits then return notify(bad, 'error') end
        local ok, why = send.line(line, { cursor = cursor, index = t and t.index or 0 })
        if not ok then return notify(why, 'error') end
        for _, n in ipairs(info and info.names or {}) do store.name_used(n) end
        if cursor and not game.ready(t) then
            notify(('Queued %s: it goes once the server has your target.'):format(line), 'warn')
        else
            notify(('Sent %s'):format(line))
        end
    end,
    -- Queues several lines (a macro's, a Target action's), each checked first: all or none; those that read the
    -- cursor bound to the target you have now.
    send_lines = function (lines, name)
        local t = game.target()
        local index = t and t.index or 0
        for _, l in ipairs(lines) do
            local fits, bad = build.cursor_check(l, t)
            if not fits then return notify(('%s: %s'):format(name or 'Macro', bad), 'error') end
        end
        local ok, why = send.lines(lines, function (l) return { cursor = build.reads_cursor(l), index = index } end)
        if not ok then return notify(why, 'error') end
        notify(('%s: %d line%s queued.'):format(name or 'Macro', #lines, #lines == 1 and '' or 's'))
    end,
    -- Drops every line waiting.
    clear_queue = function ()
        local n = send.clear()
        notify(('Dropped %d queued line%s.'):format(n, n == 1 and '' or 's'), 'warn')
    end,
    toast = notify,
    close = function ()
        store.cfg.ui.open = false
        store.dirty()
    end,
    clear_history = function ()
        store.cfg.history = {}
        store.dirty()
    end,
}

-- The players near you, read once a second at most (a scan of every player entity).
local players, players_at = {}, -math.huge
local entities, entities_at = {}, -math.huge  -- the Nearby page's, read while it shows
local failed  -- the window's last error, said once; /gmt opens it again

local function view(now)
    local me = game.me()
    if now - players_at > 1 then
        players, players_at = game.players(), now
    end
    local page = window.state.page
    if (page == 'nearby' or page == 'zones') and store.cfg.ui.open and now - entities_at > 1 then
        entities, entities_at = game.entities(150), now
    end
    local t = game.target()
    return {
        cfg = store.cfg, me = me, target = t, ready = game.ready(t), players = players,
        zone_name = me and me.zone and game.zone_name(me.zone), now = now, time = os.time(),
        pending = send.pending(), queued = send.queued(), toast = toast, entities = entities,
    }
end

local saved_at = -math.huge

ashita.events.register('d3d_present', 'gmtool_present', function ()
    local now = os.clock()
    send.tick(now, store.cfg.send, game.probe)
    if (store.cfg.ui.open or store.cfg.ui.bar) and not failed then
        local ok, err = pcall(window.render, view(now), act)
        if not ok then
            failed = tostring(err)
            say(chat.error, 'The window failed and closed: %s. /gmt opens it again.', failed)
        end
    end
    -- Saved once nothing is held (a slider mid-drag would save each frame), at most once a second.
    if store.is_dirty() and now - saved_at > 1 and not imgui.IsAnyItemActive() then
        store.save()
        saved_at = now
    end
end)

ashita.events.register('load', 'gmtool_load', function ()
    store.load()
    store.watch()
    window.load()
end)

ashita.events.register('unload', 'gmtool_unload', function ()
    if store.is_dirty() then store.save() end
end)

-- The server's answer to a line just sent: kept with it (History) and shown in the status line.
ashita.events.register('text_in', 'gmtool_text_in', function (e)
    local s = replies.text(e.message, os.clock(), e.mode, e.injected)
    if s then notify(s, 'reply') end
end)

ashita.events.register('packet_in', 'gmtool_packet_in', function (e)
    game.on_packet_in(e.id)
end)

ashita.events.register('packet_out', 'gmtool_packet_out', function (e)
    game.on_packet_out(e.id, e.data)
end)

-- What a macro or place needs to know, as the window's: you, your target, Acting on, where you stand.
local function context()
    local me, a = game.me(), store.cfg.acting
    return { me = me and me.name, target = game.target(), mode = a.mode, name = a.name,
             pos = me and me.x and { x = me.x, y = me.y, z = me.z } or nil, zone = me and me.zone }
end

local HELP = {
    '/gmt  open or close GM Tool (/gmtool too)',
    '/gmt <command> [args]  send a GM command through GM Tool: /gmt hp 100 Kupipi, /gmt !where',
    '/gmt page <name>  open a page: favorites, target, nearby, zones, player, travel, items, macros, history...',
    '/gmt find <words>  open the window searching for commands',
    '/gmt macro <name>  run a macro (Macros page)',
    '/gmt place <name> [player]  put yourself, or a player, at a saved place (Places page)',
    '/gmt clear  drop every line still waiting in the queue',
    '/gmt bar  show or hide the GM Bar: your favorites as buttons',
    '/gmt help  this list',
}

-- A page by its id or title, any case, a prefix will do.
local function page_named(s)
    s = s:lower()
    local pages = { 'favorites', 'console', 'history', 'settings' }
    for _, p in ipairs(catalog.PAGES) do pages[#pages + 1] = p[1] end
    for _, id in ipairs({ 'target', 'nearby', 'zones', 'macros', 'places' }) do pages[#pages + 1] = id end
    local TITLES = { zones = 'zone browser' }
    local function title(id)
        local p = catalog.page_of[id]
        return p and p.title:lower() or TITLES[id] or id
    end
    for _, id in ipairs(pages) do  -- a whole name first, then the first a prefix fits
        if id == s or title(id) == s then return id end
    end
    for _, id in ipairs(pages) do
        if id:sub(1, #s) == s or title(id):sub(1, #s) == s then return id end
    end
end

local function open_page(id)
    store.cfg.ui.open, store.cfg.ui.page = true, id
    window.state.page = id
    failed = nil
    store.dirty()
end

ashita.events.register('command', 'gmtool_command', function (e)
    local args = e.command:args()
    if #args == 0 then return end
    local head = args[1]:lower()
    if head ~= '/gmt' and head ~= '/gmtool' then return end
    e.blocked = true
    local sub = (args[2] or ''):lower()
    if sub == '' then
        store.cfg.ui.open = not store.cfg.ui.open or failed ~= nil
        failed = nil
        store.dirty()
        return
    end
    if sub == 'help' then
        for _, l in ipairs(HELP) do printf('%s', l) end
        return
    end
    local rest = e.command:match('^%S+%s+%S+%s*(.*)$') or ''
    if sub == 'clear' then return act.clear_queue() end
    if sub == 'bar' then
        store.cfg.ui.bar, failed = not store.cfg.ui.bar, nil
        store.dirty()
        return printf('GM Bar %s.', store.cfg.ui.bar and 'on' or 'off')
    end
    if sub == 'page' then
        local id = page_named(rest)
        if not id then return say(chat.error, 'No page "%s". /gmt help', rest) end
        return open_page(id)
    end
    if sub == 'find' or sub == 'search' then
        open_page(store.cfg.ui.page or 'favorites')
        window.state.search[1] = rest
        window.state.page = rest ~= '' and 'search' or window.state.page
        return
    end
    if sub == 'macro' or sub == 'run' then
        if rest:match('^%s*$') then return say(chat.error, '/gmt macro <name>: the Macros page lists them.') end
        local m = macros.find(store.cfg.macros, rest)
        if not m then return say(chat.error, 'No macro "%s" (the Macros page lists them).', rest) end
        local lines, why = macros.lines(m, context())
        if not lines then return say(chat.error, '%s: %s', m.name, why) end
        if why == true then
            return say(chat.error, '%s has a risky line: run it from the Macros page, where it asks twice.', m.name)
        end
        return act.send_lines(lines, m.name)
    end
    if sub == 'place' then
        -- the longest name that matches, so a place's name may have spaces: /gmt place Ru'Lude Gardens Kupipi
        local words, p, who = {}, nil, nil
        for w in rest:gmatch('%S+') do words[#words + 1] = w end
        for n = #words, 1, -1 do
            p = macros.find(store.cfg.places, table.concat(words, ' ', 1, n))
            if p then who = words[n + 1] break end
        end
        if not p then return say(chat.error, 'No place "%s" (the Places page lists them).', rest) end
        local ctx = context()
        if who then
            local named, why = build.substitute(who, ctx)
            if not named then return say(chat.error, '%s', why) end
            if not build.is_name(named) then return say(chat.error, '"%s" is not a character name.', named) end
            who = named
        end
        local here = who and game.zone_of(who) or ctx.zone  -- the zone the one moved is in, if known
        local ok, err = send.line(macros.place_line(p, who, here), { cursor = false })
        if not ok then say(chat.error, '%s', err) end
        return
    end
    -- Anything else is a GM command: '/gmt hp 100', '/gmt !hp 100'.
    local ctx = context()
    local line, why = build.tidy(e.command:match('^%S+%s+(.*)$') or '', ctx)
    if not line then return say(chat.error, '%s', why) end
    local name = line:match('^!(%S+)') or ''
    local server = data.raw('server') or {}
    if not server[name:lower()] then
        say(chat.warning, 'The server has no !%s: sending it anyway.', name)
    end
    act.send(line, { cursor = build.reads_cursor(line) })
end)
