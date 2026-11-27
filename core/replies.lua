--[[
    The server's answers to what GM Tool sent: the chat lines that arrive in the moment after a line goes
    (!getid's id, !geteffects' list, !pos's position), kept with that line for the History page and shown in the
    status line. Pure: GMTool.lua feeds it the lines sent (replies.sent) and every incoming chat line
    (replies.text, from Ashita's text_in).

    The server's printToPlayer lines come as system messages, a moment after the command. GM Tool can't be sure
    which lines those are (Ashita gives each line's chat mode, but which modes the server's system lines take
    isn't something GM Tool can check outside the game), so it keeps what comes within the window after a send
    (WINDOW seconds, stretched by STRETCH after each line kept, to LONGEST at most), MAX lines, and leaves out:
      - a line an addon printed (Ashita marks it injected), GM Tool's own echo too;
      - a line shaped like a player's chat: say and shout ("Name : ..."), yell ("Name[Zone]: ..."), tells
        ("Name>> ...", ">>Name : ..."), party ("(Name) ..."), linkshell ("<Name> ...", "[1]<Name> ..."), unity
        ("{Name} ..."), after any timestamp an addon put in front ("[12:00:00] ...").
    Each line keeps its chat mode, to tell the rest apart if need be.

    Lines sent together (a macro's, a Target action's: within one window) are one batch: what comes back belongs to
    the batch, shown under its newest line. Kept in memory only.
]]--

local replies = {}

replies.WINDOW = 2.5
replies.STRETCH = 1.5
replies.LONGEST = 8
replies.MAX = 16

local open                                           -- the batch being answered: { lines, owner, from, ends }
local by_entry = setmetatable({}, { __mode = 'k' })  -- [history entry] = its batch

-- Chat text without the client's colour and control codes ('\30\1', '\31\121', auto-translate's '\253...\253').
function replies.clean(s)
    s = tostring(s or '')
    s = s:gsub('\253.....', ''):gsub('[\30\31].', ''):gsub('\127.', ''):gsub('[%c]', ' ')
    return (s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

local CHAT = {
    '^%a+ : ',               -- say, shout
    '^%a+%[[^%]]*%]: ',      -- yell
    '^%a+>> ', '^>>%a+ : ',  -- tells, in and out
    '^%(%a+%) ',             -- party
    '^<%a+> ', '^%[%d%]<%a+> ',  -- linkshells
    '^{%a+} ',               -- unity
}

-- Whether cleaned line `s` is shaped like a player's chat.
function replies.chat(s)
    s = s:gsub('^%[%d+:%d+:?%d*%]%s*', '')  -- a timestamp addon's
    for _, p in ipairs(CHAT) do if s:find(p) then return true end end
    return false
end

-- A line went, its history entry `entry`: what comes next belongs to it, or to the batch it joins.
function replies.sent(entry, now)
    if open and now <= open.ends then
        open.owner = entry
        open.ends = math.max(open.ends, now + replies.WINDOW)
    else
        open = { lines = {}, modes = {}, owner = entry, from = now, ends = now + replies.WINDOW }
    end
    by_entry[entry] = open
end

-- An incoming chat line, its chat `mode`, whether an addon `injected` it. Returns it, cleaned, when it was kept
-- as an answer; else nil.
function replies.text(msg, now, mode, injected)
    if not open or now > open.ends or injected then return nil end
    local s = replies.clean(msg)
    if s == '' or replies.chat(s) then return nil end
    if #open.lines >= replies.MAX then return nil end
    open.lines[#open.lines + 1] = s
    open.modes[#open.lines] = mode
    open.ends = math.min(math.max(open.ends, now + replies.STRETCH), open.from + replies.LONGEST)
    return s
end

-- A position as !pos prints it ("Kupipi's position: X 1.2340  Y -3.0000  Z 100.5000  Rot 12  (Zone: 230)"):
-- { name, x, y, z, zone }, or nil.
function replies.position(s)
    local name, x, y, z, zone = tostring(s):match(
        "^(%a+)'s position: X (%-?[%d%.]+)%s+Y (%-?[%d%.]+)%s+Z (%-?[%d%.]+)%s+Rot %-?%d+%s+%(Zone: (%d+)%)")
    if not name then return nil end
    return { name = name, x = tonumber(x), y = tonumber(y), z = tonumber(z), zone = tonumber(zone) }
end

-- The answers kept for history entry `entry` (its batch's, under the batch's newest line), or nil.
function replies.of(entry)
    local b = by_entry[entry]
    if b and b.owner == entry and #b.lines > 0 then return b.lines end
end

function replies.reset()
    open = nil
    by_entry = setmetatable({}, { __mode = 'k' })
end

return replies
