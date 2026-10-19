  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
  package.path = package.path..";"..script_path.."?.lua"
  local L=require("_lib._Lyx_HOME")
  if not L.Need("SWS") then return end

  r=reaper
  
  local function main()
      
      E=reaper.MIDIEditor_GetActive()
      if not E then return end
      win,seg,detail=reaper.BR_GetMouseCursorContext()
      if win~="midi_editor" then return end
      
      if seg~="cc_lane" then
         reaper.MIDIEditor_OnCommand(E,40010)
      else
         cmd=L.ScriptID("MPL Scripts/MIDI editor/mpl_Copy selected CC.lua", 32060)
         if cmd~=0 then reaper.MIDIEditor_OnCommand(E,cmd) end
      end
  end
  
  main()
