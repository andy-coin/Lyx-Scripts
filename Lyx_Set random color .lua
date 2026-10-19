
r=reaper

c_chart={25182272,25196864,21790784,21004396,20994432,
23085184,25182310,25187136,24346688,21004358,21004416,
20989568,24330368,25182291,25192000,23101504,21004377,
20999296,21774464,25182329,27487340,27500140,24617836,
23896979,23888547,25652387,27487373,27491436,26780524,
23896945,23896995,23884195,26766499,27487356,27495788,
25666412,23896962,23892899,24603811,27487390}


function main()

    local color = tonumber(reaper.GetExtState("color","color")) or 0 -- empty on first use
    color=color%40+1
    
    win,_,det=reaper.BR_GetMouseCursorContext()
    
    tr_n=reaper.CountSelectedTracks(0)
    it_n=reaper.CountSelectedMediaItems(0)
    
    if  it_n==0 and tr_n==0 then return end
    
    if  ( it_n == 1 and tr_n == 1 ) or det=="item" or det=="item_stretch_marker" or it_n > tr_n  then
        for abi=1,reaper.CountSelectedMediaItems(0) do
            item=reaper.GetSelectedMediaItem(0,abi-1)
            reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",c_chart[color])
        end
        
    else
        
        for abi=1,reaper.CountSelectedTracks(0) do
            track=reaper.GetSelectedTrack(0,abi-1)
            reaper.SetMediaTrackInfo_Value(track,"I_CUSTOMCOLOR",c_chart[color])
        end
        
    end
    
    reaper.UpdateArrange()
    color=color%40+1
    reaper.SetExtState("color","color",color,true)
    return 
    
end
    
main()

green=18313493
blue=18696831

