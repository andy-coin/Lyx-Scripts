
  r=reaper

  ----------------------------Select tracks by states-----------------------
  --Folder = |P,parent|C,children|SC,smallchildren|TC,tinychildren|N,normal|
  --State  = |R,record|A,recarmed|S,solo|M,mute|  (empty = any state)
  --bool   = |true,1|false,0|
  --------------------------------------------------------------------------

  local function prompt()

    local ok, csv = reaper.GetUserInputs('Select tracks by states', 3,
      "Track folder ( P / C / SC / TC / N ) :,Track state ( R / A / S / M ):,Select / Unselect ,extrawidth=50",'N,,select')
    if not ok then return end
    local Folder, State, bool = csv:lower():match('^%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s*$')

    if bool == 'yes' or bool == 'select' or bool == '1' or bool == 'true' or bool == '' then
       bool = true
    elseif bool == 'no' or bool == 'unselect' or bool == '0' or bool == 'false' then
       bool = false
    else
       bool = nil
    end

    return Folder,State,bool
  end

  --------------------------------------------------------------------------

  local function FolderMatch(tr, Folder)
    local parent = reaper.GetParentTrack(tr)
    if Folder == 'p' or Folder == 'parent' then
      return not parent and reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH") == 1
    elseif Folder == 'c' or Folder == 'children' then
      return parent ~= nil
    elseif Folder == 'sc' or Folder == 'smallchildren' then
      return parent ~= nil and reaper.GetMediaTrackInfo_Value(parent,"I_FOLDERCOMPACT") == 1
    elseif Folder == 'tc' or Folder == 'tinychildren' then
      return parent ~= nil and reaper.GetMediaTrackInfo_Value(parent,"I_FOLDERCOMPACT") == 2
    elseif Folder == 'n' or Folder == 'normal' or Folder == '' then
      return not parent
        and reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERCOMPACT") == 0
        and reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH") == 0
    end
    return false
  end

  local function StateMatch(tr, State)
    if State == 'r' or State == 'record' then
      return reaper.GetMediaTrackInfo_Value(tr,"I_RECARM") == 1
    elseif State == 'a' or State == 'arm' or State == 'recarmed' then
      return reaper.GetMediaTrackInfo_Value(tr,"B_AUTO_RECARM") == 1
    elseif State == 's' or State == 'solo' then
      return reaper.GetMediaTrackInfo_Value(tr,"I_SOLO") ~= 0
    elseif State == 'm' or State == 'mute' then
      return reaper.GetMediaTrackInfo_Value(tr,"B_MUTE") == 1
    elseif State == '' or State == 'n' then
      return true
    end
    return false
  end

  function main(Folder,State,bool)
    if bool == nil then return end
    for abi = 0, reaper.CountTracks(0)-1 do
      local tr = reaper.GetTrack(0,abi)
      if FolderMatch(tr,Folder) and StateMatch(tr,State) then
        reaper.SetTrackSelected(tr,bool)
      end
    end
  end

  local a,b,c = prompt()
  if c == nil then return end
  reaper.Undo_BeginBlock()
  main(a,b,c)
  reaper.Undo_EndBlock("Select tracks by states",-1)
