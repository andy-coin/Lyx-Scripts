# Lyx Scripts for REAPER

Everyday editing, MIDI and workflow scripts, written and used by a working musician. Most are small one-shot actions you put on a shortcut. A few are full GUI tools, and those share one theme that you can restyle in one place.

## Install

1. Install [ReaPack](https://reapack.com) if you don't have it.
2. In REAPER: **Extensions > ReaPack > Import repositories...** and paste:
   ```
   https://github.com/andy-coin/Lyx-Scripts/raw/main/index.xml
   ```
3. **Extensions > ReaPack > Browse packages**, search for `Lyx`, and install what you want.

**Also install every `_Lyx_...` package.** They are the shared libraries the scripts load, and ReaPack doesn't pull them in by itself.

### Requirements

- Most GUI tools need [ReaImGui](https://forum.cockos.com/showthread.php?t=250419) (available from ReaPack).
- Many actions need the [SWS extension](https://www.sws-extension.org), and some need [js_ReaScriptAPI](https://forum.cockos.com/showthread.php?t=212174). A script tells you when something is missing.
- The FFMPEG tool needs [FFmpeg](https://ffmpeg.org).

Developed on macOS with REAPER 7.

## The GUI tools

### MIDI Note Quantize Filter
Quantize with a tolerance window. Notes already close enough to the grid keep their natural timing, and the rest are pulled in by Strength. The window can be wider on one side, so you can fix rushing and keep a laid-back feel. It previews live, has Bypass for A/B, and can mark the moved notes right inside the MIDI editor (needs js_ReaScriptAPI).

### MIDI Note Compressor and Expander
Compress or expand note velocities around a threshold, like a compressor for MIDI. Drag the transfer curve with the mouse, add Humanize, and compare settings with A–D slots and Bypass. Works across several items or on selected notes only.

### Theme Layout Modifier
A visual editor for third-party theme layouts (`rtconfig.txt` / WALTER). Pick a theme, see its layouts drawn with its own images, then move, resize, hide or link elements. Nothing touches REAPER until you press Apply and Refresh.

### Randomize...
Randomize parameters of selected tracks or items with instant preview. The same seed gives the same result, Reroll draws a new one, and editing one parameter never re-rolls the others. Cancel restores everything; Apply is one undo point.

### Insert Free Fall MIDI Notes
Bouncing-ball note sequences from real physics: each bounce gets shorter and quieter. Start from the edit cursor, from each selected note, or fit the whole bounce into the time selection.

### Tap Tempo
Tap with the mouse or any key. BPM comes from a least-squares fit over recent taps, which is steadier than a plain average. Includes a running metronome, click-to-copy delay times, and a typed BPM mode.

### FFMPEG Replace Audio in Video
Swap the audio of video files as a background job list. Drag files in or use selected video items, choose AAC or lossless, and get a new file next to the original. For video items, the source is swapped only after FFmpeg succeeds.

### Global Theme Manager
Colours, fonts, rounding, spacing and scale for all Lyx GUIs, with a live preview. Open windows follow within a second.

## Everyday actions

Smart copy, cut, paste, delete, duplicate, solo and mute; fades and crossfades; track versions on fixed lanes; razor-area coloring for good and bad sections; stretch markers; grid and swing control; MIDI note, CC and velocity editing; FX window management. Browse the full list in ReaPack.

Scripts with a `-----CUSTOM-----` section at the top have settings you can edit there.

## Support

These scripts are free. Bug reports and ideas are welcome in [Issues](https://github.com/andy-coin/Lyx-Scripts/issues).

<!-- DONATE: add the PayPal.Me link here, and in DONATE in make_index.py -->

## Credits and license

Released under the [GNU GPL v3](LICENSE). You can use, change and share these scripts, including commercially. If you distribute a modified version, it has to stay GPL v3 with its source available.

Some scripts are built on the work of others. Thanks to:

| Script | Based on | Author |
|---|---|---|
| Buss Driver (Lyx mod) | [MB_Buss Driver](https://github.com/MonkeyBars3k/ReaScripts) (GPL v3) | MonkeyBars |
| Quick Adder 2 (Lyx mod) | Quick Adder 2 (GPL v3) | Neutronic |
| Tap Tempo | [Tap Tempo](https://github.com/X-Raym/REAPER-ReaScripts) (GPL v3) | X-Raym |
| MIDI Note Compressor and Expander | Refactor of an earlier script | amagalma |

Buss Driver also bundles [rtk](https://reapertoolkit.dev) by Jason Tackaberry and Serpent by Paul Kulchenko (MIT). Their notices stay with their files.
