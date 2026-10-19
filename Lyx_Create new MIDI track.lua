    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
        
    if reaper.NamedCommandLookup("_S&M_ADD_TRTEMPLATE1") == 0 then
        reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0)
        return
    end
    local track_n = reaper.CountTracks(0)
    reaper.Undo_BeginBlock()
    r.ImportTrackTemplate(1)
    reaper.Undo_EndBlock("Create new MIDI track",-1)
    if reaper.CountTracks(0) == track_n then
        reaper.MB("Nothing was inserted: SWS track template slot 1 is empty.\nAssign a track template to slot 1 in Extensions > Resources (Track templates).","Lyx Scripts",0)
    end
