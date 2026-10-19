
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOM-----
    
        ---buffer size-
        auto_change_buffersize = false
        small = 128
        large = 2048
        guitar_icon = reaper.GetResourcePath()..'/Data/track_icons/Logic/Guitar/'
        eg_io = {   dry = 13,     -- input
                    wet = 1038,   -- input
                    kemper = 1037 -- ouput from 1032~1039
                }

    --------------
    local function ChangeBufferSize()
    
        for abi=1,reaper.CountTracks(0) do
            local tr=reaper.GetTrack(0,abi-1)
            if  api.gtv(tr,"I_RECARM")==1 then
                r.SetBufferSize(small)
                return
            end
        end
        
        r.SetBufferSize(large)

    end

    local function toggle_track_arm(tr)
                        
        if  reaper.TrackFX_GetInstrument(tr) >= 0 then
            api.stv(tr,"I_RECINPUT",6112)
        end
        
        api.stv(tr,"I_RECARM",rec_arm)
        input = api.gtv(tr,"I_RECINPUT")
        if  input ~= 1030 then
            if  input == 6112 then
                api.stv(tr,"I_RECMON",rec_arm)
            end
        else
            api.stv(tr,'I_SOLO',rec_arm)
        end
    end
    --------------
    local function main()
        
        r.SelTrackFilter()

        if api.cst(0) == 0 then return end
        
        r.SaveTracks(true)

        if api.cst(0) == 1 then -- eg, reamp
        
            local tr, _, name, idx, dry, wet, reamp, parent, input, kemper, cnt
            tr = api.gst(0,0)
            _, name = api.gtn(tr)
            input = api.gtv(tr, 'I_RECINPUT')
            
            cnt = reaper.GetTrackNumSends(tr, 1)
            for i = 0, cnt - 1 do
                local output = reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN")
                kemper =  math.abs(output - eg_io.kemper)<=8
                if kemper then break end
            end
            
            ::START::
            if name:find('EG') and input == -1 and api.gtv(tr, 'I_FOLDERDEPTH') == 1 or PASS then
                idx = api.gtv((PASS and parent) or tr,'IP_TRACKNUMBER')                
                repeat
                    local kemper
                    local tr = api.gt(0,idx)
                    if not tr then break end
                    input = api.gtv(tr,'I_RECINPUT')
                    local cnt = reaper.GetTrackNumSends(tr, 1)
                    for i = 0, cnt - 1 do
                        local output = reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN")
                        kemper = math.abs(output - eg_io.kemper)<=8
                        if kemper then break end
                    end

                    if input == eg_io.dry and kemper then
                        dry = tr
                    elseif input == eg_io.wet and not kemper then
                        wet = tr
                    elseif input == eg_io.wet and kemper then
                        reamp = tr
                    end
                    
                    idx = idx + 1
                    
                until api.gtv(tr, 'I_FOLDERDEPTH') < 0

                if  tr == reamp then
                    rec_arm = (api.gtv(reamp, "I_RECARM") == 0 and 1 ) or 0
                    api.cmd(40491,0) -- unram all tracks
                    api.stv(reamp,'I_RECARM',rec_arm)
                    api.stv(reamp,'B_MUTE', 0)
                    if dry then api.stv(dry,'B_MUTE',math.abs(rec_arm-1)) end
                    if wet then api.stv(wet,'B_MUTE',1) end
                else
                    if not dry or not wet then goto NORMAL end
                    rec_arm = (api.gtv(dry, "I_RECARM") == 0 and 1 ) or 0
                    api.cmd(40491,0) -- unram all tracks
                    api.stv(dry,'I_RECARM',rec_arm)
                    api.stv(wet,'I_RECARM',rec_arm)
                    api.stv(wet,'B_MUTE', 0)
                    if reamp then api.stv(reamp,'B_MUTE',rec_arm) end
                end
                
                goto CHANGE_BUFFER

            elseif (input == eg_io.dry and kemper) or (input == eg_io.wet and not kemper) or (input == eg_io.wet and kemper) then
                parent = r.HaveParent(tr)
                if parent then PASS = true goto START end
                
            else
                goto NORMAL 
            end


            -- if name:find('Dry') or name:find('Wet') or name:find('Reamp') then

            --     parent = r.HaveParent(tr)
            --     if parent then 
            --         _, name = api.gtn(parent)
            --         if name:find('EG') then PASS = true goto START end
            --     end
            -- elseif (name:find('EG') and api.gtv(tr,"I_FOLDERDEPTH") == 1) or PASS then
            --     idx = api.gtv((PASS and parent) or tr,'IP_TRACKNUMBER')
            --     repeat
            --         local tr = api.gt(0,idx)
            --         if not tr then break end

            --         input = api.gtv(tr,'I_RECINPUT')

            --         msg(input)
            --         local cnt = reaper.GetTrackNumSends(tr, 1)
            --         for i = 0, cnt - 1 do
            --             kemper = reaper.GetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN") == eg_io.kemper
            --             if kemper then break end
            --         end

            --         if input == eg_io.dry and kemper then
            --             dry = tr
            --         elseif input == eg_io.wet then
            --             if not kemper then wet = tr else reamp = tr end
            --         end

            --         idx = idx + 1

            --     until api.gtv(tr, 'I_FOLDERDEPTH') == -1
                
            --     if tr == reamp then
            --         rec_arm = (api.gtv(reamp, "I_RECARM") == 0 and 1 ) or 0
            --         api.cmd(40491,0) -- unram all tracks
            --         api.stv(reamp,'I_RECARM',rec_arm)
            --         api.stv(reamp,'B_MUTE', 0)
            --         api.stv(dry,'B_MUTE',math.abs(rec_arm-1))
            --         api.stv(wet,'B_MUTE',math.abs(rec_arm-1))
            --     else
            --         rec_arm = (api.gtv(dry, "I_RECARM") == 0 and 1 ) or 0
            --         api.cmd(40491,0) -- unram all tracks
            --         api.stv(dry,'I_RECARM',rec_arm)
            --         api.stv(wet,'I_RECARM',rec_arm)
            --         api.stv(wet,'B_MUTE', 0)
            --         api.stv(reamp,'B_MUTE',rec_arm)
            --     end

            -- end
        end
        
        ::NORMAL::

        rec_arm = (api.gtv(api.gst(0,0),"I_RECARM") == 0 and 1 ) or 0
        for abi=1,reaper.CountSelectedTracks(0) do
            local tr=reaper.GetSelectedTrack(0,abi-1)
            toggle_track_arm(tr)
        end

        r.RestoreTracks(true)

        ::CHANGE_BUFFER::
        play = reaper.GetPlayState()
        if play==0 and auto_change_buffersize then
            ChangeBufferSize()
        end

    end
    api.cc()

    main()
