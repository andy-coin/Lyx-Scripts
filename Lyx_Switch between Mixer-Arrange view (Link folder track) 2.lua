  
  r=reaper
  
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
  
      for abi=1,reaper.CountTracks(0) do
          tr=reaper.GetTrack(0,abi-1)
          reaper.GetSetMediaTrackInfo_String(tr,"P_MCP_LAYOUT",layout,true)
      end
  
  end
 
  local function main()
      
      local hwnd,midi_editor,position,mixer,dock_state
      
      if reaper.MIDIEditor_GetActive() then
         editor=reaper.NamedCommandLookup("_RS0396f993d9aaee64e106335c730ede2426fd1222")
         reaper.Main_OnCommand(editor,0)
      end
      
      cmd=reaper.NamedCommandLookup("_RSb1e93ac3761b4f57cc5a22940819794ffdac66ad")
      mixer = reaper.JS_Window_Find("Mixer",true)
      
      if not mixer then --show mixer
         reaper.Main_OnCommand(40078,0)
         mixer = reaper.JS_Window_Find("Mixer",true)
      end 
      
      dock_state = reaper.DockIsChildOfDock(mixer,left)
      reaper.DockWindowRemove(mixer, "Mixer")
      
      if dock_state==7 then --change to mixer
         position=0         --left
         layout="c2 -- FX Rack_EX"
      else                  --change to inspector
         position=7         --bottom
         layout="z1 -- Dead Ringer Colonial 4000XL PRO_EX"
         reaper.Main_OnCommand(cmd,0)--side mixer 
         RestoreHidesInMCP()
      end--]]
      
      ChangeMixer(layout)
      reaper.DockWindowAdd(mixer, "Mixer", position, true)
      reaper.DockWindowAdd(mixer, "Mixer", 0, true)
      reaper.DockWindowRefresh(hwnd)

      if position==0 then reaper.Main_OnCommand(cmd,0) end--side mixer 
  
  end
  
  reaper.defer(main)
  
  
