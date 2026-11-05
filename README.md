# RS3 Metronome

A native RuneScape 3 plugin that makes a short sound every configurable number
of game ticks. It also includes an optional flashing counter and pause/reset
buttons. Inspired by the [RuneLite metronome's behavior](https://github.com/runelite/runelite/wiki/Metronome),
with an original Lua implementation and original sounds.

## Try it in the game

This folder is already in the beta client's `dev_plugins` directory. Use a
**plugin developer/beta world** and make sure **PrettyUI (6398181)** is installed
from the Plugin Hub; this is the same dependency used by BloodAlert and BuffBeacon.

Open the developer console with **Alt + the key below Esc**, then run each line:

```text
prf
plist
pon rs3-metronome
```

The console should report `RS3 Metronome v0.1.0 loaded`. Open **Plugin Hub → Manage
→ RS3 Metronome → settings cog** to adjust it. After editing a file, reload with:

```text
prl rs3-metronome
```

To stop and remove its overlay:

```text
poff rs3-metronome
```

These commands are documented in Jagex's
[getting started tutorial](https://developer.runescape.com/rs/tutorial/1helloworld.html).
Local development plugins require a developer world; release to ordinary worlds
goes through the [Plugin Hub submission process](https://developer.runescape.com/rs/getting-started.html).

## Controls

| Setting | Default | Behavior |
| --- | --- | --- |
| Enable metronome | On | Pause/resume sounds and counting |
| Show tick counter | On | Hide the overlay while keeping audio running |
| Ticks between beats | 1 | Play a beat every 1–100 received game ticks |
| Tick volume | 38% | 0 mutes the tick sound |
| Tock volume | 0% | Above 0 alternates tick and tock on successive beats |

At 3 ticks, beats arrive roughly every 1.8 seconds. The first beat waits for
three ticks; the counter repeats 1, 2, 3. With tock enabled, sound alternates on
each **beat**, not each tick. Setting tick volume to zero leaves its beat silent
while the tock still plays. At zero for both volumes, the counter still works.

Hold **Alt and drag** the counter to move it. Position currently resets when the
overlay is recreated. **Reset** starts a fresh count from the next received tick;
it does not change the server's tick phase. Pausing, resuming, changing the interval,
and leaving/re-entering the game reset the count. Preferences are saved locally
for this plugin and shared between characters using this client installation.

The sounds follow RuneScape's **sound effects** and master volume settings. If
the counter moves but the plugin is silent, check those and the plugin volumes.

## Timing and implementation

The clock is [`Event.ServerLogic`](https://developer.runescape.com/rs/core/events.html),
which follows processed server packets at approximately 600 ms per tick. Network
delays can shift or bunch arrivals; this is not a prediction of a future tick.
Client update events only mount the overlay and end its brief highlight.

The plugin uses no network requests, gameplay inputs or extra permissions.
It stops its own audio and removes subscriptions and views when disabled.
The manifest reuses the contact email from the neighboring local plugins.

## Development checks

Run from this folder:

```sh
lua tests/run.lua
python3 scripts/check_plugin.py
```

The Lua tests exercise real timing/settings modules and the complete entrypoint
with doubles for client events, sound, persistence and PrettyUI. They cannot
confirm actual game rendering, resource decoding in the client, or sound latency.
The installed local Lua is 5.5.1; source uses Lua 5.4-compatible syntax for RS3.

Bundled sound files need no build step. To regenerate their original synthesized
tones, run `python3 scripts/generate_sounds.py` with Python 3 and ffmpeg available.
No RuneLite audio or code is bundled.

### In-game smoke test

1. Enable the plugin and listen for one tick per game tick. Confirm the counter
   flashes even with an interval of 1.
2. Set interval to 3, tick volume to 40 and tock to 60. Listen for alternating
   sounds every third tick, then mute tick and verify only the tocks remain.
3. Pause/resume and reset. Hide the counter and verify sound continues. Reopen
   settings, then reload and check that the preferences were saved.
4. Move the overlay with Alt-drag. Log out and back in, and switch worlds. Check
   that the count restarts and there is one overlay with no duplicate beats.
5. Disable the plugin and confirm its UI and sound stop. Inspect the console for
   errors, especially missing PrettyUI or audio resources.

**Live client smoke testing is still required.** No RuneScape game window was
available during initial implementation.
# metronome
