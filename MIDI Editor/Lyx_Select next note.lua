-- Select the nearest note to the right (desktop-style focus move). Weights: _Lyx_MIDI_Tools.lua (CUSTOM)
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
script_path = script_path:gsub("/MIDI Editor", "")
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_Lyx_HOME")
local T = require("_Lyx_MIDI_Tools")
if not r.IsMidiEditorFocus(reaper.MIDIEditor_GetActive()) then
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS15fe264880bb8d5030dabb8c1b1d6767a4c36b28"), 0)
    return
end
T.nav("right")
