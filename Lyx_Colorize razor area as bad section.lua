  
  r=reaper
  
  --------------
  local function GetItemsInRange(track, areaStart, areaEnd)
      local items = {}
      local itemCount = reaper.CountTrackMediaItems(track)
      for k = 0, itemCount - 1 do 
          local item = reaper.GetTrackMediaItem(track, k)
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local itemEndPos = pos+length
  
          --check if item is in area bounds
          if (itemEndPos > areaStart and itemEndPos <= areaEnd) or
              (pos >= areaStart and pos < areaEnd) or
              (pos <= areaStart and itemEndPos >= areaEnd) then
                  table.insert(items,item)
          end
      end
  
      return items
  end
  
  --------------
  local function SplitRazorEdits()
      local trackCount = reaper.CountTracks(0)
      local newItems = {}
      for i = 0, trackCount - 1 do
          local track = reaper.GetTrack(0, i)
          local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
          if area ~= '' then
              --PARSE STRING
              local str = {}
              for j in string.gmatch(area, "%S+") do
                  table.insert(str, j)
              end
          
              --FILL AREA DATA
              local j = 1
              while j <= #str do
                  --area data
                  local areaStart = tonumber(str[j])
                  local areaEnd = tonumber(str[j+1])
                  local GUID = str[j+2]
                  
                  items = GetItemsInRange(track, areaStart, areaEnd)
                  for abi=1,#items do
                      local newItem = reaper.SplitMediaItem(items[abi],areaStart)
                        if newItem == nil then
                            r_item=reaper.SplitMediaItem(item,areaEnd)
                            table.insert(newItems,items[abi])
                        else
                            r_item=reaper.SplitMediaItem(newItem,areaEnd)
                            table.insert(newItems,newItem)
                        end
                  end 
                  
                  j = j + 3
              end
          end
          reaper.GetSetMediaTrackInfo_String(track,'P_RAZOREDITS','',true)
      end
      return newItems
  end
  
  --------------
  local function main()
      
      itemz=SplitRazorEdits()
      
      for abi=1,#itemz do
          reaper.SetMediaItemInfo_Value(itemz[abi],"I_CUSTOMCOLOR",26317201)
      end
      
      reaper.UpdateArrange()
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Colorize razor area as good section",-1)
