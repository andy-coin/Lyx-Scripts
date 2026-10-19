
  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  
  -----CUSTOM-----
  mode = 1
  
  --------------
  local function main()
  
          local editor,focus
          
          editor = reaper.MIDIEditor_GetActive()
          focus = r.IsMidiEditorFocus(editor)
          
          if  editor and focus then
          
              local take = api.Mgt(editor)
  
              if  take then
  
                  local track = reaper.GetMediaItemTake_Track(take)
  
                  api.cmd(40491,0)-- unarm all track recording
                  api.stv(track,"I_RECARM",1)
                  api.stv(track,"I_RECMON",1)
  
              end
  
          end
          
  end
  
  main()
  
  reaper.defer(function() end)
