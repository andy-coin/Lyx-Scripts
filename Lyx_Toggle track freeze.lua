
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

    play=reaper.GetPlayState()
    if reaper.MIDIEditor_GetActive() or play==5 then return end

    trz={}
    for abi=1,reaper.CountSelectedTracks(0) do
        tr=reaper.GetSelectedTrack(0,abi-1)
        --reaper.ShowConsoleMsg(reaper.BR_GetMediaTrackFreezeCount(tr))
        if 0==reaper.BR_GetMediaTrackFreezeCount(tr) then
            it_n=reaper.CountTrackMediaItems(tr)
            --[[if it_n>0 then
                for abigel=1,it_n do
                    item=reaper.GetTrackMediaItem(tr,abigel-1)
                    take=reaper.GetActiveTake(item)
                    FX=reaper.TrackFX_GetCount(tr)
                    fx=reaper.TakeFX_GetCount(take)
                    if FX>0 or fx>0 then
                    freeze=1
                    end
                end
            end--]]
            freeze=1
        else
            freeze=0
            trz[#trz+1]=tr
        end
    end
    --reaper.ShowConsoleMsg(freeze)
    if not freeze then return end


    if freeze==1 then
        for abi=1,#trz do
            reaper.SetTrackSelected(trz[abi],false)
        end
        reaper.Main_OnCommand(41223,0)--freeze track
        for abi=1,#trz do
            reaper.SetTrackSelected(trz[abi],true)
        end
    elseif freeze==0 then  
        reaper.Main_OnCommand(41644,0)--unfreeze track
    end

    reaper.Main_OnCommand(cmd,0)
    end

    reaper.Undo_BeginBlock()
    main()
    reaper.Undo_EndBlock("Toggle track freeze",0)
