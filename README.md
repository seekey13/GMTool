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
- **Acting on:** choose once whom an empty player box means: **Me**, your **Target** (its name when it's a player, else yours), a typed **Name**, or **None** (the server's own default). The line shows the exact name either way. A command that needs a name (`!goto`, `!giveitem`...) never takes yours, and a risky one (`!jail`, `!promote`, delete inventory...) takes only the name typed in its own box. Every player box also has a picker with your target, party, nearby players and recent names.
- **Live preview:** each open form shows the line it will send (`!addeffect Kupipi 3 10 120`), or why it can't: a word where a number goes, a name that isn't one, a line past the server's 120 bytes.
- **The cursor race handled:** commands that act on your cursor target (a mob's `!hp`, `!getid`, `!setmoblevel`...) are bound to the target you had when you clicked. They go only once the server has heard of it, never at whatever it heard last. They are dropped, with a message, if you target something else first. A mob-only one refuses with no mob targeted, rather than landing on you.
- **Queue:** the title bar counts lines still waiting. Hover it to see them, and **Clear** (or `/gmt clear`) drops them.
- **Presets:** one-click values (Full HP, Kill, 3000 TP, Bind, Fast...).
- **Favorites:** star any command to keep it on the Favorites page, or start from a suggested set.
- **GM Bar:** your favorites as a strip of buttons that stays up with the main window closed (`/gmt bar`, or Settings). A click sends a favorite with its form as it is; hover a button to see the line.
- **Enter to send:** press Enter in any box of a form to send it (a risky command still wants its button, twice).
- **Console:** type any line with autocomplete from the server's command list and each match's usage.
- **History:** the last 100 lines sent, with Send again and Edit. Under each line sent this session is what the server said back (`!getid`'s id, `!geteffects`' list...), caught from the chat in the moment after it went (addons' lines and anything shaped like a player's chat are left out; lines sent together share their answers). **Copy** puts an answer on the clipboard, and a `!pos` answer (yours or another player's) can be **saved as a place**. The newest answer also shows in the window's status line.
- **Target:** one-click actions that fit what you target. For a player: Go to, Bring, Restore, Raise, Effects, Jail... For a mob: Kill, 1 HP, Level 1, Despawn, Bring here, Stats, Enmity... NPCs and pets get their own. Lines name the target, or give its server id, wherever the server takes one.
- **Nearby:** every player, mob and NPC around you, nearest first, with its server id (a click copies it), distance, Go to, and Bring and Despawn (which ask twice). Filter it by kind and name. The order holds still while your pointer is over the list, so a row never moves under a click.
- **Macros:** named runs of lines with placeholders: `{who}` (whoever Acting on means), `{me}`, `{target}`, `{tid}` (your target's server id), `{x} {y} {z} {zone}` (where you stand). A run checks every line first and sends none if any fails. A risky command in a macro (`!jail`, `!promote`...) must spell its name: it never takes it from `{who}` or `{target}`. A macro holding one asks twice to run, and `/gmt macro` won't run it. A bare `!hp` in a macro acts only on a targeted mob, never a player. It starts you with Restore, Revive here, Bring and restore, Go incognito and Punching bag.
- **Places:** save where you stand and `!pos` yourself, or whoever Acting on means, back there with one click. The position comes from your own position packet, so it is exactly what the server has. A place in the zone the player is already in is reached without zoning (no loading screen, trusts kept).
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
| `/gmt page <name>` | Open a page: `favorites`, `player`, `travel`, `items`, `console`, `history`, `settings`... |
| `/gmt find <words>` | Open the window searching for commands |
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

`data/` is generated from the server checkout and committed, so the addon needs no server source to run. When the server gains or changes a command, regenerate it: `tests/catalog_test.lua` then fails on any command without a form, or any form whose arguments don't fit the server's parameters.

## License

GM Tool is released under the [GNU GPL v3 or later](LICENSE). Copyright © 2026 Seekey.

The UI kit (`ui/kit.lua`) comes from Sidekick, which based it on VanaCore's `/vana` window (Copyright © 2026 Vekien, GPL-3.0-or-later), so GM Tool is GPL too. GM Tool is not affiliated with or endorsed by VanaCore or Vekien. `data/` is generated from the CatsEyeXI server source (LandSandBoat, GPL-3.0).
