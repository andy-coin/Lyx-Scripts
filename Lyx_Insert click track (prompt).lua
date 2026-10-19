--[[
    Lyx_Insert click track (prompt)

    在時間選取範圍（沒有選取就用整個專案長度）插入一軌 Click。 / Inserts a click track over the time selection (whole project if none).

    對話框欄位 / Dialog fields
      double_or_half : x1 = 每拍一下，x2 = 每拍兩下，x0.5 或 /2 = 兩拍一下 / x1 = one click per beat, x2 = two per beat, x0.5 or /2 = one every two beats
      Pattern        : ts / time signature = 依拍號，A = 每小節第一拍，B = 其他拍 / ts = follow the time signature, A = first beat of the bar, B = other beats
                       或輸入字母序列（例如 ABBB、ABAC），依序循環，每個字母一個音色 / or a letter sequence (e.g. ABBB, ABAC) looped in order, one sound per letter
      Click sound    : n      = 用上次存的音色 / use the last saved sound
                       y      = 重新選擇音色檔 / pick a sound file again
                       custom = 輸入參數產生合成音 / synthesize a click from parameters
                       reaper = 用 SWS 的 click track（忽略其他欄位） / use the SWS click track (other fields ignored)
      Track position : top / bottom / current / 數字（插在第幾軌） / or a number (insert at that track)

    原始版本備份在 "Lyx_Insert click track (prompt).lua.bak" / original version backed up in "Lyx_Insert click track (prompt).lua.bak"
]]

    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    -----CUSTOM-----
    local primary_vol   = 0.9 -- 每小節第一下的音量 0~1 / volume of the first beat of each bar, 0~1
    local secondary_vol = 0.7 -- 其他拍的音量 0~1 / volume of the other beats, 0~1
    local patient       = 3   -- 最長處理秒數，超過就停止 / max processing time in seconds, stops after that

    local EXT            = "Click Track"
    local FILE_EXT       = "*.wav; *.aiff; *.mp3; *.m4a; *.flac"
    local DEFAULT_ANSWER = "x1,time signature,n,bottom"
    local DEFAULT_CUSTOM = "2500,18,2,2,24"

    local function oops(message)
        reaper.ShowMessageBox(message, "Oops...>_<", 0)
    end

    local function trim(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    --------------------------
    ---------SOUNDS-----------
    --------------------------
    -- how: "saved" = 上次存的檔案（不存在就詢問）, "choose" = 重新選檔, "custom" = 產生合成音 / "saved" = last saved file (asks if missing), "choose" = pick again, "custom" = synthesize
    -- 回傳音色檔路徑；取消則回傳 nil / returns the sound file path; nil when cancelled
    local function get_sound(letter, how)

        if  how == "custom" then
            local key  = "Tmp Sound_" .. letter
            local last = api.load(EXT, key)

            local ok, csv = r.GetUserInputs("Custom click sound [" .. letter .. "]", 5,
                "frequency, ms, channel, intensity (1 - 10), bit, extrawidth=60",
                (#last > 0 and last) or DEFAULT_CUSTOM)

            if not ok then return end

            local frequency, ms, channel, intensity, bit = csv:match("^(.*),(.*),(.*),(.*),(.*)$")
            if not frequency then oops("Custom click sound needs 5 values") return end

            local file = r.GenerateWave(frequency, ms, channel, intensity, bit)
            if not file then return end

            api.save(EXT, key, csv, true)
            return file
        end

        local key = "Click Sound_" .. letter

        if  how == "saved" then
            local file = api.load(EXT, key)
            if reaper.file_exists(file) then return file end
            if  reaper.ShowMessageBox("Click_" .. letter .. " is missing!\nSelect new one?", "Click sound missing...>_<", 4) ~= 6 then
                return
            end
        end

        local ok, file = reaper.GetUserFileNameForRead("", "Choose click_" .. letter .. "'s sound:", FILE_EXT)
        if not ok then return end

        api.save(EXT, key, file, true)
        return file
    end

    --------------------------
    ---------PROMPT-----------
    --------------------------
    -- "x2" / "2" -> 2,  "x0.5" / "/2" / "1/2" -> 0.5
    local function parse_rate(s)
        s = s:gsub("%s", ""):gsub("^[xX%*]", "")
        local a, b = s:match("^(%d*%.?%d*)/(%d+%.?%d*)$")
        local n
        if  a then
            n = (tonumber(a) or 1) / tonumber(b)
        else
            n = tonumber(s)
        end
        return (n and n > 0) and n or nil
    end

    -- 回傳 InsertTrackAtIndex 用的 index（0 起算） / returns the index for InsertTrackAtIndex (0-based)
    local function parse_position(s)
        local tr_n = reaper.CountTracks(0)
        local n = tonumber(s)

        if  n then
            return math.max(0, math.min(math.floor(n) - 1, tr_n))
        elseif s == "top" then
            return 0
        elseif s == "current" then
            local tr = reaper.GetLastTouchedTrack() or reaper.GetSelectedTrack(0, reaper.CountSelectedTracks(0) - 1)
            if not tr then return tr_n end
            return math.max(0, math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1)
        end

        return tr_n -- bottom
    end

    -- 回傳設定 table；取消或輸入錯誤回傳 nil / returns the settings table; nil on cancel or bad input
    local function prompt()

        local last = api.load(EXT, "Last answer")

        local ok, csv = r.GetUserInputs("Insert click track", 4,
            "double_or_half ( x2 / x0.5 ):,Pattern ( ts / ABBB ):,Click sound ( n / y / custom / reaper ):,Track position ( top / bottom / current / 1~ ):,extrawidth=60",
            (#last > 0 and last) or DEFAULT_ANSWER)

        if not ok then return end

        local rate_s, pattern_s, sound_s, position_s = csv:match("^([^,]*),([^,]*),([^,]*),([^,]*)$")
        if not rate_s then oops("Fields can't contain commas") return end

        local sound = trim(sound_s):lower()

        -- 記住這次的輸入；但 "y"（重新選檔）不保留，否則每次都要重選 / remember this input, except "y" (pick again), or it would ask every time
        local keep_sound = (sound == "y" or sound == "yes") and "n" or sound_s
        api.save(EXT, "Last answer", table.concat({rate_s, pattern_s, keep_sound, position_s}, ","), true)

        local opt = { idx = parse_position(trim(position_s):lower()) }

        if  sound == "reaper" then
            opt.system = true
            return opt
        end

        opt.rate = parse_rate(rate_s)
        if not opt.rate then oops("double_or_half: type something like x1, x2, x0.5 or /2") return end

        local letters
        local pattern = trim(pattern_s):lower()

        if  pattern == "" or pattern == "ts" or pattern == "time signature" then
            letters = {"A", "B"}
        else
            opt.pattern = {}
            for letter in pattern_s:gmatch("%a") do
                opt.pattern[#opt.pattern + 1] = letter:upper()
            end
            if #opt.pattern == 0 then oops("Pattern: type ts or a letter sequence (e.g. ABBB)") return end
            letters = opt.pattern
        end

        local how = ((sound == "y" or sound == "yes") and "choose")
                 or ((sound == "custom" or sound == "c") and "custom")
                 or "saved"

        opt.sounds = {}
        for _, letter in ipairs(letters) do
            if  not opt.sounds[letter] then
                opt.sounds[letter] = get_sound(letter, how)
                if not opt.sounds[letter] then return end
            end
        end

        return opt
    end

    --------------------------
    -------BUILD CLICK--------
    --------------------------
    local function measure_at(time)
        local _, measure = reaper.TimeMap2_timeToBeats(0, time)
        return measure
    end

    local function add_click(track, file, pos, vol)
        local item = reaper.AddMediaItemToTrack(track)
        local take = reaper.AddTakeToMediaItem(item)
        local src  = reaper.PCM_Source_CreateFromFile(file)
        reaper.SetMediaItemTake_Source(take, src)
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", (reaper.GetMediaSourceLength(src)))
        reaper.SetMediaItemInfo_Value(item, "D_VOL", vol)
        return item
    end

    -- 從 first_m 到 last_m 小節逐拍放入 click，回傳 items 與是否在時限內完成 / place clicks beat by beat from bar first_m to last_m; returns the items and whether it finished in time
    local function build_clicks(track, first_m, last_m, opt)

        local items, step_i, start = {}, 0, api.now()

        for m = first_m, last_m do

            local _, qn, qn_end, _, div = reaper.TimeMap_GetMeasureInfo(0, m)
            local step  = 4 / div / opt.rate -- 每下 click 間隔幾個四分音符 / quarter notes between clicks
            local first = true

            while qn < qn_end - 1e-9 do

                local letter
                if  opt.pattern then
                    letter = opt.pattern[step_i % #opt.pattern + 1]
                    step_i = step_i + 1
                else
                    letter = first and "A" or "B"
                end

                items[#items + 1] = add_click(track, opt.sounds[letter],
                                              reaper.TimeMap_QNToTime_abs(0, qn),
                                              first and primary_vol or secondary_vol)
                first = false
                qn = qn + step
            end

            if (api.now() - start) > patient then return items, false end
        end

        return items, true
    end

    local function insert_system_click(opt, starttime, endtime)
        api.cmd(40289,0) -- unselect all items
        api.cmd(api.name('_SWS_AWINSERTCLICKTRK'),0)

        reaper.ApplyNudge(0, 1, 1, 1, starttime, false, 0)
        reaper.ApplyNudge(0, 1, 3, 1, endtime, false, 0)

        reaper.ReorderSelectedTracks(opt.idx + 1, 0)

        api.cmd(api.name("_S&M_SCROLL_ITEM"),0) -- vertical scroll to item
    end

    local function insert_click(opt, starttime, endtime)

        api.pur(1)

        reaper.InsertTrackAtIndex(opt.idx, false)
        local click_tr  = reaper.GetTrack(0, opt.idx)
        local neighbour = reaper.GetTrack(0, opt.idx + 1) or reaper.GetTrack(0, opt.idx - 1)
        reaper.GetSetMediaTrackInfo_String(click_tr, "P_NAME", "Click", true)

        local items, finished = build_clicks(click_tr, measure_at(starttime), measure_at(endtime), opt)

        -- glue 成一個 item，再裁到範圍 / glue into one item, then trim to the range
        api.cmd(40289,0) -- unselect all items
        for _, item in ipairs(items) do reaper.SetMediaItemSelected(item, true) end
        api.cmd(40362,0) -- glue items
        reaper.ApplyNudge(0, 1, 1, 1, starttime, false, 0)
        reaper.ApplyNudge(0, 1, 3, 1, endtime, false, 0)

        api.pur(-1)

        if neighbour then r.SameTCPH(click_tr, neighbour) end
        reaper.SetOnlyTrackSelected(click_tr)
        reaper.GetSet_LoopTimeRange2(0, true, false, starttime, endtime, false)

        api.cmd(api.name("_S&M_SCROLL_ITEM"),0) -- vertical scroll to item
        reaper.UpdateArrange()

        if not finished then
            oops("Took over " .. patient .. " s, the click track is only partly built.\nUse a shorter time selection, or raise patient in the script.")
        end
    end

    --------------------------
    -----------MAIN-----------
    --------------------------
    local function main()

        if api.gps(0) ~= 0 then BBB("Please stop playing") return end

        local starttime, endtime = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)

        if  endtime == starttime then
            starttime, endtime = r.GetProjectLength()
            if endtime == starttime then return end
        end

        if  api.gtc(41885) == 1 then -- Toggle framerate grid
            oops("Click track don't support framerate grid")
            return
        end

        local focus = reaper.JS_Window_GetFocus and reaper.JS_Window_GetFocus()

        local opt = prompt()
        if not opt then return end

        r.Undo("Insert click track", function()
            if  opt.system then
                insert_system_click(opt, starttime, endtime)
            else
                insert_click(opt, starttime, endtime)
            end
        end)

        if focus then reaper.JS_Window_SetFocus(focus) end
    end

    r.run(main)
