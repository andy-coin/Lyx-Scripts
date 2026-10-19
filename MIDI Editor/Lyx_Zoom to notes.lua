    -- Zoom the active MIDI editor horizontally and vertically to the notes:
    -- the selected notes if any are selected, otherwise all notes. Note selection is left untouched.
    -- Run it as an action, or load it from another script:
    --     local ZoomToNotes = require("MIDI Editor/Lyx_Zoom to notes")   -- returns the function, does not run
    --     ZoomToNotes(editor)

    local function ZoomToNotes(editor)

        editor = editor or reaper.MIDIEditor_GetActive()
        if not editor then return end

        -- pitch range of the selected notes, or of all notes when none is selected
        local low, high, LOW, HIGH, has_sel = 128, -1, 128, -1, false
        local i = 0
        local take = reaper.MIDIEditor_EnumTakes(editor, i, true)
        while take do
            local _, cnt = reaper.MIDI_CountEvts(take)
            for n = 0, cnt-1 do
                local _, sel, _, _, _, _, pitch = reaper.MIDI_GetNote(take, n)
                LOW, HIGH = math.min(LOW, pitch), math.max(HIGH, pitch)
                if sel then
                    has_sel = true
                    low, high = math.min(low, pitch), math.max(high, pitch)
                end
            end
            i = i + 1
            take = reaper.MIDIEditor_EnumTakes(editor, i, true)
        end

        --horizontal fit (native)
        reaper.MIDIEditor_OnCommand(editor, has_sel and 40725 or 40466) -- View: Zoom to selected notes / View: Zoom to content
        if HIGH < 0 then return end -- no notes at all
        if not has_sel then low, high = LOW, HIGH end

        --vertical fit: zoom fully out, then step in until the pitch range (+ margin) still fits
        reaper.MIDIEditor_SetSetting_int(editor, 'active_note_row', math.floor((low+high)/2))
        for _ = 1, 60 do reaper.MIDIEditor_OnCommand(editor, 40112) end -- View: Zoom out vertically
        local range = high - low + 10
        local ZoomChart = {112,94,80,70,63,56,51,47,43,40,37,35,33,31,29,28,26,25,24,23,22,21,20,19,18,0} -- visible rows per zoom-in step
        for step = 2, #ZoomChart do
            if range > ZoomChart[step] then
                for _ = 1, math.min(step-1, 17) do reaper.MIDIEditor_OnCommand(editor, 40111) end -- View: Zoom in vertically
                break
            end
        end
    end

    if ... then return ZoomToNotes end -- loaded with require: hand back the function only

    ZoomToNotes()
    reaper.defer(function() end) -- no undo point
