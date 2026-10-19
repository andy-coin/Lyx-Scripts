  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  
  local function main()
      
      local tr,new_tr
      tr=api.gst(0,0) or api.gt(0,0)

      api.cmd(api.name("_S&M_ADD_TRTEMPLATE4"),0)--insert track template, slot 4
      
      new_tr=api.gst(0,0)

      r.SameTCPH(new_tr,tr)
        
  end
  
  if reaper.NamedCommandLookup("_S&M_ADD_TRTEMPLATE1") == 0 then
      reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0)
      return
  end
  local track_n = reaper.CountTracks(0)
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Create acoustic guitar track",-1)
  if reaper.CountTracks(0) == track_n then
      reaper.MB("Nothing was inserted: SWS track template slot 4 is empty.\nAssign a track template to slot 4 in Extensions > Resources (Track templates).","Lyx Scripts",0)
  end

