
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    local hold_time = 0.3   -- 放開後多久判定為鬆手（秒）
    local first_grace = 0.4 -- 第一次按下多給的緩衝（等鍵盤連發開始）
    local EXT = "holding solo"

    --------------
    -- 原生 API 直接用螢幕座標找軌，支援 Pin tracks to top
    local function TrackUnderMouse()
        local x, y = reaper.GetMousePosition()
        return (reaper.GetTrackFromPoint(x, y))
    end

    -- 輕量版 razor 掃描：只要軌道 + 最早起點
    local function RazorTracks()
        local tracks, min = {}, nil
        for i = 0, reaper.CountTracks(0) - 1 do
            local tr = reaper.GetTrack(0, i)
            local _, area = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
            if area ~= "" then
                tracks[#tracks+1] = tr
                for str in area:gmatch("(%S+) %S+ %S+") do
                    local s = tonumber(str)
                    if s and (not min or s < min) then min = s end
                end
            end
        end
        return tracks, min
    end

    --------------
    local function WaitRelease(P)
        local time = tonumber(api.load(EXT, "time")) or reaper.time_precise()
        if reaper.time_precise() - time <= hold_time then
            reaper.defer(function() WaitRelease(P) end)
            return
        end
        if P == 0 then reaper.Main_OnCommand(1016,0) end --stop
        local last_mouse_tr = api.idt(0, api.load(EXT, 'last mouse track'))
        local lane = tonumber(api.load(EXT, 'last mouse track lane'))
        if api.check(0, last_mouse_tr, 'MediaTrack*') and lane then
            api.stv(last_mouse_tr, 'C_LANEPLAYS:' .. (lane-1), 1)
        end
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_RESTORE_SOLO_MUTE_ALL_TRACKS_SLOT_3"),0)
        api.save(EXT,"state","0",false)
        reaper.DeleteExtState(EXT,"time",true)
    end

    --------------
    local now = reaper.time_precise()

    if api.load(EXT,"state") == "1" and api.gps() ~= 0 then -- 按住中：續命
        api.save(EXT,"time",now,false)
        return
    end

    -- 1) 決定要 solo 的軌：razor > 多選 > 滑鼠底下
    local sel = r.SaveTracks()
    local mouse_tr = TrackUnderMouse()
    local razor_tr, razor_min = RazorTracks()
    local solo_tr = (#razor_tr > 0 and razor_tr) or (#sel > 1 and sel) or {mouse_tr or sel[1]}
    if #solo_tr == 0 then return end

    -- 2) 目標 + 所有 parent
    local want = {}
    for _, tr in ipairs(solo_tr) do
        local t = tr
        while t and not want[t] do
            want[t] = true
            t = reaper.GetParentTrack(t)
        end
    end

    reaper.PreventUIRefresh(1)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_BR_SAVE_SOLO_MUTE_ALL_TRACKS_SLOT_3"),0)

    -- 3) 先 solo 目標（用 40728 尊重偏好設定的 solo 模式），再關掉其他軌 → 中間沒有「全部都響」的空檔
    reaper.Main_OnCommand(40297,0) --unselect all tracks
    for tr in pairs(want) do reaper.SetTrackSelected(tr, true) end
    reaper.Main_OnCommand(40728,0) --solo selected tracks
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if want[tr] then
            -- parent 被 mute 也會沒聲音：暫時解除（放開時 SWS slot 一併還原）
            local p = reaper.GetParentTrack(tr)
            if p then reaper.SetMediaTrackInfo_Value(p, "B_MUTE", 0) end
        elseif reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") ~= 0 then
            reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
        end
    end

    -- 4) fixed lanes：滑鼠底下那軌只播滑鼠所在 lane，並記住原本播放的 lane
    if mouse_tr and want[mouse_tr] then
        for i = 0, api.gtv(mouse_tr,"I_NUMFIXEDLANES") - 1 do
            if api.gtv(mouse_tr,"C_LANEPLAYS:"..i) == 1 then
                api.save(EXT, 'last mouse track', api.tid(mouse_tr), false)
                api.save(EXT, 'last mouse track lane', i+1, false)
                break
            end
        end
        api.cmd(42478,0) -- Play only lane under mouse
    end

    r.RestoreTracks(sel)
    reaper.PreventUIRefresh(-1)

    -- 5) solo 都設好才開始播
    local P = reaper.GetPlayState()
    local E = reaper.GetCursorPosition()
    local p = razor_min or reaper.BR_PositionAtMouseCursor(false)
    p = (p ~= -1 and p) or E
    if P == 0 then
        reaper.SetEditCurPos(p,false,false)
        reaper.Main_OnCommand(1007,0)--play
    else
        reaper.SetEditCurPos(p,false,true)
    end
    reaper.SetEditCurPos(E,false,false)

    api.save(EXT,"state",1,false)
    api.save(EXT,"time",now+first_grace,false)
    WaitRelease(P)
