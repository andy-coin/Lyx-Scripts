  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    exclude = {'Colors','Licensed for personal/small business use','Item/track info',"Lyx_ESC",'Color palette','MIDI take:'}
    
    local Kill_list = {
                    -----Main-----
                    "Actions","REAPER Preferences","Track Manager","Theme development/tweaker",
                    "Screensets/Layouts","Cycle Actions","LFO tool","Reascript console output",
                    "Render to File","Virtual MIDI keyboard","Media Item Properties","MTuner",
                    "Metronome","Snap/Grid","ReaLauncher","Add FX to","ReaConsole","Batch File/Item Converter",
                    "Render to File","Finished in",'Notes for','Crossfade Editor',
                    -----FX-----
                    "FX: Track","FX: Item","FX: Monitoring","VST:","VSTi:",
                    "VST3:","VST3i:","AU:","AUi:","LV2:","LV2i:","JS:","(x86_64)",
                    "CLAP:","CALPi:","ReWire:","Container","%[parallel%]"}
    
    local function WindowKiller_lagacy(windows,exclude)

        for abi=1,#windows do
            local hwnd = reaper.JS_Window_Find(windows[abi],false)
            if  hwnd then
                floating = true
                while hwnd do
                    reaper.JS_Window_Destroy(hwnd)
                    hwnd=reaper.JS_Window_Find(windows[abi],false)
                end
            end
        end
        
        if desory then  api.cmd(api.name('_S&M_WNCLS3'),0) end
        api.ua()
        return destroy
    end

    local function WindowKiller()
        
        local ret,list = reaper.JS_Window_ListAllTop()
        
        title_list = ''
        
        local destroy

        for  address in list:gmatch('[^,]+') do
            local window,title,found,vip
            window = reaper.JS_Window_HandleFromAddress(address)
            title = reaper.JS_Window_GetTitle(window)
            
            local idx = title:match(' %- Track (%d+)')
            
            if idx then -- for fx witch changed name
                local tr = api.gt(0,idx-1)
                local pre_fx_n = reaper.TrackFX_GetRecCount(tr)
                local post_fx_n = reaper.TrackFX_GetCount(tr)

                for abi = 0, pre_fx_n-1 do
                    local _, name =  reaper.TrackFX_GetFXName(tr, abi|0x1000000 )
                    name = ESCPattern(name)
                    if  title:match(name) then
                        reaper.JS_Window_Destroy(window)
                        destroy = true
                    end
                end
                
                for abi = 0, post_fx_n-1 do
                    local _, name =  reaper.TrackFX_GetFXName(tr, abi )
                    name = ESCPattern(name)
                    if  title:match(name) then
                        reaper.JS_Window_Destroy(window)
                        destroy = true
                    end
                end
            end 
            
            for abi=1,#Kill_list do
                if  title:match(Kill_list[abi]) and api.check(0,window,"HWND*") and reaper.JS_Window_IsVisible(window) then
                    reaper.JS_Window_Destroy(window)
                    destroy = true
                end
            end
        end    

        if  destroy then 
            return true
        end 
    end

        -- for  abi=1,#exclude do
        --     if  title:find(exclude[abi]) then
        --         vip = true
        --         break
        --     end
        -- end

        -- if  not vip and api.check(0,window,"HWND*") and reaper.JS_Window_IsVisible(window) then
        --     reaper.JS_Window_Destroy(window)
        --     destroy = true
        -- end
    
    --end

    local function main()

        local editor,video

        editor = api.M()
        video = reaper.JS_Window_Find("Video Window",false)
        
        if  r.IsMidiEditorFocus(editor) then 
            reaper.MIDIEditor_OnCommand(editor,40214)--midi editor unselect all
            return
        elseif api.gtc(50124)==1 then
            api.cmd(50124,0)--close media exploer
        elseif video and reaper.GetToggleCommandState(50122) == 1 then
            api.cmd(50122,0)-- exit fullscreen
        elseif not WindowKiller() then
            if editor then
               api.cmd(40716,0)--close editor
            end
            if api.cst(0)==0 and api.csi(0)==0 and video then
                reaper.JS_Window_Destroy(video)
            else
                r.SaveTracks(true)
                api.cmd(40296,0)
                api.cmd(42692,0)--turn of  comping
                
                cmd=r.ScriptID("ReaTeam Scripts/Envelopes/Automation Items/cfillion_Unselect all automation items (all tracks).lua")
                reaper.Main_OnCommand(cmd,0)--unselect all automation items
                api.cmd(40769,0)-- Unselect (clear selection of) all tracks/items/envelope points
                
                --cmd=reaper.NamedCommandLookup("_SWS_UNSELALL")
                --reaper.Main_OnCommand(cmd,0)--unselect all
                --reaper.Main_OnCommand(40331,0)--unselect all points
                master=api.gmt()
                api.sts(master,false)
                r.RestoreTracks(true)
            end
        end
        
    end
    
    main()
    reaper.defer(function() end)

