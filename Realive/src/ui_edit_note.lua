-- ui_edit_note.lua — Edit panel: Notes tab
-- 顯示+外部編輯（osascript） -- display + native dialog edit

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

        -- 工具列：右對齊三個按鈕
        local total_btn_w = btn_sz * 3 + btn_gap * 2
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

        -- / Edit button — opens native osascript dialog (async)
        local is_pending = popup.notes_pending ~= nil
        if nt_btn("##nt_edit", "✎", is_pending and "Waiting..." or "Edit notes",
          is_pending and FUNC.rgba(60,60,30) or FUNC.rgba(40,60,40),
          FUNC.rgba(55,90,55), FUNC.rgba(70,120,70)) and not is_pending then
          local cur = not multi and (c.notes or "") or ""
          local tmp_in   = "/tmp/_realive_notes_in.txt"
          local tmp_scpt = "/tmp/_realive_notes.scpt"
          -- 保證至少20行高度 -- ensure at least 20 lines in dialog
          local padded = cur
          local line_count = 1
          for _ in cur:gmatch("\n") do line_count = line_count + 1 end
          if line_count < 20 then padded = cur .. string.rep("\n", 20 - line_count) end
          local fi = io.open(tmp_in, "w"); if fi then fi:write(padded); fi:close() end
          -- 記住要套用的 cue ids -- capture cue ids for async apply
          local ids = {}
          for _, si in ipairs(valid) do ids[#ids+1] = cues[si].id end
          popup.notes_pending = {cue_ids = ids}
          -- 刪除舊的 output 以免誤判 -- remove stale output
          os.remove(tmp_out)
          -- AppleScript: 結果寫入檔案而非 stdout -- write result to file instead of stdout
          local title = ("Cue " .. (c.cue_number or "?") .. " - " .. ((c.name ~= "" and c.name) or FUNC.tr_name(c.track_idx) or "Untitled")):gsub('"', '\\"')
          -- 輔助 script：延遲送 Cmd+Down 把游標移到文末、取消全選 -- helper: deselect after dialog appears
          local desel_scpt = '/tmp/_realive_notes_desel.scpt'
          local ds = table.concat({
            'delay 0.05',
            'tell application "System Events"',
            '  key code 126 using command down', -- Cmd+Up = move to top
            'end tell'
          }, '\n')
          local df = io.open(desel_scpt, "w"); if df then df:write(ds); df:close() end
          os.execute("osascript " .. desel_scpt .. " &")
          local scpt = table.concat({
            'try',
            '  set def to read POSIX file "' .. tmp_in .. '" as \xC2\xABclass utf8\xC2\xBB',
            'on error',
            '  set def to ""',
            'end try',
            'try',
            '  set r to text returned of (display dialog "Notes :" default answer def with title "' .. title .. '" buttons {"Cancel", "OK"} default button "OK")',
            '  set f to open for access POSIX file "' .. tmp_out .. '" with write permission',
            '  set eof f to 0',
            '  write r to f as \xC2\xABclass utf8\xC2\xBB',
            '  close access f',
            'on error',
            '  set f to open for access POSIX file "' .. tmp_out .. '" with write permission',
            '  set eof f to 0',
            '  write "__RLCXL__" to f',
            '  close access f',
            'end try'
          }, '\n')
          local sf = io.open(tmp_scpt, "w"); if sf then sf:write(scpt); sf:close() end
          os.execute("osascript " .. tmp_scpt .. " &")
        end

        ImGui.SameLine(ctx, 0, btn_gap)

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
        ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg(), FUNC.rgba(15,15,15,150))
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
end
