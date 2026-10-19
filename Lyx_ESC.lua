  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    -- visible windows whose title contains one of these are never closed (plain text)
    local exclude = {'Colors','Licensed for personal/small business use','Item/track info',"Lyx_ESC",'Color palette','MIDI take:',"Video Window"}

    -- REAPER dialogs closed by title (plain text). FX windows are found through the API instead,
    -- so they close in any language.
    local Kill_list = {"Actions","REAPER Preferences","Track Manager","Screensets/Layouts","Render to File",
                       "Media Item Properties","Snap/Grid","Metronome","Add FX to","Crossfade Editor",'Notes for',
                       "Virtual MIDI keyboard","Batch File/Item Converter","Finished in","Reascript console output",
                       "Theme development/tweaker","Cycle Actions","LFO tool","ReaLauncher","ReaConsole"}

    local main_hwnd = reaper.GetMainHwnd()
    local addr = reaper.JS_Window_AddressFromHandle

    local function close(hwnd) reaper.JS_WindowMessage_Post(hwnd, "WM_CLOSE", 0, 0, 0, 0) end

    local function has_any(title, list)
        for i = 1, #list do
            if title:find(list[i], 1, true) then return true end
        end
    end

    -- Close floating FX / FX chain windows of one track (fx_base 0) or its input/monitor FX (0x1000000).
    -- Returns true if something was closed.
    local function close_track_fx(tr, open, fx_base, n, chain)
        local hit
        if chain ~= -1 then reaper.TrackFX_Show(tr, fx_base, 0) hit = true end
        for i = 0, n - 1 do
            local w = reaper.TrackFX_GetFloatingWindow(tr, fx_base + i)
            if w then reaper.TrackFX_Show(tr, fx_base + i, 2) open[addr(w)] = nil hit = true end
        end
        return hit
    end

    local function any(t) return next(t) ~= nil end

    -- drop windows that got hidden (FX chain windows have no API handle)
    local function prune(open)
        for k, w in pairs(open) do
            if not reaper.JS_Window_IsVisible(w) then open[k] = nil end
        end
    end

    local function WindowKiller()
        local _, list = reaper.JS_Window_ListAllTop()
        local open, destroy = {}, false

        for address in list:gmatch('[^,]+') do
            local window = reaper.JS_Window_HandleFromAddress(address)
            if window ~= main_hwnd and reaper.JS_Window_IsVisible(window)
               and reaper.MIDIEditor_GetMode(window) == -1 then
                local title = reaper.JS_Window_GetTitle(window)
                if has_any(title, Kill_list) then
                    close(window) destroy = true
                elseif not has_any(title, exclude) then
                    open[addr(window)] = window   -- maybe an FX window, checked below
                end
            end
        end

        -- Fast path: no unknown window open -> skip the FX scan.
        -- ponytail: otherwise scans all tracks/takes until every unknown window is accounted for;
        -- an always-open script window (not in exclude) forces a full scan each press.
        if any(open) then
            local tracks = reaper.CountTracks(0)
            for t = -1, tracks - 1 do
                local tr = t < 0 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
                local a = close_track_fx(tr, open, 0, reaper.TrackFX_GetCount(tr), reaper.TrackFX_GetChainVisible(tr))
                local b = close_track_fx(tr, open, 0x1000000, reaper.TrackFX_GetRecCount(tr), reaper.TrackFX_GetRecChainVisible(tr))
                if a or b then destroy = true prune(open) end
                if not any(open) then break end
            end
            for i = 0, (any(open) and reaper.CountMediaItems(0) or 0) - 1 do
                local item = reaper.GetMediaItem(0, i)
                for k = 0, reaper.CountTakes(item) - 1 do
                    local take = reaper.GetTake(item, k)
                    if take then
                        local hit
                        if reaper.TakeFX_GetChainVisible(take) ~= -1 then reaper.TakeFX_Show(take, 0, 0) hit = true end
                        for f = 0, reaper.TakeFX_GetCount(take) - 1 do
                            local w = reaper.TakeFX_GetFloatingWindow(take, f)
                            if w then reaper.TakeFX_Show(take, f, 2) open[addr(w)] = nil hit = true end
                        end
                        if hit then destroy = true prune(open) end
                    end
                end
                if not any(open) then break end
            end
        end

        return destroy
    end

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

