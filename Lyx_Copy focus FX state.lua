-- Copy the focused FX state (track / take / master / monitor / rec-input FX).
-- Engine: _Lyx_FXState.lua
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"
require("_Lyx_HOME")
require("_Lyx_FXState").copy()
reaper.defer(function() end)
