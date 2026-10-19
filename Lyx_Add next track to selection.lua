local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
--script_path=script_path:gsub("/MIDI Editor","")
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")

local function main()

    top_tr = api.gst(0,0)
    bottom_tr = api.gst(0,api.cst(0)-1)
    last_select_tr = reaper.GetLastTouchedTrack() or top_tr
    
    if  last_select_tr == bottom_tr and api.cst(0) > 1 then 
        api.sts(top_tr, false)
        return 
    end

    idx = api.gtv (bottom_tr, 'IP_TRACKNUMBER')

    r.SaveTracks(true)

    while true do
        
        idx = idx + 1

        local tr = api.gt(0, idx-1)
        
        if  tr and api.itv(tr,false) then
            r.RestoreTracks(true,true)
            api.sts(tr,true)
            api.cmd(40914,0)--set first selected track as last touch track
            break
        elseif  tr == api.gt(0,api.ct(0)-1) or not tr then
            break
        end

    end

    api.ua()
end

main()

reaper.defer(function()end)