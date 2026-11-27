--[[
    Adjust fade length
      Only sets the default length used by "Lyx_Create fade or crossfade to
      select items" (ExtState fade_length). Nothing is applied to items.
      Old version that also applied fades: git eca2078
]]
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path .. ";" .. script_path .. "?.lua"
local r = require("_lib._Lyx_HOME")

local EXT = "fade_length"

-- dialog runs in a coroutine (r.run)
r.run(function()
    local ok, csv = r.GetUserInputs("Adjust fade length...", 2,
        "Length :,Time unit: ( s / ms ),extrawidth=100",
        (tonumber(reaper.GetExtState(EXT, "fade_length")) or 10) .. "," ..
        (reaper.GetExtState(EXT, "length_unit") == "s" and "s" or "ms")) -- same defaults as Create
    if not ok then return end

    local length, unit = csv:match("^(.*),(.*)$")
    length = tonumber(length)
    if not length or length <= 0 then
        reaper.ShowMessageBox("Length must be a number > 0 >_<", "Oops...", 0)
        return
    end
    if unit ~= "ms" and unit ~= "s" then
        reaper.ShowMessageBox("Got wrong unit >_< \n please type s or ms !", "Oops...", 0)
        return
    end

    reaper.SetExtState(EXT, "fade_length", tostring(length), true)
    reaper.SetExtState(EXT, "length_unit", unit, true)
end)
