    
        
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    TCP_max = r.GetTCP_Size()
    local FATTY_name = "\30\31\30\31\30\31" -- invisible spacer track under the MIDI editor
    local ZoomToNotes = require("MIDI Editor/Lyx_Zoom to notes")
    
    mainHWND = reaper.GetMainHwnd()
    windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
    _,ori_scroll = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
    
    ---------------
    ---CUSTOMIZE---
    ---------------
    local midi_editor = {
                    screen_height = TCP_max*0.85,
                    single_zoom   = math.floor(TCP_max*0.45),   --single item vertical zoom pixel
                    bound_limit   = true,                     -- zoom in media item with limit
                    bound=10,                               -- limit left edge to right edge to setting seconds
                    --midi editor window position: the one saved with "Save midi editor window position",
                    --otherwise the bottom part of the screen REAPER is on
                    fix          = true,
                    default_size = 0.45,                    -- default editor height, share of the screen
                 }      
                 
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

    -- set track heights directly (replaces r.SameTCPH, which stepped zoom actions dozens of times)
    local function SetHeights(trz, h)
        for _, tr in ipairs(trz) do
            if reaper.ValidatePtr2(0, tr, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", math.floor(h))
            end
        end
        reaper.TrackList_AdjustWindows(false)
    end

    --------------
    local function EditorRect() -- l, t, r, b in native coords, as JS_Window_GetRect gives them
        local e = {}
        for v in api.load("Item Editor","midi editor window position"):gmatch("(-?[%d.]+)|") do e[#e+1] = tonumber(v) end
        if  #e == 4 then -- saved spot, kept only while its monitor is still connected
            local cx, cy = math.floor((e[1]+e[3])/2), math.floor((e[2]+e[4])/2) -- my_getViewport wants integers
            local vl, vt, vr, vb = reaper.my_getViewport(0, 0, 0, 0, cx, cy, cx+1, cy+1, true)
            if cx >= vl and cx <= vr and cy >= math.min(vt,vb) and cy <= math.max(vt,vb) then
                return e[1], e[2], e[3], e[4]
            end
        end
        local w, h, x0, y0 = r.GetScreenResolution()
        local eh  = math.floor(h * midi_editor.default_size)
        local mac = reaper.GetOS():find("OS")       -- macOS: origin bottom-left, y grows upward
        local lower = (mac and y0) or y0 + h        -- the screen's bottom edge
        local upper = (mac and y0 + eh) or y0 + h - eh
        return x0, upper, x0 + w, lower
    end

    --------------
    local function AdjustMidiEditorSize(hwnd)
        -- returns how many pixels of the arrange view the editor covers (height for the spacer track)
        local left, top, right, bottom = r.GetWindowPosition(hwnd)
        local L, T, R, B = EditorRect()

        if  midi_editor.fix and (left~=L or top~=T or right~=R or bottom~=B) then
            r.SetWindowPosition(hwnd, L, B, R, T)
            left, top, right, bottom = L, T, R, B
        end

        -- overlap of two vertical spans: same math whichever way the screen's y axis points
        local _, _, at, _, ab = reaper.JS_Window_GetRect(windowHWND)
        local overlap = math.min(math.max(at,ab), math.max(top,bottom)) - math.max(math.min(at,ab), math.min(top,bottom))
        return math.max(0, overlap)
    end

    -----------------------------------SAVE SCREEN POSITION-------------------------------------------------
    local function SaveScreenPosition()
    
        CurStart,CurEnd = reaper.BR_GetArrangeView(0)
        api.save("Screen Position Start(editor)",pro_name,CurStart, true)
        api.save("Screen Position End(editor)",pro_name,CurEnd, true)
    end
    
    -----------------------------------LOAD SCREEN POSITION-------------------------------------------------
    local function LoadScreenPosition()
    
        OldStart = api.load("Screen Position Start(editor)",pro_name,true)
        OldEnd = api.load("Screen Position End(editor)",pro_name,true)
        if type(tonumber(OldStart))~="number" or type(tonumber(OldEnd))~="number" then return end
        reaper.BR_SetArrangeView(0,OldStart,OldEnd)
        
    end
    
    -------------------------------------GET VERTICAL ZOOM-------------------------------------
    local function GetVerticalZoom(tracks)

        if #tracks==0 then return end
        
        local TR_code = {}
        local TR_TCPH = {}
        for abi = 1,#tracks do
            if  api.gtv(tracks[abi],"C_LANESCOLLAPSED")==0 then
                reaper.Main_OnCommand(43100,0)--small lane (acts on all selected tracks, once is enough)
                break
            end
        end
        for abi = 1,#tracks do
            local tr = tracks[abi]
            _,TR_code[abi] = reaper.GetSetMediaTrackInfo_String(tr,"GUID","",false)
            TR_TCPH[abi] = reaper.GetMediaTrackInfo_Value(tr,"I_TCPH")
        end

        return TR_code,TR_TCPH
  
    end
    
    -------------------------------------SAVE VERTICAL ZOOM-------------------------------------
    local function SaveVerticalZoom(TR_code,TR_TCPH)

        TR_code[#TR_code+1]=ori_scroll
        local TR_code = serialize(TR_code)
        local TR_TCPH = serialize(TR_TCPH)
        
        api.save("Guid",pro_name,TR_code, true)
        api.save("Vertical level",pro_name,TR_TCPH, true)
    
    end
    
    -------------------------------------LOAD VERTICAL ZOOM-------------------------------------
    local function LoadVerticalZoom()
        
        local TR_code,TR_TCPH,code,TCPH,scroll,trz
        TR_code = api.load("Guid",pro_name)
        TR_TCPH = api.load("Vertical level",pro_name)
        
        code=unserialize(TR_code)
        TCPH=unserialize(TR_TCPH)

        if  type(code[#code])=="number" then
            scroll=code[#code]
            table.remove(code)
        end

        trz={}
        for abi=1,#code do
            trz[#trz+1]=reaper.BR_GetMediaTrackByGUID(0,code[abi])
            if  not TCPH[abi+1] or TCPH[abi]~=TCPH[abi+1] then
                SetHeights(trz,TCPH[abi])
                trz={}
          end
        end 
        
        reaper.JS_Window_SetScrollPos(windowHWND, "v", scroll or ori_scroll )
        reaper.CSurf_OnScroll(0,1)
        reaper.CSurf_OnScroll(0,-1)

    end
        
    ----------------------------------------RESET-----------------------------------------------
    local function Reset(ME)
        
        local tr,_,name
        Kill_Dummy_Space()
        
        if  ME then
            reaper.JS_Window_Destroy(ME)
            api.save("MIDI_OPEN",pro_name,0,false)
        end
        
        LoadScreenPosition()
        LoadVerticalZoom()

        --api.save("Item Editor",pro_name.."__toggle",0,true)

    end
    
    ----------------
    local function GetLastItems(pro_name)
        
        local last_itemz={}
        local GUID = api.load("editor_items",pro_name,true)
        
        if GUID == "" then return {} end
        
        GUID = unserialize(GUID)
        
        if type(GUID) ~= 'table' then return end

        for abi=1,#GUID do
            last_itemz[#last_itemz+1]=reaper.BR_GetMediaItemByGUID(0,GUID[abi])
        end
        
        return last_itemz
    end
    
    ----------------
    local function SetLastItems(pro_name,current_itemz)
        
        local GUID={}
        for abi=1,#current_itemz do
            local item = current_itemz[abi]
            if  item then
                _,GUID[#GUID+1]=reaper.GetSetMediaItemInfo_String(item,"GUID","",false)
            end
        end

        GUID=serialize(GUID)

        api.save("editor_items",pro_name,GUID,true)

    end
    
    ----------------
    local function RefreshMIDIEditor()
        
        if  reaper.MIDIEditor_GetActive() then
            reaper.defer(RefreshMIDIEditor)
        else
            Kill_Dummy_Space()
            
            if  api.load("MIDI_OPEN",pro_name)=="1" then
                api.save("MIDI_OPEN",pro_name,0,false)
                api.save("Item Editor",pro_name.."__toggle",0,true)
            end
        end

    end
    
    ----------------
    local function UpdateLastItems()
    
        local last_itemz=GetLastItems(pro_name)
        
        SetLastItems(pro_name,itemz)
        
        return last_itemz
    end
    
    --------------
    local function UpdateEditorToggle(state,last_itemz)
        
        if razor then
            --reaper.ShowConsoleMsg("1\n")
            state = 1
        elseif #itemz == 0 or not last_itemz then
            --reaper.ShowConsoleMsg("2\n")
            state = 0
        else
            --reaper.ShowConsoleMsg("3\n")
            state = math.abs(state-1)
            for abi=1,#itemzzz do
                local found
                for abii=1,#last_itemz do
                    if  itemzzz[abi]==last_itemz[abii] then
                        found = true
                    end
                end
                if  not found then
                    state = ((ME and isMidi) and 0) or 1
                    break
                end
            end
        end
        
        api.save("Item Editor",pro_name.."__toggle",tostring(state),true)
        
        --reaper.ShowConsoleMsg("state = "..state)
        
        return state==1
            
    end

    --------------
    local function VerZoomSelItems(itemz,min,max)
        
        local first_tr,last_tr,first_ip,last_ip,target_trs,target,ceiling,code,TCPH,multi_lanes
        
        reaper.Main_OnCommand(40297,0)--unselect all tracks
        
        first_tr=reaper.GetMediaItemTrack(itemz[1])
        last_tr=reaper.GetMediaItemTrack(itemz[#itemz])

        first_ip=reaper.GetMediaTrackInfo_Value(first_tr,"IP_TRACKNUMBER")
        last_ip=reaper.GetMediaTrackInfo_Value(last_tr,"IP_TRACKNUMBER")

        target_trs={}
        for abi=first_ip,last_ip do
            target_trs[#target_trs+1]=reaper.GetTrack(0,abi-1)
            reaper.SetTrackSelected(target_trs[#target_trs],true)
        end
        
        code,TCPH=GetVerticalZoom(target_trs)       

        if  #target_trs==1 then
            local tr=target_trs[1]
            multi_lanes=(api.gtv(tr,"I_NUMFIXEDLANES")>1 and api.gtv(tr,"C_LANESCOLLAPSED")==0)
            target=(multi_lanes and midi_editor.screen_height) or midi_editor.single_zoom
            ceiling=midi_editor.screen_height-target 
        else            
            target=midi_editor.screen_height/#target_trs
            ceiling=midi_editor.screen_height-target*#target_trs
        end
                
        SetHeights(target_trs,target)

        if  max-min < 2 then
            local center = (max+min)/2
            reaper.BR_SetArrangeView(0,center-1,center+1)
        else
            reaper.BR_SetArrangeView(0,min,max)
        end
        
        return reaper.GetMediaTrackInfo_Value(target_trs[1],"I_TCPY") - ceiling,code,TCPH

    end
    

    --------------
    local function isAllMIDI(items)
        
        local midi = true

        for abi=1,#items do
            local take=reaper.GetActiveTake(items[abi])
            if  (take and not reaper.TakeIsMIDI(take)) or not take then
                midi = false
                break
            end 
        end

        return midi,reaper.MIDIEditor_GetActive()
    end
    --------------
    local function Editor(itemz,midi)
        
        local _,bound,cur,code,TCPH,win,seg,det,new_scroll,scroll_offset,mouse,audio,MIDI
        
        code,TCPH={},{}
        
        reaper.BR_GetMouseCursorContext()
        mouse=reaper.BR_GetMouseCursorContext_Position()
        cur=reaper.GetCursorPosition()
        
        bound=midi_editor.bound

        if  midi then
            
            local starttime, endtime, H_zoom
            
            starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
            
            if  not razor then
                reaper.GetSet_LoopTimeRange2(0,true,false,cur-bound/2,cur+bound/2,false)
            else
                reaper.GetSet_LoopTimeRange2(0,true,false,razorMap.min,razorMap.max,false)
                for abi=1,#itemz do
                    reaper.SetMediaItemSelected(itemz[abi],true)
                end
            end
            
            reaper.Main_OnCommand(40153,0)--open MIDI editor
            MIDI = reaper.MIDIEditor_GetActive()
            
            --Zoom in to midi content
            reaper.MIDIEditor_OnCommand(MIDI,40746)--select note in time selection
            H_zoom = 40725
            H_zoom = 40151
            
            reaper.MIDIEditor_OnCommand(MIDI,H_zoom)
            ZoomToNotes(MIDI) -- notes in the time selection are selected now: fit to them, else to all notes
            reaper.MIDIEditor_OnCommand(MIDI,40214)--unselect all notes
            reaper.GetSet_LoopTimeRange2(0, true, false,starttime, endtime, false)
            

            reaper.SetOnlyTrackSelected(reaper.GetMediaItemTrack(itemz[1]))
            scroll_offset = reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack(0,0),"I_TCPY")-175

            --make track won't hide behind midi editor window
            local idx=reaper.CountTracks(0)+1
            local FATTY = AdjustMidiEditorSize(MIDI)
            reaper.InsertTrackAtIndex(idx,false)
            local tr=reaper.GetTrack(0,idx-1)
            local _,chunk=reaper.GetTrackStateChunk(tr,"",false)
            chunk=chunk:gsub('NAME ""','NAME "'.. FATTY_name ..'"')
            chunk=chunk:gsub("(TRACKHEIGHT )%d+",'%1'..tostring(FATTY))
            reaper.SetTrackStateChunk(tr,chunk,false)

            api.save("MIDI_OPEN",pro_name,1,false)


            RefreshMIDIEditor()
            
            --code,TCPH = GetVerticalZoom(trackzzz)
            --SaveVerticalZoom(code,TCPH) 

        else

            local L_edge,R_edge,center,offset_m,offset_M,m,M,mouse_item,MOUSE,H_scroll_50

            if  razor then
                L_edge=razorMap.min
                R_edge=razorMap.max
            else
                local zoom_offset = 1.1

                if  #itemz==1 then
                    m=reaper.GetMediaItemInfo_Value(itemz[1],"D_POSITION")
                    M=m+reaper.GetMediaItemInfo_Value(itemz[1],"D_LENGTH")
                else
                    m,M=r.GetProjectLength(true)
                end
                
                mouse_item = reaper.BR_GetMouseCursorContext_Item()
                
                for abi=1,#itemz do
                    if  mouse_item == itemz[abi] then
                        MOUSE = true
                        break
                    end
                end
                
                cur = ( MOUSE and mouse ) or cur
                
                if  cur<m or cur>M then
                    cur=(m+M)/2
                elseif  cur == -1 then 
                    cur=(as+ae)/2
                elseif not MOUSE then
                    H_scroll_50 = true
                end 

                if  midi_editor.bound_limit and M-m > bound then
                    m = cur-bound/2
                    M = cur+bound/2
                end
                
                -- center = (m+M)/2
                -- offset_m = ((cur-as)/(ae-as)) * bound
                -- offset_M = ((ae-cur)/(ae-as)) * bound
                L_edge   = (m - (M-m)*(zoom_offset - 1))
                R_edge   = ( M + (M-m)*(zoom_offset - 1))
            end
        
            scroll_offset,code,TCPH=VerZoomSelItems(itemz,L_edge,R_edge)

            if  H_scroll_50 then api.cmd(api.name('_SWS_HSCROLL50'),0) end

            if  #code>0 then
                SaveVerticalZoom(code,TCPH) 
            end
        end

        _,new_scroll = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )

        --reaper.JS_Window_SetScrollPos( windowHWND, "v",math.floor(new_scroll+scroll_offset ))

        api.save("Item Editor",pro_name.."__toggle",1,true)
        
        return MIDI
    end
    
    ----------------
    local function main()
            
        toggle = api.load("Item Editor",pro_name.."__toggle")
        toggle = (toggle=="1" and 1) or 0
   
        as,ae=reaper.BR_GetArrangeView(0)
     
        trackzzz=r.SaveTracks()
        itemzzz=r.SaveItems() 

        _,razorMap=r.GetRazorEdits(true)
        razor = #razorMap.item>0
        itemz=(razor and razorMap.item) or itemzzz
        
        last_itemz=UpdateLastItems()

        isMidi,ME = isAllMIDI(itemz)
        run = UpdateEditorToggle(toggle,last_itemz)
        
        if  isMidi then 
            if  not run then
                if  toggle == 1 then
                    SaveScreenPosition()
                    Reset(ME)
                else
                    local M = api.M()
                    if M then api.cmd(40716,0) end
                    return
                end
            else
                SaveVerticalZoom({ori_scroll},{})
            end
        else
            if  toggle == 1 then
                Reset(ME)
            else
                Kill_Dummy_Space()
                SaveScreenPosition()
            end
        end

        if  run then 
            midi = Editor(itemz,isMidi) 
            if midi then api.cmd(api.name('_SN_FOCUS_MIDI_EDITOR'),0) end--focus MIDI Editor
        end

        r.RestoreTracks(trackzzz)
        
    end
    
    ------------------------
    ---------EXECUTE--------
    ------------------------

    main() -- no PreventUIRefresh here: scroll restore needs the live track layout
    r.AdjustGrid()
    
    reaper.defer(function()end)
