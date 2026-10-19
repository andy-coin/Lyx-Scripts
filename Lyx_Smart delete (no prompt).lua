

    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")


    -----SETTING-----
    preserve_point = true --automation_item

    --------------
    local function KillRazorItems(razorEdits)

        local Save_time    = api.name("_SWS_SAVELOOP1")
        api.cmd(Save_time,0)
        
        api.cmd(40635,0)--Time selection: Remove (unselect) time selection
        api.cmd(40061,0)--Item: Split items at time selection or razor edit

        local Restore_time = api.name("_SWS_RESTLOOP1")
        api.cmd(Restore_time,0)


    end

    local function main()
        
        local win,seg,det = api.mcw()

        local Tn = reaper.CountSelectedTracks(0) 
        local In = reaper.CountSelectedMediaItems(0) 
        local Env = reaper.GetSelectedEnvelope(0) or api.mce()
        if  Tn==0 and In==0 and not Env then return "Delete nothing" end
        
        local razor,razorMap=r.GetRazorEdits(false,false)
        if  razor then
            for abi=1,#razorMap do
            
                local Data = razorMap[abi]

                if  not Data.envelope then
                    api.cmd(40312,0)--Item: Remove selected area of items
                    delete="razor area media item"
                else
                    reaper.DeleteEnvelopePointRange(Data.envelope,Data.areaStart,Data.areaEnd)
                    delete="razor area envelope point"
                end

            end
            reaper.UpdateArrange()
            return delete
        end
        
        if  Env or seg == "envelope" then            

            r.SaveTracks(true)
            api.cmd(api.name('_SWS_SAVEALLSELITEMS1'),0)

            local env_tr,AIs,kill_point,selected_AI

            env_tr= api.get(Env)
            
            AIs = r.GetAutomationItems(env_tr)
            
            for abi = 1, #AIs do
                local env
                env = AIs[abi].env
                for abii = 0, api.cep(env,AIs[abi].idx) do
                    local retval, time, value, shape, tension, selected  = api.gep(env,AIs[abi].idx,abii-1)
                    if  selected then
                        kill_point = true
                        delete = 'automation item points'
                        break
                    end
                end
                if  kill_point then break end
                if  AIs[abi].selected then
                    selected_AI = true 
                end
            end
            
            if  not kill_point and selected_AI then 
                if  preserve_point then
                    api.cmd(42088,0)--delete automation item, preserve points
                else
                    api.cmd(42086,0)--delete automation item, don't preserve points
                end
                delete = "automation items"
            else
                local _,chunk = api.geC(Env,'',false)
                
                if  chunk:match('PT [%d%.%-]+ [%d%.%-]+ [%d%.%-]+ [01] 1')  then
                    kill_point = true
                    delete="envelope points"
                end

                if  kill_point then
                    api.cmd(40333,0)--delete all select point
                    api.cmd(40769,0)--unselect all points
                    --else
                        --api.cmd(40065,0)--remove envelope
                    delete="envelope"
                else
                    return
                end
            end
                        
            -- if  not kill_point and selected_AI then 
            --     api.cmd(42086,0)--delete automation item, don't preserve points
            --     --api.cmd(42088,0)--delete automation item, preserve points
            --     delete = "automation items"
            -- else
            --     for abi = 1, api.cep(Env,-1) do
            --         local retval, time, value, shape, tension, selected  = api.gep(Env,-1,abi-1)
            --         if  selected then
            --             kill_point = true
            --             delete="envelope points"
            --             break
            --         end
            --     end
            --     if  kill_point then
            --         api.cmd(40333,0)--delete all select point
            --         api.cmd(40769,0)--unselect all points
            --     else
            --         api.cmd(40065,0)--remove envelope
            --         delete="envelope"
            --     end
            -- end

            r.RestoreTracks(true)

            api.cmd(api.name('_SWS_RESTALLSELITEMS1'),0)
            reaper.UpdateArrange()
            return delete
        end
        
::ITEM::
        if  (In>0 and (det=="item" or det=="item_stretch_marker" )) or
            (win~="tcp" and In>=Tn) or
            (In>1 and Tn==1) then
            
            local midi =reaper.MIDIEditor_GetActive()
            
            reaper.Main_OnCommand(40689,0)--unlock item 
            reaper.Main_OnCommand(40006,0)--delete items
            
            if  midi and not reaper.MIDIEditor_GetActive() then 
                tr=reaper.GetTrack(0,reaper.CountTracks(0)-1)
                _,name=reaper.GetTrackName(tr)
                if  name=="I'm FATTY :B" then
                    reaper.DeleteTrack(tr)
                end
                reaper.CSurf_OnScroll(0,1)
                reaper.CSurf_OnScroll(0,-1)
            end
            
            delete = "items"
            reaper.UpdateArrange()
            return delete
        end

::TRACK_LANES::

        if  api.cst(0)==1 and api.gtv(api.gst(0,0),"I_NUMFIXEDLANES")>1 and 
            win ~= 'tcp' and api.gtv(api.gst(0,0),"C_LANESCOLLAPSED")==0 then
            api.cmd(42676,0)--delete lanes under mouse
            
            delete="fixed lanes"
            reaper.UpdateArrange()
            return delete
        end

::TRACK::

        if reaper.CountSelectedTracks(0) == 0 then return 'nothing' end

        api.cmd(api.name('_SWS_SAVETIME1'),0)
        local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
        r.TimeSelection(start_time, end_time)
        
        r.SaveItems(true)
        
        api.cmd(40289, 0)
        api.cmd(40718, 0) -- Item: Select all items on selected tracks in current time selection
        local clean = api.csi(0) == 0

        api.cmd(api.name('_SWS_RESTTIME1'),0)

        for abi=1,reaper.CountSelectedTracks(0) do
            local tr=reaper.GetSelectedTrack(0,abi-1)
            local message
            if  api.cti(tr) ~= 0 and (api.gtv(tr,"I_RECARM") == 1 or clean ) then
                message = (clean and 'Items in track') or "This track is Rec armed" 
                ret = reaper.ShowMessageBox("Do you want to delete it !? ", message.." !!!  Q_Q",1)
                if  ret ~= 1 then
                    return "nothing"
                else
                    break
                end
            end
        end
        
        last=reaper.GetSelectedTrack(0,reaper.CountSelectedTracks(0)-1)

        idx=reaper.GetMediaTrackInfo_Value(last,"IP_TRACKNUMBER")

        for abi=idx,reaper.CountTracks(0) do
            local tr =reaper.GetTrack(0,abi-1)
            if  not reaper.IsTrackSelected(tr) and reaper.IsTrackVisible(tr,false) then
                left=tr
                break
            end
        end

        if left then goto kill end

        for abi=idx,1,-1 do
            local tr =reaper.GetTrack(0,abi-1)
            if  not reaper.IsTrackSelected(tr) and reaper.IsTrackVisible(tr,false) then
                left = tr
                break
            end
        end

        ::kill::

        reaper.Main_OnCommand(40005,0)--delate tracks

        if  reaper.ValidatePtr2(0,left,"MediaTrack*") then
            reaper.SetOnlyTrackSelected(left)
        end
        
        delete="tracks"
        reaper.UpdateArrange()
        return delete

    end

    --reaper.ClearConsole()
    reaper.Undo_BeginBlock()
    Act = main()
    context = "Delete selected "..(Act or 'nothing')
    reaper.Undo_EndBlock(context,-1)

    
