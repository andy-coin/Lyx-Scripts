-- Decrease arpeggiation of the selected chords (whole notes move; never covers the next same-pitch note).
-- Step size: ARP_STEP_MS in _Lyx_MIDI_Tools.lua
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
script_path = script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_lib._Lyx_HOME")
local T = require("_lib._Lyx_MIDI_Tools")
T.arp(-1)
reaper.defer(function() end)
