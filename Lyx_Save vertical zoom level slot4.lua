  
  r=reaper
   
  ----------------------------------------------------------------------------------
  local nl = string.char(10) -- newline
  local function serialize (tabl, indent)
      indent = indent and (indent.."  ") or ""
      local str = ''
      complex=false
      for key, value in pairs (tabl) do
          local pr = (type(key)=="string") and ('["'..key..'"]=') or ""
          if type (value) == "table" then
              str = str..'<<'..serialize(value, indent)
              str = str .. indent..">>"..nl
              complex=true
          elseif type (value) == "string" then
              str = str..indent..pr..'"'..tostring(value)..'",'..nl
          else
              str = str..indent..pr..'"'..tonumber(value)..'",'..nl
          end
      end
      
      if complex then
        str= "<<true>>\n"..str
      end
      
      return str
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
  
  ----------------------------------------------------------------------------------
  local function KillRepeatValue(missabi)
    
    t=DeepCopy(missabi)
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
  
  ----------------------------------------------------------------------------------
  local function SaveVerticalZoom()
  
    if 0 == reaper.CountTracks(0) then return end
    
    local TR = {}
    local TR_code={}
    local TR_TCPH = {}
    local TR_GROUP={}
    for abi = 0,reaper.CountTracks(0)-1 do
      TR[abi+1] = reaper.GetTrack(0,abi)
      _,TR_code[abi+1] = reaper.GetSetMediaTrackInfo_String(TR[abi+1],"GUID","",false)
      TR_TCPH[abi+1] = reaper.GetMediaTrackInfo_Value(TR[abi+1],"I_TCPH")
    end
    local code=DeepCopy(TR_code)
    local V,N=KillRepeatValue(TR_TCPH)
    
    if N>1 then
      for abi=1,N do
        TR_GROUP[abi]={}
        abii=1
        repeat  
          if TR_TCPH[abii]==V[abi] then
            TR_GROUP[abi][#TR_GROUP[abi]+1]=TR_code[abii]
            table.remove(TR_code,abii)
            table.remove(TR_TCPH,abii)
          else
            abii=abii+1
          end
        until abii-1 == #TR_code 
      end
    else
      TR_GROUP=TR_code
    end
    
    local TR_GROUP=serialize(TR_GROUP)
    local TCPH = serialize(V)
    
    local ext_name = "Vertical zoom 4_TR_code"
    reaper.SetExtState(ext_name,"Vertical zoom 4_TR_code",TR_GROUP,false)
    
    local ext_name = "Vertical zoom 4_TR_TCPH"
    reaper.SetExtState(ext_name,"Vertical zoom 4_TR_TCPH",TCPH,false)
    
  end
  
  reaper.defer(SaveVerticalZoom)
  
  
