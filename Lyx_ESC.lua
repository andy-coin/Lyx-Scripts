  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOM-----
    -- ESC closes FX windows (through the API) and the windows in Kill_list below; nothing else,
    -- so script GUIs (ReaImGui etc.) are never killed.
    -- (unused since ESC only closes Kill_list; kept in case the "close everything" mode comes back)
    -- local exclude = {'Colors','Licensed for personal/small business use','Item/track info',"Lyx_ESC",'Color palette','MIDI take:',"Video Window"}

    -- windows ESC closes: title contains one of these (plain text, case-insensitive)
    local Kill_list = {"Actions","REAPER Preferences","Track Manager","Screensets/Layouts","Render to File",
                       "Media Item Properties","Snap/Grid","Metronome","Add FX to","Crossfade Editor",'Notes for',
                       "Virtual MIDI keyboard","Batch File/Item Converter","Finished in","Reascript console output",
                       "Theme development/tweaker","Cycle Actions","LFO tool","ReaLauncher","ReaConsole"}

    local DEBUG = false -- TEMP: print what ESC does to the console
    local function log(...) if DEBUG then reaper.ShowConsoleMsg(table.concat({...}," ").."\n") end end

    local main_hwnd = reaper.GetMainHwnd()
    -- ask the window to close (like clicking X); Post doesn't arrive on macOS, so Send.
    -- ReaImGui windows close themselves on their next frame: forcing one crashes its script.
    -- Everything else still open right after is forced.
    local function close(hwnd)
        reaper.JS_WindowMessage_Send(hwnd, "WM_CLOSE", 0, 0, 0, 0)
        if (reaper.JS_Window_GetClassName(hwnd) or ""):lower():find("imgui", 1, true) then return end
        if reaper.JS_Window_IsWindow(hwnd) and reaper.JS_Window_IsVisible(hwnd) then reaper.JS_Window_Destroy(hwnd) end
    end

    local function has_any(title, list)
        title = title:lower()
        for i = 1, #list do
            if title:find(list[i]:lower(), 1, true) then return true end
        end
    end

    -- Close floating FX / FX chain windows of one track (fx_base 0) or its input/monitor FX (0x1000000).
    local function close_track_fx(tr, fx_base, n, chain)
        local hit
        if chain ~= -1 then reaper.TrackFX_Show(tr, fx_base, 0) hit = true end
        for i = 0, n - 1 do
            if reaper.TrackFX_GetFloatingWindow(tr, fx_base + i) then reaper.TrackFX_Show(tr, fx_base + i, 2) hit = true end
        end
        return hit
    end

    -- FX windows are found through the API, not the window list: on macOS they don't show up as top-level windows.
    -- ponytail: scans every track and take on each press; fine unless a project has tens of thousands of takes.
    local function close_all_fx()
        local hit
        for t = -1, reaper.CountTracks(0) - 1 do
            local tr = t < 0 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
            if close_track_fx(tr, 0, reaper.TrackFX_GetCount(tr), reaper.TrackFX_GetChainVisible(tr)) then hit = true end
            if close_track_fx(tr, 0x1000000, reaper.TrackFX_GetRecCount(tr), reaper.TrackFX_GetRecChainVisible(tr)) then hit = true end
        end
        for i = 0, reaper.CountMediaItems(0) - 1 do
            local item = reaper.GetMediaItem(0, i)
            for k = 0, reaper.CountTakes(item) - 1 do
                local take = reaper.GetTake(item, k)
                if take then
                    if reaper.TakeFX_GetChainVisible(take) ~= -1 then reaper.TakeFX_Show(take, 0, 0) hit = true end
                    for f = 0, reaper.TakeFX_GetCount(take) - 1 do
                        if reaper.TakeFX_GetFloatingWindow(take, f) then reaper.TakeFX_Show(take, f, 2) hit = true end
                    end
                end
            end
        end
        log("  FX closed:", tostring(hit == true))
        return hit
    end

    local function WindowKiller()
        local destroy = close_all_fx() or false
        local _, list = reaper.JS_Window_ListAllTop()

        -- visible windows from Kill_list: close them like clicking their X
        for address in list:gmatch('[^,]+') do
            local window = reaper.JS_Window_HandleFromAddress(address)
            if window ~= main_hwnd and reaper.JS_Window_IsVisible(window)
               and reaper.MIDIEditor_GetMode(window) == -1 then
                local title = reaper.JS_Window_GetTitle(window)
                log("  window:", "["..title.."]", "class:", reaper.JS_Window_GetClassName(window) or "")
                if DEBUG and title:find("console output", 1, true) then -- TEMP: keep the log readable
                elseif has_any(title, Kill_list) then
                    close(window) destroy = true
                end
            end
        end

        if DEBUG then -- TEMP: windows hanging under the main window
            local _, kids = reaper.JS_Window_ListAllChild(main_hwnd)
            for address in kids:gmatch('[^,]+') do
                local w = reaper.JS_Window_HandleFromAddress(address)
                local t = reaper.JS_Window_GetTitle(w)
                if t ~= "" and reaper.JS_Window_IsVisible(w) then
                    log("  child:", "["..t.."]", " parent is main:", tostring(reaper.JS_Window_GetParent(w) == main_hwnd))
                end
            end
        end
        log("  closed something:", tostring(destroy))
        return destroy
    end

    local function main()

        local editor,video

        editor = api.M()
        video = reaper.JS_Window_Find("Video Window",false)
        log("---- ESC  focus: ["..(reaper.JS_Window_GetTitle(reaper.JS_Window_GetFocus() or main_hwnd) or "").."]",
            " midi editor:", tostring(editor~=nil), " media explorer:", tostring(api.gtc(50124)), " video:", tostring(video~=nil))
        
        if  r.IsMidiEditorFocus(editor) then 
            log("  branch: MIDI editor unselect")
            reaper.MIDIEditor_OnCommand(editor,40214)--midi editor unselect all
            return
        elseif api.gtc(50124)==1 then
            log("  branch: close media explorer")
            api.cmd(50124,0)--close media exploer
        elseif video and reaper.GetToggleCommandState(50122) == 1 then
            log("  branch: exit fullscreen")
            api.cmd(50122,0)-- exit fullscreen
        elseif not WindowKiller() then
            log("  branch: no window closed -> unselect")
            if editor then
               api.cmd(40716,0)--close editor
            end
            if api.cst(0)==0 and api.csi(0)==0 and video then
                close(video)
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

