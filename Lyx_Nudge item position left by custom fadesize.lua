
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r=require("_lib._Lyx_HOME")

local function main()

    local length,unit,nudge

    length=reaper.GetExtState("fade_length","fade_length",true)
    unit=reaper.GetExtState("fade_length","length_unit",true)
    
    unit=(unit=="s" and "s") or "ms" 
    
    if  tonumber(length) then
        nudge=(unit=="s" and tonumber(length)) or tonumber(length)/1000
    else
        nudge=0.01
    end

    reaper.ApplyNudge(0,0,0,1,-nudge,false,0)

    api.ua()

end

api.ubb()
main()
api.ueb(0,"Move item left by fade length",-1)

