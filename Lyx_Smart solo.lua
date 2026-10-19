    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOM-----
    mode = 1
    
    --------------
    local function SoloGroup(tr)
        
        if  reaper.GetSetTrackGroupMembership(tr,'SOLO_LEAD',0,0)~=0 or
            reaper.GetSetTrackGroupMembershipHigh(tr,'SOLO_LEAD',0,0)~=0 then
            return true
        end
                
        return false 
    end

    --------------
    local function PlaytilDead(E)
        
        local p=reaper.GetPlayPosition()
        
        if  reaper.GetPlayState()==0 or reaper.GetPlayState()==2 then
            return
        elseif p>=E then
            api.cmd(1016,0)--play/stop
        else
            reaper.defer(function() PlaytilDead(E) end)
        end
        
    end
    
    --------------
    local function ToggleSoloRazorAreaTracks(razorEdits,lock)
    
        if  not lock then
            solo = api.gtv(razorEdits.track[1],'I_SOLO') ~= 0
        end
    
        for abi=1, #razorEdits.track do
            local tr = razorEdits.track[abi]
            api.stv(tr,'I_SOLO',(solo and 0) or mode)
        end
    
    end
    
    --------------
    local function SaveSoloTracks()
        r.SaveTracks(true)
        api.cmd(api.name('_SWS_SELSOLOEDTRACKS'),0)--select solo tracks
        for abi = api.cst(0), 1, -1 do
            local tr = api.gst(0,abi-1)
            if  api.gtv(tr, 'B_SOLO_DEFEAT') == 1 then
                api.sts(tr, false)
            end
        end
        r.SaveTracks('solo_tracks')
        r.RestoreTracks(true)
    end
    
    --------------
    local function solo(sel_trs, editor)
        
        local razor,razorMap
    
        razor,razorMap=r.GetRazorEdits()

        if  razor then
            if  reaper.GetPlayState()==0 or reaper.GetPlayState()==2 then --stop
                ToggleSoloRazorAreaTracks(razorMap,true)
                reaper.SetEditCurPos(razorMap.min,false,false)
                api.cmd(1007,0)--play/stop
                PlaytilDead(razorMap.max)
            else --playing
                ToggleSoloRazorAreaTracks(razorMap)
            end
        elseif r.IsMidiEditorFocus(editor) then

            r.SelTrackFilter()
            sel_trs = {}
            local take_idx = 0
            
            local snap_state = reaper.GetToggleCommandStateEx(32060, 1014) == 1
            

            while (reaper.MIDIEditor_EnumTakes(editor,take_idx,false)) do
                
                local take = reaper.MIDIEditor_EnumTakes(editor,take_idx,false)
                
                if  reaper.MIDI_EnumSelNotes(take, -1) ~= -1 then
                    if  snap_state then
                        api.Mcmd(editor,1014)--disable snap
                    end
                    api.Mcmd(editor,api.name('_RS7d3c_0982f40f2cfb848c3fa4895717bfd05481f0ca38'))--split notes at mouse cursor
                    if  snap_state then
                        api.Mcmd(editor,1014)--enable snap
                    end
                    return
                end

                sel_trs[#sel_trs+1] = api.git(reaper.GetMediaItemTake_Item(take))
                take_idx = take_idx+1
            end

        end

        if #sel_trs == 0 then return end

        api.cmd(40297,0) -- unselect all track

        SOLO = (api.gtv(sel_trs[1],'I_SOLO') ~= 0 and 0 ) or mode

        ----------------
        -----SIMPLE-----
        ----------------
        
        -- for abi=1, #sel_trs do

        --     tr = sel_trs[abi]
        --     api.stv(tr,'I_SOLO',SOLO) 
            
        --     parent = r.HaveParent(tr)
        --     while parent do
        --         api.stv(parent,'I_SOLO',SOLO) 
        --         parent = r.HaveParent(parent)
        --     end

        -- end

        -----------------
        -----COMPLEX-----
        -----------------

        for abi=1, #sel_trs do
            local tr = sel_trs[abi]
            if reaper.TrackFX_GetByName(tr, 'Superior Drummer 3', false) >= 0 then --deal with drum vst routing
                for abii=1, reaper.GetTrackNumSends( tr, 0) do
                    local found
                    local dist_tr = reaper.BR_GetMediaTrackSendInfo_Track(tr, 0, abii-1, 1)
                    if dist_tr then 
                        local _, name = reaper.GetTrackName( dist_tr)
                        local drum_chart = {'D_hi-hat', 'D_kick in', 'D_kick out', 'D_kick sub', 'D_snare top',
                                            'D_snare bottom', 'D_tom 1', 'D_tom 2', 'D_tom 3', 'D_floortom 1','D_floortom 2', 
                                            'D_OH Dyn', 'D_OH Cond', 'D_room near', 'D_room ribbon', 'D_room mid'}
                        for abiii=1, #drum_chart do
                            local n = ESCPattern(drum_chart[abiii])
                            if name:find(n) then
                                local dr_parent = r.HaveParent(dist_tr)
                                if dr_parent then
                                    api.stv(dr_parent, 'I_SOLO', SOLO)
                                end
                                found = true
                                break
                            end
                        end
                    end
                    if found then break end
                end
            end
            local parent = r.HaveParent(tr)
            if SOLO == 0 then
                while(parent) do
                    local skip = false
                    api.sot(parent)
                    r.cmd('_SWS_SELCHILDREN')
                    for abii=1, api.cst(0) do
                        local child = api.gst(0, abii-1)
                        if api.gtv(child,'I_SOLO') ~= 0 and child ~= sel_trs[1] then
                            skip =  true
                            break
                        end
                    end
                    if not skip then api.stv(parent,'I_SOLO',SOLO) end
                    parent = r.HaveParent(parent)
                end
            else
                while (parent) do
                    api.stv(parent, 'I_SOLO', SOLO)
                    parent = r.HaveParent(parent)
                end
            end
            api.stv(tr,'I_SOLO',SOLO)
        end
        
        if SOLO ~= 0 then SaveSoloTracks() end
        r.RestoreTracks('sel_tracks')

    end

    local function main()
        
        local state = api.load('Midi_editor','move note state')
        local editor = reaper.MIDIEditor_GetActive()

        if  state == '1' or state == 'ON' then
            api.Mcmd(editor,api.name('_RS7d3c_ac23609aa3551cdbf8b8d3ccd04dcbe7a4934160'))--move note down
        else
            solo(r.SaveTracks('sel_tracks'), editor)
        end
        
    end

    main()
    
    reaper.defer(function() end)
