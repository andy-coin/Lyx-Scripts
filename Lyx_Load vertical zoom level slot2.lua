  
  r=reaper

  ---------------------SAVE INITIAL SELECTED TRACKS------------------------------------
  local trackzzz={}
  local function SaveSelectedTracks (table)--trackzzz
    for i = 0, reaper.CountSelectedTracks(0)-1 do
      table[i+1] = reaper.GetSelectedTrack(0, i)
    end
  end
  
  ---------------------RESTORE INITIAL SELECTED TRACKS------------------------------------
  local function RestoreSelectedTracks (table)--trackzzz
    reaper.Main_OnCommand(40297,0)
    for _, track in ipairs(table) do
      reaper.SetTrackSelected(track, true)
    end
  end
  
  ----------------------------------------------------------------------------------
  local function unserialize(str)
    
    local tbl = {}
    local time=reaper.time_precise()
    
    comx=string.gmatch(str,'<<(.-)>>')
    complex=comx()
    
    if complex =="true" then
      tb=string.gmatch(str,'<<(.-)>>')
      abi=1
      repeat
        --reaper.ShowConsoleMsg("falg"..abi.."|")
        tab=tb()
        if not tab then break end
        tbl[abi]={}
        v=string.gmatch(tab,'"(.-)"')
        repeat 
          value=v()
          if not value then break end
          table.insert(tbl[abi],value)
        until time==reaper.time_precise()-5
        abi=abi+1
      until time==reaper.time_precise()-5
      table.remove(tbl,1)
    else
        v=string.gmatch(str,'"(.-)"')
      repeat 
        value=v()
        if not value then break end
        table.insert(tbl,value)
      until time==reaper.time_precise()-5
    end
      
    return tbl
  end
  
  -----------------------------------------------------------------------------------
  local function DeepCopy(ori_table)
    copy_table={}
    for abi=1,#ori_table do
      local a=ori_table[abi]
      copy_table[abi]=a
    end
    return copy_table
  end
  
  -----------------------------------------------------------------------------------
  local function KillRepeatValue(missabi)
    
    t=DeepCopy(missabi)
    
    for abi=1,#t do
      t[abi]=t[abi]-0
    end
    
    table.sort(t)
    
    if t[1]==t[#t] then
      return t,1
    end
    
    abi=1
    repeat
      if t[abi]==t[abi+1]then
        table.remove(t,abi+1) 
      else
        abi=abi+1
      end
    until abi==#t 

    return t,#t
  end
  
  -----------------------------------------------------------------------------------
  local function LoadVerticalZoom()
  
    SaveSelectedTracks(trackzzz)
    
    local ext_name = "Vertical zoom 2_TR_code"
    local TR_code = reaper.GetExtState(ext_name,"Vertical zoom 2_TR_code",false)
    
    local ext_name = "Vertical zoom 2_TR_TCPH"
    local TR_TCPH = reaper.GetExtState(ext_name,"Vertical zoom 2_TR_TCPH",false)
    
    local code=unserialize(TR_code)
    local TCPH=unserialize(TR_TCPH)
    
    local tr={}
    local tcph={}
    cmd=reaper.NamedCommandLookup("_SWS_MINTRACKS")
    
    if type(code[1])=='table' then
      for abi=1,#code do 
        reaper.Main_OnCommand(40297,0)
        for abii=1,#code[abi] do
          tr[abii]=reaper.BR_GetMediaTrackByGUID(0,code[abi][abii])
          if tr[abii] then 
            tcph[#tcph+1]=reaper.GetMediaTrackInfo_Value(tr[abii],"I_TCPH")
            if tcph[#tcph] ~= TCPH[abi] then
              reaper.SetTrackSelected(tr[abii],true)
            end
          end
        end
        times=(TCPH[abi]-22)/2
        reaper.Main_OnCommand(cmd,0)--minimize selected tracks
        for abii=1,times do
          reaper.Main_OnCommand(41327,0)--increase track height a bit
        end
      end
    else
      for abi=1,#code do 
        reaper.Main_OnCommand(40297,0)
        tr[abi]=reaper.BR_GetMediaTrackByGUID(0,code[abi])
        if tr[abi] then 
          tcph[#tcph+1]=reaper.GetMediaTrackInfo_Value(tr[abi],"I_TCPH")
          if tcph[#tcph] ~= TCPH[abi] then
            reaper.SetTrackSelected(tr[abi],true)
          end
        end
        times=(TCPH[abi]-22)/2
        reaper.Main_OnCommand(cmd,0)--minimize selected tracks
        for abii=1,times do
          reaper.Main_OnCommand(41327,0)--increase track height a bit
        end
      end
    end
    
    RestoreSelectedTracks(trackzzz)
  end
  
  reaper.defer(LoadVerticalZoom)

