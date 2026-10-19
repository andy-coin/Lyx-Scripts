-- Select the nearest note above (desktop-style focus move). Weights: _Lyx_MIDI_Tools.lua (CUSTOM)
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
script_path = script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_Lyx_HOME")
local T = require("_Lyx_MIDI_Tools")

T.nav("up")
