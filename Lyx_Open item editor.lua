

    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")

    TCP_max = r.GetTCP_Size()
    local FATTY_name = "\30\31\30\31\30\31" -- invisible spacer track under the MIDI editor
    local okZ, ZoomToNotes = pcall(require, "MIDI Editor/Lyx_Zoom to notes")

    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
    _,ori_scroll = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )

    ---------------
    ---CUSTOMIZE---
    ---------------
    data = api.load("Item Editor","midi editor window position")
    edge={}
    for value in data:gmatch("(%d*)|") do
        edge[#edge+1] = value
    end

    local midi_editor = {
                    screen_height = TCP_max,                    -- zoomed tracks share the arrange view height
                    single_zoom   = math.floor(TCP_max*0.45),   --single item vertical zoom pixel
                    bound_limit   = true,                     -- zoom in media item with limit
                    bound=10,                               -- limit left edge to right edge to setting seconds
                    --midi editor window position
                    fix    = true,
                    left   = edge[1] or 110,
                    top    = edge[2] or 595,
                    right  = edge[3] or 1753,
                    bottom = edge[4] or 0,
                 }

    -- How a press is decided (state is kept per project):
    --   1. the arrange view (all track heights, vertical scroll, horizontal view) is saved only from idle
    --   2. finish = close the MIDI editor + restore the saved view -> idle. A press finishes when:
    --        the selection is empty / the MIDI editor is open and only MIDI items are selected
    --        (the editor already follows the selection) / zoomed and exactly the same items again
    --   3. otherwise: only MIDI items -> restore the view, open the MIDI editor
    --                 any other item  -> close the MIDI editor, restore the view if already zoomed
    --                                    (other items than last time), then zoom (1 track: single_zoom,
    --                                    several: share screen_height)
    --   4. MIDI editor closed by hand = idle
    local STATE_SEC = "Item Editor state"

    --------------
    local function Kill_Dummy_Space()
        while true do
            local tr = reaper.GetTrack(0, reaper.CountTracks(0)-1)
            if not tr then break end
            local _, name = reaper.GetTrackName(tr)
            if name ~= FATTY_name then break end
            reaper.DeleteTrack(tr)
        end
    end

    --------------
    local function AdjustMidiEditorSize(hwnd)

        local fix,left,right,top,bottom,L,T,R,B
        left, top, right, bottom=r.GetWindowPosition(hwnd)
        fix=midi_editor.fix
        L=midi_editor.left
        R=midi_editor.right
        T=midi_editor.top
        B=midi_editor.bottom

        if  fix and (left~=L or top~=T or right~=R or bottom~=B) then
            r.SetWindowPosition(hwnd, L, B, R, T)
        end

        return top
    end

    -------------------------------------STATE-------------------------------------
    local function LoadState()
        local st = unserialize(api.load(STATE_SEC, pro_name))
        st.items = st.items or {}
        return st
    end

    local function SaveState(st)
        api.save(STATE_SEC, pro_name, serialize(st), true)
    end

    local function GUIDs(items)
        local g = {}
        for i = 1, #items do
            local _, guid = reaper.GetSetMediaItemInfo_String(items[i], "GUID", "", false)
            g[#g+1] = guid
        end
        return g
    end

    local function SameSet(a, b)
        if #a ~= #b then return false end
        local seen = {}
        for i = 1, #a do seen[a[i]] = true end
        for i = 1, #b do if not seen[b[i]] then return false end end
        return true
    end

    -------------------------------------SAVE / RESTORE ARRANGE VIEW-------------------------------------
    -- every track's height override (0 = default height), vertical scroll and horizontal view
    local function SaveView()
        local view = {h = {}, scroll = ori_scroll}
        view.s, view.e = reaper.BR_GetArrangeView(0)
        for i = 0, reaper.CountTracks(0)-1 do
            local tr = reaper.GetTrack(0, i)
            local _, guid = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
            view.h[guid] = reaper.GetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE")
        end
        return view
    end

    local function RestoreHeights(view)
        for guid, h in pairs(view.h or {}) do
            local tr = reaper.BR_GetMediaTrackByGUID(0, guid)
            if tr then reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", h) end
        end
        reaper.TrackList_AdjustWindows(false)
        if view.scroll then
            reaper.JS_Window_SetScrollPos(windowHWND, "v", math.floor(view.scroll))
            reaper.CSurf_OnScroll(0,1)
            reaper.CSurf_OnScroll(0,-1)
        end
    end

    local function RestoreView(view)
        RestoreHeights(view)
        if view.s and view.e then reaper.BR_SetArrangeView(0, view.s, view.e) end
    end

    -------------------------------------MIDI EDITOR-------------------------------------
    local function CloseEditor()
        local ME = reaper.MIDIEditor_GetActive()
        if ME then reaper.JS_Window_Destroy(ME) end
        Kill_Dummy_Space()
    end

    local function RefreshMIDIEditor()
        -- remove the spacer track once the editor is closed (by hand or by this script)
        if  reaper.MIDIEditor_GetActive() then
            reaper.defer(RefreshMIDIEditor)
        else
            Kill_Dummy_Space()
        end
    end

    -------------------------------------ZOOM RANGE-------------------------------------
    -- time range to look at: the items' span, or bound seconds around the edit cursor
    -- (or the mouse, when it is over one of the items) when the span is longer than bound
    local function ZoomRange(itemz)
        if  razor then return razorMap.min, razorMap.max end

        local m,M,cur,mouse,mouse_item,MOUSE,H_scroll_50
        local bound = midi_editor.bound

        reaper.BR_GetMouseCursorContext()
        mouse = reaper.BR_GetMouseCursorContext_Position()
        mouse_item = reaper.BR_GetMouseCursorContext_Item()
        cur = reaper.GetCursorPosition()

        m = math.huge
        M = -math.huge
        for abi=1,#itemz do
            local pos = reaper.GetMediaItemInfo_Value(itemz[abi],"D_POSITION")
            m = math.min(m, pos)
            M = math.max(M, pos + reaper.GetMediaItemInfo_Value(itemz[abi],"D_LENGTH"))
            if  mouse_item == itemz[abi] then MOUSE = true end
        end

        cur = ( MOUSE and mouse ) or cur

        if  cur<m or cur>M then
            cur=(m+M)/2
        elseif not MOUSE then
            H_scroll_50 = true
        end

        if  midi_editor.bound_limit and M-m > bound then
            m = cur-bound/2
            M = cur+bound/2
        end

        return m, M, H_scroll_50
    end

    -------------------------------------MEDIA ZOOM (horizontal)-------------------------------------
    -- New arrange view: as long as the items (bound seconds at most) + 10% each side, placed by:
    --   1. mouse over one of the items  -> the time under the mouse stays under the mouse
    --   2. edit cursor inside the items -> the edit cursor stays where it is on screen
    --   3. otherwise                    -> centred on the items' middle
    -- Razor edits: exactly the razor range.
    local function MediaView(itemz)
        if  razor then return razorMap.min, razorMap.max end
        local m, M = math.huge, -math.huge
        for i = 1, #itemz do
            local pos = reaper.GetMediaItemInfo_Value(itemz[i], "D_POSITION")
            m = math.min(m, pos)
            M = math.max(M, pos + reaper.GetMediaItemInfo_Value(itemz[i], "D_LENGTH"))
        end
        local len = M - m
        if  midi_editor.bound_limit and len > midi_editor.bound then len = midi_editor.bound end
        len = math.max(2, len * 1.2)

        local s0, e0 = reaper.BR_GetArrangeView(0)
        local function frac(t) -- where t sits on screen now, 0..1 (centre when off screen)
            local f = (t - s0) / (e0 - s0)
            return (f >= 0 and f <= 1) and f or 0.5
        end
        reaper.BR_GetMouseCursorContext()
        local mouse_item, mouse = reaper.BR_GetMouseCursorContext_Item(), reaper.BR_GetMouseCursorContext_Position()
        local cur = reaper.GetCursorPosition()
        local anchor, f
        for i = 1, #itemz do if itemz[i] == mouse_item then anchor = mouse end end
        if      anchor           then f = frac(anchor)
        elseif  cur >= m and cur <= M then anchor, f = cur, frac(cur)
        else    anchor, f = (m + M) / 2, 0.5 end
        local s = anchor - f * len
        return s, s + len
    end

    -------------------------------------MEDIA ZOOM-------------------------------------
    -- m, M: new horizontal view from MediaView, measured on the view the user was looking at
    local function ZoomMedia(itemz, m, M)

        local first_tr,last_tr,first_ip,last_ip,target_trs,target,multi_lanes

        reaper.Main_OnCommand(40297,0)--unselect all tracks

        first_tr=reaper.GetMediaItemTrack(itemz[1])
        last_tr=reaper.GetMediaItemTrack(itemz[#itemz])
        first_ip=reaper.GetMediaTrackInfo_Value(first_tr,"IP_TRACKNUMBER")
        last_ip=reaper.GetMediaTrackInfo_Value(last_tr,"IP_TRACKNUMBER")
        if first_ip > last_ip then first_ip, last_ip = last_ip, first_ip end

        target_trs={}
        for abi=first_ip,last_ip do
            target_trs[#target_trs+1]=reaper.GetTrack(0,abi-1)
            reaper.SetTrackSelected(target_trs[#target_trs],true)
        end

        for abi = 1,#target_trs do
            if  api.gtv(target_trs[abi],"C_LANESCOLLAPSED")==0 then
                reaper.Main_OnCommand(43100,0)--small lane (acts on all selected tracks, once is enough)
                break
            end
        end

        if  #target_trs==1 then
            local tr=target_trs[1]
            multi_lanes=(api.gtv(tr,"I_NUMFIXEDLANES")>1 and api.gtv(tr,"C_LANESCOLLAPSED")==0)
            target=(multi_lanes and midi_editor.screen_height) or midi_editor.single_zoom
        else
            target=midi_editor.screen_height/#target_trs
        end

        for _, tr in ipairs(target_trs) do
            reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", math.floor(target))
        end
        reaper.TrackList_AdjustWindows(false)

        -- scroll so the last zoomed track's bottom (envelopes included) sits on the arrange view's bottom
        -- ponytail: visible envelopes add height, so the top tracks may then start above the view
        local last = target_trs[#target_trs]
        local bottom = reaper.GetMediaTrackInfo_Value(last,"I_TCPY") + reaper.GetMediaTrackInfo_Value(last,"I_WNDH")
        local _, pos = reaper.JS_Window_GetScrollInfo(windowHWND, "v")
        reaper.JS_Window_SetScrollPos(windowHWND, "v", math.max(0, math.floor(pos + bottom - midi_editor.screen_height)))
        reaper.CSurf_OnScroll(0,1)
        reaper.CSurf_OnScroll(0,-1)

        reaper.BR_SetArrangeView(0,m,M)
    end

    -------------------------------------OPEN MIDI EDITOR-------------------------------------
    local function OpenMidi(itemz)

        local starttime, endtime, MIDI
        local m, M = ZoomRange(itemz)   -- reference range for the note zoom only, arrange is not zoomed

        starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        reaper.GetSet_LoopTimeRange2(0,true,false,m,M,false)
        if  razor then
            for abi=1,#itemz do
                reaper.SetMediaItemSelected(itemz[abi],true)
            end
        end

        reaper.Main_OnCommand(40153,0)--open MIDI editor
        MIDI = reaper.MIDIEditor_GetActive()
        if not MIDI then reaper.GetSet_LoopTimeRange2(0, true, false,starttime, endtime, false) return end

        --Zoom in to midi content
        reaper.MIDIEditor_OnCommand(MIDI,40746)--select note in time selection
        reaper.MIDIEditor_OnCommand(MIDI,40151)
        if okZ then pcall(ZoomToNotes, MIDI) end -- notes in the range are selected now: fit to them, else to all notes
        reaper.MIDIEditor_OnCommand(MIDI,40214)--unselect all notes
        reaper.GetSet_LoopTimeRange2(0, true, false,starttime, endtime, false)

        reaper.SetOnlyTrackSelected(reaper.GetMediaItemTrack(itemz[1]))

        --make track won't hide behind midi editor window
        local idx=reaper.CountTracks(0)+1
        local FATTY = AdjustMidiEditorSize(MIDI)-87
        reaper.InsertTrackAtIndex(idx,false)
        local tr=reaper.GetTrack(0,idx-1)
        local _,chunk=reaper.GetTrackStateChunk(tr,"",false)
        chunk=chunk:gsub('NAME ""','NAME "'.. FATTY_name ..'"')
        chunk=chunk:gsub("(TRACKHEIGHT )%d+",'%1'..tostring(FATTY))
        reaper.SetTrackStateChunk(tr,chunk,false)

        RefreshMIDIEditor()

        return MIDI
    end

    --------------
    local function isAllMIDI(items)
        for abi=1,#items do
            local take=reaper.GetActiveTake(items[abi])
            if  not take or not reaper.TakeIsMIDI(take) then return false end
        end
        return true
    end

    ----------------
    local function main()

        trackzzz=r.SaveTracks()
        local selected=r.SaveItems()

        _,razorMap=r.GetRazorEdits(true)
        razor = #razorMap.item>0
        local itemz=(razor and razorMap.item) or selected

        local st = LoadState()
        local guids = GUIDs(itemz)
        local ME = reaper.MIDIEditor_GetActive()
        local isMidi = #itemz>0 and isAllMIDI(itemz)

        if  st.branch=="midi" and not ME then st = {} end -- editor closed by hand = idle

        if  #itemz==0 or (isMidi and ME) or (st.branch=="media" and not razor and SameSet(guids, st.items)) then
            CloseEditor()
            if st.active then RestoreView(st.view) end
            SaveState({})
            r.RestoreTracks(trackzzz)
            return
        end

        if  not st.active then
            st = {active=true, view=SaveView()}
        end

        if  isMidi then
            RestoreView(st.view)
            st.branch = "midi"
            if OpenMidi(itemz) then api.cmd(api.name('_SN_FOCUS_MIDI_EDITOR'),0) end--focus MIDI Editor
        else
            local m, M = MediaView(itemz) -- from the view on screen now, before any restore
            CloseEditor()
            if st.branch then RestoreView(st.view) end -- already zoomed on other items: start from the original view
            st.branch = "media"
            ZoomMedia(itemz, m, M)
        end

        st.items = guids
        SaveState(st)

        r.RestoreTracks(trackzzz)

    end

    ------------------------
    ---------EXECUTE--------
    ------------------------

    main() -- no PreventUIRefresh here: scroll restore needs the live track layout
    r.AdjustGrid()

    reaper.defer(function()end)
