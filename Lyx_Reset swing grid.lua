
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r=require("_lib._Lyx_HOME")

-----CUSTOM-----
reset_value = 0.50   -- swing feel 0 = straight
link_editor = true

local function main()

    local _,grid,swing = reaper.GetSetProjectGrid(0,false)
    local triplet = ((1/grid)/3)%1==0

    if  triplet or swing==0 then
        return
    end

    reaper.GetSetProjectGrid(0,true,grid,1,reset_value)

    if  link_editor and api.gtc(42010) == 0 then
        reaper.Main_OnCommand(42010,0) --Grid: Use the same grid division in arrange view and MIDI editor
    end

    r.billboard(string.format("Reset swing feel value to %.2f",reset_value))
end

reaper.defer(main)
