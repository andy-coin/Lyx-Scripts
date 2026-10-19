  
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
      
      local tr,new_tr
      tr=api.gst(0,0) or api.gt(0,0)

      api.cmd(api.name("_S&M_ADD_TRTEMPLATE4"),0)--insert track template 1
      
      new_tr=api.gst(0,0)

      r.SameTCPH(new_tr,tr)
        
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Create new MIDI track",-1)

