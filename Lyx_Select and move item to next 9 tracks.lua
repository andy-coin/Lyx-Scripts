  
  local function main()
  
      local B = reaper.GetCursorPosition()
      local X,Y=reaper.GetSet_ArrangeView2(0,false,0,0,_,_)
      
      for abi=1,8 do
          reaper.Main_OnCommand(40419,0)
          reaper.SetEditCurPos(B,false,false)
          reaper.GetSet_ArrangeView2(0,true,0,0,X,Y)
          
          tr=reaper.GetSelectedTrack(0,0)
          reaper.SetMixerScroll(tr)
      end
  
  end
  
  reaper.defer(main)
  
