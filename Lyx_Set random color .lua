
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")

function main()

    local color = r.RandomColor() -- shared 64-colour palette in _Lyx_HOME.lua

    win,_,det=reaper.BR_GetMouseCursorContext()

    tr_n=reaper.CountSelectedTracks(0)
    it_n=reaper.CountSelectedMediaItems(0)

    if  it_n==0 and tr_n==0 then return end

    if  ( it_n == 1 and tr_n == 1 ) or det=="item" or det=="item_stretch_marker" or it_n > tr_n  then
        for abi=1,reaper.CountSelectedMediaItems(0) do
            item=reaper.GetSelectedMediaItem(0,abi-1)
            reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",color)
        end

    else

        for abi=1,reaper.CountSelectedTracks(0) do
            track=reaper.GetSelectedTrack(0,abi-1)
            reaper.SetMediaTrackInfo_Value(track,"I_CUSTOMCOLOR",color)
        end

    end

    reaper.UpdateArrange()
    return

end

main()

