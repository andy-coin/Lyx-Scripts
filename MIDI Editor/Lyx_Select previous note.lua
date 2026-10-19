-- Select the nearest note to the left (desktop-style focus move). Weights: _Lyx_MIDI_Tools.lua (CUSTOM)
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
script_path = script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_lib._Lyx_HOME")
local T = require("_lib._Lyx_MIDI_Tools")
if not r.IsMidiEditorFocus(reaper.MIDIEditor_GetActive()) then
    reaper.Main_OnCommand(r.ScriptID("ReaTeam Scripts/Cursor/amagalma_Move edit cursor to previous visible grid line.lua"), 0)
    return
end
T.nav("left")
