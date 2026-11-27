<div align="center">

# GM Tool

**Every GM command of a LandSandBoat server, a click away: an Ashita v4 addon for [CatsEyeXI](https://www.catseyexi.com/).**

[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)
![Ashita v4](https://img.shields.io/badge/Ashita-v4.16-8a2be2.svg)

</div>

---

GM Tool puts a form and a button on each of the server's 199 GM commands. It reads them from the CatsEyeXI server's own `scripts/commands/` (a LandSandBoat fork) rather than the old DSP wiki, whose list has drifted. Each command's form checks what you type the way the server will read it. You see the exact line before it goes, and it reaches the server without the chat box's 1.5-second limit between lines.

## Features

- **Every command, grouped:** Player, Jobs & Skills, Spells & Abilities, Effects & Mods, Items, Gil & Currency, Key Items & Titles, Quests & Missions, Nation & Fame, Travel, Mobs, NPCs & Entities, Appearance & World, Variables, Events & Debug, Moderation, and (opt-in) Server. [docs/commands.md](docs/commands.md) lists them all.
- **Forms, not syntax:** a box per argument in the order the server reads it, with GM Tool filling the gaps between them. Pick zones, status effects, modifiers, skills, key items, titles, mounts, currencies, weather, quest and mission logs (with their quests and missions) from searchable lists generated from the server source. Search items and spells by their client names.
- **Acting on:** choose once whom an empty player box means: **Me**, your **Target** (its name when it's a player, else yours), a typed **Name**, your **Party**, or **None** (the server's own default). The line shows the exact name either way. A command that needs a name (`!goto`, `!giveitem`...) never takes yours, and a risky one (`!jail`, `!promote`, delete inventory...) takes only the name typed in its own box. Every player box also has a picker with your target, party, nearby players and recent names.
- **Party:** with Acting on set to **Party**, a form sends its line once for you and each member of your party and alliance (Raise, Restore, give an item, set a level...), trusts left out, checked all together before any goes. Since one click then reaches everyone, Send, presets, the GM Bar and a macro's Run ask twice (Enter won't send to a party). `!bring` leaves you out, `!goto` never goes to a party, and a risky command still takes only the name typed in its own box. A macro runs the lines from its first `{who}` line to its last for each member (those without `{who}` once, so `!hide` isn't toggled back), the lines before them once first and those after once last. **Places › Send** puts each member at the place.
- **Live preview:** each open form shows the line it will send (`!addeffect Kupipi 3 10 120`), or why it can't: a word where a number goes, a name that isn't one, a line past the server's 120 bytes.
- **The cursor race handled:** commands that act on your cursor target (a mob's `!hp`, `!getid`, `!setmoblevel`...) are bound to the target you had when you clicked. They go only once the server has heard of it, never at whatever it heard last. They are dropped, with a message, if you target something else first. A mob-only one refuses with no mob targeted, rather than landing on you.
- **Queue:** the title bar counts lines still waiting. Hover it to see them, and **Clear** (or `/gmt clear`) drops them.
- **Presets:** one-click values (Full HP, Kill, 3000 TP, Bind, Fast...).
- **Favorites:** star any command to keep it on the Favorites page, or start from a suggested set.
- **GM Bar:** your favorites as a strip of buttons that stays up with the main window closed (`/gmt bar`, or Settings). A click sends a favorite with its form as it is; hover a button to see the line. Star a macro or a place to put it there too: a click runs the macro (twice for a risky one, or one that goes to each of a party) or puts you at the place.
- **Enter to send:** press Enter in any box of a form to send it (a risky command still wants its button, twice).
- **Console:** type any line with autocomplete from the server's command list and each match's usage.
- **History:** the last 100 lines sent, with Send again and Edit. Under each line sent this session is what the server said back (`!getid`'s id, `!geteffects`' list...), caught from the chat in the moment after it went (addons' lines and anything shaped like a player's chat are left out; lines sent together share their answers). **Copy** puts an answer on the clipboard, and a `!pos` answer (yours or another player's) can be **saved as a place**. The newest answer also shows in the window's status line.
- **Target:** one-click actions that fit what you target. For a player: Go to, Bring, Restore, Raise, Effects, Jail... For a mob: Kill, 1 HP, Level 1, Despawn, Bring here, Stats, Enmity... NPCs and pets get their own. Lines name the target, or give its server id, wherever the server takes one.
- **Players:** any player by name, targeted or not, in any zone: the Target page's actions for them (Go to, Bring, Restore, Raise, Where, Effects, Release, Jail, Kick...), sent by name. Those that only read your cursor (Stats, Server id) show while they are your target. Pick from your party, the players near you and recent names, click a player's name on Nearby, or `/gmt player <name>`.
- **Status effects:** the Players and Target pages show the server's own list of a player's (or a mob's) effects as a table: power, time left, food, dispelable. **List them** asks (`!geteffects`), and each of a player's effects has **Remove**, which sends `!deleffect` and lists them again so the table stays current. **Remove all** (twice) clears every one.
- **Nearby:** every player, mob and NPC around you, nearest first, with its server id (a click copies it), distance, Go to, and Bring and Despawn (which ask twice). Filter it by kind and name. The order holds still while your pointer is over the list, so a row never moves under a click.
- **Zone Browser:** every mob and NPC of any zone, from the server's own database rather than what you can see: NMs (with their levels, family, and how they spawn: lottery, scripted, at night...), mobs grouped by name with each id, and NPCs, hidden ones too. Filter by name, server id or index, or pick **All zones** to find a mob or NPC in any zone ("where is Fafnir?"), each match with its zone. **Spawn**, **Go to** (zoning you there from another zone), **Despawn**, and in your own zone **Bring**; the ones up near you are marked. A click opens a row to each of its ids and, for a mob, its drop list: each item by the client's name, with its base chance per kill as the server rolls it (a group's chance times the item's share of its picks; an item listed twice, both rolls; steal and despoil), before Treasure Hunter, and **Add** to put one in your inventory. Targeting a mob or NPC shows the same facts, drops too, on the Target page.
- **Macros:** named runs of lines with placeholders: `{who}` (whoever Acting on means), `{me}`, `{target}`, `{tid}` (your target's server id), `{x} {y} {z} {zone}` (where you stand). A run checks every line first and sends none if any fails. A risky command in a macro (`!jail`, `!promote`...) must spell its name: it never takes it from `{who}` or `{target}`. A macro holding one asks twice to run, and `/gmt macro` won't run it. A bare `!hp` in a macro acts only on a targeted mob, never a player. It starts you with Restore, Revive here, Bring and restore, Go incognito and Punching bag.
- **Places:** save where you stand and `!pos` yourself, or whoever Acting on means, back there with one click. The position comes from your own position packet, so it is exactly what the server has. A place in the zone the player is already in is reached without zoning (no loading screen, trusts kept).
- **Setup:** a test character in one go, for yourself: main job and level (mastered, if you like), sub job, then cap every skill, learn every spell, quest weapon skill, trust, map, mount or automaton attachment, set your gil, full HP and MP. It shows the lines in the order they go (the job first, as `!capallskills` caps for the job you have when it runs). **Apply** sends them; **Keep as macro** saves them with `{me}`, to set up any character.
- **Sharing:** **Copy all** on the Macros or Places page puts them on the clipboard as plain text (`[Restore]` then its lines; `@ Jeuno AH: -12.5 0 33.25 246` for a place), to paste on another character, hand to another GM or keep in a file. **Paste** adds what's on the clipboard, macros and places alike: each line checked, ones already there skipped, a taken name made `name 2`, and it says which lines it left out.
- **Safety:** commands that delete or disrupt (jail, delete inventory, crash, provoke all...) ask for a second click. The server-wide page stays hidden until you turn it on.
- **Sidekick's look:** the same palette, controls and layout as [Sidekick](https://github.com/seekey13/Sidekick)'s settings window, after VanaCore's `/vana`.

## Installation

1. Put this folder in `Ashita/addons/GMTool` (so `Ashita/addons/GMTool/GMTool.lua` exists).
2. In game, on a GM character: `/addon load gmtool`.
3. `/gmt` opens and closes the window.

> [!WARNING]
> Only a GM's `!` lines are read by the server. If you're not a GM, a line no command takes is said aloud as `/say` to everyone near you, and since GM Tool sends it as a packet you won't even see it in your own chat. Use GM Tool on a GM character only.

## Commands

| Command | What it does |
| --- | --- |
| `/gmt` (or `/gmtool`) | Open or close GM Tool |
| `/gmt <command> [args]` | Send a GM command through GM Tool's queue: `/gmt hp 100 Kupipi`, `/gmt !where` |
| `/gmt page <name>` | Open a page: `favorites`, `target`, `players`, `nearby`, `zones`, `setup`, `player`, `travel`, `items`, `macros`, `history`, `settings`... |
| `/gmt find <words>` | Open the window searching for commands |
| `/gmt player <name>` | Open a player on the Players page |
| `/gmt macro <name>` | Run a macro |
| `/gmt place <name> [player]` | Put yourself, or a player, at a saved place |
| `/gmt clear` | Drop every line still waiting in the queue |
| `/gmt bar` | Show or hide the GM Bar |
| `/gmt help` | List these |

`/gmt <command>` works in macros. It goes through the same queue as the buttons, so a macro's lines aren't dropped by the chat box's throttle.

## How it sends

By default each line goes as a say chat packet (0x0B5), injected, as Sidekick's GM test tools do. The server reads a `!` line before anyone hears it, and never repeats a GM's. Injected lines skip the client's chat box, so none are dropped for coming too fast. They also skip your own chat log, so GM Tool echoes each one there. Under **Settings › Send as › Typed**, lines go through the chat box instead (`/say !...`), 1.6 seconds apart.

The server answers in your chat log as usual. A command above your GM level, or one it doesn't have, gets no answer at all. Set **My GM level** to dim the commands above yours.

## Configuration

Settings are per character, in `config/addons/GMTool/<character>/settings.lua`: favorites, history, recent names, macros, places, each form's last values, and the window's preferences.

## Development

Requires `luajit` and `luacheck`.

```sh
luajit tests/run.lua        # offline tests: the catalog against the server's commands, the line builder, the window on a fake ImGui
luacheck .
luajit tools/gen_data.lua [path to the server]   # regenerate data/ from the server source (default ../../../../../catseyexi)
luajit tools/gen_docs.lua   # regenerate docs/commands.md
```

`data/` is generated from the server checkout and committed, so the addon needs no server source to run. `data/spawns.lua` (the Zone Browser's mobs and NPCs) comes from the server's `sql/` tables: `mob_spawn_points`, `mob_groups`, `mob_pools`, `mob_family_system` and `npc_list`; `data/drops.lua` from `mob_droplist`. When the server gains or changes a command, regenerate it: `tests/catalog_test.lua` then fails on any command without a form, or any form whose arguments don't fit the server's parameters.

## License

GM Tool is released under the [GNU GPL v3 or later](LICENSE). Copyright © 2026 Seekey.

The UI kit (`ui/kit.lua`) comes from Sidekick, which based it on VanaCore's `/vana` window (Copyright © 2026 Vekien, GPL-3.0-or-later), so GM Tool is GPL too. GM Tool is not affiliated with or endorsed by VanaCore or Vekien. `data/` is generated from the CatsEyeXI server source (LandSandBoat, GPL-3.0).
