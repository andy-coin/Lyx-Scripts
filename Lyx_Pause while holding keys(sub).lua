  
    ---------------------SAVE INITIAL SELECTED TRACKS------------------------------------
    trackzzz={}
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
    
    local function SaveCT(closetime)
    
	 local name = "holding"
	 reaper.SetExtState(name,"holding",closetime,true)
    end
    
    local function SaveLT(last_time)
	  local name = "last time"
	 reaper.SetExtState(name,"last_time",last_time,true)
    end
    
    local function LoadLT()
	  local name = "last time"
	  last_time = reaper.GetExtState(name,"last_time",true)
	  return last_time
    end
    
    local function SavePC(play_cursor)
	  local name = "play_cursor"
	  reaper.SetExtState(name,"play_cursor",play_cursor,true)
    end
    
    local function LoadPC()
	  local name = "play_cursor"
	 play_cursor = reaper.GetExtState(name,"play_cursor",true)
	 return play_cursor
    end
    
    
    --------------------------------------CreateTakeFolder----------------------------------------------
	 
    local function CreateTakeFolder()  
  
		  
		  cmd = reaper.NamedCommandLookup("_SWS_SELTRKWITEM")
		  reaper.Main_OnCommand(cmd,0)--Select only track(s) with selected item(s)
		  
		  tr_sel = reaper.GetSelectedTrack(0,0)
		  
		  item = reaper.GetSelectedMediaItem(0,0)
		  reaper.Main_OnCommand(41039,0)--set loop point to item
		  cmd = reaper.NamedCommandLookup("_SWS_SAVETIME2")
		  reaper.Main_OnCommand(cmd,0)--save time selection slot 2
		  
		  ori_position = reaper.GetMediaItemInfo_Value(item,"D_POSITION")
		  reaper.SetMediaItemInfo_Value(item,"D_POSITION" , ori_position+18000)
		  cmd = reaper.NamedCommandLookup("_SWS_SAVEALLSELITEMS1")--save item
		  reaper.Main_OnCommand(cmd,0)
		  
		  reaper.Main_OnCommand(40718,0)--Select all items on selected tracks in current time selection
		  
		  old_item = {}
		  for abii = 0 ,reaper.CountSelectedMediaItems(0)-1 do
		  old_item[abii+1] = reaper.GetSelectedMediaItem(0,abii)
		  end
		  
		 
		 
		  if reaper.GetSelectedMediaItem(0,0) then
			 
			 if nil ~= reaper.GetParentTrack(tr_sel) 
			 and 0 == reaper.GetMediaTrackInfo_Value(tr_sel,"I_FOLDERDEPTH") then
  --reaper.ShowConsoleMsg("|".."CHILDREN".."|")             
		  
			 reaper.Main_OnCommand(41039,0)--Set loop points to items
			 reaper.Main_OnCommand(40001,0)--insert new track
			 cmd = reaper.NamedCommandLookup("_XENAKIOS_SELPREVTRACK")
			 reaper.Main_OnCommand(40730,0)--mute tracks
			 reaper.Main_OnCommand(40118,0)--Move items down one track/a bit
			 for abii = 0 ,reaper.CountSelectedMediaItems(0)-1 do 
			 reaper.SetMediaItemInfo_Value(old_item[abii+1], "C_LOCK", 1) 
			 end
			 end              
		   
			 if nil == reaper.GetParentTrack(tr_sel) --
			    and 1 == reaper.GetMediaTrackInfo_Value(tr_sel,"I_FOLDERDEPTH") then
  --reaper.ShowConsoleMsg("|".."PARENT".."|")
  
			    reaper.Main_OnCommand(41039,0)--Set loop points to items
			    
			    cmd = reaper.NamedCommandLookup("_SWS_SELCHILDREN")
			    reaper.Main_OnCommand(cmd,0)--select children track
			    tr_fol = reaper.CountSelectedTracks(0)
			    
			    cmd = reaper.NamedCommandLookup("_SWS_SELPARENTS")
			    reaper.Main_OnCommand(cmd,0)--Select only parent(s) of selected folder track(s)
			    
			    if tr_fol > 3 then
			    cmd = reaper.NamedCommandLookup("_SWS_COLLAPSE")
			    reaper.Main_OnCommand(cmd,0)--Set selected folder(s) collapsed
			    end
			    
			    abi = 0
			    repeat
			    reaper.Main_OnCommand(40289,0)--clear item selection
			    cmd = reaper.NamedCommandLookup("_XENAKIOS_SELNEXTTRACK")
			    reaper.Main_OnCommand(cmd,0)--Select next tracks
			    reaper.Main_OnCommand(40718,0)--Select all items on selected tracks in current time selection
			    if reaper.GetSelectedMediaItem(0,0) then break end
			    abi = abi + 1--count empty slot from folder
			    if abi == 1000 then reaper.ShowConsoleMsg("|".."BUG A".."|") break end
			    until abi == tr_fol
			    reaper.Main_OnCommand(40289,0)--clear item selection
			    cmd = reaper.NamedCommandLookup("_SWS_SELPARENTS")
			    reaper.Main_OnCommand(cmd,0)--Select only parent(s) of selected folder track(s)
			
				   if abi == 0 then -- no empty slot
					 
					 reaper.Main_OnCommand(40001,0)--insert new track
					 reaper.Main_OnCommand(40730,0)--mute tracks
					 cmd = reaper.NamedCommandLookup("_SWS_SELPARENTS")
					 reaper.Main_OnCommand(cmd,0)--Select only parent(s) of selected folder track(s)
					 reaper.Main_OnCommand(40718,0)--Select all items on selected tracks in current time selection
					 reaper.Main_OnCommand(40118,0)--Move items down one track/a bit
					 for abii = 0 ,reaper.CountSelectedMediaItems(0)-1 do 
					 reaper.SetMediaItemInfo_Value(old_item[abii+1], "C_LOCK", 1) 
					 end
					 cmd = reaper.NamedCommandLookup("_SWS_SELPARENTS")
					 reaper.Main_OnCommand(cmd,0)--Select only parent(s) of selected folder track(s)
					 
				   else
					
					reaper.Main_OnCommand(40718,0)--Select all items on selected tracks in current time selection
					abigel = 0
					repeat
					reaper.Main_OnCommand(40118,0)--Move items down one track/a bit
					abigel = abigel + 1
					if abi == 1000 then reaper.ShowConsoleMsg("|".."BUG B".."|") break end
					until abigel == abi
					
					
					for abii = 0 ,reaper.CountSelectedMediaItems(0)-1 do 
					reaper.SetMediaItemInfo_Value(old_item[abii+1], "C_LOCK", 1)
					end
					
				   
				   end
				   
			    end
			   
			   if nil == reaper.GetParentTrack(tr_sel) 
			   and 0 == reaper.GetMediaTrackInfo_Value(tr_sel,"I_FOLDERDEPTH") then
  --reaper.ShowConsoleMsg("|".."NORMAL".."|")                 
				 reaper.Main_OnCommand(40001,0)--insert new track
				 cmd = reaper.NamedCommandLookup("_XENAKIOS_SELPREVTRACK")
				 reaper.Main_OnCommand(40730,0)--mute tracks
				 reaper.Main_OnCommand(40118,0)--Move items down one track/a bit
				 for abii = 0 ,reaper.CountSelectedMediaItems(0)-1 do 
				 reaper.SetMediaItemInfo_Value(old_item[abii+1], "C_LOCK", 1) 
				 end
				 cmd = reaper.NamedCommandLookup("_XENAKIOS_SELPREVTRACKKEEP")
				 reaper.Main_OnCommand(cmd,0)--Select previous tracks, keeping current selection
				 cmd = reaper.NamedCommandLookup("_XENAKIOS_SELTRACKSASFOLDER")
				 reaper.Main_OnCommand(cmd,0)--Set selected tracks as folder
				 cmd = reaper.NamedCommandLookup("_SWS_FOLDSMALL")
				 reaper.Main_OnCommand(cmd,0)--Set selected folder(s) small
				 cmd = reaper.NamedCommandLookup("_SWS_SELPARENTS")
				 reaper.Main_OnCommand(cmd,0)--Select only parent(s) of selected folder track(s)
				 end                
		 
		  end
		  
		  cmd = reaper.NamedCommandLookup("_SWS_RESTALLSELITEMS1")--restore item
		  reaper.Main_OnCommand(cmd,0)
		  reaper.SetMediaItemInfo_Value(item,"D_POSITION",ori_position)
		  reaper.Main_OnCommand(40635,0)--clear time seelction
    end
    
  -----
    
    local function RECORD()
	 
  
	 SaveSelectedTracks (trackzzz)
	 tr_sel = reaper.GetSelectedTrack(0,0)
  
	 --if 5 == reaper.GetPlayState() then  
	 
		reaper.Main_OnCommand(1016,0)--play/stop
		
		LoopA,LoopB = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
		if LoopA-LoopB ~= 0 then 
		cmd = reaper.NamedCommandLookup("_SWS_SAVETIME1")
		reaper.Main_OnCommand(cmd,0)--save time selection slot 1
		end
		
		cmd = reaper.NamedCommandLookup("_BR_SAVE_CURSOR_POS_SLOT_1")
		reaper.Main_OnCommand(cmd,0)--Save edit cursor position, slot 01
		
		cmd = reaper.NamedCommandLookup("_SWS_SELTRKWITEM")
		reaper.Main_OnCommand(cmd,0)--Select only track(s) with selected item(s)
		--reaper.ShowConsoleMsg(reaper.CountSelectedTracks(0))
		
		if 1 == reaper.CountSelectedTracks(0)then
  
		    CreateTakeFolder()
		    
		elseif 2<= reaper.CountSelectedTracks(0)then
  
		    rec_items={}
		    for i = 0,reaper.CountSelectedMediaItems(0)-1 do
		    rec_items[i+1] = reaper.GetSelectedMediaItem(0,i)
		    end
		   
		    for i = 0,reaper.CountSelectedMediaItems(0)-1 do
		    reaper.Main_OnCommand(40289,0)--unselect all item
		    reaper.SetMediaItemSelected(rec_items[i+1],1)
		    CreateTakeFolder()
		    end
		    
		    --for i = 0,reaper.CountSelectedMediaItems(0)-1 do
		    --reaper.SetMediaItemSelected(rec_items[i+1],1)
		    --end
		    
		end
    
		
		if LoopA-LoopB ~= 0 then 
		cmd = reaper.NamedCommandLookup("_SWS_RESTTIME1")
		reaper.Main_OnCommand(cmd,0)--restore time selection slot 1
		end
		
		cmd = reaper.NamedCommandLookup("_BR_RESTORE_CURSOR_POS_SLOT_1")
		reaper.Main_OnCommand(cmd,0)--Resotre edit cursor position, slot 01
		
		reaper.Main_OnCommand(41330,0)--New recording splits existing items and creates new takes (default)
		
		RestoreSelectedTracks (trackzzz)
	 
    end
    
  ------------------------------------------------------------------------------------------------------------------------
	  
	  ---------------------------------------
	  ------------ USER SETTINGS ------------
	  
	  -- Minimum time (in seconds) to keep
	  -- window open if no key is detected
	  local close_time = 0.11     
	  
	  ---------------------------------------
	  ---------------------------------------
	  
	  local w, h = 192, 64
	  
	  local startup = true
	  local key_down, hold_char
	  local last = reaper.time_precise()
	  
	  if not (act and interval) then
		  local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
		  return 0
	  end
	  
	  
	  -- Convert script GUIDs to action IDs if necessary
	  if string.sub(act, 1, 1) == "_" then act = reaper.NamedCommandLookup(act) end
	  
	  -- Just some error checking because Lua occasionally 
	  -- throws a fit about numbers that are strings
	  act = tonumber(act)
	  
	  -- Make really, really sure it's a valid action.
	  if not act or act <= 0 then
		  reaper.ShowMessageBox("Invalid action ID.", "Whoops", 0)
		  return 0
	  end
	  
	  local wnd = midi and reaper.MIDIEditor_GetActive()
		  
	  
	  local char
	  
  --------------------------------------------------------------------------------------------------------------
	  local function check_key()
		  
		  if startup then
			  
			  key_down = char
			  
			  if key_down ~= 0 then
						  
				  --[[
					  
					  (I have no idea if the same values apply on a Mac)
					  
					  Need to narrow the range to the normal keyboard ASCII values:
					  
					  ASCII 'a' = 97
					  ASCII 'z' = 122
					  
					  1-26          Ctrl+               char + 96
					  65-90          Shift/Caps+          char + 32
					  257-282          Ctrl+Alt+          char - 160
					  321-346          Alt+               char - 224
	  
					  gfx.mouse_cap values:
					  
					  4     Ctrl
					  8     Shift
					  16     Alt
					  32     Win
					  
					  For Ctrl+4 or Ctrl+}... I have no fucking clue short of individually
					  checking every possibility.
	  
				  ]]--     
				  
				  local cap = gfx.mouse_cap
				  local adj = 0
				  if cap & 4 == 4 then               
					  if not (cap & 16 == 16) then
						  mod_str = "Ctrl"
						  adj = adj + 96               -- Ctrl
					  else                    
						  mod_str = "Ctrl Alt"
						  adj = adj - 160               -- Ctrl+Alt
					  end
					  --     No change                    -- Ctrl+Shift
					  
				  elseif (cap & 16 == 16) then
					  mod_str = "Alt"
					  adj = adj - 224                    -- Alt
					  
					  --  No change                    -- Alt+Shift
					  
				  elseif cap & 8 == 8 or (key_down >= 65 and key_down <= 90) then          
					  mod_str = "Shift/Caps"
					  adj = adj + 32                    -- Shift / Caps
				  end
		  
				  hold_char = math.floor(key_down + adj)
				 
				  
				  startup = false
			  elseif not up_time then
				  up_time = reaper.time_precise()
			  end
			  
		  else
			  key_down = gfx.getchar(hold_char)
		  end     
	  end
	  
	  
  --------------------------------------------------------------------------------------------------------------     
	  local function check_act()
	
		  local time = reaper.time_precise()
	
		  if time - last > interval then
			  
			  if string.sub(act, 1, 1) == "_" then act = reaper.NamedCommandLookup(act) end
			  
			  -- Just some error checking because Lua occasionally 
			  -- throws a fit about numbers that are strings
			  act = tonumber(act)
			  if not midi then
				  reaper.Main_OnCommand(act, 0)
			  else
				  reaper.MIDIEditor_OnCommand(wnd, act)
			  end
			  
			  last = time
		  end     
	  end
	  
	  
   --------------------------------------------------------------------------------------------------------------    
	  local function Main()
		  char = gfx.getchar()
		  
		  if char == -1 or char == 27 then return 0 end
		  
		  check_key()
		  local diff = up_time and (reaper.time_precise() - up_time) or 0
		  
		  if timeQQ-LT < 0.1 then --Hold
			if P == 0 then
			   if key_down ~= 0 or (startup and diff < close_time) then
				 --reaper.ShowConsoleMsg("Holding!".."\n")
				 reaper.Main_OnCommand(1016,0)
				 gfx.update()
				 reaper.defer(Main)
			   else
				 --reaper.ShowConsoleMsg("Release!".."\n")
				 local A = LoadPC()
				 local B = reaper.GetCursorPosition()
				 reaper.SetEditCurPos(A,false,false)
				 reaper.Main_OnCommand(1007,0)
				 reaper.SetEditCurPos(B,false,false)
			   end
			elseif P == 1 then
			   if key_down ~= 0 or (startup and diff < close_time) then
				 --reaper.ShowConsoleMsg("Holding!".."\n")
				 reaper.Main_OnCommand(1016,0)
				 gfx.update()
				 reaper.defer(Main)
			   else
				 --reaper.ShowConsoleMsg("Release!".."\n")
				 local A = LoadPC()
				 local B = reaper.GetCursorPosition()
				 reaper.SetEditCurPos(A,false,false)
				 reaper.Main_OnCommand(1007,0)
				 reaper.SetEditCurPos(B,false,false)
				 
			   end
			end
		  elseif timeQQ-LT > 0.1 and timeQQ-LT < 0.8 then --Hold 
			--reaper.ShowConsoleMsg("Hold2|"..P.."\n")
			if P == 5 then
			   --reaper.Main_OnCommand(1013,0)
			   RECORD()
			elseif P == 1 then
			   reaper.Main_OnCommand(1016,0)
			   A = reaper.GetPlayPosition()
			   SavePC(A)
			else
			   --local A = LoadPC()
			   --local B = reaper.GetCursorPosition()
			   --reaper.SetEditCurPos(A,false,false)
			   --reaper.Main_OnCommand(1007,0)
			   --reaper.SetEditCurPos(B,false,false)
			   --reaper.Main_OnCommand(1016,0)
			end
		  else
			--reaper.ShowConsoleMsg("Short1|"..P.."\n")
			if P == 5 then
			   --reaper.Main_OnCommand(1013,0)
			   RECORD()
			elseif P == 1 then
			   A = reaper.GetPlayPosition()
			   SavePC(A)
			   reaper.Main_OnCommand(40044,0)--play/stop
			else
			   --[[local A = LoadPC()
			   local B = reaper.GetCursorPosition()
			   reaper.SetEditCurPos(A,false,false)
			   reaper.Main_OnCommand(1007,0)
			   reaper.SetEditCurPos(B,false,false)--]]
			end
		  end

	  end
	 
   --------------------------------------------------------------------------------------------------------------
	  P = reaper.GetPlayState()
	  name = "holding"
	  LT = LoadLT()
	  timeQQ = reaper.time_precise()
	  SaveLT(timeQQ)
	  gfx.init("", 0,0, 0, 0, 1633, 1311)
	  Main()
	  
	  
  
  
	
