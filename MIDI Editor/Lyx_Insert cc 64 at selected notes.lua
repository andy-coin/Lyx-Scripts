  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --------------
     
    
    local function main()
        
        local editor,tk,_,cc_lane,time, timeout, tk_idx, silence
        
        local peakL = reaper.Track_GetPeakInfo(api.gmt(), 0)
        local peakR = reaper.Track_GetPeakInfo(api.gmt(), 1)

        silence = true --peakL+peakR < 0.003

        editor = reaper.MIDIEditor_GetActive()
        --if not editor or api.gps() ~= 0  or not silence  then return end
        
        --api.ubb()--undo begin block
        
        time = api.now()
        timeout = 1
        cc_lane = 64
        tk_idx = 0
        tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)
        
        
        while tk and (api.now() - time < timeout) do 

            local  note, point, lookahead, cc_n

            lookahead = 15 -- 128th note
            
            reaper.BR_MIDI_CCLaneReplace(editor,0,cc_lane)
            
            note = reaper.MIDI_EnumSelNotes(tk, -1)
            if note == -1 then goto NEXT end
                    
            point = {}

            while( note ~= -1 and (api.now() - time < timeout)) do
                _,_,_,point[#point+1],point[#point+2]= reaper.MIDI_GetNote(tk,note)
                if  #point>2 and point[#point-1] < point[#point-2] then 
                    point[#point-2] = point[#point-1]
                end
                note = reaper.MIDI_EnumSelNotes(tk, note)
            end

            --delete selection old cc values
            _,_,cc_n = reaper.MIDI_CountEvts(tk)
            for abii = cc_n, 1, -1 do
                local _,_,_,position, chanmsg, chan, lane, msg3 = reaper.MIDI_GetCC(tk, abii-1)
                if  lane == cc_lane and position > point[1] - lookahead and position < point[#point] then
                    reaper.MIDI_DeleteCC(tk, abii-1)
                end
            end
                     
            for abii = 1, #point, 2 do
                reaper.MIDI_InsertCC(tk,true,false,point[abii] + abii%2 ,176,0,cc_lane, 0)
                reaper.MIDI_InsertCC(tk,true,false,point[abii] + abii%2 + lookahead*4 ,176,0,cc_lane, 127)
            end
                
            ::NEXT::                
            
            reaper.MIDIEditor_OnCommand(editor,42081)
            reaper.MIDI_RefreshEditors(tk)
            --reaper.MIDI_Sort(tk)
            tk_idx = tk_idx +1
            tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx , true)
                
        end
         
        cmd = api.name("_BR_ME_SET_CC_LANES_HEIGHT_200")
        api.Mcmd(editor,cmd)
        
        reaper.MIDIEditor_OnCommand(editor,40669)--Unselect all CC events in last clicked lane
        
        --api.ueb(0,"Insert cc events at the start and the end of selected notes",-1)
    end
    
    main()
    
    reaper.defer(function() end)
