  
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --------------
    local function main()
        
        local editor,last_answer,default_input,shape_guide,rev,csv,CSV,cc_lane,high,low,shape,tk,_,lanes,cc_shape,time,tk_idx, timeout

        editor = reaper.MIDIEditor_GetActive()
        if not editor then return end
        
        last_answer = api.load('Insert cc script','Insert cc script') 

        default_input = ( last_answer ~= '' and last_answer ) or '1,64,40,5'
        shape_guide = '[1] ／ [2] ⎍ [3]  ∫  [4]⎛  [5] ⎠[6]  ß :'

        rev,csv = r.GetUserInputs('Insert cc events at selected notes',4,
                                     'Insert cc events at lane  :,'..
                                     'Highest  Value  :,'..
                                     'Lowest Value  :,'..
                                     shape_guide,default_input)
        if not rev then return end

        CSV={}
        for value in csv:gmatch("[%d/?]+") do
            CSV[#CSV+1] = value
        end

        if  #CSV<4 then return end 

        lanes = CSV[1]
        high  = r.NumberCage(tonumber(CSV[2]),0,127,true)
        low   = r.NumberCage(tonumber(CSV[3]),0,127,true)
        shape = r.NumberCage(tonumber(CSV[4]),1,6,true)
        
        
        api.save('Insert cc script','Insert cc script',lanes..","..high..","..low..','..shape,true)
        
        api.ubb()--undo begin block

        api.cmd(api.name("_SWS_SAVETIME5"),0)

        cc_lane = {}
        for lane in lanes:gmatch('[^/]+') do
            cc_lane[#cc_lane+1] = tonumber(lane)
        end

        time = api.now()
        timeout = 15
        tk_idx = 0
        
        if #cc_lane == 0 then goto END end

        while (api.now() - time < timeout) do 
            
            tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)

            if not tk then break end

            local  note, last_note, Start, End, s, e, point, cc_n, lookahead

            lookahead = 60 -- 64th note
            
            for abi=1, #cc_lane do
                
                reaper.BR_MIDI_CCLaneReplace(editor,0,cc_lane[abi])
                
                note = reaper.MIDI_EnumSelNotes(tk, -1)
                if note == -1 then goto NEXT end
                    
                Start, End = {}, {}
                point = {}
                while( note ~= -1 and (api.now() - time < timeout)) do
                    _, _, _, s, e= reaper.MIDI_GetNote(tk,note)
                    Start[#Start+1] = s
                    End[#End+1] = e
                    point[#point+1] = s
                    point[#point+1] = e
                    --if  point[#point] and s > point[#point] then point[#point+1] = s end
                    --if  point[#point] and e > point[#point] then point[#point+1] = e end
                    if  #point>2 and point[#point-1] < point[#point-2] then 
                        point[#point-2] = point[#point-1]
                    end
                    note = reaper.MIDI_EnumSelNotes(tk, note)
                end

                --delete selection old cc values
                _,_,cc_n = reaper.MIDI_CountEvts(tk)
                for abii = cc_n, 1, -1 do
                    local _,_,_,position, chanmsg, chan, lane, msg3 = reaper.MIDI_GetCC(tk, abii-1)
                    --if  lane == cc_lane[abi] and position > Start[1] - lookahead and position < End[#End] then
                    if  lane == cc_lane[abi] and position > point[1] - lookahead and position < point[#point] then
                        reaper.MIDI_DeleteCC(tk, abii-1)
                    end
                end
                
                if  cc_lane[abi] == 64 then

                    -- --insert start point
                    -- reaper.MIDI_InsertCC(tk,true,false,Start[1] - lookahead * 2 ,176,0,cc_lane[abi],low)
                    -- reaper.MIDI_InsertCC(tk,true,false,Start[1] + lookahead,176,0,cc_lane[abi],high)
                    -- --insert end point
                    -- reaper.MIDI_InsertCC(tk,true,false,End[#End],176,0,cc_lane[abi],low)
                    
                    for abii = 1, #point, 2 do
                        reaper.MIDI_InsertCC(tk,true,false,point[abii] + abii%2 ,176,0,cc_lane[abi], low)
                        reaper.MIDI_InsertCC(tk,true,false,point[abii] + abii%2 + lookahead*4 ,176,0,cc_lane[abi], high)
                    end

                    -- --insert start point
                    -- reaper.MIDI_InsertCC(tk,true,false,point[1] - lookahead * 2 ,176,0,cc_lane[abi],low)
                    -- reaper.MIDI_InsertCC(tk,true,false,point[1] + lookahead,176,0,cc_lane[abi],high)
                    -- --insert end point
                    -- reaper.MIDI_InsertCC(tk,true,false,point[#point],176,0,cc_lane[abi],low)

                else

                    --common
                    -- for abii = 1, #point do
                    --     reaper.MIDI_InsertCC(tk,true,false,point[abii] - lookahead + abii%2 ,176,0,cc_lane[abi], (abii%2 == 1 and low)or high )
                    -- end

                    ---strings
                    for abii = 1, #Start do
                       reaper.MIDI_InsertCC(tk,true,false,Start[abii], 176,0,cc_lane[abi],low)
                       reaper.MIDI_InsertCC(tk,true,false,Start[abii]   + lookahead*2 , 176,0,cc_lane[abi],high)
                       reaper.MIDI_InsertCC(tk,true,false,End[abii]   - lookahead*2 , 176,0,cc_lane[abi],high)
                    end

                end
                
                ::NEXT::                
                
                cc_shape = {42080,42081,42082,42083,42084,42085}
                reaper.MIDIEditor_OnCommand(editor,cc_shape[shape])
                reaper.MIDI_RefreshEditors(tk)
                --reaper.MIDI_Sort(tk)
                
            end

            tk_idx = tk_idx +1
            
        end

        ::END::

        api.cmd(api.name("_SWS_RESTTIME5"),0)
        
        reaper.MIDIEditor_OnCommand(editor,40669)--Unselect all CC events in last clicked lane

        api.ueb(0,"Insert cc events at the start and the end of selected notes",-1)
        
    end
    r.run(main)
