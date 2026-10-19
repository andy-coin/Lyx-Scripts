    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    --------------------------------------------------------------------------------

    local function AdjustTracks()

        -- Hide Tracks
        local track_states = ''
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local track_guid = reaper.GetTrackGUID(track)
    
            local visible = tostring(api.gtv(track, 'B_SHOWINMIXER'))
            visible = visible:gsub('(.)%..', '%1', 1)
    
            api.stv(track, 'B_SHOWINMIXER', 0)
    
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            local _, e = chunk:find('\nBUSCOMP %d %d')
            local buscomp = chunk:sub(e, e)
            if  buscomp == '1' then
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 0', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
    
            track_states = track_states .. track_guid .. visible .. buscomp .. '\n'
    
        end
        reaper.SetProjExtState(0,"Side Mixer",'track_states', track_states)
        reaper.TrackList_AdjustWindows(false)

    end
    
    local function RestoreTracks()

        -- Set master send region scales
        local master = reaper.GetMasterTrack(0)

        -- Restore track states
        local _, states = reaper.GetProjExtState(0, "Side Mixer", 'track_states')
        if  states ~= '' then
            for i = 0, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                local track_guid = reaper.GetTrackGUID(track)
    
                local _, guid_end = states:find(track_guid, 0, true)
                if  guid_end then
                    local visible = tonumber(states:sub(guid_end + 1,guid_end + 1))
                    visible = visible or 1
                    api.stv(track, 'B_SHOWINMIXER', visible)
    
                    local buscomp = states:sub(guid_end + 2, guid_end + 2)
                    if  buscomp == '1' then
                        local _, chunk = reaper.GetTrackStateChunk(track, '')
                        chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 1', 1)
                        reaper.SetTrackStateChunk(track, chunk)
                    end
                else
                    api.stv(track, 'B_SHOWINMIXER', 1)
                end
            end
        end
        reaper.SetProjExtState(0, "Side Mixer", 'track_states', '')
        reaper.TrackList_AdjustWindows(false)

    end
    
    local function FallBack()-- Select first track if no track selected

        local sel_track = api.gst(0,0)
        if  not sel_track and api.ct(0) > 0 then
            sel_track = api.gt(0,0)
            reaper.SetCursorContext(0)
            reaper.SetTrackSelected(sel_track,true)
            reaper.SetCursorContext(0)
            api.stv(sel_track, 'B_SHOWINMIXER', 1)
            reaper.TrackList_AdjustWindows(false)
            reaper.UpdateArrange()
        end

    end
    
    local function Exit()

        -- Restore tracks for all projects
        local curr_proj, fn = reaper.EnumProjects( -1, '')
        if  not reaper.ValidatePtr(curr_proj, 'ReaProject*') then
            return
        end
        local i = 0
        local proj = reaper.EnumProjects(i)
        
        while reaper.ValidatePtr(proj, 'ReaProject*') do
            reaper.SelectProjectInstance(proj)
            RestoreTracks()
            i = i + 1
            proj = reaper.EnumProjects(i)
        end
        
        if  reaper.ValidatePtr(curr_proj, 'ReaProject*') then
            reaper.SelectProjectInstance(curr_proj)
        end

    end
    
    local function init()

        AdjustTracks()
        FallBack()

        local proj_old
        local file_name_old
        local old_sel_track
        local track_cnt_old = -1

    end

    local function Main()

        -- Tab change
        local proj_new, file_name_new = reaper.EnumProjects( -1, '')
        if  proj_old ~= proj_new or file_name_old ~= file_name_new then
            proj_old = proj_new
            file_name_old = file_name_new
            local _, states = reaper.GetProjExtState(0, "Side Mixer", 'track_states')
            if  states == '' then
                AdjustTracks()
            end
            FallBack()
        end
    
        local new_sel_track = api.gst(0,0)
    
        -- Track count change
        local track_cnt_new = api.ct(0)

        if  track_cnt_old ~= track_cnt_new then
            track_cnt_old = track_cnt_new
            local _, states = reaper.GetProjExtState(0, "Side Mixer", 'track_states')
            for abi = 1,api.ct(0) do
                local track = reaper.GetTrack(0,abi-1)
                local track_guid = reaper.GetTrackGUID(track)
    
                local visible = api.gtv(track,'B_SHOWINMIXER')
                -- Append new tracks
                if visible and track ~= old_sel_track then
                    states = states .. track_guid .. visible .. '\n'
                    api.stv(track, 'B_SHOWINMIXER', 0)
                end
            end
            reaper.SetProjExtState(0, "Side Mixer", 'track_states', states)
    
            if  not new_sel_track and track_cnt_new > 0 then
                local track_first = reaper.GetTrack(0, track_cnt_new - 1)
                reaper.SetCursorContext(0)
                reaper.SetTrackSelected(track_first, true)
                reaper.SetCursorContext(0)
                api.stv(track_first, 'B_SHOWINMIXER', 1)
                old_sel_track = track_first
            end

            reaper.TrackList_AdjustWindows(false)
            reaper.UpdateArrange()
        end
        -- Track selection change
        if new_sel_track and new_sel_track ~= old_sel_track then
            api.stv(new_sel_track, 'B_SHOWINMIXER', 1)
            if  old_sel_track and reaper.ValidatePtr(old_sel_track, 'MediaTrack*') then
                api.stv(old_sel_track, 'B_SHOWINMIXER', 0)
            end
            reaper.TrackList_AdjustWindows(false)
            reaper.UpdateArrange()
            old_sel_track = new_sel_track
        end

        reaper.defer(Main)
    end
    
    reaper.defer(init)
    reaper.defer(Main)
    reaper.atexit(RestoreTracks)
    --reaper.atexit(Exit)
