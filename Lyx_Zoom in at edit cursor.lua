
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    api.cmd(api.name('_WOL_SETHZOOMC_EDITCUR'),0)
    api.cmd(1012,0)
    api.cmd(api.name('_WOL_SETHZOOMC_MOUSECUR'),0)

    reaper.defer(function()end)