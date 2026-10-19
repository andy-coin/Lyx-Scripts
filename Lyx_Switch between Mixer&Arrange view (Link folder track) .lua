  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  
  ---CUSTOM---
  -- MCP layout names below must exist in your current theme (these are from Andy's theme); edit them to match yours.
  
     ---mixer--- 
        layout_M="A - Analog"
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

      local num=api.gtv(tr,"IP_TRACKNUMBER")
      if num>=14 then
         tr=reaper.GetTrack(0,num-14)
      else
         tr=reaper.GetTrack(0,0)
      end
      reaper.SetMixerScroll(tr)
  
  end
  
  local function toggle_folder_state(mode)
    
    
    if mode == 'save' then
        api.cmd(api.name('_SWS_SELFOLDSTARTS'),0)--select all folder
        --r.SaveTracks('Folder_Parents')
          local collapsed_state = {}
          for abi=1, api.cst(0) do
            local tr = api.gst(0, abi-1)
            collapsed_state[abi] = {guid = api.tid(tr), state = api.gtv(tr, 'I_FOLDERCOMPACT')}
          end
          collapsed_state = serialize(collapsed_state)
          api.save('toggle mixer', 'track folder state', collapsed_state, false)
    elseif mode == 'load' then
        local collapsed_state = api.load('toggle mixer', 'track folder state')
        if collapsed_state ~= '' then
            collapsed_state = unserialize(collapsed_state)
        end
        for abi = 1, #collapsed_state do
            local tr = api.idt(0, collapsed_state[abi].guid)
            if tr then 
                api.stv(tr, 'I_FOLDERCOMPACT', collapsed_state[abi].state)
            end
        end
        reaper.DeleteExtState('toggle mixer', 'track folder state', true)
      end
  end
  --------------
  local function main()
      
      local hwnd,midi_editor,position,mixer,dock_state
      
      if  reaper.MIDIEditor_GetActive() then
          open_editor=r.ScriptID("Lyx Scripts/Lyx_Open item editor.lua")
          reaper.Main_OnCommand(open_editor,0)
      end
        
      mixer = reaper.JS_Window_Find("Mixer",true)
      
      if not mixer then --show mixer
         reaper.Main_OnCommand(40078,0)
         mixer = reaper.JS_Window_Find("Mixer",true)
      end 
      
      if not mixer then
          reaper.MB("Mixer window not found (this script looks for a window titled \"Mixer\"; non-English language packs are not supported).","Lyx Scripts",0)
          return
      end
      
      dock_state = reaper.DockIsChildOfDock(mixer)
      
      reaper.DockWindowRemove(mixer, "Mixer")
      
      --msg(dock_state)

      position=position_I
      layout=layout_M
      
      -- inspector → mixer
      if  dock_state==1 or dock_state==2 then
          -- mixer
          position=position_M
          r.SaveTracks(true)
          toggle_folder_state('save')
          api.cmd(api.name('_SWS_UNCOLLAPSE'),0)   --Set selected folder(s) uncollapsed
          r.RestoreTracks(true)
          reaper.SetProjExtState(0,"Side Mixer","track_states","inspector")
          icon = 1
      -- mixer → inspector
      elseif dock_state==7 then
          position=position_I
          toggle_folder_state('load')
          layout=layout_I
          reaper.SetProjExtState(0,"Side Mixer","track_states","mixer")
          icon = 0
      end 
      
      mixer = reaper.JS_Window_Find("Mixer",true)

      ChangeMixer(layout)
      
      reaper.DockWindowAdd(mixer,"Mixer",position,true)
      reaper.DockWindowRefresh(mixer)
      reaper.UpdateArrange()
      api.cmd(41610,0)--master mixer
      --reaper.SetToggleCommandState(0,40903,icon)--show icon in mixer
      api.cmd(r.ScriptID("Lyx Scripts/Lyx_Side mixer.lua"),0)
      ScrollMixer()
  end
  
  api.ubb()
  
  if  (api.csi(0) > 0 and not api.mcw():find('cp')) or ( api.gse() and api.cep(api.gse(),-1) > 0 ) then
      api.cmd(r.ScriptID("Lyx Scripts/Lyx_Smart delete (no prompt).lua"),0)--delete
  else
      main()
  end
  
  api.ueb(0,"Toggle mixer visible",0)
  reaper.defer(function() end)

  
