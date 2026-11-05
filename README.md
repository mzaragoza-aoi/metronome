# Metronome

By **moishe6669**.

A RuneScape 3 metronome with configurable tick intervals, alternating sounds,
and a movable, click-through counter.

## Installation

Requires a plugin developer world and **PrettyUI (6398181)** from the Plugin Hub.
Place this folder in the beta client's `dev_plugins` directory. Console commands
use the folder name, `rs3-metronome` in this checkout:

```text
prf
pon rs3-metronome
```

Open **Plugin Hub → Manage → Metronome → settings cog** to configure it.
Use `prl rs3-metronome` to reload or `poff rs3-metronome` to disable it.

See Jagex's [developer setup guide](https://developer.runescape.com/rs/tutorial/1helloworld.html)
for installation details. Availability on regular worlds requires
[Plugin Hub submission](https://developer.runescape.com/rs/submission/process.html).
The Hub's author label comes from the mod.io listing; local development copies
may display “NOT AVAILABLE.”

## Controls

| Setting | Default | Behavior |
| --- | --- | --- |
| Enable metronome | On | Pause or resume counting and sounds |
| Show tick counter | On | Show or hide the counter without changing audio |
| Ticks between beats | 1 | Play a beat every 1–100 game ticks |
| Tick volume | 38% | Set tick volume; 0 mutes it |
| Tock volume | 0% | Above 0, alternate tick and tock on successive beats |

Hold **Option (⌥) on Mac** or **Alt on Windows**, then left-click and drag the
counter to move it. Close the developer console first. Its position is saved
automatically. Normal clicks pass through to the game.

Use **Enable metronome** and **Reset count** in settings to pause, resume, or
restart the count. Reset does not change the server's tick phase. Changing the
interval, pausing, resuming, or leaving the game also restarts the count.

One game tick is approximately 600 ms. At an interval of 3, the first beat plays
after three ticks and repeats roughly every 1.8 seconds. Tick and tock alternate
on beats when tock volume is above 0. Setting tock volume to 0 plays tick on every
beat; setting tick volume to 0 leaves tick beats silent. Muting both keeps the
visual counter running.

## Audio

Playback uses built-in RuneScape UI sounds and follows the game's master and
sound-effects volumes.

If the metronome is silent, check the plugin's volume sliders and the **Game
audio** readout in settings. Raise muted master or sound-effects levels in
RuneScape's audio settings. Playback errors appear in the developer console.

## Development

The plugin targets Lua 5.4 and uses
[`Event.ServerLogic`](https://developer.runescape.com/rs/core/events.html) for
timing. Network delays can shift or bunch received ticks. Preferences are stored
locally through PersistentDB. No network access or additional permissions are
required.

Run the checks from the project directory:

```sh
lua tests/run.lua
python3 scripts/check_plugin.py
```

The checks require Lua, `luac`, and Python 3. Tests cover timing,
preferences, audio requests, positioning, and cleanup with client API doubles.
Confirm audio output, click-through, dragging, and reload behavior in RuneScape
before distributing a release.

## Credits

- Interface components provided by PrettyUI.
# metronome
# metronome
