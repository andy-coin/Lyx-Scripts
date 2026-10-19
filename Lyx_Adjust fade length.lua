
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  
  --------------------------------------CHECK-------------------------------------
  local function MarkItemsInRange(track, areaStart, areaEnd)
      local itemCount = reaper.CountTrackMediaItems(track)
      local Bad={}
      local P={}
      local E={}
      local L={}
      for k = 0, itemCount - 1 do 
          local item = reaper.GetTrackMediaItem(track, k)
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local itemEndPos = pos+length
  
          --check if item is in area bounds
          if  (itemEndPos > areaStart and itemEndPos <= areaEnd) or
              (pos >= areaStart and pos < areaEnd) or
              (pos <= areaStart and itemEndPos >= areaEnd) then
              itemzz[#itemzz+1]=item
          end
      end
  end
  
  ----------------------------------------NORMAL-------------------------------------------------
  local function GetUserInput()
    
      extname="fade_length"
      last_setting=reaper.GetExtState(extname,"fade_length",true)
      last_unit=reaper.GetExtState(extname,"length_unit",true)
      
      local ok, csv = r.GetUserInputs("Adjust fade length...", 2,
        "Length :,Time unit: ( s / ms ),extrawidth=100",
        last_setting..','..last_unit)
      
      if not ok or csv:len() <= 1 then return end
    
      local length,unit = csv:match("^(.*),(.*)$")
      
      if  unit ~= 'ms' and unit ~= 's' then
          reaper.ShowMessageBox("Got wrong unit >_< \n please type s or ms !","Oops...",0)
          return false
      end
      
      unit=(unit=="s" and "s") or "ms" 
      
      fadesize=(tonumber(length) and tonumber(length)) or 10 
      fadesize=(unit=="s" and tonumber(fadesize)) or fadesize/1000
      
      reaper.SetExtState(extname,"fade_length",length,true)
      reaper.SetExtState(extname,"length_unit",unit,true)
      
      
      return true,fadesize
    
  end
  
  ----------------------------------------NORMAL-------------------------------------------------
  local function FADE(itemz,fadesize,m,M)
      
      reaper.Main_OnCommand(41118,0)
      reaper.Main_OnCommand(40289,0)--unselect all items
      
      default_fade=tonumber(REAPER_ini:match("deffadelen=(.-)\n"))
      
      for abi=1,#itemz do
          
          tr=reaper.GetMediaItem_Track(itemz[abi])
          IP=reaper.GetMediaItemInfo_Value(itemz[abi],"IP_ITEMNUMBER")
          P=reaper.GetMediaItemInfo_Value(itemz[abi],"D_POSITION")
          L=reaper.GetMediaItemInfo_Value(itemz[abi],"D_LENGTH")
          E=L+P
          
          fdin=reaper.GetMediaItemInfo_Value(itemz[abi],"D_FADEINLEN")
          fdin_a=reaper.GetMediaItemInfo_Value(itemz[abi],"D_FADEINLEN_AUTO")
          fdout=reaper.GetMediaItemInfo_Value(itemz[abi],"D_FADEOUTLEN")
          fdout_a=reaper.GetMediaItemInfo_Value(itemz[abi],"D_FADEOUTLEN_AUTO")
          
          local pre,next,skipfdin,skipfdout
          
          pre = ((IP>0 and P>m and P<M ) and reaper.GetTrackMediaItem(tr,IP-1))
          if  pre then -- no crossfadeout
              pre=reaper.GetTrackMediaItem(tr,IP-1)
              pre_p=reaper.GetMediaItemInfo_Value(pre,"D_POSITION")
              pre_l=reaper.GetMediaItemInfo_Value(pre,"D_LENGTH")
              pre_e=pre_p+pre_l
          end
  
          next= ((IP<reaper.CountTrackMediaItems(tr)-1 and E>m and E<M ) and reaper.GetTrackMediaItem(tr,IP+1))
          if next then
              next_p=reaper.GetMediaItemInfo_Value(next,"D_POSITION")
              next_l=reaper.GetMediaItemInfo_Value(next,"D_LENGTH")
              next_e=next_p+next_l 
          end
  
          ::skipin::
          
          skipfdin = (P<m or P>M) or fadesize>L/2 or done
          skipfdout= (E<m or E>M) or fadesize>L/2
          
          if  not skipfdin then
              if  pre and P<=pre_e+0.001 then -- cross
                  local center=(pre_e+P)/2
                  local bound=math.min(center+fadesize,E)
                  reaper.SetMediaItemInfo_Value(pre,"D_LENGTH",pre_l+fadesize-(pre_e-center))
                  reaper.SetMediaItemSelected(itemz[abi],true)
                  reaper.ApplyNudge(0,0,1,1,(center-P)-fadesize,false,0)
                  reaper.SetMediaItemSelected(itemz[abi],false)
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_FADEINLEN_AUTO",fadesize*2)
                  reaper.SetMediaItemInfo_Value(pre,"D_FADEOUTLEN_AUTO",fadesize*2)
              else
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_FADEINLEN",fadesize)
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_FADEINLEN_AUTO",fadesize)
              end
          end
          
          ::skipout::
          
          done=nil
          
          if  not skipfdout then
              if  next and E>=next_p-0.001 then --cross
                  local center=(E+next_p)/2
                  local bound=math.min(center+fadesize,next_e)
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_LENGTH",L+fadesize-(E-center))
                  reaper.SetMediaItemSelected(next,true)
                  reaper.ApplyNudge(0,0,1,1,(center-next_p)-fadesize,false,0)
                  reaper.SetMediaItemSelected(next,false)
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_FADEOUTLEN_AUTO",fadesize*2)
                  reaper.SetMediaItemInfo_Value(next,"D_FADEINLEN_AUTO",fadesize*2)
                  done=(itemz[abi+1] and next==itemz[abi+1])
              else
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_FADEOUTLEN",fadesize)
                  reaper.SetMediaItemInfo_Value(itemz[abi],"D_FADEOUTLEN_AUTO",fadesize)
              end
          end
          
          ::END::
          
      end 
      reaper.Main_OnCommand(41119,0)
  end
  
  -----------------------------------RAZOR AREA CHECK-----------------------------------------------
  local function main(len)
      
      itemzzz=r.SaveItems(itemzzz)
      
      local trackCount = reaper.CountTracks(0)
      itemzz={}
      local areaStart={}
      local areaEnd={}
      local razor=false
      local min=reaper.GetProjectLength()
      local max=0
      
      for i = 0, trackCount - 1 do
          local track = reaper.GetTrack(0, i)
          local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
          if area ~= '' then
              razor=true
              local str = {}
              for j in string.gmatch(area,"%S+") do
                  table.insert(str,j)
              end
              
              local j = 1
              while j <= #str do
                  areaStart[#areaStart+1] = tonumber(str[j])
                  areaEnd[#areaEnd+1] = tonumber(str[j+1])
                  if min>areaStart[#areaStart] then min=areaStart[#areaStart] end
                  if max<areaEnd[#areaEnd] then max=areaEnd[#areaEnd] end
                  MarkItemsInRange(track,areaStart[#areaStart],areaEnd[#areaEnd])
                  j = j + 3
              end
          end
      end
      
      if #itemzzz==0 and #itemzz==0 then return end
      
      if  razor then
          FADE(itemzz,len,min,max)
      else
          Start,End = reaper.BR_GetArrangeView(0)
          FADE(itemzzz,len,Start,End)
      end
      r.RestoreItems(itemzzz)
      
      reaper.UpdateArrange()
  end
  
  -- dialog runs in a coroutine (r.run); ask first, then one undo block around the edit
  r.run(function()
      local ret, len = GetUserInput()
      if ret then r.Undo("Adjust fade length", main, len) end
  end)
