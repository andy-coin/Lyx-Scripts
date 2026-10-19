--[[
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    --local r=require("_Lyx_HOME")
    
    --HOME="/Users/andy/Library/Application Support/REAPER/Scripts/Lyx Scripts/"
    --package.path = package.path..";"..HOME.."?.lua"
    --local lyx=require("_Lyx_HOME")
--]]

local Lyx_computer = true --reaper.GetResourcePath():find("/Users/andy/") or reaper.GetResourcePath():find("/Users/will/")

pro_name = reaper.GetProjectName(0) 
pro_name = (#pro_name > 0 and pro_name) or "Unsaved project"
REAPER = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(),1000)

DE_BUG_MODE = false
REAPER_ini = reaper.get_ini_file()

sys = {tab_h = math.floor(12 * ((Lyx_computer and 0.75) or 1))
      }

----------------------------
------------API-------------
----------------------------

api = {
        --project
        gpl  = reaper.GetProjectLength,
        gmt  = reaper.GetMasterTrack,
        gpc  = reaper.GetPlayPosition2,
        gpn  = reaper.GetProjectName,
        gec  = reaper.GetCursorPosition,
        sec  = reaper.SetEditCurPos,
        ua   = reaper.UpdateArrange,
        ut   = reaper.UpdateTimeline,
        gps  = reaper.GetPlayState,--&1=playing, &2=paused, &4=is recording
        Ttq  = reaper.TimeMap2_timeToQN,--(ReaProject proj, number tpos)
        Tqt  = reaper.TimeMap2_QNToTime,--(ReaProject proj, number qn)
        --track
        ct   = reaper.CountTracks,
        gt   = reaper.GetTrack,
        gtn  = reaper.GetTrackName,-- boolean retval, string buf
        cst  = reaper.CountSelectedTracks,
        gst  = reaper.GetSelectedTrack,
        sts  = reaper.SetTrackSelected,
        sot  = reaper.SetOnlyTrackSelected,
        iti  = reaper.InsertTrackAtIndex,
        itv  = reaper.IsTrackVisible,
        dt   = reaper.DeleteTrack,
        gtv  = reaper.GetMediaTrackInfo_Value,
        stv  = reaper.SetMediaTrackInfo_Value,
        gtsv = reaper.GetTrackSendInfo_Value,-- category is <0 for receives, 0=sends, >0 for hardware outputs
        stsv = reaper.SetTrackSendInfo_Value,
        ts   = reaper.GetSetMediaTrackInfo_String,
        tid  = reaper.BR_GetMediaTrackGUID,
        idt  = reaper.BR_GetMediaTrackByGUID, -- proj, guid
        gtC  = reaper.GetTrackStateChunk,
        stC  = reaper.SetTrackStateChunk,
        ctl  = function(track) reaper.GetMediaTrackInfo_Value(track, 'I_NUMFIXEDLANES') end,

        --item
        ci   = reaper.CountMediaItems,
        gi   = reaper.GetMediaItem,
        gti  = reaper.GetTrackMediaItem,
        git  = reaper.GetMediaItemTrack,
        cti  = reaper.CountTrackMediaItems,
        csi  = reaper.CountSelectedMediaItems,
        gsi  = reaper.GetSelectedMediaItem,
        iis  = reaper.IsMediaItemSelected,
        sis  = reaper.SetMediaItemSelected,
        giv  = reaper.GetMediaItemInfo_Value,
        siv  = reaper.SetMediaItemInfo_Value,
        is   = reaper.GetSetMediaItemInfo_String,
        iid  = reaper.BR_GetMediaItemGUID,
        idi  = reaper.BR_GetMediaItemByGUID, --proj, guid
        giC  = reaper.GetItemStateChunk,
        siC  = reaper.SetItemStateChunk,
        sie  = reaper.BR_SetItemEdges,
        an   = reaper.ApplyNudge,--[[ReaProject project, integer nudgeflag, integer nudgewhat, integer nudgeunits, number value, boolean reverse, integer copies
                                nudgeflag: &1=set to value (otherwise nudge by value), &2=snap
                                nudgewhat: 0=position, 1=left trim, 2=left edge, 3=right edge, 4=contents, 5=duplicate, 6=edit cursor
                                nudgeunit: 0=ms, 1=seconds, 2=grid, 3=256th notes, ..., 15=whole notes, 16=measures.beats (1.15 = 1 measure + 1.5 beats), 17=samples, 18=frames, 19=pixels, 20=item lengths, 21=item selections
                                value: amount to nudge by, or value to set to
                                reverse: in nudge mode, nudges left (otherwise ignored)
                                copies: in nudge duplicate mode, number of copies (otherwise ignored)]]--
        --take
        gatk = reaper.GetActiveTake,
        gtkn = reaper.GetTakeName,
        gtki = reaper.GetMediaItemTake_Item,
        gitk = reaper.GetMediaItemTake,
        gtkv = reaper.GetMediaItemTakeInfo_Value,
        stkv = reaper.SetMediaItemTakeInfo_Value,
        tks  = reaper.GetSetMediaItemTakeInfo_String,
        itkm = reaper.BR_IsTakeMidi,
        --envelope
        cte  = reaper.CountTrackEnvelopes,
        gte  = reaper.GetTrackEnvelope,
        gse  = reaper.GetSelectedEnvelope,
        gev  = reaper.GetEnvelopeInfo_Value,
        gen  = reaper.GetEnvelopeName,
        get  = reaper.Envelope_GetParentTrack,--MediaTrack , index1, index2 (env)
        cep  = reaper.CountEnvelopePointsEx,--(env, autoitem_idx)
        gep  = reaper.GetEnvelopePointEx,--retval, time, value, shape, tension, selected | ( env, autoitem_idx, ptidx)
        sep  = reaper.SetEnvelopePointEx,--(env, autoitem_idx, ptidx, opt number timeIn, opt number valueIn, opt integer shapeIn, opt number tensionIn, opt boolean selectedIn, opt boolean noSortIn)
        esp  = reaper.Envelope_SortPointsEx,--(env, autoitem_idx)
        es   = reaper.GetSetEnvelopeInfo_String,
        dep  = reaper.DeleteEnvelopePointEx,--(env, autoitem_idx, ptidx)
        geC  = reaper.GetEnvelopeStateChunk,
        seC  = reaper.SetEnvelopeStateChunk,
        brea = reaper.BR_EnvAlloc,
        breg = reaper.BR_EnvGetProperties,
        bres = reaper.BR_EnvSetProperties,
        bref = reaper.BR_EnvFree,
        cai  = reaper.CountAutomationItems,--(TrackEnvelope env)
        aiv  = reaper.GetSetAutomationItemInfo,--(TrackEnvelope env, integer autoitem_idx, string desc, number value, boolean is_set)
                                            --[[Get or set automation item information. autoitem_idx=0 for the first automation item on an envelope, 1 for the second item, etc. desc can be any of the following:
                                            D_POOL_ID : double * : automation item pool ID (as an integer); edits are propagated to all other automation items that share a pool ID
                                            D_POSITION : double * : automation item timeline position in seconds
                                            D_LENGTH : double * : automation item length in seconds
                                            D_STARTOFFS : double * : automation item start offset in seconds
                                            D_PLAYRATE : double * : automation item playback rate
                                            D_BASELINE : double * : automation item baseline value in the range [0,1]
                                            D_AMPLITUDE : double * : automation item amplitude in the range [-1,1]
                                            D_LOOPSRC : double * : nonzero if the automation item contents are looped
                                            D_UISEL : double * : nonzero if the automation item is selected in the arrange view
                                            D_POOL_QNLEN : double * : automation item pooled source length in quarter notes (setting will affect all pooled instances)]]--
        ais  = reaper.GetSetAutomationItemInfo_String,--(env,autoitem_idx,desc,valuestrNeedBig,is_set)
                                            --[[Get or set automation item information. autoitem_idx=0 for the first automation item on an envelope, 1 for the second item, etc. returns true on success. desc can be any of the following:
                                            P_POOL_NAME : char * : name of the underlying automation item pool
                                            P_POOL_EXT:xyz : char * : extension-specific persistent data]]--
        --FX

        --MIDI
        M    = reaper.MIDIEditor_GetActive,
        Mgt  = reaper.MIDIEditor_GetTake,
        Mcmd = reaper.MIDIEditor_OnCommand,
        Min  = reaper.MIDI_InsertNote,              --( take,B selected,B muted,D startppqpos,D endppqpos,I chan,I pitch,I vel,B noSortIn)
        Ms   = reaper.MIDI_Sort,                    --(MediaItem_Take take)
        Mre  = reaper.MIDI_RefreshEditors,          --(MediaItem_Take tk)
        Mpft = reaper.MIDI_GetPPQPosFromProjTime,   --(MediaItem_Take take, number projtime)
        Mqfp = reaper.MIDI_GetProjQNFromPPQPos,     --(MediaItem_Take take, number ppqpos)
        Mtfp = reaper.MIDI_GetProjTimeFromPPQPos,   --(MediaItem_Take take, number ppqpos)
        Mpfq = reaper.MIDI_GetPPQPosFromProjQN,     --(MediaItem_Take take, number projqn)
        Mpsm = reaper.MIDI_GetPPQPos_StartOfMeasure,--(MediaItem_Take take, number ppqpos)
        Mpem = reaper.MIDI_GetPPQPos_EndOfMeasure,  --(MediaItem_Take take, number ppqpos)
        Mgs  = reaper.MIDIEditor_GetSetting_int,--[[(HWND midieditor, string setting_desc)
                                                    Get settings from a MIDI editor. setting_desc can be:
                                                    snap_enabled: returns 0 or 1
                                                    active_note_row: returns 0-127
                                                    last_clicked_cc_lane: returns 0-127=CC, 0x100|(0-31)=14-bit CC, 0x200=velocity, 0x201=pitch, 0x202=program, 0x203=channel pressure, 0x204=bank/program select, 0x205=text, 0x206=sysex, 0x207=off velocity, 0x208=notation events, 0x210=media item lane
                                                    default_note_vel: returns 0-127
                                                    default_note_chan: returns 0-15
                                                    default_note_len: returns default length in MIDI ticks
                                                    scale_enabled: returns 0-1
                                                    scale_root: returns 0-12 (0=C)
                                                    list_cnt: if viewing list view, returns event count
                                                    if setting_desc is unsupported, then returns -1.--]]
        Mss  =  reaper.MIDIEditor_SetSetting_int,   --[[(HWND midieditor, string setting_desc, integer setting)
                                                        Set settings for a MIDI editor. setting_desc can be:
                                                        active_note_row: 0-127 --]]
        --misc
        cc   = reaper.ClearConsole,
        pur  = reaper.PreventUIRefresh,
        now  = reaper.time_precise,
        smb  = reaper.ShowMessageBox,-- 'massage','title',type = 0.OK 1.OK/CANCEL 2.ABORT/RETRY/IGNORE 3.YES/NO/CANCEL 4.YES/NO 5.RETRY/CANCEL
                                     -- ret {1=OK,2=CANCEL,3=ABORT,4=RETRY,5=IGNORE,6=YES,7=NO}
        ubb  = reaper.Undo_BeginBlock2,
        ueb  = reaper.Undo_EndBlock2,--(ReaProject proj, string descchange, integer extraflags)
        name = reaper.NamedCommandLookup,
        cmd  = reaper.Main_OnCommand,
        gtc  = reaper.GetToggleCommandState,
        stc  = reaper.SetToggleCommandState,--(section_id, command_id,  state)
        save = reaper.SetExtState,
        load = reaper.GetExtState,
        mcw  = reaper.BR_GetMouseCursorContext,
        mcp  = reaper.BR_GetMouseCursorContext_Position,
        mce  = reaper.BR_GetMouseCursorContext_Envelope,
        mct  = reaper.BR_GetMouseCursorContext_Track,
        mci  = reaper.BR_GetMouseCursorContext_Item,
        check= reaper.ValidatePtr2,--{"MediaTrack*","MediaItem*","MediaItem_Take*","TrackEnvelope*","PCM_source*","ReaProject*","MediaItem_TakePool*","MediaSample*"
      }       

local FUN={}

----------------------------
------BASIC FUNCTION--------
----------------------------

    function msg(message,detail,solo,symbol)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  msg\n')
            end

        if solo then reaper.ClearConsole() solo=nil end

        symbol=symbol or "\n"
        
        detail=(type(detail)=="number" and detail<=3 and detail) or 1

        if  detail<=0 then return end
        
        if  type(message)=="table" then

            local function printTable(tbl, indent)
                if  not indent then indent = 0 end
                for k, v in pairs(tbl) do
                    local Type=(detail>1 and type(v).." - ") or ""
                    formatting = string.rep("     ", indent)
                    if  type(v) == "table" then
                        reaper.ShowConsoleMsg(formatting.."{"..k.."}: ".."\n")
                        printTable(v, indent+1)
                    else
                        reaper.ShowConsoleMsg(formatting.."["..k.."]: "..Type..tostring(v).."\n")
                    end
                end
            end

            printTable(message)      
            return
        else
            local fun={function(x) return ((type(x)=="number" and x%1~=0) and string.format("%.3f",x)) or tostring(x) end,
            type,
            function(x) return string.len(tostring(x)) end
        }
            for i=1,detail do
                if i>1 then
                    reaper.ShowConsoleMsg("|")
                end
                reaper.ShowConsoleMsg(fun[i](message))
            end
            reaper.ShowConsoleMsg(symbol)
        end
    end
    --------------------------
    -- Table -> Lua table-constructor string, read back by unserialize().
    -- Keeps key/value types (string "10" vs number 10), nested tables, any bytes in
    -- strings and exact float values. Output is a single line, safe for ExtState.
    -- Functions / userdata / cyclic references are dropped (store a GUID instead of a
    -- MediaTrack etc.).
    function serialize(tbl)

        if  DE_BUG_MODE then
            reaper.ShowConsoleMsg('    Running FUNCTION --  serialize\n')
        end

        local function num(v)
            if math.type(v) == "integer" then
                -- the literal 9223372036854775808 overflows to float, so build it
                return v == math.mininteger and "(-9223372036854775807-1)" or tostring(v)
            end
            if v ~= v then return "0/0" end
            if v ==  math.huge then return "1/0" end
            if v == -math.huge then return "-1/0" end
            -- shortest form that round-trips exactly; keep it a float
            local s
            for p = 15, 17 do
                s = string.format("%." .. p .. "g", v)
                if tonumber(s) == v then break end
            end
            if not s:find("[%.eEn]") then s = s .. ".0" end
            return s
        end

        local function encode(v, path)
            local t = type(v)
            if t == "boolean" then
                return tostring(v)
            elseif t == "number" then
                return num(v)
            elseif t == "string" then
                -- %q leaves a real newline as "\<newline>"; turn it into \n
                return (string.format("%q", v):gsub("\\\n", "\\n"))
            elseif t == "table" then
                if path[v] then return nil end   -- cycle
                path[v] = true
                local parts = {}
                for k, val in pairs(v) do
                    local ek, ev = encode(k, path), encode(val, path)
                    if ek and ev then parts[#parts+1] = "[" .. ek .. "]=" .. ev end
                end
                path[v] = nil                    -- shared (non-cyclic) subtables still allowed
                return "{" .. table.concat(parts, ",") .. "}"
            end
            return nil
        end

        return encode(tbl, {}) or "{}"
    end

    -- String from serialize() -> table. Anything else (empty string, nil, old
    -- formats, broken data) returns {}. Runs with an empty environment, so stored
    -- text can't call any function.
    function unserialize(str)

        if  DE_BUG_MODE then
            reaper.ShowConsoleMsg('    Running FUNCTION --  unserialize\n')
        end

        if type(str) ~= "string" or not str:find("^%s*{") then return {} end

        local f = load("return " .. str, "=unserialize", "t", {})
        if not f then return {} end

        local ok, result = pcall(f)
        return (ok and type(result) == "table") and result or {}
    end

    function ESCPattern(text,terminal)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  ESCPattern\n')
            end
        -- 將所有特殊模式匹配字符前加上 '%' 進行轉義
        local escapedText
        if  terminal then
            escapedText = text:gsub("([%s%^%$%(%)%%%.%[%]%*%+%-%?%&])", "\\%1")
        else
            escapedText = text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        end
        return escapedText
    end

    function BBB(str,second,focus_window)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  BBB\n')
            end

        local font,x,y,FOCUS,S0,dpi,emoji,str_w,str_h,rect_w
        local fix_mode,fix_x,fix_y,btn_x,btn_y,btn_size,last_click

        font = 'WenQuanYiZenHei'
        -- 讀取持久化的 lock 狀態
        fix_mode = api.load("billboard","fix_mode") == "true"
        fix_x = tonumber(api.load("billboard","fix_x"))
        fix_y = tonumber(api.load("billboard","fix_y"))
        FOCUS = focus_window or reaper.JS_Window_GetFocus() or reaper.GetMainHwnd()
        S0=reaper.time_precise()

        local function ProjectsTab(bypass)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  ProjectsTab\n')
            end

            if bypass then return 0 end
            local p=0
            repeat
                local proj = reaper.EnumProjects(p)
                p=p+1
            until not proj
            return (p>2 and sys.tab_h ) or 0
        end

        local function DrawToggle()
            -- 右上角 toggle 按鈕：手繪鎖頭 icon
            local s = btn_size
            local cx = btn_x + s/2
            local body_w = s * 0.7
            local body_h = s * 0.48
            local body_x = cx - body_w/2
            local body_y = btn_y + s*0.45
            local sh_r = s * 0.26
            local sh_cy = body_y

            -- 背景清除（避免重繪殘影）
            gfx.set(9/255, 38/255, 44/255)
            gfx.rect(btn_x - 1, btn_y - 1, s + 2, s + 2, 1)

            -- 主色
            if fix_mode then
                gfx.set(251/255, 184/255, 47/255)   -- locked = 橘
            else
                gfx.set(0.6, 0.6, 0.6)              -- unlocked = 灰
            end

            -- 鎖身
            gfx.rect(body_x, body_y, body_w, body_h, 1)

            -- 鎖環（畫 2 圈粗線）
            for i = 0, 1 do
                if fix_mode then
                    -- 完整倒 U
                    gfx.arc(cx, sh_cy, sh_r - i, -math.pi/2, math.pi/2, 1)
                else
                    -- 開鎖：右端斷開
                    gfx.arc(cx, sh_cy, sh_r - i, -math.pi/2, math.pi/6, 1)
                end
            end

            -- 鑰匙孔
            gfx.set(9/255, 38/255, 44/255)
            gfx.circle(cx, body_y + body_h*0.45, math.max(1, s*0.08), 1, 1)
            gfx.rect(cx - s*0.04, body_y + body_h*0.45, s*0.08, body_h*0.35, 1)
        end

        local function Wait(sec)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  Wait\n')
            end

            local billboard = reaper.JS_Window_Find("( ˊ_>ˋ )",true) or reaper.JS_Window_Find("｡ﾟヽ(ﾟ´Д`)ﾉﾟ｡",true)
            local S1= reaper.time_precise()
            local focus = reaper.JS_Window_GetFocus()

            -- 處理 toggle 按鈕點擊
            local mx, my = gfx.mouse_x, gfx.mouse_y
            local clicked_now = (gfx.mouse_cap & 1) == 1
            local in_btn = mx >= btn_x and mx <= btn_x + btn_size
                       and my >= btn_y and my <= btn_y + btn_size
            if clicked_now and not last_click and in_btn then
                fix_mode = not fix_mode
                api.save("billboard","fix_mode", tostring(fix_mode), true)
                if fix_mode and billboard then
                    -- 切換到 fix：記錄當下視窗位置
                    local _, l, t, r, b = reaper.JS_Window_GetRect(billboard)
                    fix_x = (l + r)/2
                    fix_y = b + tab_h
                    api.save("billboard","fix_x", fix_x, true)
                    api.save("billboard","fix_y", fix_y, true)
                end
                DrawToggle()
                gfx.update()
                S0 = reaper.time_precise()  -- 點擊後延長顯示，方便確認
            end
            last_click = clicked_now

            if  (S1-S0) < sec or focus == billboard then
                reaper.defer(function()Wait(sec)end)
            else
                if  billboard and not fix_mode then
                    -- 僅 free 模式才記錄關閉時位置
                    local _, l, t, r, b = reaper.JS_Window_GetRect(billboard)
                    local cx = (l + r )/2
                    local cy = b + tab_h
                    api.save("billboard","gfx.x",cx,true)
                    api.save("billboard","gfx.y",cy,true)
                end
                gfx.quit()
            end

        end
        
        tab_h = ProjectsTab(true)
        str = tostring(str) or "Oops, I just lost my train of thought..."
        str = " " .. str .. " "
        second = second or 2

        --find computer hi_DPI
        gfx.ext_retina = 1 
        gfx.init("",1,1)
        dpi = gfx.ext_retina
        gfx.quit()

        -- fix 模式用記錄位置；否則用上次 free 位置
        if fix_mode and fix_x and fix_y then
            x = fix_x
            y = fix_y
        else
            x = tonumber(api.load("billboard","gfx.x")) or 0
            y = tonumber(api.load("billboard","gfx.y")) or 0
        end
        gfx.setfont(1,font,28*dpi)

        emoji = (reaper.JS_Window_Find("( ˊ_>ˋ )",true) and "｡ﾟヽ(ﾟ´Д`)ﾉﾟ｡") or "( ˊ_>ˋ )"
        str_w,str_h = gfx.measurestr(str)
        rect_w = (str_w>600  and str_w + 103 ) or 600


        gfx.x = x-(rect_w/dpi/2)
        gfx.y = y

        --main billboard
        gfx.init(emoji, rect_w / dpi, str_h*1.2/dpi, 0, gfx.x, gfx.y )
        gfx.set(9/255,38/255,44/255)
        gfx.gradrect(0,0,gfx.w,gfx.h,9/255,38/255,44/255,1);
        --show text
        gfx.x = rect_w/2-str_w/2
        gfx.y = 6
        gfx.set(251/255,184/255,47/255)
        gfx.drawstr(str)

        -- 右上角 toggle 按鈕
        btn_size = math.floor(20 * dpi)
        btn_x = gfx.w - btn_size - 6
        btn_y = 4
        last_click = false
        DrawToggle()

        gfx.update()
        --keep window open
        Wait(second)
        --focus original window
        reaper.JS_Window_SetFocus(FOCUS)
    end

----------------------------
-----PROJECT FUNCTION-------
----------------------------

    function FUN.CountProjects()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.CountProjects\n')
            end

        local projects = {}
        local p=0
        repeat
            local proj = reaper.EnumProjects(p)
            if  reaper.ValidatePtr(proj,'ReaProject*') then
                projects[#projects + 1] = proj
            end
            p=p+1
        until not proj
        
        return #projects,projects

    end --return #projects,projects
    --------------
    function FUN.GetProjectLength(selected)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetProjectLength\n')
            end

        local min,max, exclude_hide

        min=reaper.GetProjectLength(0)
        max=0
        exclude_hide = false

        for abi=1,api.ct(0) do
            local tr,it_n,it,S,E
            tr=api.gt(0,abi-1)            
            it_n=reaper.CountTrackMediaItems(tr)
            if it_n==0 then goto NEXT end
            
            ::find_start::
            for abii=1,it_n do
                local it=reaper.GetTrackMediaItem(tr,abii-1)
                if  selected and not reaper.IsMediaItemSelected(it) then goto Next end
                if  not exclude_hide or (exclude_hide and  api.giv(it,"B_FIXEDLANE_HIDDEN")==0 and reaper.IsTrackVisible(reaper.GetMediaItemTrack(it),false)) then
                    S=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
                    min=(min>S and S) or min
                    goto find_end
                end
                ::Next::
            end
            
            ::find_end::
            for abii=it_n,1,-1 do
                it=reaper.GetTrackMediaItem(tr,abii-1)
                if  selected and not reaper.IsMediaItemSelected(it) then goto Next end
                if  not exclude_hide or (exclude_hide and api.giv(it,"B_FIXEDLANE_HIDDEN")==0 and reaper.IsTrackVisible(reaper.GetMediaItemTrack(it),false)) then
                    E=api.giv(it,"D_POSITION")+api.giv(it,"D_LENGTH")
                    max=(max<E and E) or max
                    goto NEXT
                end
                ::Next::
            end
            
            ::NEXT::
        end
        
        return min,max
    end --return min,max
    -------------    
    function FUN.GetTCP_Size()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetTCP_Size\n')
            end
        
        local _,main_window,arrange,t,b,arrange_max,tr_min,tr_fold

        tr_fold,tr_min = reaper.NF_GetThemeDefaultTCPHeights()

        tr_min=(Lyx_computer and tr_min*0.75) or tr_min
                
        main_window = reaper.GetMainHwnd()
        arrange = reaper.JS_Window_FindChildByID(main_window,1000)
        _,_,t,_,b=reaper.JS_Window_GetRect(arrange)
        
        arrange_max = math.abs(t-b)-sys.tab_h
        
        return arrange_max,tr_min,tr_fold

    end --return arrange_max,tr_min,tr_fold
    -------------    
    function FUN.GetSetProjectStart(set)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetSetProjectStart\n')
            end

        local Offset=reaper.TimeMap2_beatsToTime(0,12)

        if  set then
            reaper.SNM_SetDoubleConfigVar('projtimeoffs', -Offset)
            reaper.UpdateTimeline()
            reaper.SetEditCurPos(Offset,false,false)
        end
        return Offset

    end
    -------------
    function FUN.AdjustGrid()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.AdjustGrid\n')
            end

        local lock = api.load("Grid",'Grid lock')
        if lock == "1" then return end
        
        ---Thanks FTC's adaptive guid
        local fixed  = '_RSd4c23469a25528b9075743ce7e7baf5e5c9edeaa'
        local medium = '_RS18326a165ec53a69aedced71d97a0f95715a0a8a'
        local wild   = '_RS8156a582bcab3d91af2bb026e78690e99f4464da'
        local narrow = '_RSf612c71a2852e9cc682dbec04707f9e452448d6f'

        local grid = api.name(medium)
        local adaptive_grid = (api.gtc(grid)~=1 and grid) or 0
                
        api.cmd(adaptive_grid,0)
        
        -- local ZoomChart,S,E,QN_S,QN_E,beats,_,grid,swing,swingamt,cmd,triplet

        -- ZoomChart= {--3,  --64th note
        --             12, --32th note
        --             32, --16th note
        --             52, --8th  note
        --             120,--4th  note
        --             208,--2th  note
        --             384,--1bar
        --           }

        -- S,E =reaper.GetSet_ArrangeView2(0,false,0,0,0,0)
        -- QN_S=reaper.TimeMap2_timeToQN(0,S)
        -- QN_E=reaper.TimeMap2_timeToQN(0,E)

        -- cmd=api.name("_SWS_AWTOGGLETRIPLET")
        -- triplet=reaper.GetToggleCommandState(cmd)==1
        
        -- _,grid,swing,swingamt=reaper.GetSetProjectGrid(0,false)

        -- beats=QN_E-QN_S
        
        -- grid=2

        -- if  beats>800 then
        --     local abi=0
        --     while abi<10 do
        --           if  (beats < 800*2^abi) then
        --               grid=2*2^abi
        --               break
        --           end
        --           abi=abi+1
        --     end 
        -- else
        --     for abi=1,#ZoomChart do
        --         if  beats < ZoomChart[abi] then
        --             grid=1/2^((#ZoomChart-abi))
        --             break
        --         end
        --     end
        -- end

        -- grid=(triplet and grid*4/3) or grid
        -- reaper.SetProjectGrid(0,grid,swing,swingamt)

        -- api.ua()
    end
    -------------seperate table
    function FUN.GetRazorEdits(clear,check) 
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetRazorEdits\n')
            end

        local Trz,Itz,Envz,razor,razor_area,Start,End,min,max

        Trz={}
        Itz={}
        Envz={}
        Start={}
        End={}
        
        for abi=1,reaper.CountTracks(0) do
            local track=reaper.GetTrack(0,abi-1)
            local _,area=reaper.GetSetMediaTrackInfo_String(track,"P_RAZOREDITS_EXT","",false)
            
            if  area~='' then
                if  check then return true end
                
                razor = true

                Trz[#Trz+1]=track

                local String={}
                
                for str in area:gmatch('[^,]+')do
                    table.insert(String,str)
                end
                
                razor_area={}
                for abi=1, #String do
                    razor_area={}
                    for j in String[abi]:gmatch("%S+") do
                        table.insert(razor_area,j)
                    end
                    --area data
                    Start[#Start+1]=tonumber(razor_area[1])
                    End[#End+1]=tonumber(razor_area[2])
                    min=((not min or min>Start[#Start]) and Start[#Start]) or min
                    max=((not max or max<End[#End]) and End[#End]) or max
                    local GUID=razor_area[3]
                    local isEnvelope=GUID~='""'
                    --get item/envelope data
                    local envelopeName, envelope,envelopePoints

                    if  not isEnvelope then
                        local function GetItemsInRange(track,areaStart,areaEnd,item_table,all_lanes)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  GetItemsInRange\n')
            end
                            for abi=1,reaper.CountTrackMediaItems(track) do 

                                local item=reaper.GetTrackMediaItem(track,abi-1)
                                if  not all_lanes then
                                    if  reaper.GetMediaItemInfo_Value(item,"B_FIXEDLANE_HIDDEN")==0 then
                                        local Pos=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
                                        local End=Pos+reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
                                        if  FUN.NumberCage(Pos,areaStart,areaEnd)==Pos or FUN.NumberCage(End,areaStart,areaEnd)==End then
                                            table.insert(item_table,item)
                                        end
                                    end
                                end

                            end
                        end
                        GetItemsInRange(track,Start[#Start],End[#End],Itz,false)
                    else
                        local function GetEnvelopePointsInRange(envelopeTrack,areaStart,areaEnd)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  GetEnvelopePointsInRange\n')
            end
                            local envelopePoints={}
                            for abi=1,reaper.CountEnvelopePoints(envelopeTrack) do
                                local _,time,value,shape,tension,selected=reaper.GetEnvelopePoint(envelopeTrack,abi-1)
                                if time>=areaStart and time<=areaEnd then
                                    envelopePoints[#envelopePoints + 1]={
                                        idx=abi-1 ,
                                        time=time,
                                        value=value,
                                        shape=shape,
                                        tension=tension,
                                        selected=selected
                                    }
                                end
                            end
                            return envelopePoints
                        end
                        envelope=reaper.GetTrackEnvelopeByChunkName(track,GUID:sub(2,-2))
                        _,envelopeName=reaper.GetEnvelopeName(envelope)
                        envelopePoints=GetEnvelopePointsInRange(envelope,Start[#Start],End[#End])
                        Envz[#Envz+1]={env=envelope,name=envelopeName,point=envelopePoints,guid=GUID}
                    end
                end
            end
        end
        if clear then api.cmd(42406,0) end--clear all razor
        local areaMap={track=Trz,item=Itz,envelope=Envz,left_edge=Start,right_edge=End,min=min,max=max}
        return razor,areaMap
    end --return israzor,areaMap{Trz={},Itz={},Envz={},Start={},End={},min,max}
    --------------in one table
    function FUN.GetRazorEdits2(clear,check)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetRazorEdits2\n')
            end

        local trackCount = reaper.CountTracks(0)
        local areaMap = {}
        local min,max

        for i = 0, trackCount - 1 do
            --msg('I\'m track'..i)
            local track = reaper.GetTrack(0, i)
            local _,area=reaper.GetSetMediaTrackInfo_String(track,"P_RAZOREDITS_EXT","",false)
            
            if  area~='' then
                if  check then return true  end

                local String={}
                
                count = 0
                for str in area:gmatch('[^,]+')do
                    --msg('I\'m count'..count)
                    count = count + 1
                    table.insert(String,str)
                end
                
                --FILL AREA DATA
                for abi=1, #String do

                    --msg('I\'m abi'..abi)
                    local razor_area,Start,End,GUID,isEnvelope,items,envelope,envelopeName,envelopePoints
                    
                    razor_area = {}
                    for j in String[abi]:gmatch("%S+") do
                        --msg('I\'m j'..j)
                        table.insert(razor_area,j)
                    end
                    --area data
                    Start = tonumber(razor_area[1])
                    End = tonumber(razor_area[2])
                    min=((not min or min>Start) and Start) or min
                    max=((not max or max<End ) and End) or max
                    GUID = razor_area[3]
                    isEnvelope = GUID ~= '""'

                    --get item/envelope data                   
                    if  not isEnvelope then
                        local function GetItemsInRange(track,areaStart,areaEnd)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  GetItemsInRange\n')
            end
                            local items = {}
                            for abi=1,reaper.CountTrackMediaItems(track) do 
                                local item=reaper.GetTrackMediaItem(track,abi-1)
                                if  reaper.GetMediaItemInfo_Value(item,"B_FIXEDLANE_HIDDEN")==0 then
                                    local Pos=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
                                    local End=Pos+reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
                                    if  FUN.NumberCage(Pos,areaStart,areaEnd)==Pos or FUN.NumberCage(End,areaStart,areaEnd)==End then
                                        table.insert(items,item)
                                    end
                                end
                            end
                            return items
                        end
                        items = GetItemsInRange(track,Start,End,items,false)
                    else
                        local function GetEnvelopePointsInRange(envelopeTrack,areaStart,areaEnd)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  GetEnvelopePointsInRange\n')
            end
                            local envelopePoints={}
                            for abi=1,reaper.CountEnvelopePoints(envelopeTrack) do
                                local _,time,value,shape,tension,selected=reaper.GetEnvelopePoint(envelopeTrack,abi-1)
                                if time>=areaStart and time<=areaEnd then
                                    envelopePoints[#envelopePoints + 1]={
                                        idx=abi-1 ,
                                        time=time,
                                        value=value,
                                        shape=shape,
                                        tension=tension,
                                        selected=selected
                                    }
                                end
                            end
                            return envelopePoints
                        end
                        envelope=reaper.GetTrackEnvelopeByChunkName(track,GUID:sub(2,-2))
                        _,envelopeName=reaper.GetEnvelopeName(envelope)
                        envelopePoints=GetEnvelopePointsInRange(envelope,Start,End)--idx=abi-1, time=time, value=value, shape=shape, tension=tension, selected=selected
                    end

                    areaMap[#areaMap+1]={
                                        areaStart = Start,
                                        areaEnd = End,
                                        
                                        track = track,
                                        items = items,
                                        
                                        --envelope data
                                        isEnvelope = isEnvelope,
                                        envelope = envelope,
                                        envelopeName = envelopeName,
                                        envelopePoints = envelopePoints,
                                        GUID = GUID:sub(2, -2)
                        }
                end
            end

        end
        areaMap.min = min
        areaMap.max = max

        if clear then api.cmd(42406,0) end--clear all razor

        return #areaMap>0, areaMap
    end --return IsRazor,areaMap={areaStart,areaEnd,track,items,isEnvelope,envelope,envelopeName,envelopePoints,GUID}
    --------------
    function FUN.SetBufferSize(BufferSize)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SetBufferSize\n')
            end
        
        local cmd,Cmd,buffer
                    
        local _,current_size = reaper.GetAudioDeviceInfo('BSIZE')

        if  current_size == tostring(BufferSize) then return end

        buffer = (BufferSize and BufferSize) or 256

        Cmd = {
                    ['64']   = "_RSbcc69ced35229feaa2b5a1b73638e06b5e19d723",
                    ['128']  = "_RS5db737d4f3ee480349dd5a083598f9b00632f5bc",
                    ['256']  = "_RS29926750f3de52111bc6f90b3d2efc1cd5b0f686",
                    ['512']  = "_RSea61a03b390bc2b1bd6f613d35bd91c7107cb2fa",
                    ['1024'] = "_RS84cd6d5120685c9c5bad735b576b605ba0dafafd",
                    ['2048'] = "_RSd282aac18c6d35638bbf636946bdda131a56ab46",
                    }

        
        cmd = reaper.NamedCommandLookup(Cmd[tostring(buffer)])
        reaper.Main_OnCommand(cmd,0)
        
    end

    function FUN.TimeSelection(ts_start, ts_end)

        local loop = reaper.GetToggleCommandState(1068) == 1

        if ts_start == 'loop' then
            api.cmd(1168, 0)
        elseif ts_start == 'get' then
            s, e = reaper.GetSet_LoopTimeRange2(0, false, loop, 0, 0,false)
            return s, e
        elseif not ts_start or not ts_end then
            reaper.GetSet_LoopTimeRange2(0, true, loop, 0, 0,false)
        else
            reaper.GetSet_LoopTimeRange2(0, true, loop, ts_start, ts_end,false)
        end

    end

    function FUN.cmd(cmd,editor)

        local command = (type(cmd) == 'string' and api.name(cmd)) or cmd

        if editor == 'midi' or editor == true then 
            api.Mcmd(api.M(), command)
        else
            api.cmd(command,0)
        end
        
    end

----------------------------
------TRACK FUNCTION--------
----------------------------

    -------------
    function FUN.SaveTracks(mode)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SaveTracks\n')
            end
         
        if  mode == true then
            api.cmd(api.name("_SWS_SAVESEL"),0)
            return {}
        elseif type(mode) == 'string' then
            tb={}
            for abi = 1, reaper.CountSelectedTracks(0) do
                local tr = reaper.GetSelectedTrack(0, abi-1)
                guid = api.tid(tr)
                tb[#tb+1] = guid
            end
            local tracks = serialize(tb)
            api.save('SaveTracks',mode,tracks,false)
        end

        local tb={}
        for i = 1, reaper.CountSelectedTracks(0) do
            tb[i] = reaper.GetSelectedTrack(0, i-1)
        end

        return tb
    end --return table
    -------------
    function FUN.RestoreTracks(tracks,only)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.RestoreTracks\n')
            end

        if  type(tracks)=="boolean" and tracks==true then 
            api.cmd(api.name("_SWS_RESTORESEL"),0)
            return
        elseif type(tracks)=='string' then
            
            local data = api.load('SaveTracks',tracks)
            if not data or data == '' then return end
            
            GUID = unserialize(data)
            
            if  type(GUID)~='table' then return end

            tracks = {}
            for abi=1,#GUID do
                tr = api.idt(0,GUID[abi])
                if  api.check(0,tr,"MediaTrack*") then
                    tracks[#tracks+1] = tr
                end
            end
            -- api.cmd(40297,0)
            -- reaper.SetOnlyTrackSelected(tracks[#tracks])
            -- for abi=1,#tracks do
            --     reaper.SetTrackSelected(tracks[abi],true)
            -- end
        end

        
        if type(tracks)=="table" then
            reaper.Main_OnCommand(40297,0)
            if  reaper.ValidatePtr2(0,tracks[#tracks],"MediaTrack*") and not only then
                reaper.SetOnlyTrackSelected(tracks[#tracks])
            end
            for i=1,#tracks do
                if  reaper.ValidatePtr2(0,tracks[i],"MediaTrack*") then
                    reaper.SetTrackSelected(tracks[i],true)
                end
            end

        end
    end
    --------------
    function FUN.GetRecTrack(only_check,save)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetRecTrack\n')
            end
        
        FUN.SaveTracks(true)
        api.cmd(api.name('_SWS_SELRECARM'),0)--select only arm tracks
        local rec_tracks = {}
        if  only_check then
            if  api.cst(0) > 0 then
                rec_tracks = true
            else
                FUN.RestoreTracks(true)
                return false
            end
        else
            rec_tracks = {}
            for abi=1,api.cst(0) do
                rec_tracks[#rec_tracks+1] = api.gst(0,abi-1)
            end
            if  save then FUN.SaveTracks('rec_tracks') end
        end
        
        FUN.RestoreTracks(true)
        return rec_tracks
    end
    -------------
    function FUN.SameTCPH(tr,target,KeepTr)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SameTCPH\n')
            end
        
        local tcph,height,Step,step,trz

        if  KeepTr then
            trz={}
            for abi=1,reaper.CountSelectedTracks(0) do
                trz[abi]=reaper.GetSelectedTrack(0,abi-1)
            end--]]
        end

        if  reaper.ValidatePtr2(0,target,"MediaTrack*") then
            target=reaper.GetMediaTrackInfo_Value(target,"I_TCPH")
        elseif type(target)~="number" then
            return
        end
            
        if  type(tr)=="table" then
            if  #tr==0 then return end 
            api.cmd(40297,0)--unselect all track
            for abi=1,#tr do
                if  reaper.ValidatePtr2(0,tr[abi],"MediaTrack*") then 
                    reaper.SetTrackSelected(tr[abi],true)
                end
            end
            cmd=reaper.NamedCommandLookup("_SWS_MINTRACKS")
            reaper.Main_OnCommand(cmd,0)
            tcph=api.gtv(api.gst(0,0),"I_TCPH")
        else
            if not reaper.ValidatePtr2(0,tr,"MediaTrack*") then return end
            reaper.SetOnlyTrackSelected(tr)
            tcph=reaper.GetMediaTrackInfo_Value(tr,"I_TCPH")
        end
        
        height=target-tcph

        Step=(height>0 and 41325) or 41326
        step=(height>0 and 41327) or 41328
        
        local times=math.abs(height/2)
        
        local bug=((Lyx_computer and 0 ) or 1) 

        for abi=1,times/4+bug do
            reaper.Main_OnCommand(Step,0)
        end

        for abi=1,times%4 do
            reaper.Main_OnCommand(step,0)
        end

        ::END::

        if  KeepTr then
            reaper.Main_OnCommand(40297,0)--unselect all track
            for abi=1,#trz do
                reaper.SetTrackSelected(trz[abi],true)
            end
        end
    end
    -------------
    function FUN.HaveParent(tr, Bigmom, select)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.HaveParent\n')
            end
        
        if not tr then return end
        
        local parent
        
        ::begin::

        local leader=reaper.GetParentTrack(tr)
        
        if  leader then
            parent=leader
            if select then api.sts(leader, true) end
            if  Bigmom then
                tr=leader
                goto begin
            end
        end

        return parent
    
    end --return parent
    -------------
    function FUN.FolderStructure(translate)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.FolderStructure\n')
            end

        local stack=0
        local tbl={}
        local min=math.huge

        for abi=1,api.ct(0) do
            local tr=api.gt(0,abi-1)
            local depth=api.gtv(tr,"I_FOLDERDEPTH")
            tbl[#tbl+1]=math.floor(stack)
            stack=stack-depth
            if  min>stack then
                min=stack
            end
        end

        if  translate then
            for abi=1,#tbl do
                tbl[abi]=math.abs(tbl[abi])
                tbl[abi]=tbl[abi]+1
            end
            min=math.abs(min)+1
        end

        return tbl,min
    end
    -------------
    function FUN.SelTrackFilter()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SelTrackFilter\n')
            end

        local skip_collapsed = true

        for abi=api.cst(0),1,-1 do
            local tr = api.gst(0,abi-1)
            --local parent = FUN.HaveParent(tr)
            visible = reaper.IsTrackVisible(tr,false)
            if  not visible then 
                api.sts(tr,false)
            end
        end
    end
    -------------
    function FUN.ShowHideTrackLaneNames(state,check)
        
        if state == "Show" or state == "Hide" then goto Start end

        state = "Show"

        for abi=1,api.ct(0) do
            
            local _, tr, lane_n, tr_name
            
            tr=api.gt(0,abi-1)
            lane_n=api.gtv(tr,"I_NUMFIXEDLANES")
            _,tr_name = api.ts(tr,"P_NAME","",false)

            if lane_n > 1 and tr_name:match("%[ .* %]") then 
                state = "Hide"
                break
            end

        end
        
        if  check then goto END end

        ::Start::
        
        for abi = 1, api.ct(0) do
        
            local _, tr, lane_n, tr_name, lane_name, new_name, current_lane, new_lane
        
            tr = api.gt(0,abi-1)
            lane_n = api.gtv(tr,"I_NUMFIXEDLANES")
            _, tr_name = api.ts(tr,"P_NAME","",false)
            
            new_name = tr_name:gsub("(   %[ .* %])","")
            
            if state == "Show" and lane_n > 1 then
                
                for abig=1,lane_n do    
                    if  api.gtv(tr,"C_LANEPLAYS:"..(abig-1)) == 1 then
                        
                        current_lane = abig-1
                        _,lane_name = api.ts(tr,"P_LANENAME:"..current_lane,"",false)
                        new_name = tr_name .. '   [ ' .. lane_name .. ' ]'

                    end
                end

            elseif state == "Hide" then
                    
                --PASS

            end

            api.ts(tr,"P_NAME",new_name,true)
            
        end

        ::END::

        return (state == "Show" and 0) or 1

    end

    function FUN.ImportTrackTemplate(slot, timebase)
        
        local tr,new_tr,folder

        tr=api.gst(0,0) or api.gt(0,0)

        api.cmd(api.name("_S&M_ADD_TRTEMPLATE"..slot),0)
        
        new_tr=api.gst(0,0)

        folder = ( tr and api.gtv(tr,"I_FOLDERDEPTH")) or 0
            
        if  folder < 0 then
            api.stv(tr,"I_FOLDERDEPTH",0)
            api.stv(new_tr,"I_FOLDERDEPTH",folder)
        end

        FUN.cmd((timebase == 'time' and '_SWS_AWTRACKTBASETIME') or '_SWS_AWTRACKTBASEBEATPOS',0)
        FUN.SameTCPH(new_tr,tr)
            
    end

----------------------------
-------ITEM FUNCTION--------
----------------------------

    function FUN.SaveItems(eco,include_hidden)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SaveItems\n')
            end
        local table={}
        if  eco then
            api.cmd(api.name('_SWS_SAVEALLSELITEMS1'),0)
            return
        end
        for i = 0, reaper.CountSelectedMediaItems(0)-1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            if  not include_hidden or ( include_hidden and reaper.GetMediaItemInfo_Value(item,"B_FIXEDLANE_HIDDEN") == 0 ) then
                table[#table+1] = item
            end
        end
        return table
    end --return table
    -------------
    function FUN.RestoreItems(mode,keep_razor)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.RestoreItems\n')
            end
        
        local razorMap = {}

        if  keep_razor then
            for abi = 1,api.ct(0) do
                local _,data = api.ts(api.gt(0,abi-1),"P_RAZOREDITS_EXT","",false)
                razorMap[abi] = data
            end
        else
            reaper.Main_OnCommand(40289,0) 
        end

        if  type(mode) == 'boolean' then
            api.cmd(api.name('_SWS_RESTALLSELITEMS1'),0)
            return
        elseif type(mode)=='table' then
            for _, item in ipairs(table) do
                if  reaper.ValidatePtr2(0,item,"MediaItem*") then
                    reaper.SetMediaItemSelected(item, true)
                end
            end
        end

        if  keep_razor then
            for abi = 1,api.ct(0) do
                api.ts(api.gt(0,abi-1),"P_RAZOREDITS_EXT",razorMap[abi],true)
                api.ua()
            end
        end
        
        reaper.UpdateArrange()
    end

    -------------
    function FUN.IsItemVisible(item)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.IsItemVisible\n')
            end

        if  api.check(0,item,'MediaItem*') then
            return reaper.GetMediaItemInfo_Value(item,"B_FIXEDLANE_HIDDEN")==0
        end

    end

    -------------
    function FUN.GetItemName(item)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetItemName\n')
            end

        local name = ''

        if  type(item) == 'table' then
            name = {}
            for abi=1,#items do
                local item = item[abi]
                if  reaper.ValidatePtr2(0,item,'MediaItem*') then
                    local take = api.gat(item)
                    local name = (take and api.gtkn(take)) or ''
                    name[#name+1]= name
                end
            end
        elseif  reaper.ValidatePtr2(0,item,'MediaItem*') then
            local take = api.gat(item)
            name = (take and api.gtkn(take)) or ''
        end

        return name
    end
    -------------
    function FUN.SelItemFilter()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SelItemFilter\n')
            end

        local OUT
        
        OUT = {}
        
        for abi=1,api.csi(0) do
            local item = api.gsi(0,abi-1)
            tr = api.git(item)
            local parent = FUN.HaveParent(tr)
            tr_visible = reaper.IsTrackVisible(tr,false) and not (parent and api.gtv(parent,"I_FOLDERCOMPACT")==2)
            it_visible = api.giv(item,'B_FIXEDLANE_HIDDEN') == 0            
            if  not tr_visible or not it_visible then OUT[#OUT+1] = item end
        end

        for abi=1,#OUT do
            api.sis(OUT[abi],false)
        end

        api.ua()
    end
    -------------
    function FUN.GetItemsInRange(track,areaStart,areaEnd)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetItemsInRange\n')
            end
        local items={}
        for abi=1,reaper.CountTrackMediaItems(track) do 
            local item=reaper.GetTrackMediaItem(track,abi-1)
            if  reaper.GetMediaItemInfo_Value(item,"B_FIXEDLANE_HIDDEN")==1 then goto Next end
            local Pos=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
            local End=Pos+reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
            if  (math.min(areaStart,Pos)==areaStart and math.max(Pos,areaEnd)==areaEnd) or
                (math.min(areaStart,End)==areaStart and math.max(End,areaEnd)==areaEnd) then
                table.insert(items,item)
            end
            ::Next::
        end
        return items
    end
    -------------
    function FUN.NudgeTrackItems(track,dis)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.NudgeTrackItems\n')
            end

        for abi=1,reaper.CountTrackMediaItems(track) do
            local item=reaper.GetTrackMediaItem(track,abi-1)
            local position=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
            reaper.SetMediaItemInfo_Value(item,"D_POSITION",position+dis)
        end
    
    end  
    -------------
    function FUN.GetSetColor(title,Set)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetSetColor\n')
            end
        
        local GUID,COLOR,default,item,take,color
        
        title = title or ""
        
        if  Set then

            GUID =reaper.GetExtState("ITEMS_COLOR - "..title.."guid" ,pro_name)  
            COLOR=reaper.GetExtState("ITEMS_COLOR - "..title.."color",pro_name)  
            
            GUID =unserialize(GUID)
            COLOR=unserialize(COLOR)
            
            itemz={}
            
            for abi=1,#GUID do
                item = reaper.BR_GetMediaItemByGUID(0,GUID[abi])
                if  api.check(0,item,'MediaItem*') then
                    take = reaper.GetActiveTake(item)
                    default = ((take and reaper.TakeIsMIDI(take)) and 18313493 ) or 18696831
                    color=COLOR[abi] or default
                    reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",color)
                end
                ::NEXT::
            end

            reaper.UpdateArrange()

        else  

            COLOR={}
            GUID={}
                            
            for abi=1,reaper.CountMediaItems(0) do
                local item=reaper.GetMediaItem(0,abi-1)
                _,GUID[abi]=reaper.GetSetMediaItemInfo_String(item,"GUID","",false)
                COLOR[abi]=reaper.GetMediaItemInfo_Value(item,"I_CUSTOMCOLOR")
            end
            
            GUID=serialize(GUID)
            COLOR=serialize(COLOR)
            
            reaper.SetExtState("ITEMS_COLOR - "..title.."guid",pro_name,GUID,false)  
            reaper.SetExtState("ITEMS_COLOR - "..title.."color",pro_name,COLOR,false)  

        end

    end
    -------------
    function FUN.isMIDI(item)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.isMIDI\n')
            end
        
        local midi
        
        if  item then 
            local take = reaper.GetActiveTake(item)
            if take and reaper.TakeIsMIDI(take) then
                midi = true
            end
        end

        return midi

    end --return boolean



----------------------------
-----ENVELOPE FUNCTION------
----------------------------

    function FUN.GetEnvelopePointsInRange(envelope, areaStart, areaEnd,WantSelect)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetEnvelopePointsInRange\n')
            end
        local envelopePoints={}
        local selected_point
        areaStart = areaStart or 0
        areaEnd = areaEnd or math.huge
        for abi=1,reaper.CountEnvelopePoints(envelope) do
            local _,time,value,shape,tension,selected=reaper.GetEnvelopePoint(envelope,abi-1)
            if  time>=areaStart and time<=areaEnd then
                if  WantSelect and selected then
                    envelopePoints[#envelopePoints + 1]={
                        id=abi-1 ,
                        time=time,
                        value=value,
                        shape=shape,
                        tension=tension,
                        selected=selected
                    }
                elseif not WantSelect then
                    envelopePoints[#envelopePoints + 1]={
                      id=abi-1 ,
                      time=time,
                      value=value,
                      shape=shape,
                      tension=tension,
                      selected=selected
                    }
                end
                ::NEXT::
            end
        end
        return envelopePoints,selected_point
    end
    -------------
    function FUN.GetEvlopePointValue(env,point_time)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetEvlopePointValue\n')
            end

        -- GET THE ENVELOPE
        br_env=reaper.BR_EnvAlloc(env,false)
        active,visible,armed=reaper.BR_EnvGetProperties(br_env,true,true,true,true,0,0,0,0,0,0,true)
        if  visible and armed then
            env_points_count=reaper.CountEnvelopePoints(env)
            if  env_points_count>0 then
                for k=0,env_points_count+1 do 
                    reaper.SetEnvelopePoint(env,k,nil,nil,nil,nil,false,true)
                end
            end
        
            -- IF THERE IS PREVIOUS POINT
            old_point=reaper.GetEnvelopePointByTime(env,point_time)
            if  old_point~=-1 then
                _,valueout,_,_,_= reaper.Envelope_Evaluate(env,point_time,0,0)
            end
        end
        reaper.BR_EnvFree(br_env,0)
        if  not valueout then
            valueout=FUN.dB_Value(0)
        end
        return valueout

    end
    -------------
    function FUN.CheckEnvelopePoolTrack()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.CheckEnvelopePoolTrack\n')
            end
        
        local env_tr,vol_env

        for abi=reaper.CountTracks(0),1,-1 do
            local tr=reaper.GetTrack(0,abi-1)
            local _,name=reaper.GetTrackName(tr)
            if  name=="###Envelope Pool###" then 
                env_tr=tr
                break
            end
        end

        if  not env_tr then
            reaper.InsertTrackAtIndex(reaper.CountTracks(0),false)
            env_tr=reaper.GetTrack(0,reaper.CountTracks(0)-1)
            reaper.GetSetMediaTrackInfo_String(env_tr,"P_NAME","###Envelope Pool###",true)
        end
        
        reaper.SetOnlyTrackSelected(env_tr)
        reaper.ReorderSelectedTracks(reaper.CountTracks(0)+1,0)

        vol_env=reaper.GetTrackEnvelopeByName(env_tr,"Volume")
        if  not vol_env then
            local default_chunk,track_chunk,GUID,env_chunk
            default_chunk="<VOLENV2\nEGUID {abigel}\nACT 1 -1\nVIS 0 1 1\nLANEHEIGHT 0 0\nARM 1DEFSHAPE 0 -1 -1\nVOLTYPE 1\nPT 0 1 0\n>\n"
            _,track_chunk=reaper.GetTrackStateChunk(env_tr,"",false)
            GUID=reaper.genGuid()
            env_chunk=default_chunk:gsub("abigel",GUID)
            track_chunk=track_chunk:gsub("(MAINSEND %d %d\n)","%1"..env_chunk)
            reaper.SetTrackStateChunk(env_tr,track_chunk,false)
            vol_env=reaper.GetTrackEnvelopeByName(env_tr,"Volume")
        end 
        reaper.SetMediaTrackInfo_Value(env_tr,"B_SHOWINTCP",0)
        return env_tr,vol_env

    end
    -------------
    function FUN.AddPoint(env,time,valueout,shape,tension)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.AddPoint\n')
            end

        if  not valueout then
            old_point=reaper.GetEnvelopePointByTime(env,time-0.0001)
            if  old_point~=-1 then
                _,valueout,_,_,_= reaper.Envelope_Evaluate(env,time-0.0001,0,0)
            end
        end

        if  not shape then shape=3 end
        if  not tension then tension=0 end

        reaper.InsertEnvelopePoint(env,time,valueout,shape,tension,false,false)

    end
    -------------
    function FUN.SetVolEnvVis(tr,see,inlane)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SetVolEnvVis\n')
            end

        local default_chunk="<VOLENV2\nEGUID {abigel}\nACT 1 -1\nVIS 0 1 1\nLANEHEIGHT 0 0\nARM 1DEFSHAPE 0 -1 -1\nVOLTYPE 1\nPT 0 1 0\n>\n"
        local vis,env_chunk,new_chunk,track_chunk,GUID
        
        vis="VIS 0 1 1"
        if see and inlane then vis="VIS 1 1 1"
        elseif see then vis="VIS 1 0 1"
        end
        
        local vol_env=reaper.GetTrackEnvelopeByName(tr,"Volume")
        if  vol_env then
            _,env_chunk=reaper.GetEnvelopeStateChunk(vol_env,"",false)
            new_chunk=env_chunk:gsub("VIS %d %d %d",vis)
            reaper.SetEnvelopeStateChunk(vol_env,new_chunk,false)
        else
            _,track_chunk=reaper.GetTrackStateChunk(tr,"",false)
            GUID=reaper.genGuid()
            env_chunk=default_chunk:gsub("abigel",GUID):gsub("VIS %d %d %d",vis)
            track_chunk=track_chunk:gsub("(MAINSEND %d %d\n)","%1"..env_chunk)
            reaper.SetTrackStateChunk(tr,track_chunk,false)
            vol_env=reaper.GetTrackEnvelopeByName(tr,"Volume")
        end
        return vol_env

    end
    -------------
    function FUN.SwitchEnvFilledMode(toggle)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SwitchEnvFilledMode\n')
            end

        local setting=reaper.SNM_GetIntConfigVar("envlanes",-1)
        if  toggle==1 then
            setting=setting|32
        elseif toggle==0 then
            setting=setting&~32
        else
            setting=setting~32
        end
        reaper.SNM_SetIntConfigVar("envlanes",setting)
        reaper.UpdateArrange()
        
    end
    -------------
    function FUN.CheckEnvVisible()
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.CheckEnvVisible\n')
            end

        for sel_tr = 1, reaper.CountTracks(0) do
            local track=reaper.GetTrack(0,sel_tr-1)
            if  api.check(0,track,'MediaTrack*') then 
                for i = 1,reaper.CountTrackEnvelopes( track ) do
                    local _,env,chunk
                    env = reaper.GetTrackEnvelope( track, i-1 )
                    _,chunk = api.geC(env,'',false)                    
                    if  chunk:find('VIS 1') then
                        return true
                    end
                end
            end
        end 

        return false
    end

----------------------------
----AUTOMATION FUNCTION-----
----------------------------

    function FUN.SearchSameAI(ENV,AI_id,want)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SearchSameAI\n')
            end

        local tr,env,NAME,FindList
        FindList={"idx","pool_id"}
        NAME=reaper.GetEnvelopeName(ENV)

        AI={Name={},idx={}}
        for abi=1,reaper.CountTracks(0) do
            tr=reaper.GetTrack(0,abi-1)
            for abii=1,reaper.CountTrackEnvelopes(tr) do
                env=reaper.GetTrackEnvelope(tr,abii-1)
                for abiii=0,reaper.CountAutomationItems(env) do
                    if  abiii<reaper.CountAutomationItems(env) and reaper.GetSetAutomationItemInfo(env,abiii,"D_UISEL",0,false)==1 then
                        local _,name=reaper.GetEnvelopeName(env)
                        table.insert(AI.Name,name)
                        table.insert(AI.Pool,reaper.GetSetAutomationItemInfo(env,abiii,"D_POOL_ID",0,false))
                    end
                end
            end
        end
        return AI,false

    end
    -------------
    function FUN.OrderAI(env)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.OrderAI\n')
            end
        
        if  env then
            local room,LEN,AI_n,AIz
            room=reaper.GetProjectLength(0)
            AI_n=reaper.CountAutomationItems(env)
            AIz={}
            
            for abi=1,AI_n do
                local pool_id=reaper.GetSetAutomationItemInfo(env,abi-1,"D_POOL_ID",0,false)
                table.insert(AIz,{index=abi-1,pool_id=pool_id})
            end
            
            table.sort(AIz,function(a,b) return a.pool_id<b.pool_id end)

            for _,ai in ipairs(AIz) do
                local idx=ai.index
                LEN=reaper.GetSetAutomationItemInfo(env,idx,"D_LENGTH"  ,0,false) 
                reaper.GetSetAutomationItemInfo(env,idx,"D_POSITION",room+LEN*0.1,true)
                room=room+(LEN*1.2)
            end
        end

    end  
    -------------
    function FUN.GetSetAIinfo(env,ai_idx,pool_id,pos,len,ptx,sel,isSet,reset)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetSetAIinfo\n')
            end
            
        if not env then return end

        local PTX,ai_n

        ai_n=reaper.CountAutomationItems(env)

        if  isSet then
            local shape,tension
            ai_idx=ai_idx or -1
            if  ai_idx>=ai_n then 
                pool_id=((type(pool_id)=="number" and pool_id>=0) and pool_id) or -1
                reaper.InsertAutomationItem(env,pool_id,pos,len)
                ai_idx=ai_n
            elseif ai_idx<0 then
                ai_idx=-1 goto ADD_POINT
            end

            if  reset then
                reaper.DeleteEnvelopePointRangeEx(env,ai_idx,pos,pos+len)       
            end
            
            --set automation item data
            if   type(pool_id)=="number" and pool_id>=0 then 
                reaper.GetSetAutomationItemInfo(env,ai_idx,"D_POOL_ID",pool_id,true)
            end
            if   type(pos)=="number" and pos>=0 then 
                reaper.GetSetAutomationItemInfo(env,ai_idx,"D_POSITION",pos,true) 
            end
            if   type(len)=="number" and len>pos then
                reaper.GetSetAutomationItemInfo(env,ai_idx,"D_LENGTH",len,true) 
            end
            if  type(sel)=="boolean" then
                sel = sel and 1 or 0
                reaper.GetSetAutomationItemInfo(env,ai_idx,"D_UISEL",sel,true) 
            end

            ::ADD_POINT::
            
            if type(ptx)=='table' and #ptx > 0 then
                
                for abi=1,#ptx do
                    if  not ptx[abi].time or not ptx[abi].value then goto NEXT end
                    shape=ptx[abi].shape or 0
                    tension=ptx[abi].tension or 0
                    reaper.InsertEnvelopePointEx(env,ai_idx,ptx[abi].time,ptx[abi].value,shape,tension,false,true)
                    ::NEXT::
                end
                reaper.Envelope_SortPointsEx(env,ai_idx)

            end
        else
            if not ai_idx or ai_idx<0 or ai_idx>=ai_n then return end

            local time,value,shape,tension,POS,LEN,POOL_ID,SEL

            PTX={}
            POS=reaper.GetSetAutomationItemInfo(env,ai_idx,"D_POSITION",0,false)
            LEN=reaper.GetSetAutomationItemInfo(env,ai_idx,"D_LENGTH",0,false)
            POOL_ID=reaper.GetSetAutomationItemInfo(env,ai_idx,"D_POOL_ID",0,false)
            SEL=reaper.GetSetAutomationItemInfo(env,ai_idx,"D_UISEL",0,false)==1

            for abi=1,reaper.CountEnvelopePointsEx(env,ai_idx) do
                _,time,value,shape,tension=reaper.GetEnvelopePointEx(env,ai_idx,abi-1)
                PTX[abi]={time=time,value=value,shape=shape,tension=tension}
            end 

            return POOL_ID, POS, LEN, PTX, SEL
        end
    end -- POOL_ID, POS, LEN, PTX, SEL
    -------------
    function FUN.GetAI_EXT(tr,env)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetAI_EXT\n')
            end
        local _,tr_GUID=reaper.GetSetMediaTrackInfo_String(tr,"GUID","",false)
        local _,env_GUID=reaper.GetSetEnvelopeInfo_String(env,"GUID","",false)
        local AI_GUID="Realive|"..tr_GUID:sub(2,4)..env_GUID:sub(2,4)
        return AI_GUID
    end  
    -------------
    function FUN.CheckEnvelopeSelection(trz)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.CheckEnvelopeSelection\n')
            end
        
        local _,tr,env,time,selected,SEL,AI,POINT

        SEL={}
        AI,POINT={},{}

        trz=((trz and type(trz)=="table" and #trz>0) and trz) or {}
        if #trz==0 then
            for abi=1,reaper.CountTracks(0) do
                trz[abi]=reaper.GetTrack(0,abi-1)
            end 
        end

        for abi=1,#trz do
            tr=trz[abi]
            if  FUN.UserDataType(tr):match("Track*") then
                for abii=1,reaper.CountTrackEnvelopes(tr) do
                    env=reaper.GetTrackEnvelope(tr,abii-1)
                    for abiii=1,reaper.CountEnvelopePoints(env) do--under lying envelope
                        _,time,_,_,_,selected=reaper.GetEnvelopePoint(env,abiii-1)
                        if  time>0 and selected then 
                            POINT[#POINT+1]={tr=tr,env=env,point=abiii-1}
                        end
                    end
                    for abiii=1,reaper.CountAutomationItems(env) do--automation item
                        for abiiii=1,reaper.CountEnvelopePointsEx(env,abiii-1) do
                            _,_,_,_,_,selected=reaper.GetEnvelopePointEx(env,abiii-1,abiiii-1)
                            if  selected then 
                                POINT[#POINT+1]={tr=tr,env=env,ai=-1}
                            end
                        end
                        if reaper.GetSetAutomationItemInfo(env,abiii-1,"D_UISEL",0,false)==1 then
                        AI[#AI+1]={tr=tr,env=env,ai=abiii-1}
                        end
                    end
                end
            end
        end
        SEL=(#POINT>0 and {Type="Point",POINT}) or (#AI>0 and {Type="AI",AI}) or {Type=nil}
        return SEL
    end
    ----------------------------
    function FUN.GetAutomationItems(source)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetAutomationItems\n')
            end
        
        local tracks
        
        AIs,Envs = {},{}
        
        local function CollectEnv(tr)
            for abi = 1, api.cte(tr) do
                Envs[#Envs+1] = api.gte(tr,abi-1)
            end
        end

        if  api.check(0,source,"TrackEnvelope*") then
            Envs = {source} 
        elseif  api.check(0,source,'MediaTrack*') then
            CollectEnv(source)
        elseif type(source) == 'table' then
            for  _,value in pairs(source) do
                if  api.check(0,value,'MediaTrack*') then
                    CollectEnv(value)
                elseif api.check(0,value,"TrackEnvelope*") then
                    Envs[#Envs+1] = value
                end
            end
        else
            return
        end
        
        if #Envs == 0 then return {} end
        
        for abi = 1, #Envs do
            local env,ai_n,env_name
            env = Envs[abi]
            ai_n = api.cai(env)
            env_name = api.gen(env)
            for abii = 1, ai_n do
                local p_id, selected
                p_id = reaper.GetSetAutomationItemInfo(env,abii-1,"D_POOL_ID",0,false)
                selected = reaper.GetSetAutomationItemInfo(env,abii-1,"D_UISEL",0,false) ~= 0
                AIs[#AIs+1] = {env = env, name = env_name, idx = abii-1, p_idx = p_id, selected = selected}
            end
        end

        return AIs,false

    end --{env, name, idx, p_id, selected}

----------------------------
------TOOLS FUNCTION--------
----------------------------

    function FUN.SelectMachine(Type,select,target)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SelectMachine\n')
            end
            
        local cmd,_,tr,env

        select=((select==true or select==1 ) and 1) or 0
        target=((type(target)=="table" and #target.env>0) and target) or {env={},ai={}}

        if  Type==0 then--unselect ALL
            reaper.Main_OnCommand(40297,0)--unselect all tracks
            reaper.Main_OnCommand(40289,0)--unselect all items
            FUN.SelectMachine(3)
            FUN.SelectMachine(4)
            FUN.SelectMachine(5)
        elseif  Type==1 or tostring(Type):match("tr")  then--tracks
            if  #target>0 then
                for abi=1,#target do
                    if  FUN.UserDataType(target[abi]):match("Track*") then
                        reaper.SetTrackSelected(target[abi],select==1)
                    end
                end
            else 
                cmd=(select==1 and 40296) or 40297
                reaper.Main_OnCommand(40297-select,0)
            end
        
        elseif  Type==2 or tostring(Type):match("it")  and not tostring(Type):match("ai")    then--items
            if  #target>0 then
                for abi=1,#target do
                    if  FUN.UserDataType(target[abi]):match("Item*") then
                        reaper.SetMediaItemSelected(target[abi],select==1)
                    end
                end
            else
                cmd=(select==1 and 40182) or 40289
                reaper.Main_OnCommand(cmd,0)
            end 
        elseif  Type==3 or tostring(Type):match("env") and     tostring(Type):match("point") then--envelope points
            local time,value,shape,tension,env_n,env_point
            if  #target.env>0 then
                for abi=1,#target.env do
                    if  FUN.UserDataType(target.env[abi]):match("Envelope*") then
                        env_n=(#target.point>0 and #target.point) or reaper.CountEnvelopePoints(target.env[abi])
                        for abii=1,env_n do
                            env_point=(#target.point>0 and #target.point[abii]) or abii-1
                            _,time,value,shape,tension=reaper.GetEnvelopePoint(target.env[abi],env_point)
                            reaper.SetEnvelopePoint(target.env[abi],env_point,time,value,shape,tension,select==1,true)
                        end
                        reaper.Envelope_SortPoints(target.env[abi])
                    end
                end
            else
                for abi=1,reaper.CountTracks(0) do
                    tr=reaper.GetTrack(0,abi-1)
                    for abii=1,reaper.CountTrackEnvelopes(tr) do
                        env=reaper.GetTrackEnvelope(tr,abii-1)
                        for abiii=1,reaper.CountEnvelopePoints(env) do
                            _,time,value,shape,tension=reaper.GetEnvelopePoint(env,abiii-1)
                            reaper.SetEnvelopePoint(env,abiii-1,time,value,shape,tension,select==1,true)
                        end
                        reaper.Envelope_SortPoints(env)
                    end
                end
            end
        elseif  Type==4 or (tostring(Type):match("ai")  and not tostring(Type):match("point")) then--automation items
            if  #target.env>0 then
                for abi=1,#target.env do
                    if  FUN.UserDataType(target.env[abi]):match("Envelope*") then
                        local ai_n=(#target.ai>0 and #target.ai) or reaper.CountAutomationItems(target.env[abi])
                        for abii=1,ai_n do
                            local ai=(type(target.ai[abii])=="number" and target.ai[abii]) or abii-1
                            reaper.GetSetAutomationItemInfo(target.env[abi],ai,"D_UISEL",select,true)
                        end
                    end
                end
            else
                for abi=1,reaper.CountTracks(0) do
                    tr=reaper.GetTrack(0,abi-1)
                    for abii=1,reaper.CountTrackEnvelopes(tr) do
                        env=reaper.GetTrackEnvelope(tr,abii-1)
                        for abiii=1,reaper.CountAutomationItems(env) do
                            reaper.GetSetAutomationItemInfo(env,abiii-1,"D_UISEL",select,true)
                        end
                    end
                end
            end
        elseif  Type==5 or (tostring(Type):match("ai")  and     tostring(Type):match("point")) then--automation item points
            if  #target.env>0 then
                for abi=1,#target.env do
                    if  FUN.UserDataType(target.env[abi]):match("Envelope*") then
                        local ai_n=(#target.ai>0 and #target.ai) or reaper.CountAutomationItems(target.env[abi])
                        for abii=1,ai_n do
                            local ai=(type(target.ai[abii])=="number" and target.ai[abii]) or abii-1
                            for abiii=1,reaper.CountEnvelopePointsEx(target.env[abi],ai) do
                                reaper.SetEnvelopePointEx(target.env[abi],ai,abiii-1,_,_,_,_,select==1,true)
                            end
                            reaper.Envelope_SortPointsEx(target.env[abi],ai)
                        end
                    end
                end
            else
                for abi=1,reaper.CountTracks(0) do
                    tr=reaper.GetTrack(0,abi-1)
                    for abii=1,reaper.CountTrackEnvelopes(tr) do
                        env=reaper.GetTrackEnvelope(tr,abii-1)
                        for abiii=1,reaper.CountAutomationItems(env) do
                            for abiiii=1,reaper.CountEnvelopePointsEx(env,abiii-1) do
                                reaper.SetEnvelopePointEx(env,abiii-1,abiiii-1,_,_,_,_,select==1,true)
                            end
                            reaper.Envelope_SortPointsEx(env,abiii-1)
                        end
                    end
                end
            end
        else
            return      
        end

    end
    -------------
    function FUN.NumberCage(x,m,M,integer)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.NumberCage\n')
            end

        local min,max

        x = tonumber(x)

        if  type(x)~="number" then
            msg("WRONG INPUT type to Function NumberCage(x,min,max,int)")
            return
        end
        
        min = (m<M and m) or M
        max = (m<M and M) or m

        min = (type(min)~="number" and -math.huge) or min
        max = (type(max)~="number" and  math.huge) or max
        
        x=(x < min and min) or x
        x=(x > max and max) or x
        
        if  type(integer) == 'boolean' then
            if  integer then 
                x = math.floor(x)
            end
        elseif type(integer) == 'str' then
            if  integer == 'ceil' or integer == 'up' then
                integer = math.ceil
            else
                integer = matg.floor
            end
            x = integer(x)
        elseif type(integer) == 'number' then
            x = tonumber(string.format("%."..integer.."f",x))
        end

        return x

    end
    -------------
    function FUN.UserDataType(data)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.UserDataType\n')
            end

        local Source_type={"MediaTrack*","MediaItem*","MediaItem_Take*","TrackEnvelope*",
                            "PCM_source*","ReaProject*","MediaItem_TakePool*","MediaSample*"}
        for abi=1,#Source_type do
            if  reaper.ValidatePtr2(0,data,Source_type[abi]) then
                return Source_type[abi]
            end
        end

    end    
    -------------
    function FUN.dB_Value(dB)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.dB_Value\n')
            end
        local value=reaper.ScaleToEnvelopeMode(1,10^(dB/20))
        value=(value>4 and value) or 0
        return value
    end
    -------------
    function FUN.Value_dB(value)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.Value_dB\n')
            end
        local dB=20*math.log(reaper.ScaleFromEnvelopeMode(1,value),10)  
        dB=(dB<-144 and -144) or (dB>12 and 12) or dB
        return dB
    end 
    -------------
    function FUN.Vol_to_dB(dvol)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.Vol_to_dB\n')
            end

        if  dvol == 0 then
            return -math.huge -- -∞ dB
        else
            return 20*math.log(dvol,10)
        end

    end
    -------------
    function FUN.dB_to_Vol(dB)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.dB_to_Vol\n')
            end
        return 10^(dB/20)
    end
    -------------
    function FUN.CountLetters(pattern)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.CountLetters\n')
            end
        local count = {}

        for letter in pattern:gmatch("%a") do
            if  not count[letter] then
                count[letter]=true
                count[#count+1] = letter
            end
        end

        return count
    end
    -------------
    function FUN.is_divisible(a, b, epsilon)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.is_divisible\n')
            end
        epsilon = epsilon or 1e-10
        local result = a/b
        local remainder = math.abs(result - math.floor(result + 0.5))
        return remainder < epsilon
    end
    -------------
    function FUN.Reorder(tbl1,tbl2)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.Reorder\n')
            end

        local combined = {}
        for abi = 1, #tbl1 do
            combined[abi] = {value1 = tbl1[abi], value2 = tbl2[abi],originalIndex = abi}
        end

        table.sort(combined,function(a,b) return a.value2 < b.value2 end)
        
        for abi = 1, #combined do
            tbl1[abi] = combined[abi].value1
            tbl2[abi] = combined[abi].value2
        end
        return tbl1,tbl2
    end
    -------------
    function FUN.DIGI(num,digi,ceil,to_string)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.DIGI\n')
            end
      
        if  not num then return end
        
        digi = digi or 3
        
        num = (ceil and math.ceil(num*10^digi)/10^digi) or math.floor(num*10^digi)/10^digi
        
        if digi == 0 then num = string.format("%.0f", num) end
        
        return (to_string and tostring(num)) or num

        
    end
    -------------
    function FUN.NotesMonitor(editor)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.NotesMonitor\n')
            end

        local take,abi,notes,NOTES,idx,last_pitch,note_n
        
        if not editor then return end

        take = reaper.MIDIEditor_GetTake(editor)
        
        abi = 0
        note_n = 0

        notes = {'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'}
        NOTES = ''

        while(abi ~= -1) do
            
            idx = reaper.MIDI_EnumSelNotes(take,abi)

            local retval, selected, muted, startppqpos, endppqpos, chan, pitch, vel = reaper.MIDI_GetNote(take,abi)
            
            if  selected then
                if  not last_pitch or last_pitch ~= pitch then
                    NOTES = NOTES .. tostring(notes[pitch%12+1]) .. tostring(math.floor(pitch/12)-2) .. " | "
                    note_n = note_n +1 
                end
            end
            
            last_pitch = pitch
            abi = idx
        
        end
        
        NOTES = NOTES:sub(1,-4)

        if  NOTES ~= '' then
            FUN.billboard(NOTES,0.8,editor)
        end
    end
    -------------
    function FUN.KillTable(tbl)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.KillTable\n')
            end
        local seen = {}
        local result = {}
   
        for _, value in ipairs(tbl) do
            if not seen[value] then
                table.insert(result, value)
                seen[value] = true
            end
        end
   
        return #tbl ~= #result, result
    end
    ------------
    function FUN.SearchFiles(directory,extension)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SearchFiles\n')
            end

        local found_files = {}
        local i = 0
        while true do
            -- 使用 reaper.EnumerateFiles 和 reaper.EnumerateSubdirectories 函數
            local file = reaper.EnumerateFiles(directory, i)
            local subdir = reaper.EnumerateSubdirectories(directory, i)

            -- 如果沒有更多檔案或資料夾，跳出迴圈
            if not file and not subdir then break end

            -- 檢查檔案是否符合指定的副檔名
            if  file and file:match(extension .. "$") then
                table.insert(found_files, directory .. "/" .. file)
            end

            -- 如果是資料夾，遞迴搜尋
            if  subdir then
                search_files(directory .. "/" .. subdir, extension)
            end

            i = i + 1
        end
        
        return found_files
    end
    ------------   
    function FUN.DeepCopy(orig)
        local orig_type = type(orig)
        local copy
        if orig_type == 'table' then
            copy = {}
            for orig_key, orig_value in next, orig, nil do
                copy[FUN.DeepCopy(orig_key)] = FUN.DeepCopy(orig_value)
            end
            setmetatable(copy, FUN.DeepCopy(getmetatable(orig)))
        else -- number, string, boolean, etc
            copy = orig
        end
        return copy
    end

    function FUN.GenerateWave(freq, dur_ms, channels, intensity, bit)

        -- CUSTOM
        local amplitude = 1                       -- 0..1（Peak），最後會裁切到 int16 範圍
        local click_sound_directory = reaper.GetProjectPath() .. "/Click Sound/"

        os.execute('mkdir -p '..ESCPattern(click_sound_directory,true))

        local tn = tonumber
        local freq = tn(freq) or 1400                   -- click 基頻 (Hz)
        local dur_sec = tn(dur_ms) / 1000 or 0.01       -- 長度 (秒)，例如 0.01 = 10 ms
        local channels = tn(channels) or 1              -- 1 = mono, 2 = stereo
        local bitsPerSample = tn(bit) or 24             
        local sampleRate

        if  reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false) == 1 then
            sampleRate = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
        else
            retval, sampleRate = reaper.GetAudioDeviceInfo("SRATE", "")
        end

        local click_name = click_sound_directory .. string.format("%.1f",(freq/1000)) .. 'k_' .. dur_ms .. 'ms_' .. string.format("%.0f",sampleRate) .. ".wav"
        
        -- 計算
        local samples = math.floor(sampleRate * dur_sec)
        local bytesPerSample = bitsPerSample / 8
        local blockAlign = channels * bytesPerSample
        local byteRate = sampleRate * blockAlign
        local dataChunkSize = samples * blockAlign
        local riffChunkSize = 4 + (8 + 16) + (8 + dataChunkSize)  -- "WAVE" + fmt chunk + data chunk
        -- 注意：riff size = 4 + (8+fmtLen) + (8+dataLen)

        -- 打開檔案 (二進位寫入)
        local f, err = io.open(click_name, "wb")

        if not f then
            reaper.ShowMessageBox("無法開檔寫入: " .. tostring(err), "Error", 0)
            return
        end

        -- helper: 寫小端 unsigned 32 / 16 via string.pack
        local function writeLE_s16(n) f:write(string.pack("<h", n)) end
        
        -- 用位運算手工寫小端 unsigned 32/16
        local function writeLE_u32(n)
            n = n % 4294967296           -- 保證在 0..2^32-1
            local b1 = n & 0xFF
            local b2 = (n >> 8) & 0xFF
            local b3 = (n >> 16) & 0xFF
            local b4 = (n >> 24) & 0xFF
            f:write(string.char(b1, b2, b3, b4))
        end
        
        local function writeLE_u16(n)
            n = n & 0xFFFF
            local b1 = n & 0xFF
            local b2 = (n >> 8) & 0xFF
            f:write(string.char(b1, b2))
        end
        
        local function writeLE_s24(n)
            n = n & 0xFFFFFF
            local b1 = n & 0xFF
            local b2 = (n >> 8) & 0xFF
            local b3 = (n >> 16) & 0xFF
            f:write(string.char(b1, b2, b3))
        end

        -- WAV header
        f:write("RIFF")
        writeLE_u32(riffChunkSize)
        f:write("WAVE")

        -- fmt chunk (PCM)
        f:write("fmt ")
        writeLE_u32(16)             -- subchunk1 size for PCM
        writeLE_u16(1)              -- audio format 1 = PCM
        writeLE_u16(channels)
        writeLE_u32(sampleRate)
        writeLE_u32(byteRate)
        writeLE_u16(blockAlign)
        writeLE_u16(bitsPerSample)

        -- data chunk
        f:write("data")
        writeLE_u32(dataChunkSize)

        -- 產生samples：短 sine + 指數衰減 envelope
        -- 用較平滑的 envelope 減少突變引起的高頻 click
        local tau_factor = FUN.NumberCage(intensity, 1, 10)  -- 控制衰減速率；增大會更快衰減

        local function scale(v,bitsPerSample)
            local depth = 2^(bitsPerSample-1) -1
            return math.floor( FUN.NumberCage(v, -1, 1) * depth + 0.5)  -- clip 與四捨五入
        end

        local writeLE = (bitsPerSample == 16 and writeLE_s16) or writeLE_s24

        for i = 0, samples - 1 do
            local t = i / sampleRate
            -- 基本正弦
            local s = math.sin(2 * math.pi * freq * t)
            -- 指數衰減 envelope：exp(-k * i / N) 讓最後剩很少
            local env = math.exp(-tau_factor * (i / samples))
            local v = s * env * amplitude
        
            -- 轉成 PCM
            local intv = scale(v, bitsPerSample)

            -- 如果 stereo 要寫兩個 channel，這裡可複寫
            for abi = 1, channels do
                writeLE(intv)
            end 
        end

        f:close()

        -- 告知完成
        -- BBB("Click written to: " .. click_name .. "\n")
        
        -- 將檔案插入當前軌道 / 時間 (InsertMedia 參數 0 = insert as new item at edit cursor)
        return click_name

    end

----------------------------
-----------GUI--------------
----------------------------

    -------------
    function FUN.PickColor(source,format)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.PickColor\n')
            end
            
        local function rgbToHex(value)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  rgbToHex\n')
            end
            local hexadecimal = '0X'
        
            --for key, value in pairs(rgb) do
            local hex = ''

            while(value > 0)do
                local index = math.fmod(value, 16) + 1
                value = math.floor(value / 16)
                hex = string.sub('0123456789ABCDEF', index, index)..hex      
            end
        
            if  (string.len(hex) == 0)then
                hex = '00'
        
            elseif(string.len(hex) == 1)then
                hex = '0'..hex
            end
        
            hexadecimal = hexadecimal..hex
        
            return hexadecimal
        end

        if  type(source)=="table" and #source==3 then
            color=reaper.ColorToNative(source[1],source[2],source[3])|0x1000000
        elseif type(source)=="number" then
            color=source
        elseif source=="item" then
            local item=reaper.GetSelectedMediaItem(0,0)
            color=( item and reaper.GetMediaItemInfo_Value(item,"I_CUSTOMCOLOR") ) or -1
        elseif source=="track" then
            local tr=reaper.GetSelectedTrack(0,0)
            color= ( tr and reaper.GetMediaTrackInfo_Value(tr,"I_CUSTOMCOLOR") ) or -1
        else
            return 
        end

        if  format=="rgb" then
            msg(reaper.ColorFromNative(color))
        elseif format=="hex" then
            msg(rgbToHex(color))
        else
            msg(color)
        end

    end
    -------------
    function FUN.SwitchFxWindow(tr)

        api.cc()
        -- JS extension required
        if not (reaper.JS_Window_GetRect and reaper.JS_Window_SetPosition) then
            reaper.ShowMessageBox("需要安裝/啟用 JS_ReaScriptAPI 才能控制視窗位置。", "Missing JS_ReaScriptAPI", 0)
            return
        end

        local function NormalizeFXName(raw)
            if not raw then return "" end
            return raw:match(".-: (.*)%(.-%)") or raw
        end

        local function ParseTrackNumberFromTitle(title)
            if not title or title == "" then return nil end

            -- 排除 item/take FX（你說之後再管，這裡先略過）
            if title:find("FX:Item", 1, true) or title:find("FX:Take", 1, true) then
                return nil
            end

            -- Master
            if title:find(" %- Master Track", 1, true) then
                return api.gMt()
            end
            
            --Normal tracks
            local n = title:match("%) %- Track%s+(%d+)")
            if n then return api.gt(0,n-1) end
        end

        local function BuildNameToPositions(track, mode)
            local n = (mode == "recFX") and reaper.TrackFX_GetRecCount(track) or reaper.TrackFX_GetCount(track)
            local map = {}
            for pos = 1, n do
                local fx = (mode == "recFX") and (pos - 1 + 0x1000000) or (pos - 1)
                local _, raw = reaper.TrackFX_GetFXName(track, fx, "")
                local name = NormalizeFXName(raw)
                map[name] = map[name] or {}
                map[name][#map[name] + 1] = pos
            end
            return map
        end

        local function FindTargetFxIndex(targetTrack, mode, nameMap, name, occWanted)
            local positions = nameMap[name]
            if not positions or #positions == 0 then return nil end

            local pos = positions[occWanted] or positions[1]
            if mode == "recFX" then
                return pos - 1 + 0x1000000
            else
                return pos - 1
            end
        end

        local function CopyWindowRect(srcHwnd, dstHwnd)
            if not (srcHwnd and dstHwnd) then return end
            local ori_L, ori_T, ori_R, ori_B = FUN.GetWindowPosition(srcHwnd)
            local L, T, R, B = FUN.GetWindowPosition(dstHwnd)
            if  L~=ori_L or B~=ori_B or R~=ori_R or T~=ori_T then
                FUN.SetWindowPosition(dstHwnd, ori_L, ori_B, ori_R, ori_T)
            end
            return true
        end

        local function ResolveFloatingFXOnTrackByHWND(track, hwnd)
            -- postFX
            for abi=1, 2 do
                local mode = (abi==1 and 'recFX' ) or 'postFX'
                local seen = {}
                local n = reaper.TrackFX_GetCount(track)
                for pos = 1, n do
                    local fx = (mode =='recFX' and (pos - 1 + 0x1000000)) or (pos - 1)
                    local fHwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
                    local _, raw = reaper.TrackFX_GetFXName(track, fx, "")
                    local name = NormalizeFXName(raw)
                    seen[name] = (seen[name] or 0) + 1
                    local slot = seen[name]

                    if fHwnd and fHwnd == hwnd then
                        
                        return { track = track, mode = mode, fx = fx, name = name, slot = slot, hwnd = hwnd }
                    end 
                end
            end

            return nil
        end

        local function GetAllFloatingFXByWindowTitles()
            local floats = {}

            local _, list = reaper.JS_Window_ListAllTop()
            if not list or list == "" then return floats end

            for addr in list:gmatch("[^,]+") do
                    local hwnd = reaper.JS_Window_HandleFromAddress(addr)
                    if hwnd then
                    local title = reaper.JS_Window_GetTitle(hwnd)
                    local track = ParseTrackNumberFromTitle(title)

                    if track then
                        local item = ResolveFloatingFXOnTrackByHWND(track, hwnd)
                        if item then
                            floats[#floats + 1] = item
                        end
                    end
                end
            end
            return floats
        end

        local function ApplyToSelectedTrackAndCloseSources(target)

            local floats = GetAllFloatingFXByWindowTitles()
            if not target or #floats == 0 then return end

            local postMap = BuildNameToPositions(target, "postFX")
            local recMap  = BuildNameToPositions(target, "recFX")

            -- avoid mapping multiple source floats onto the same target FX
            local usedPost = {}
            local usedRec  = {}

            -- "例外：能優先匹配什麼就是什麼" -> 順序就照掃描到的 floats 先後；先搶到就先用
            for i = 1, #floats do
                local s = floats[i]
                if s.track == target then return end
                local nameMap = (s.mode == "recFX") and recMap or postMap
                local usedMap = (s.mode == "recFX") and usedRec or usedPost

                local tfx = FindTargetFxIndex(target, s.mode, nameMap, s.name, s.slot)

                -- 如果 occurrence 對位成功但那顆已被其他浮動視窗佔用，就嘗試回退第一顆同名（如果不同顆）
                if tfx and usedMap[tfx] then
                    local tfxFallback = FindTargetFxIndex(target, s.mode, nameMap, s.name, 1)
                    if tfxFallback and not usedMap[tfxFallback] then
                        tfx = tfxFallback
                    else
                        tfx = nil
                    end
                end

                if tfx and not usedMap[tfx] then
                    reaper.TrackFX_Show(target, tfx, 3)
                    local target_hwnd = reaper.TrackFX_GetFloatingWindow(target, tfx)
                    if CopyWindowRect(s.hwnd, target_hwnd) then
                        usedMap[tfx] = true
                        reaper.TrackFX_Show(s.track, s.fx, 2)
                    end
                end
            end
        end

        ApplyToSelectedTrackAndCloseSources(tr)
        api.cmd(api.name('_S&M_WNMAIN'),0)
    end
    -------------
    function FUN.PassThroughShortcut(char)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.PassThroughShortcut\n')
            end
        local _, _, section_id = reaper.get_action_context()

        local shortcut
        
        local my_shortcuts = {}
        my_shortcuts['Ctrl+Shift+X'] = function() print('Another one!') end
        my_shortcuts['Ctrl+Shift+C'] = function() print('And another one!') end
        
        local special_chars = {}
        special_chars[8] = 'Backspace'
        special_chars[9] = 'Tab'
        special_chars[13] = 'Enter'
        special_chars[27] = 'ESC'
        special_chars[32] = 'Space'
        special_chars[176] = '°'
        special_chars[26161] = 'F1'
        special_chars[26162] = 'F2'
        special_chars[26163] = 'F3'
        special_chars[26164] = 'F4'
        special_chars[26165] = 'F5'
        special_chars[26166] = 'F6'
        special_chars[26167] = 'F7'
        special_chars[26168] = 'F8'
        special_chars[26169] = 'F9'
        special_chars[6697264] = 'F10'
        special_chars[6697265] = 'F11'
        special_chars[6697266] = 'F12'
        special_chars[65105] = '﹑'
        special_chars[65106] = '﹒'
        special_chars[6579564] = 'Delete'
        special_chars[6909555] = 'Insert'
        special_chars[1752132965] = 'Home'
        special_chars[6647396] = 'End'
        special_chars[1885828464] = 'Page Up'
        special_chars[1885824110] = 'Page Down'
        
        local function ConvertCharToShortcut(char)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  ConvertCharToShortcut\n')
            end
            local is_ctrl = gfx.mouse_cap & 4 == 4
            local is_shift = gfx.mouse_cap & 8 == 8
            local is_alt = gfx.mouse_cap & 16 == 16
        
            local key
        
            -- Check for special characters, avoid 1..26 (Ctrl+A..Z)
            if not (is_ctrl and char <= 26) then key = special_chars[char] end
        
            if not key then
                -- Add offset for 1..26 (Ctrl+A..Z)
                if char >= 1 and char <= 26 then char = char + 64 end
                -- Add offset for 257..282 (Ctrl+Alt+A..Z)
                if char >= 257 and char <= 282 then char = char - 192 end
                -- Convert char to key string
                key = string.char(char & 0xFF):upper()
            end
        
            -- Add keyboard modifiers in text form
            if is_shift and key ~= key:lower() then key = 'Shift+' .. key end
            if is_alt then key = 'Alt+' .. key end
            if is_ctrl then key = 'Ctrl+' .. key end
        
            return key
        end
        
        local function GetCommandByShortcut(section_id, shortcut)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  GetCommandByShortcut\n')
            end
            -- Check REAPER version
            local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
            if version < 6.71 then return end
            -- On MacOS, replace Ctrl with Cmd etc.
            local is_macos = reaper.GetOS():match('OS')
            if is_macos then
                shortcut = shortcut:gsub('Ctrl%+', 'Cmd+', 1)
                shortcut = shortcut:gsub('Alt%+', 'Opt+', 1)
            end
            -- Go through all actions of the section
            local sec = reaper.SectionFromUniqueID(section_id)
            local i = 0
            repeat
                local cmd = reaper.kbd_enumerateActions(sec, i)
                if cmd ~= 0 then
                    -- Go through all shortcuts of each action
                    for n = 0, reaper.CountActionShortcuts(sec, cmd) - 1 do
                        -- Find the action that matches the given shortcut
                        local _, desc = reaper.GetActionShortcutDesc(sec, cmd, n, '')
                        if desc == shortcut then return cmd, n end
                    end
                end
                i = i + 1
            until cmd == 0
        end
    
        if  char ~= 0 then
            shortcut = ConvertCharToShortcut(char)
            if shortcut == 'Ctrl+Alt+C' then
                -- Check whether it's a custom shortcut for your own script
                print('My custom script shortcut!')
            elseif my_shortcuts[shortcut] then
                -- Alternative: If you have a lot of custom shortcuts, it might
                -- be a good idea to put functions in a table instead
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION -- s in a table instea\n')
            end
                my_shortcuts[shortcut]()
            else
                -- Check if script is executed through MIDI editor section
                if section_id == 32060 then
                    -- Passthrough unused shortcut to MIDI editor
                    local hwnd = reaper.MIDIEditor_GetActive()
                    if hwnd then
                        cmd = GetCommandByShortcut(section_id, shortcut)
                        if cmd then
                            reaper.MIDIEditor_OnCommand(hwnd, cmd)
                        end
                    end
                else
                    -- Passthrough unused shortcut to main window
                    cmd = GetCommandByShortcut(0, shortcut)
                    if cmd then reaper.Main_OnCommand(cmd, 0) end
                end
            end
        end
    end
    -------------
    function FUN.GetScreenResolution(reScan,show)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetScreenResolution\n')
            end

        local file,result,OS,mainHWND,hwnd,width,height,scale
        
        width=api.load("Screen Resolution","width")
        height=api.load("Screen Resolution","height")

        if  reScan or (type(tonumber(width))~="number" or type(tonumber(height))~="number") then
            --mainHWND = reaper.GetMainHwnd()
            --hwnd= reaper.JS_Window_FindChildByID(mainHWND,1000)
            OS = reaper.GetOS()

            if  OS:find("OS") then
                file=io.popen("system_profiler SPDisplaysDataType | awk '/Resolution/ {print $2, $4}'")
                result=file:read('*a')
                width, height=result:match("(%d+)%s+(%d+)")
            elseif OS:find("Win") then
                file=io.popen("wmic path Win32_VideoController get CurrentHorizontalResolution,CurrentVerticalResolution /format:value")
                result=file:read("*a")
                width,height=result:match("CurrentHorizontalResolution=(%d+)"),result:match("CurrentVerticalResolution=(%d+)")
            
            elseif OS:find("Linux") then
                file=io.popen("xrandr | grep '*'")
                result=file:read("*a")
                width, height=result:match("(%d+)x(%d+)")
            end

            file:close()

            scale,gfx.ext_retina = 1, 1 -- init with 1
            gfx.init("",1,1)
            scale=gfx.ext_retina
            gfx.quit()

            width=tonumber(width/scale)
            height=tonumber(height/scale)

            api.save("Screen Resolution","width",width,true)
            api.save("Screen Resolution","height",height,true)

            if  show then
                msg("Screen Resolution:")
                msg("Width  | "..width)
                msg("Height | "..height)
            end
          
        end

        return tonumber(width),tonumber(height)

    end
    -------------
    function FUN.GetWindowPosition(hwnd)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetWindowPosition\n')
            end
        if not hwnd then return end
        local _, l, t, r, b=reaper.JS_Window_GetRect(hwnd)
        return l, t, r, b
    end --return l, t, r, b
    -------------
    function FUN.SetWindowPosition(hwnd, l, b, r, t)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.SetWindowPosition\n')
            end
        reaper.JS_Window_SetPosition(hwnd,math.floor(l),math.floor(b),math.floor(r-l),math.floor(math.abs(t-b)))
    end  
    -------------
    function FUN.IsMidiEditorFocus(editor)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.IsMidiEditorFocus\n')
            end

        local focus,currentWindow

        editor = editor or reaper.MIDIEditor_GetActive()
        
        if  not editor then return false end
        
        focus = reaper.JS_Window_GetFocus()

        currentWindow = focus

        while currentWindow do
            if  currentWindow == editor then
                focus = currentWindow
                break
            end
            currentWindow = reaper.JS_Window_GetParent(currentWindow)
        end

        if  currentWindow == editor then return true end
        
        return false

    end
    -------------
    function FUN.GetSetTime(check,Start,End,Loop)
            if  DE_BUG_MODE then
                reaper.ShowConsoleMsg('    Running FUNCTION --  FUN.GetSetTime\n')
            end

        local starttime,endtime
        starttime, endtime = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
        
        if  type(Start)=='number' and type(End)=='number' and Start <= End then
            reaper.GetSet_LoopTimeRange2(0,true,Loop or false,Start,End,false)
        elseif check then
            return starttime ~= endtime 
        else
            return starttime,endtime
        end
    end
    
    -- Drop-in replacement for reaper.GetUserInputs() — ReaImGui-based.
    -- Signature:  ok, csv = FUN.GetUserInputs(title, num_inputs, captions_csv, retvals_csv [, opts])
    -- opts (optional): { bg_color, text_color, accent, scale, native }  overrides ExtState
    -- Global theme stored via SetExtState in section "Lyx_GetUserInputs".
    -- ImGui needs defer frames, so the ImGui dialog only shows when called inside
    -- FUN.run(...). Called synchronously (or without ReaImGui / with opts.native),
    -- it falls back to the native reaper.GetUserInputs, so plain scripts still work.
    function FUN.GetUserInputs(title, num_inputs, captions_csv, retvals_csv, opts)
        opts = opts or {}
        local SECTION = "Lyx_GetUserInputs"

        if opts.native or not reaper.ImGui_CreateContext or not coroutine.isyieldable() then
            return reaper.GetUserInputs(title or "", num_inputs, captions_csv or "", retvals_csv or "")
        end

        ---------- parse captions / defaults ----------
        -- Reaper supports a hidden "separator=X" declaration at the end of
        -- captions_csv where X is a single char that replaces "," as delimiter.
        -- Example: "A\30B\30C\30separator=\30"  (each field separated by \x1E)
        captions_csv = captions_csv or ""
        local sep = ","
        do
            local idx = captions_csv:find("separator=", 1, true)
            if idx then
                local sep_char = captions_csv:sub(idx + 10, idx + 10)
                if sep_char ~= "" then sep = sep_char end
                -- strip "<sep>separator=<sep>" (or as much as matches) off end
                local cut = idx
                if captions_csv:sub(idx - 1, idx - 1) == sep then cut = idx - 1 end
                captions_csv = captions_csv:sub(1, cut - 1)
            end
        end
        -- Plain-text split (separator may contain regex-special chars).
        local function split_by(s, d)
            local t, start = {}, 1
            while true do
                local a, b = s:find(d, start, true)
                if not a then t[#t+1] = s:sub(start); break end
                t[#t+1] = s:sub(start, a - 1)
                start = b + 1
            end
            return t
        end
        local captions = split_by(captions_csv, sep)
        local defaults = split_by(retvals_csv or "", sep)
        -- Extract "extrawidth=N" from captions. It may be its own field (the field is
        -- removed, with its default) or tacked onto a caption ("Name:extrawidth=300").
        local extrawidth = 0
        for i = #captions, 1, -1 do
            local a, b, n = captions[i]:find("%s*extrawidth%s*=%s*(%d+)%s*")
            if n then
                extrawidth = tonumber(n) or 0
                captions[i] = captions[i]:sub(1, a - 1) .. captions[i]:sub(b + 1)
                if not captions[i]:find("%S") then
                    table.remove(captions, i)
                    if defaults[i] then table.remove(defaults, i) end
                end
            end
        end
        for i = #captions + 1, num_inputs do captions[i] = "Field "..i end
        for i = #defaults + 1, num_inputs do defaults[i] = "" end

        ---------- theme (ExtState + opts overrides) ----------
        local function loadNum(k, d)
            local s = reaper.GetExtState(SECTION, k); local v = tonumber(s); return v or d
        end
        local function saveNum(k, v) reaper.SetExtState(SECTION, k, tostring(v), true) end
        local bg     = opts.bg_color   or loadNum("bg",     0x1E1E2E)
        local fg     = opts.text_color or loadNum("fg",     0xCDD6F4)
        local accent = opts.accent     or loadNum("accent", 0x89B4FA)
        local scale  = opts.scale      or loadNum("scale",  1.0)
        if scale < 0.5 then scale = 0.5 elseif scale > 2.5 then scale = 2.5 end

        ---------- color helpers ----------
        local function splitRGB(h) return ((h>>16)&0xFF)/255, ((h>>8)&0xFF)/255, (h&0xFF)/255 end
        local function mix(a, b, t)
            local ar,ag,ab = splitRGB(a); local br,bg2,bb = splitRGB(b)
            local r = math.floor((ar + (br-ar)*t)*255 + 0.5)
            local g = math.floor((ag + (bg2-ag)*t)*255 + 0.5)
            local b_= math.floor((ab + (bb-ab)*t)*255 + 0.5)
            return (r<<16)|(g<<8)|b_
        end
        -- 0xRRGGBB -> 0xRRGGBBAA (ImGui colour format), opaque
        local function rgba(h) return ((h & 0xFFFFFF) << 8) | 0xFF end

        ---------- context + font ----------
        local ctx  = reaper.ImGui_CreateContext(title or "Lyx")
        -- PingFang has full CJK coverage; dynamic font system loads glyphs on demand.
        local font = reaper.ImGui_CreateFont("/System/Library/Fonts/PingFang.ttc", 0)
                  or reaper.ImGui_CreateFont("sans-serif", 0)
        reaper.ImGui_Attach(ctx, font)

        -- Disable keyboard navigation so arrow keys (and Tab) stay inside the
        -- focused field instead of jumping focus to the row above/below.
        local _cf = reaper.ImGui_GetConfigVar(ctx, reaper.ImGui_ConfigVar_Flags())
        reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_Flags(),
            _cf & ~reaper.ImGui_ConfigFlags_NavEnableKeyboard())

        ---------- state ----------
        local values = {}
        for i = 1, num_inputs do values[i] = defaults[i] or "" end

        local saved_x = tonumber(reaper.GetExtState(SECTION, "win_x") or "")
        local saved_y = tonumber(reaper.GetExtState(SECTION, "win_y") or "")
        local cur_x, cur_y = saved_x, saved_y

        local ok_result, csv_result = false, retvals_csv or ""
        local closed = false
        local first_frame = true
        local settings_open = false
        -- macOS IME confirm-Enter leaks through as a real Enter key. We ignore
        -- Enter for a short window after any text change (an IME commit changes
        -- text on the same/adjacent frame), so picking candidates won't submit.
        local last_change_t = -1
        local IME_GUARD = 0.25
        -- manual field focus (keyboard nav is disabled, so we drive Tab ourselves)
        local active_idx = 1
        local want_focus = nil
        -- Enter/Esc only count after they've been seen released once. A dialog
        -- opened right after another one would otherwise catch the still-held
        -- Enter that closed the previous dialog and submit instantly.
        local enter_armed, esc_armed = false, false

        local function submitOK()
            ok_result  = true
            csv_result = table.concat(values, sep)
            closed = true
        end

        ---------- per-frame draw (runs in defer context via FUN.run's step) ----------
        FUN._frame = function()
            if closed then return end

            reaper.ImGui_PushFont(ctx, font, math.floor(15 * scale + 0.5))

            if first_frame and saved_x and saved_y then
                reaper.ImGui_SetNextWindowPos(ctx, saved_x, saved_y,
                    reaper.ImGui_Cond_FirstUseEver())
            end

            -- theme colours
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       rgba(bg))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(),        rgba(mix(bg, 0x000000, 0.1)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           rgba(fg))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        rgba(mix(bg, 0x000000, 0.25)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), rgba(mix(bg, fg, 0.12)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),  rgba(mix(bg, accent, 0.25)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),         rgba(mix(bg, fg, 0.2)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         rgba(mix(bg, fg, 0.15)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  rgba(mix(bg, fg, 0.28)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   rgba(mix(bg, accent, 0.4)))
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(), rgba(mix(bg, accent, 0.6)))
            local NCOL = 11

            -- rounded corners
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8 * scale)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),  6 * scale)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(),  6 * scale)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(),   4 * scale)
            -- roomier rows + slightly taller fields
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),   8 * scale, 10 * scale)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(),  6 * scale, 5 * scale)
            local NVAR = 6

            local win_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
                            | reaper.ImGui_WindowFlags_NoCollapse()
            local visible, open = reaper.ImGui_Begin(ctx, (title or "Lyx").."###lyx_getuserinputs",
                                                     true, win_flags)
            if visible then
                -- NoTabStop on every item: ImGui's own tabbing has no targets
                -- (it would land on Set/OK/Cancel); Tab is handled manually below.
                reaper.ImGui_PushItemFlag(ctx, reaper.ImGui_ItemFlags_NoTabStop(), true)

                -- compute label column width from longest caption
                local label_w = 1
                for i = 1, num_inputs do
                    local w = reaper.ImGui_CalcTextSize(ctx, captions[i])
                    if w > label_w then label_w = w end
                end
                local gap     = 12 * scale
                local field_w = (240 + extrawidth/2) * scale

                -- top-right Set button
                local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
                local set_w   = reaper.ImGui_CalcTextSize(ctx, "Set") + 16 * scale
                reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + math.max(0, avail_w - set_w))
                if reaper.ImGui_Button(ctx, "Set", set_w) then
                    settings_open = true
                    reaper.ImGui_OpenPopup(ctx, "Settings")
                end

                -- input rows
                for i = 1, num_inputs do
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_Text(ctx, captions[i])
                    reaper.ImGui_SameLine(ctx, label_w + gap)
                    reaper.ImGui_SetNextItemWidth(ctx, field_w)
                    if want_focus == i or (first_frame and i == 1) then
                        reaper.ImGui_SetKeyboardFocusHere(ctx)
                    end
                    local chg, nv = reaper.ImGui_InputText(ctx, "##field"..i, values[i])
                    if chg then values[i] = nv; last_change_t = reaper.time_precise() end
                    if reaper.ImGui_IsItemActive(ctx) then active_idx = i end
                end
                want_focus = nil

                -- Tab / Shift+Tab cycles fields (wraps around). Focus lands next
                -- frame via SetKeyboardFocusHere, which also selects the text.
                if not settings_open and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Tab(), false) then
                    local step = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift()) and -1 or 1
                    want_focus = (active_idx - 1 + step) % num_inputs + 1
                end

                -- submit / cancel on Enter / Esc.
                -- Skip Enter right after a text change so IME candidate-confirm
                -- (which commits text) doesn't accidentally close the window.
                local K_enter, K_kpenter, K_esc = reaper.ImGui_Key_Enter(), reaper.ImGui_Key_KeypadEnter(), reaper.ImGui_Key_Escape()
                if not (reaper.ImGui_IsKeyDown(ctx, K_enter) or reaper.ImGui_IsKeyDown(ctx, K_kpenter)) then enter_armed = true end
                if not reaper.ImGui_IsKeyDown(ctx, K_esc) then esc_armed = true end

                if not settings_open then
                    local enter = reaper.ImGui_IsKeyPressed(ctx, K_enter, false)
                               or reaper.ImGui_IsKeyPressed(ctx, K_kpenter, false)
                    if enter and enter_armed and (reaper.time_precise() - last_change_t) > IME_GUARD then
                        submitOK()
                    elseif esc_armed and reaper.ImGui_IsKeyPressed(ctx, K_esc, false) then
                        closed = true
                    end
                end

                reaper.ImGui_Dummy(ctx, 1, 4 * scale)

                -- OK (accent) + Cancel
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        rgba(accent))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), rgba(mix(accent, 0xFFFFFF, 0.2)))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  rgba(mix(accent, 0x000000, 0.2)))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),          rgba(bg))
                if reaper.ImGui_Button(ctx, "OK", 80 * scale) then submitOK() end
                reaper.ImGui_PopStyleColor(ctx, 4)
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Cancel", 80 * scale) then closed = true end

                -- settings popup (theme + scale)
                if reaper.ImGui_BeginPopup(ctx, "Settings") then
                    local cf = reaper.ImGui_ColorEditFlags_NoInputs()
                             | reaper.ImGui_ColorEditFlags_NoAlpha()
                    local c, v
                    c, v = reaper.ImGui_ColorEdit3(ctx, "Background", bg, cf)
                    if c then bg = v;     reaper.SetExtState(SECTION, "bg",     tostring(bg),     true) end
                    c, v = reaper.ImGui_ColorEdit3(ctx, "Text", fg, cf)
                    if c then fg = v;     reaper.SetExtState(SECTION, "fg",     tostring(fg),     true) end
                    c, v = reaper.ImGui_ColorEdit3(ctx, "Accent", accent, cf)
                    if c then accent = v; reaper.SetExtState(SECTION, "accent", tostring(accent), true) end
                    reaper.ImGui_SetNextItemWidth(ctx, 160 * scale)
                    c, v = reaper.ImGui_SliderDouble(ctx, "Scale", scale, 0.5, 2.5, "%.1fx")
                    if c then
                        scale = (v < 0.5) and 0.5 or (v > 2.5 and 2.5 or v)
                        reaper.SetExtState(SECTION, "scale", tostring(scale), true)
                    end
                    reaper.ImGui_EndPopup(ctx)
                else
                    settings_open = false
                end

                -- track window position for persistence
                local wx, wy = reaper.ImGui_GetWindowPos(ctx)
                if wx and wy then cur_x, cur_y = math.floor(wx), math.floor(wy) end

                reaper.ImGui_PopItemFlag(ctx)
            end

            if not open then closed = true end
            reaper.ImGui_End(ctx)
            reaper.ImGui_PopStyleVar(ctx, NVAR)
            reaper.ImGui_PopStyleColor(ctx, NCOL)
            reaper.ImGui_PopFont(ctx)
            first_frame = false
        end

        -- Yield until frame loop signals close (OK / Cancel / Esc / window closed)
        while not closed do coroutine.yield() end

        FUN._frame = nil
        if cur_x and cur_y and cur_x >= 0 and cur_y >= 0 then
            reaper.SetExtState(SECTION, "win_x", tostring(cur_x), true)
            reaper.SetExtState(SECTION, "win_y", tostring(cur_y), true)
        end
        return ok_result, csv_result
    end

    -- Run fn(...) inside one undo block and return its results. Inside FUN.run, call
    -- it after the last FUN.GetUserInputs so the block doesn't span defer cycles
    -- (a deferred script gets no automatic undo point, so changes need this).
    -- The block is closed even if fn errors; the error is then re-raised.
    function FUN.Undo(name, fn, ...)
        reaper.Undo_BeginBlock()
        local res = table.pack(xpcall(fn, debug.traceback, ...))
        reaper.Undo_EndBlock(name or "Lyx script", -1)
        if not res[1] then error(res[2], 0) end
        return table.unpack(res, 2, res.n)
    end

    -- Helper: wrap a function to run as a coroutine, pumping via reaper.defer.
    -- FUN._frame is invoked OUTSIDE coroutine.resume so that gfx.drawstr works
    -- (Reaper gfx.drawstr fails with "<bad string>" when called inside resume).
    function FUN.run(fn, ...)
        local args = {...}
        local co = coroutine.create(function() return fn(table.unpack(args)) end)
        local function step()
            if FUN._frame then FUN._frame() end   -- draw in defer context, before resume
            local ok, err = coroutine.resume(co)
            if not ok then
                FUN._frame = nil
                reaper.ShowConsoleMsg("[FUN.run] error: "..debug.traceback(co, tostring(err)).."\n")
                return
            end
            if coroutine.status(co) ~= "dead" then
                reaper.defer(step)
            end
        end
        reaper.defer(step)
    end


    -------------
    FUN.billboard = BBB

    function billboard(x) BBB(x) end

    return FUN
