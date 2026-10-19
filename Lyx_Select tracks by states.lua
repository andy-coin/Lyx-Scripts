  
  r=reaper
  
  ----------------------------Select tracks by states-----------------------
  --Folder = |P,parent|C,children|SC,smallchildren|TC,tinychildren|N,normal|
  --State  = |R,record|A,recarmed|S,solo|M,mute|
  --bool   = |true,1|false,0|
  --------------------------------------------------------------------------

  local function prompt()
    
    default_track_filter = 'normal' 
    local Folder, State , bool= reaper.GetUserInputs('Select tracks by states', 3,
      "Track folder ( P / C / SC / TC / N ) :,Track state ( R / A / S / M ):,Select / Unselect ,extrawidth=50",',')
    
    if bool == 'yes' or bool == 'select' or bool == '1' or bool == 'true' or bool == '' then
       bool = 1
    elseif bool == 'no' or bool == 'unselect' or bool == '0' or bool == 'false' then
       bool = 0 
    else
       bool = nil
    end
    
    --if not Folder or State or bool:len() <= 1 then return end
    
    return Folder,State,bool
  end
  
  --------------------------------------------------------------------------
  
  function main(Folder,State,bool)

--reaper.ShowConsoleMsg(Folder.."|"..State.."|"..bool.."|")
    tr = reaper.CountTracks(0)
    if tr == 0 then return end
    if bool == nil then return end
    tracks={}
--reaper.ShowConsoleMsg("|"..tr.."|")
    for abi = 0,tr-1 do

      tracks[abi+1] = reaper.GetTrack(0,abi)
      
      if Folder == 'p' or Folder == 'parent' then
      
        if nil == reaper.GetParentTrack(tracks[abi+1])
        and 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_FOLDERDEPTH") then
          if State == 'r' or State == 'record' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_RECARM") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 'a' or State == 'arm' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_AUTO_RECARM") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 's' or State == 'solo' then
            if 0 ~= reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_SOLO") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 'm'or State == 'mute' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == '' or State == 'n' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          end
        reaper.ShowConsoleMsg("|".."P".."|")
        end
        
      elseif Folder == 'C' or Folder =='children' then
      
        if nil ~= reaper.GetParentTrack(tracks[abi+1]) then
          if State == 'r' or State == 'record' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_RECARM") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 'a' or State == 'arm' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_AUTO_RECARM") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 's' or State == 'solo' then
            if 0 ~= reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_SOLO") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 'm'or State == 'mute' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == '' or State == 'n' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          end
        reaper.ShowConsoleMsg("|".."C".."|")
        end
      
      elseif Folder == 'sc' or Folder == 'smallchildren' then
      
        if nil ~= reaper.GetParentTrack(tracks[abi+1]) then
          P_track = reaper.GetParentTrack(tracks[abi+1])
          if 1 == reaper.GetMediaTrackInfo_Value(P_track,"I_FOLDERCOMPACT ") then
            if State == 'r' or State == 'record' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_RECARM") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == 'a' or State == 'arm' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_AUTO_RECARM") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == 's' or State == 'solo' then
              if 0 ~= reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_SOLO") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == 'm'or State == 'mute' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == '' or State == 'n' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            end
          end
        reaper.ShowConsoleMsg("|".."SC".."|")
        end
      
      elseif Folder == 'tc' or Folder == 'tinychildren' then
        if nil ~= reaper.GetParentTrack(tracks[abi+1]) then
          P_track = reaper.GetParentTrack(tracks[abi+1])
          if 2 == reaper.GetMediaTrackInfo_Value(P_track,"I_FOLDERCOMPACT ") then
            if State == 'r' or State == 'record' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_RECARM") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == 'a' or State == 'arm' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_AUTO_RECARM") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == 's' or State == 'solo' then
              if 0 ~= reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_SOLO") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == 'm'or State == 'mute' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            elseif State == '' or State == 'n' then
              if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
                reaper.SetTrackSelected(tracks[abi+1],bool)
              end
            end
          end
        reaper.ShowConsoleMsg("|".."TC".."|")
        end
      elseif Folder == 'n' or Folder == 'normal' or Folder == '' then
        if nil == reaper.GetParentTrack(tracks[abi+1]) 
        and 0 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_FOLDERCOMPACT ") 
        and 0 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_FOLDERDEPTH") then
          if State == 'r' or State == 'record' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_RECARM") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 'a' or State == 'arm' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_AUTO_RECARM") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 's' or State == 'solo' then
            if 0 ~= reaper.GetMediaTrackInfo_Value(tracks[abi+1],"I_SOLO") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == 'm'or State == 'mute' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          elseif State == '' or State == 'n' then
            if 1 == reaper.GetMediaTrackInfo_Value(tracks[abi+1],"B_MUTE") then
              reaper.SetTrackSelected(tracks[abi+1],bool)
            end
          end
        reaper.ShowConsoleMsg("|".."N".."|")
        end
      end
    end
  end
  
  reaper.Undo_BeginBlock()
  --a,b,c = prompt()
  --reaper.ShowConsoleMsg(a.."|"..b.."|"..c.."|")
  --main(a,b,c)
  --reaper.ShowConsoleMsg("go!")
  reaper.Undo_EndBlock("select track by states",-1)
  
