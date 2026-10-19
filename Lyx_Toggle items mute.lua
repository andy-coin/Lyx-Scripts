  
  local script_name = debug.getinfo(1).source
  local script_path = script_name:match("@?(.*/)") or "./"
  --script_path=script_path:gsub("/MIDI Editor","")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
  
      Editor=reaper.MIDIEditor_GetActive()
      
      if Editor and reaper.BR_GetMouseCursorContext()=='midi_editor' then
         take=reaper.MIDIEditor_GetTake(Editor)
         _,ALL,_,_ = reaper.MIDI_CountEvts(take)
         for abi =1,ALL do 
             local _,selected = reaper.MIDI_GetNote(take,abi-1)
             if selected then 
                reaper.MIDIEditor_OnCommand(Editor,40055)
                return
             end
         end
         item=reaper.GetMediaItemTake_Item(take)
         mute=reaper.GetMediaItemInfo_Value(item,"B_MUTE")
         reaper.SetMediaItemInfo_Value(item,"B_MUTE",math.abs(mute-1))
         reaper.UpdateArrange()
      else
          for abi = api.csi(0), 1, -1 do
              local item = api.gsi(0,abi-1)
              if api.giv(item,'C_LOCK') == 1 then
                 api.sis(item,false)
              end
          end
          reaper.Main_OnCommand(40175,0)--mute item
      end
       
  end
  
  main()
