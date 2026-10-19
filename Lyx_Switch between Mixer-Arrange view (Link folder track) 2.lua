  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local L=require("_lib._Lyx_HOME")
  r=reaper

  -----CUSTOM-----
  -- MCP layouts from your theme; leave "" to keep each track's own layout
  MIXER_LAYOUT     = "c2 -- FX Rack_EX"
  INSPECTOR_LAYOUT = "z1 -- Dead Ringer Colonial 4000XL PRO_EX"
  ----------------
  
  ---------------------------------------------------
  local function RestoreHidesInMCP()
  
      for abi=1,reaper.CountTracks(0) do
          local tr=reaper.GetTrack(0,abi-1)
          if reaper.IsTrackVisible(tr,false) then
             reaper.SetMediaTrackInfo_Value(tr,'B_SHOWINMIXER',1)
          else
             reaper.SetMediaTrackInfo_Value(tr,'B_SHOWINMIXER',0)
          end
      end 
      reaper.TrackList_AdjustWindows(false)
  end
  
  --------------
  local function ChangeMixer(layout)
  
      if layout == "" then return end
      for abi=1,reaper.CountTracks(0) do
          tr=reaper.GetTrack(0,abi-1)
          reaper.GetSetMediaTrackInfo_String(tr,"P_MCP_LAYOUT",layout,true)
      end
  
  end
 
  local function main()
      
      local hwnd,midi_editor,position,mixer,dock_state
      
      cmd=L.ScriptID("FTC Tools/Various/FTC_Side Mixer.lua")
      if reaper.GetToggleCommandState(40078) ~= 1 then --show mixer (toggle state, not the English window title)
         reaper.Main_OnCommand(40078,0)
      end
      mixer = reaper.JS_Window_Find("Mixer",true) or reaper.JS_Window_FindTop("Mixer",false)
      if not mixer then return end

      dock_state = reaper.DockIsChildOfDock(mixer,left)
      reaper.DockWindowRemove(mixer, "Mixer")
      
      if dock_state==7 then --change to mixer
         position=0         --left
         layout=MIXER_LAYOUT
      else                  --change to inspector
         position=7         --bottom
         layout=INSPECTOR_LAYOUT
         if cmd~=0 then reaper.Main_OnCommand(cmd,0) end--side mixer 
         RestoreHidesInMCP()
      end--]]
      
      ChangeMixer(layout)
      reaper.DockWindowAdd(mixer, "Mixer", position, true)
      reaper.DockWindowRefresh()

      if position==0 and cmd~=0 then reaper.Main_OnCommand(cmd,0) end--side mixer 
  
  end
  
  reaper.defer(main)
  
  
