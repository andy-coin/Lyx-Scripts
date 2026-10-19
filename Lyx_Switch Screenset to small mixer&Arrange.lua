  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  ---CUSTOM---
  -- MCP layout names below must exist in your current theme (these are from Andy's theme); edit them to match yours.
  
     ---mixer---
        layout_M="A -- 5 -- Svelte"
        position_M=1
        
     ---inspetor---
        layout_I="A -- 3 -- Auxiliary"
        position_I=0
  
  --------------
  local function ChangeMixer(layout)
  
      for abi=1,reaper.CountTracks(0) do
          tr=reaper.GetTrack(0,abi-1)
          reaper.GetSetMediaTrackInfo_String(tr,"P_MCP_LAYOUT",layout,true)
      end
  
  end
 
  local function ScrollMixer()
  
      local tr=reaper.GetSelectedTrack(0,0) or reaper.GetTrack(0,0)
      if not tr then return end

      local num=reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER")
      if num>=30 then
         tr=reaper.GetTrack(0,num-30)
      else
         tr=reaper.GetTrack(0,0)
      end
      reaper.SetMixerScroll(tr)
  
  end
  
  --------------
  local function main()
      
      local hwnd,midi_editor,position,mixer,dock_state
      
      if reaper.MIDIEditor_GetActive() then
         editor=r.ScriptID("Lyx Scripts/Lyx_Open item editor.lua")
         reaper.Main_OnCommand(editor,0)
      end
        
      mixer = reaper.JS_Window_Find("Mixer",true)
      
      if  not mixer then --show mixer
          reaper.Main_OnCommand(40078,0)
          mixer = reaper.JS_Window_Find("Mixer",true)
      end 
      
      if not mixer then
          reaper.MB("Mixer window not found (this script looks for a window titled \"Mixer\"; non-English language packs are not supported).","Lyx Scripts",0)
          return
      end
      
      dock_state = reaper.DockIsChildOfDock(mixer)
       
      --reaper.ShowConsoleMsg(dock_state)
      
      position=position_I
      layout=layout_M
      
      -- inspector → mixer
      if  dock_state==1 then        
          position=position_M   
          reaper.SetProjExtState(0,"Side Mixer","track_states","inspector")
      -- mixer → inspector
      elseif dock_state==7 then     
          for sun=1,api.ct(0) do
              local tr=api.gt(0,sun-1)
              _,layout=api.ts(tr,"P_MCP_LAYOUT","",false)
              if  layout~=layout_M then
                  ChangeMixer(layout_M)
                  return
              end
          end
          position=position_I
          layout=layout_I
          reaper.SetProjExtState(0,"Side Mixer","track_states","mixer")
      end
      
      reaper.DockWindowRemove(mixer, "Mixer")
      
      mixer = reaper.JS_Window_Find("Mixer",true)

      ChangeMixer(layout)

      reaper.DockWindowAdd(mixer,"Mixer",position,true)
      reaper.DockWindowRefresh(mixer)
      reaper.UpdateArrange()
      cmd=r.ScriptID("Lyx Scripts/Lyx_Side mixer.lua")
      api.cmd(cmd,0)--sidemixer
      ScrollMixer()
  end
        
  reaper.ClearConsole()
  main()
  reaper.defer(function() end)

  
