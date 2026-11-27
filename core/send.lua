--[[
    Sends GM command lines, in order, one queue for everything (a form's Send, a preset, a macro's lines, /gmt).

    Two ways out (settings send.mode):
      'packet'  the line as a say chat packet (0x0B5), injected: no chat box, so none of its throttle (a line
                within about 1.5 s of the last is dropped, "A command error occurred"), and several can go a
                frame. The server reads a '!' line before anyone hears it and never repeats a GM's
                (docs/gm-commands.md). Your own client doesn't show an injected line: GM Tool echoes it.
      'typed'   '/say <line>' through the chat box, as if typed: the client shows it, and lines go 1.6 s apart.

    A line that acts on your cursor target goes only while the server has the target you had when you sent it
    (core/game.lua), waiting up to WAIT seconds for the server to hear of it; it's dropped and said so if you target
    something else first, or the server never hears of it: never sent at whatever the server last heard.

    Not a GM: the server says a '!' line it doesn't take aloud, as /say. GM Tool can't tell; the README says so.
]]--

local build = require('core.build')

local send = {}

send.GAP = { packet = 0.1, typed = 1.6 }  -- seconds between lines
send.WAIT = 3                             -- seconds a cursor line waits for the server to hear your target

local queue = {}
local last_at = -math.huge

-- What sending does, set by GMTool.lua in game and by the tests: packet(line), typed(line), echo(line),
-- said(fmt, ...) for a message, sent(line) once a line is gone (history).
send.out = {
    packet = function () end, typed = function () end, echo = function () end, said = function () end, sent = function () end,
}

-- The chat packet for `line`: 0x0B5 with its size in 4-byte units above the id's ninth bit, say mode, the text,
-- NUL-padded to a multiple of 4 (at least one NUL). A list of bytes, as AddOutgoingPacket takes it.
function send.packet_bytes(line)
    local b = { 0xB5, 0, 0, 0, 0x00, 0x00 }
    for i = 1, #line do b[#b + 1] = line:byte(i) end
    repeat b[#b + 1] = 0 until #b % 4 == 0
    b[2] = #b / 4 * 2
    return b
end

-- Queues `line` (checked first). `o.cursor`: it acts on your cursor target, so it goes only while the server has
-- the target you had when you asked (`o.index`, its entity index; nil or 0 for none), and is dropped if you
-- target something else first. Returns ok, or nil and why.
function send.line(line, o)
    local ok, why = build.check(line)
    if not ok then return nil, why end
    queue[#queue + 1] = { line = line, cursor = o and o.cursor, index = o and o.index or 0, added = nil }
    return true
end

-- Every line of `lines`, all or none: each checked before the first is queued. `o` as send.line's, or a function
-- of the line giving it.
function send.lines(lines, o)
    for _, l in ipairs(lines) do
        local ok, why = build.check(l)
        if not ok then return nil, ('%s: %s'):format(l, why) end
    end
    for _, l in ipairs(lines) do send.line(l, type(o) == 'function' and o(l) or o) end
    return true
end

function send.pending() return #queue end

-- The lines waiting, in order: { line, cursor, index }, to show.
function send.queued()
    local out = {}
    for i, q in ipairs(queue) do out[i] = { line = q.line, cursor = q.cursor, index = q.index } end
    return out
end

-- Drops every line waiting. Returns how many.
function send.clear()
    local n = #queue
    queue = {}
    return n
end

-- Once a frame: the next line goes when its gap is up and, for a cursor line, while the server has its target.
-- `now` in seconds; `cfg` the send settings ({ mode, echo }); `probe()` gives what the server last heard as your
-- target (its entity index; nil before any position packet), your target now (0 for none), and whether you are
-- picking a sub-target.
function send.tick(now, cfg, probe)
    local q = queue[1]
    if not q then return end
    q.added = q.added or now
    local mode = cfg and cfg.mode == 'typed' and 'typed' or 'packet'
    if now - last_at < send.GAP[mode] then return end
    if q.cursor then
        local heard, current, sub = probe()
        if (current or 0) ~= q.index then
            table.remove(queue, 1)
            send.out.said('Dropped %s: you targeted something else before the server had your target. Resend it.', q.line)
            return
        end
        if heard ~= q.index or sub then
            if now - q.added >= send.WAIT then
                table.remove(queue, 1)
                send.out.said('Dropped %s: the server never heard of your target. Target it again and resend.', q.line)
            end
            return
        end
    end
    table.remove(queue, 1)
    last_at = now
    if mode == 'typed' then send.out.typed(q.line) else send.out.packet(q.line) end
    -- a typed line shows in your chat log already
    if mode ~= 'typed' and (cfg == nil or cfg.echo ~= false) then send.out.echo(q.line) end
    send.out.sent(q.line)
end

-- For the tests: the time the last line went.
function send.reset() queue, last_at = {}, -math.huge end

return send
