-- Show names of the selected notes; uses the track's note-name map (e.g. drum maps) when loaded.
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
script_path = script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_Lyx_HOME")
local T = require("_Lyx_MIDI_Tools")
T.show_names()
reaper.defer(function() end)
