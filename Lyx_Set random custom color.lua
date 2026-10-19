   
  r=reaper
  
  local midi =18639925 --21004358
  local audio=18696831
  local video=29846082 --[orange] 28685749 [gray]
  
  
  c_chart={25182272,25196864,21790784,21004396,20994432,
  23085184,25182310,25187136,24346688,21004358,21004416,
  20989568,24330368,25182291,25192000,23101504,21004377,
  20999296,21774464,25182329,27487340,27500140,24617836,
  23896979,23888547,25652387,27487373,27491436,26780524,
  23896945,23896995,23884195,26766499,27487356,27495788,
  25666412,23896962,23892899,24603811,27487390}
  
  
  local function ResetColor(target,n)
      
      if  target=="item" then
      
          for abi=1,n do
              local item=reaper.GetSelectedMediaItem(0,abi-1)
              local _,chunk=reaper.GetItemStateChunk(item,"",false)
              local name=chunk:match("FILE".."[^\n]+")
              local ext=(name and name:match("m4a"))
              local tr=reaper.GetMediaItemTrack(item)
              local color=reaper.GetMediaTrackInfo_Value(tr,"I_CUSTOMCOLOR")
              --if  color==12599296 or color == 0 then
                  --
                  take=reaper.GetActiveTake(item)
                  if  take then 
                      source=reaper.GetMediaItemTake_Source(take)
                      TYPE=reaper.GetMediaSourceType( source, '' )
                  end
                  if  TYPE=="MIDI" then
                      reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",midi)
                  elseif TYPE=="VIDEO" and not ext then
                      reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",video)
                  else
                      reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",0)--audio)
                  end--]]
                  --reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",0)
              --else
                  --reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",color)
              --end
              reaper.UpdateArrange()
          end
      
      elseif  target == "track" then
      
          for abi=1,n do
              local track=reaper.GetSelectedTrack(0,abi-1)
              reaper.SetMediaTrackInfo_Value(track,"I_CUSTOMCOLOR",0)
          end
          reaper.UpdateArrange()
          
      end
    
  end

  local function main()
    
      local color = reaper.GetExtState("color","color",false)
      
      color=(type(tonumber(color))~="number" and 0) or tonumber(color)
      
      color=color%40+1
      toggle=0
      
      win,_,det=reaper.BR_GetMouseCursorContext()
      it_n=reaper.CountSelectedMediaItems(0)
      tr_n=reaper.CountSelectedTracks(0)
      
      if  (win=="tcp" and it_n>1 and tr_n==1 ) or 
          (win=="arrange" and it_n>=tr_n) or
          (det=="item" or det=="item_stretch_marker" and tr_n==1 ) then
          
          for abi=1,reaper.CountSelectedMediaItems(0) do
              item=reaper.GetSelectedMediaItem(0,abi-1)
              local _,chunk=reaper.GetItemStateChunk(item,"",false)
              local name=chunk:match("FILE".."[^\n]+")
              local ext=(name and name:match("m4a"))
              local tr=reaper.GetMediaItemTrack(item)
              local color=reaper.GetMediaTrackInfo_Value(tr,"I_CUSTOMCOLOR")
              local check=reaper.GetDisplayedMediaItemColor(item)
              
              if  color==12599296 or color==0 then
               
                  take=reaper.GetActiveTake(item)
                  
                  if  take then 
                      source=reaper.GetMediaItemTake_Source(take)
                      TYPE=reaper.GetMediaSourceType( source, '' )
                      source=reaper.GetMediaItemTake_Source(take)
                      TYPE=reaper.GetMediaSourceType(source, '' )
                  end
                
                  if  TYPE=="MIDI" then
                      if  check~=midi then
                          ResetColor("item",it_n)
                          toggle=1
                          break
                      end
                  elseif TYPE=="VIDEO" and not ext then
                      if  check~=video then
                          ResetColor("item",it_n)
                          toggle=1
                          break
                      end
                  else
                      if  check~=audio and check~= 0 then
                          ResetColor("item",it_n)
                          toggle=1
                          break 
                      end
                  end
              else
                  if  check~=color then
                      ResetColor("item",it_n)
                      toggle=1
                      break
                  end
              end
              ::NEXT::
          end
        
          if  toggle==0 then
              for abi=1,it_n do
                item=reaper.GetSelectedMediaItem(0,abi-1)
                reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",c_chart[color])
                color=color%40+1
                reaper.SetExtState("color","color",color,false)
              end
              reaper.UpdateArrange()
              return 
          end
        
      elseif  tr_n > 0 then 
          
          for abi=1,tr_n do
              local track=reaper.GetSelectedTrack(0,abi-1)
              local color=reaper.GetMediaTrackInfo_Value(track,"I_CUSTOMCOLOR")
              if  color~=0 and color~= 12599296 then
                  ResetColor("track",tr_n)
                  toggle=1
                  break 
              end
          end
       
          if  toggle==0 then
          
              for abi=1,reaper.CountSelectedTracks(0) do
                  track=reaper.GetSelectedTrack(0,abi-1)
                  reaper.SetMediaTrackInfo_Value(track,"I_CUSTOMCOLOR",c_chart[color])
                  color=color%40+1
                  reaper.SetExtState("color","color",color,false)
              end
              
              reaper.UpdateArrange()
              return 
          end
      end
    
  end
      
  main()
  
  
