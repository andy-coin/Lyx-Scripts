local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r = require("_Lyx_HOME")

local NS          = "holding solo"
local KEY_ACTIVE  = "state"
local KEY_TIME    = "time"
local TIMEOUT     = 0.3
local GRACE       = 0.3
local SOLO_MODE   = 2
local SLOT_SAVE    = api.name("_BR_SAVE_SOLO_MUTE_ALL_TRACKS_SLOT_3")
local SLOT_RESTORE = api.name("_BR_RESTORE_SOLO_MUTE_ALL_TRACKS_SLOT_3")
local CMD_STOP = 1016
local CMD_PLAY = 1007

---------------
local function collect_targets()
    
    api.mcw()
    local start_pos = (razor and razor_data.min) or api.mcp()
    
    local me = reaper.MIDIEditor_GetActive()
    if me then
        local take = reaper.MIDIEditor_GetTake(me)
        if take then
            local tr = reaper.GetMediaItemTake_Track(take)
            return { tr }, start_pos
        end
    end

    local razor, razor_data = r.GetRazorEdits(false)
    local mouse_tr = reaper.BR_TrackAtMouseCursor()

    local tracks
    if razor then
        tracks = razor_data.track
    elseif api.cst(0) > 1 then
        tracks = r.SaveTracks()
    else
        api.cmd(api.name('_BR_CONT_PLAY_MOUSE_SOLO_ITEM'),0)
        return
    end

    return tracks, start_pos
end

--------------
local function build_solo_set(tracks)

    for i = 1, #tracks do
        local tr = tracks[i]
        local parent = r.HaveParent(tr)
        while parent do
            tracks[#tracks+1] = parent
            parent = r.HaveParent(parent)
        end
    end

    return tracks
end

--------------
local function apply_solo(solo_set)
    
    for i = 1, #solo_set do
        local tr = solo_set[i]
        api.stv(tr, 'I_SOLO', SOLO_MODE )
    end

end

--------------
local function watch_and_restore(was_playing)
    local raw = reaper.GetExtState(NS, KEY_TIME)
    local last = (raw ~= "" and tonumber(raw)) or reaper.time_precise()
    local now  = reaper.time_precise()

    if now - last <= TIMEOUT then
        reaper.defer(function() watch_and_restore(was_playing) end)
        return
    end

    api.cmd(api.name('_BR_TOGGLE_PLAY_MOUSE_SOLO_ITEM'),0)
    api.cmd(SLOT_RESTORE, 0)
    reaper.SetExtState(NS, KEY_ACTIVE, "0", false)
    reaper.DeleteExtState(NS, KEY_TIME, true)
end

--------------
local function enter_solo_mode(play_state, now)
    local tracks, start_pos = collect_targets()
    if not tracks then return end

    reaper.SetExtState(NS, KEY_ACTIVE, "1", false)
    reaper.SetExtState(NS, KEY_TIME, now + GRACE, false)

    api.cmd(api.name('_BR_TOGGLE_PLAY_MOUSE_SOLO_ITEM'),0)
    apply_solo(build_solo_set(tracks))

    watch_and_restore(play_state)
end

--------------
local function extend_solo_mode(now)
    reaper.SetExtState(NS, KEY_TIME, now, false)
end

--------------
local play_state = reaper.GetPlayState()
if play_state == 5 then return end

local is_active = reaper.GetExtState(NS, KEY_ACTIVE) == "1"
local now = reaper.time_precise()

if is_active then
    extend_solo_mode(now)
else
    api.cmd(SLOT_SAVE, 0)
    enter_solo_mode(play_state, now)
end
