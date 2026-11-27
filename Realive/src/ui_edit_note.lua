-- ui_edit_note.lua — Edit panel: Notes tab
-- 顯示+外部編輯（osascript） -- display + native dialog edit

local NOTES_DLG = (debug.getinfo(1, "S").source:match("@(.+[/\\])") or "") .. "../tools/notes_dialog.js"

function FUNC.draw_edit_section_note(c, apply, multi, valid)
        -- SECTION: NOTES — 顯示+外部編輯（osascript）
        -- ═══════════════════════════════════════════════════════
        local note_text = not multi and (c.notes or "") or "—"
        local has_text  = note_text ~= "" and note_text ~= "—"
        local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
        local btn_sz  = FUNC.sz(20)
        local btn_gap = FUNC.sz(3)

        -- Helper: small icon button
        local function nt_btn(id, icon, tip, bg, bg_h, bg_a)
          local dl = ImGui.GetWindowDrawList(ctx)
          local bx, by = ImGui.GetCursorScreenPos(ctx)
          ImGui.InvisibleButton(ctx, id, btn_sz, btn_sz)
          local hov = ImGui.IsItemHovered(ctx)
          local act = ImGui.IsItemActive(ctx)
          local col = act and bg_a or hov and bg_h or bg
          ImGui.DrawList_AddRectFilled(dl, bx, by, bx+btn_sz, by+btn_sz, col, FUNC.sz(3))
          ImGui.PushFont(ctx, FONT, FUNC.sz(12))
          local tw, th = ImGui.CalcTextSize(ctx, icon, 0, 0)
          ImGui.DrawList_AddText(dl, bx+(btn_sz-tw)/2, by+(btn_sz-th)/2, FUNC.dim_c(C.text), icon)
          ImGui.PopFont(ctx)
          if hov then ImGui.SetTooltip(ctx, tip) end
          return ImGui.IsItemClicked(ctx)
        end

        -- 工具列：右對齊兩個按鈕（編輯改成點文字區）-- toolbar: 2 buttons right-aligned (edit = click text area)
        local total_btn_w = btn_sz * 2 + btn_gap
        ImGui.SetCursorPosX(ctx, avail_w - total_btn_w)

        -- 非同步 poll：檢查 osascript 結果 -- async poll: check for osascript result
        local tmp_out = "/tmp/_realive_notes_out.txt"
        if popup.notes_pending then
          local f = io.open(tmp_out, "r")
          if f then
            local result = f:read("*a"); f:close()
            os.remove(tmp_out)
            if not result:find("__RLCXL__", 1, true) then
              local new_text = result:gsub("\n+$", "")
              -- 套用到當初啟動時的 cue ids -- apply to cue ids captured at launch
              for _, cue in ipairs(cues) do
                for _, id in ipairs(popup.notes_pending.cue_ids) do
                  if cue.id == id then cue.notes = new_text end
                end
              end
              FUNC.save_cues()
            end
            popup.notes_pending = nil
          end
        end

        local is_pending = popup.notes_pending ~= nil

        -- ⎘ Copy button
        if nt_btn("##nt_copy", "\xE2\x8E\x98", "Copy to clipboard", FUNC.rgba(40,40,60), FUNC.rgba(55,55,90), FUNC.rgba(70,70,120)) and has_text then
          ImGui.SetClipboardText(ctx, note_text)
        end

        ImGui.SameLine(ctx, 0, btn_gap)

        -- × Delete button
        if nt_btn("##nt_del", "\xC3\x97", "Clear notes", FUNC.rgba(70,35,35), FUNC.rgba(100,45,45), FUNC.rgba(130,55,55)) and has_text then
          if multi then apply("notes", "") else c.notes = "" end
          FUNC.save_cues()
        end

        -- 顯示區（唯讀）
        ImGui.Dummy(ctx, 0, FUNC.sz(3))
        local toolbar_h = btn_sz + FUNC.sz(6)
        local disp_h = math.max(avail_h - toolbar_h - FUNC.sz(3), FUNC.sz(30))
        local nt_pad = FUNC.sz(6)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding(), nt_pad, nt_pad)
        ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), C.field)
        if ImGui.BeginChild(ctx, "##notes_disp", -nt_pad, disp_h, ImGui.ChildFlags_Borders()) then
          ImGui.PushFont(ctx, FONT, FUNC.sz(13))
          if not has_text then
            ImGui.PushStyleColor(ctx, ImGui.Col_Text(), FUNC.rgba(90,90,90))
            ImGui.TextWrapped(ctx, multi and "\xe2\x80\x94" or "")
            ImGui.PopStyleColor(ctx, 1)
          else
            -- 逐行渲染避免 TextWrapped 吃掉空行 -- render line by line to preserve blank lines
            for line in (note_text .. "\n"):gmatch("([^\n]*)\n") do
              ImGui.TextWrapped(ctx, line == "" and " " or line)
            end
          end
          ImGui.PopFont(ctx)
          ImGui.EndChild(ctx)
        end
        ImGui.PopStyleColor(ctx, 1)
        ImGui.PopStyleVar(ctx, 1)
        local dx1, dy1 = ImGui.GetItemRectMin(ctx)
        local dx2, dy2 = ImGui.GetItemRectMax(ctx)

        -- 點文字區 = 開始編輯 -- click the text area to edit
        local want_edit = false
        if ImGui.IsMouseHoveringRect(ctx, dx1, dy1, dx2, dy2) and ImGui.IsWindowHovered(ctx, ImGui.HoveredFlags_ChildWindows()) then
          if not is_pending then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_TextInput()) end
          want_edit = ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left())
        end
        -- 編輯框程序意外消失（當掉）時，再點文字區可解除卡住 -- recover if the editor process died
        if want_edit and is_pending then
          local ph = io.popen("pgrep -f notes_dialog.js")
          local alive = ph and ph:read("*a") or ""; if ph then ph:close() end
          if alive == "" then popup.notes_pending = nil; is_pending = false else want_edit = false end
        end

        -- 開啟原生編輯框（tools/notes_dialog.js），蓋在顯示區正上方、同大小
        -- launch native editor overlaid exactly on the display area: IME works, Return = newline, Cmd+Return = save
        if want_edit and not is_pending then
          local cur = not multi and (c.notes or "") or ""
          local tmp_in = "/tmp/_realive_notes_in.txt"
          local fi = io.open(tmp_in, "w"); if fi then fi:write(cur); fi:close() end
          -- 記住要套用的 cue ids -- capture cue ids for async apply
          local ids = {}
          for _, si in ipairs(valid) do ids[#ids+1] = cues[si].id end
          popup.notes_pending = {cue_ids = ids}
          os.remove(tmp_out)  -- 刪除舊的 output 以免誤判 -- remove stale output
          -- ImGui 座標（左上原點）→ macOS 原生座標（左下原點），取顯示區左下角
          -- ImGui coords (top-left origin) → native Cocoa coords (bottom-left origin)
          -- 四邊內縮，留出 Notes 原本的外框 -- inset to keep the Notes border visible
          local bw = FUNC.sz(2)
          dx1, dy1, dx2, dy2 = dx1 + bw, dy1 + bw, dx2 - bw, dy2 - bw
          -- 裁到 edit 面板可見範圍（水平捲動 / 視窗邊被切掉的部分不露出）-- clip to the visible edit area
          local cr = FUNC.ep_clip
          if cr then
            dx1, dy1 = math.max(dx1, cr[1]), math.max(dy1, cr[2])
            dx2, dy2 = math.min(dx2, cr[3]), math.min(dy2, cr[4])
          end
          if dx2 - dx1 < FUNC.sz(40) or dy2 - dy1 < FUNC.sz(20) then  -- 幾乎整塊被裁掉：不開 -- mostly hidden: don't open
            popup.notes_pending = nil
            return
          end
          local nx, ny = ImGui.PointConvertNative(ctx, dx1, dy2, true)
          local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
          os.execute(string.format("osascript -l JavaScript %s %s %s %d %d %d %d %d &",
            shq(NOTES_DLG), shq(tmp_in), shq(tmp_out),
            math.floor(nx), math.floor(ny), math.floor(dx2 - dx1), math.floor(dy2 - dy1), math.floor(FUNC.sz(13))))
        end
end
