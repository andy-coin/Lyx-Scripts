  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  reaper.Undo_BeginBlock()
  r.ImportTrackTemplate(4)
  reaper.Undo_EndBlock("Create new MIDI track",-1)

