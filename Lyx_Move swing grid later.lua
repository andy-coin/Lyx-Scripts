
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
--script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")      

-----CUSTOM-----
link_editor = true

local function main()
    
    local _,grid,swing,swingamt = reaper.GetSetProjectGrid(0,false)--, optional number division, optional integer swingmode, optional number swingamt)
    local triplet = ((1/grid)/3)%1==0
    
    if  triplet or swing==0 then
        return
    end
    
    if  swingamt == 0 then 
        swingamt = 0.6
    end

    swingamt = swingamt+0.01
    reaper.GetSetProjectGrid(0,true,grid,1,swingamt)

    if  link_editor and api.gtc(42010) == 0 then
        reaper.Main_OnCommand(42010,0) --Grid: Use the same grid division in arrange view and MIDI editor 
    end
    
    swingamt = string.format("%.2f",swingamt)
    r.billboard("Set swing feel value to "..swingamt)
end

reaper.defer(main)
