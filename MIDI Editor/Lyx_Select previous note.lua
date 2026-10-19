-- Select the nearest note to the left (desktop-style focus move). Weights: _Lyx_MIDI_Tools.lua (CUSTOM)
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
script_path = script_path:gsub("/MIDI Editor", "")
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_Lyx_HOME")
local T = require("_Lyx_MIDI_Tools")
if not r.IsMidiEditorFocus(reaper.MIDIEditor_GetActive()) then
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS2a2550d39129b310256c72ba74993b7f92f8e235"), 0)
    return
end
T.nav("left")
