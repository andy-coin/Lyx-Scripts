  
  r = reaper
  
  trackzzz = {}
  --------------
  local function SaveSelectedTracks (table)
    for i = 0, reaper.CountSelectedTracks(0)-1 do
      table[i+1] = reaper.GetSelectedTrack(0, i)
    end
  end
  
  --------------
  local function RestoreSelectedTracks (table)
    reaper.Main_OnCommand(40297,0)
    for _, track in ipairs(table) do
      reaper.SetTrackSelected(track, true)
    end
  end
  
  --------------
  itemzzz = {}
  local function SaveSelectedItems (table)--itemzzz
    for i = 0, reaper.CountSelectedMediaItems(0)-1 do
      table[i+1] = reaper.GetSelectedMediaItem(0, i)
    end
  end
  
  --------------
  local function RestoreSelectedItems (table)--itemzzz
    reaper.Main_OnCommand(40289, 0)
    for _, item in ipairs(table) do
      reaper.SetMediaItemSelected(item, true)
    end
  end
  
  --------------
  local function serialize(tbl)
    local str = ''
   
    for _, value in ipairs(tbl) do
      str = str .. type(value) .. '\31' .. tostring(value) .. '\30'
    end
   
    return str
  end
  
  --------------
  local function unserialize(str)
    local type_map = {
      string  = tostring,
      number  = tonumber,
      boolean = function(v) return v == 'true' and true or false end,
    }
  
    local tbl = {}
  
    for type, value in str:gmatch('(.-)\31(.-)\30') do
      if not type_map[type] then
        error(string.format("unsupported value type: %s", type))
      end
  
      table.insert(tbl, type_map[type](value))
    end
  
    return tbl
  end
  
  --------------
  local function GetSetColor(Set)
      
      if Set then
          
         DATA=reaper.GetExtState("ITEMS_COLOR",pro_name,true)
         DATA=unserialize(DATA)
         
         itemz={}
         
         for abi=1,#DATA do
             if not string.find(DATA[abi],"%-") then
                color=tonumber(DATA[abi])
                for abii=1,#itemz do
                    reaper.SetMediaItemInfo_Value(itemz[abii],"I_CUSTOMCOLOR",color)
                end
                color=nil
                itemz={}
             else
                itemz[#itemz+1]=reaper.BR_GetMediaItemByGUID(0,DATA[abi])
             end
         end
         
         reaper.UpdateArrange()
         
      else
         
         local GUID,COLOR,DATA
         COLOR={}
         GUID={}
         DATA={}
                
         for abi=1,reaper.CountMediaItems(0) do
             local item=reaper.GetMediaItem(0,abi-1)
             _,GUID[abi]=reaper.GetSetMediaItemInfo_String(item,"GUID","",false)
             local color=reaper.GetMediaItemInfo_Value(item,"I_CUSTOMCOLOR")
             if color==12599296 or color == 0 then
                take=reaper.GetActiveTake(item)
                source=reaper.GetMediaItemTake_Source(take)
                TYPE=reaper.GetMediaSourceType( source, '' )
                if TYPE=="MIDI" then
                   color=midi
                elseif TYPE=="VIDEO" and not ext then
                   color=video
                else
                   color=audio
                end
             end
--reaper.ShowConsoleMsg(color.."\n")
             COLOR[abi]=color
         end
         
         time=reaper.time_precise()
         abi=1
         repeat
             DATA[#DATA+1]=GUID[abi]
             abii=abi+1
             if abii>#GUID then break end
             repeat
                 if COLOR[abi]==COLOR[abii] then
                    DATA[#DATA+1]=GUID[abii]
                    table.remove(COLOR,abii)
                    table.remove(GUID ,abii)
                 else
                    abii=abii+1
                 end
             until abii>#COLOR+1 or (reaper.time_precise()-time)>0.5
             DATA[#DATA+1]=COLOR[abi]
             abi=abi+1
             --reaper.ShowConsoleMsg(DATA[#DATA].."\n")
         until abi>#COLOR or (reaper.time_precise()-time)>0.5
         
         DATA=serialize(DATA)
         
         reaper.SetExtState("ITEMS_COLOR",pro_name,DATA,true)
         
      end
  end
  
  
  --------------
  local function ChangeColor(key)
    
    local extname="color_tint"
 
    if key=='1' then --go to automation mode
       GetSetColor(false)
       for abi=1,reaper.CountMediaItems(0) do
           local item=reaper.GetMediaItem(0,abi-1)
           local color=reaper.GetMediaItemInfo_Value(item,"I_CUSTOMCOLOR")
--reaper.ShowConsoleMsg(color.."\n")
           if color==12599296 or color == 0 then
              take=reaper.GetActiveTake(item)
              source=reaper.GetMediaItemTake_Source(take)
              TYPE=reaper.GetMediaSourceType( source, '' )
              if TYPE=="MIDI" then
                 reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",midi)
              elseif TYPE=="VIDEO" and not ext then
                 reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",video)
              else
                 reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",audio)
              end
           else
              local r,g,b=reaper.ColorFromNative(color)
              local color=reaper.ColorToNative(math.floor(r/2),math.floor(g/2),math.floor(b/2))
              reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",color|0x1000000)
           end
       end
       reaper.SetExtState(extname,pro_name,0,false)
       reaper.SetThemeColor("col_tr1_peaks",gray,0)
       reaper.SetThemeColor("col_tr2_peaks",gray,0)
       reaper.SetThemeColor("col_tr1_ps2",gray,0)
       reaper.SetThemeColor("col_tr2_ps2",gray,0)
    elseif key=='0' then --back to arrange view
       GetSetColor(true)
       reaper.SetExtState(extname,pro_name,-1,false)
       reaper.SetThemeColor("col_tr1_peaks",peak,0)
       reaper.SetThemeColor("col_tr2_peaks",peak,0)
       reaper.SetThemeColor("col_tr1_ps2",peak,0)
       reaper.SetThemeColor("col_tr2_ps2",peak,0)
    end
    
    reaper.UpdateArrange()
  
  end

-----

  local function CheckEnvVisible()
    
    for sel_tr = 1, reaper.CountTracks(0) do
      local track = reaper.GetTrack(0,sel_tr-1)
      if track then 
        for i = 1,reaper.CountTrackEnvelopes( track ) do
          local env = reaper.GetTrackEnvelope( track, i-1 )
          local br_env = reaper.BR_EnvAlloc( env, false )
          _,visible,_,_,_,_,_,_,_,_,_ = reaper.BR_EnvGetProperties( br_env )
          reaper.BR_EnvFree( br_env, true )
          if visible then return true end
        end
      end
    end 
    return false 
    
  end
  
-----
  
  local function SetEnvStates()
    
    reaper.Main_OnCommand(40296,0)
    reaper.Main_OnCommand(40406,0)
    
    for abi = 1, reaper.CountTracks(0) do
      local track = reaper.GetTrack(0,abi-1)
      if track then 
        for abii = 1,reaper.CountTrackEnvelopes( track ) do
          local env = reaper.GetTrackEnvelope( track, abii-1 )
          local br_env = reaper.BR_EnvAlloc( env, false )
          active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties( br_env )
          if Type==0 then 
             reaper.BR_EnvSetProperties(br_env,true,true,armed,false,laneHeight,defaultShape,faderScaling)
          elseif Type~=0 and active then
             reaper.BR_EnvSetProperties(br_env,true,true,armed,false,laneHeight,defaultShape,faderScaling)
          end
          reaper.BR_EnvFree( br_env, true )
        end
      end
    end
    
    RestoreSelectedTracks(trackzzz)
    
    for sel_tr = 1, reaper.CountSelectedTracks(0) do
      local track = reaper.GetSelectedTrack(0,sel_tr-1)
      if track then
        for i = 1,reaper.CountTrackEnvelopes( track ) do
          local env = reaper.GetTrackEnvelope( track, i-1 )
          local br_env = reaper.BR_EnvAlloc( env, false )
          active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties( br_env )
          if Type==0 then
             reaper.BR_EnvSetProperties(br_env,true,true,armed,true,130,defaultShape,faderScaling)
          elseif Type~=0 and visible then
             reaper.BR_EnvSetProperties(br_env,true,true,armed,false,laneHeight,defaultShape,faderScaling)
          end         
          reaper.BR_EnvFree( br_env, true )
        end
      end
    end
    
  end
  
-----

  local function main()
    
    SaveSelectedItems(itemzzz)
    
    extname="color_tint"
    pro_name=reaper.GetProjectName(0)
    if pro_name=='' then pro_name='Unsaved project' end
    key=reaper.GetExtState(extname,pro_name,false)
    
    if CheckEnvVisible() then -- visible
       
       reaper.Main_OnCommand(39013,0)--change mouse modifier to default (move item)
       reaper.Main_OnCommand(41150,0)--hide all envelopes for all tracks
       ChangeColor(key)
    else
       
       SaveSelectedTracks(trackzzz)
       
       reaper.Main_OnCommand(39000,0)--make item can't drag by mouse
       ChangeColor('1')
       SetEnvStates()
       reaper.Main_OnCommand(41149,0)
       RestoreSelectedTracks(trackzzz)
       tr=reaper.GetSelectedTrack(0,0)
       if 1<reaper.CountTrackEnvelopes(tr) then
          reaper.Main_OnCommand(40891,0)
       end
       --cmd=reaper.NamedCommandLookup("_RSdf35656e5f8aef3502ce26124efa1a441db718f5") 
       
    end
    
    RestoreSelectedItems(itemzzz)
    
  end
  
------excute main-------
  
  midi =18639924
  audio=18696831 
  video=28685749
  gray =25198720
  peak =16777215
  
  pro_name=reaper.GetProjectName()
  if pro_name=="" then pro_name="Unsaved Project" end
  reaper.ClearConsole()
  main()
  reaper.defer(function() end)
