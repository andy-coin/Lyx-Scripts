    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        local editor = api.M()

        local cursor_pos = api.gec()
        local takes_info = {}

        -- Phase 1: collect selected pitches and cursor ppq per take
        local tk_idx = 0
        local time = api.now()
        local timeout = 3

        while (api.now() - time < timeout) do
            local tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)
            if not tk then break end

            local note = reaper.MIDI_EnumSelNotes(tk, -1)
            local cc   = reaper.MIDI_EnumSelCC(tk, -1)

            if note == -1 and cc == -1 then goto NEXT end

            if note ~= -1 then
                local pitches = {}
                local ni = note
                while ni ~= -1 do
                    local _, _, _, _, _, _, pitch = reaper.MIDI_GetNote(tk, ni)
                    pitches[pitch] = true
                    ni = reaper.MIDI_EnumSelNotes(tk, ni)
                end
                local cursor_ppq = reaper.MIDI_GetPPQPosFromProjTime(tk, cursor_pos)
                takes_info[#takes_info+1] = { tk=tk, pitches=pitches, cursor_ppq=cursor_ppq }

                reaper.MIDIEditor_OnCommand(editor, 40046)
            end

            ::NEXT::
            tk_idx = tk_idx + 1
        end

        -- Phase 2: deselect left parts, select right parts (notes starting at cursor)
        for _, info in ipairs(takes_info) do
            local tk, cursor_ppq, pitches = info.tk, info.cursor_ppq, info.pitches
            local tol = 1

            local _, note_count = reaper.MIDI_CountEvts(tk)
            for i = 0, note_count - 1 do
                local retval, sel, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(tk, i)
                if retval then
                    local is_right = math.abs(startppq - cursor_ppq) <= tol and pitches[pitch]
                    if sel and not is_right then
                        reaper.MIDI_SetNote(tk, i, false, muted, startppq, endppq, chan, pitch, vel, true)
                    elseif is_right then
                        reaper.MIDI_SetNote(tk, i, true, muted, startppq, endppq, chan, pitch, vel, true)
                    end
                end
            end
            reaper.MIDI_Sort(tk)
        end

    end

    main()
