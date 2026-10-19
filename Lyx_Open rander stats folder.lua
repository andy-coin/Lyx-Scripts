    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    os.execute('open "'..os.getenv("HOME")..'/Desktop/Reaper Projects/render_stats"')

    reaper.defer(function ()end)