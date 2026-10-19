    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -- notes selected : split the selected notes that cross the mouse position
    -- nothing selected: split every note that crosses the mouse position
    function SplitNotes()

        local midieditor = reaper.MIDIEditor_GetActive()
        if midieditor == nil then return end

        local take = reaper.MIDIEditor_GetTake(midieditor)
        if take == nil then return end

        api.mcw()
        local mouse_cursor = reaper.MIDI_GetPPQPosFromProjTime(take, api.mcp())

        local _, note_cnt = reaper.MIDI_CountEvts(take)
        local only_sel = reaper.MIDI_EnumSelNotes(take, -1) ~= -1
        local notes = {}

        for abi = 1, note_cnt do
            local _, sel, muted, start, ending, chan, pitch, vel = reaper.MIDI_GetNote(take, abi-1)
            if  sel or not only_sel then
                if  start < mouse_cursor and mouse_cursor < ending then
                    reaper.MIDI_SetNote(take, abi-1, not only_sel and sel, muted, start, mouse_cursor, chan, pitch, vel, true)
                    notes[#notes+1] = {mute = muted, ending = ending, chan = chan, pitch = pitch, vel = vel}
                elseif only_sel then
                    reaper.MIDI_SetNote(take, abi-1, false, nil, nil, nil, nil, nil, nil, true)
                end
            end
        end

        -- right halves: selected when splitting a selection, so the next action keeps working on them
        for _, note in ipairs(notes) do
            reaper.MIDI_InsertNote(take, only_sel, note.mute, mouse_cursor, note.ending, note.chan, note.pitch, note.vel, true)
        end

        reaper.MIDI_Sort(take)

    end

    script_title = "Split notes at mouse cursor"

    reaper.Undo_BeginBlock()
    SplitNotes()
    reaper.Undo_EndBlock(script_title, -1)
