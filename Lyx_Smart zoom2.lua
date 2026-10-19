
  r=reaper
  
  -----------------------------------SAVE SCREEN POSITION-------------------------------------------------
  local function SaveScreenPosition()
  
  OldStart,OldEnd = reaper.BR_GetArrangeView(0)
  ext_name = "Screen Position Start_timeselection"
  OldStart = reaper.SetExtState(ext_name,pro_name,OldStart, true)
  ext_name = "Screen Position End_timeselection"
  OldEnd = reaper.SetExtState(ext_name,pro_name,OldEnd, true)
  end
  
  -----------------------------------LOAD SCREEN POSITION-------------------------------------------------
  local function LoadScreenPosition()
  
  ext_name = "Screen Position Start_timeselection"
  OldStart = reaper.GetExtState(ext_name,pro_name,false)
  ext_name = "Screen Position End_timeselection"
  OldEnd = reaper.GetExtState(ext_name,pro_name,false)
  reaper.BR_SetArrangeView(0,OldStart,OldEnd)
  end
  
  --------------------------------------ADJUST GRID-------------------------------------
  local function AdjustGrid()

      local stages = {0.38, -- no grid
                      5, -- 2
                      16,--1
                      22.84,
                      48.84, -- 1/4(48)
                      117.86,
                      351.95,-- 1/16
                      1050.92,
                      3200.07,
                      6077} -- no grid
            
      grid_t = {}
      for i = 2, -15, -1 do grid_t[#grid_t+1] = 2^i end
      
      zoom_lev = reaper.GetHZoomLevel() 
      triplet=reaper.NamedCommandLookup("_SWS_AWTOGGLETRIPLET")
      tri=reaper.GetToggleCommandState(triplet)
        --reaper.ShowConsoleMsg(zoom_lev.."\n")
        _,grid,swing,swingamt = reaper.GetSetProjectGrid(0,false)
        if zoom_lev>17 then
           for i = 1, #stages-1 do
             if zoom_lev > stages[i] and zoom_lev <= stages[i+1] then
                if i>1 and i<7 then i=i+1 end
                if swing then
                   reaper.SetProjectGrid(0,grid_t[i],swing,swingamt)
                else
                   reaper.SetProjectGrid(0,grid_t[i])
                end
                break
             end
           end
        else
           for i = 1, #stages-1 do
             if zoom_lev > stages[i] and zoom_lev <= stages[i+1] then
                if swing then
                   reaper.SetProjectGrid(0,grid_t[i],swing,swingamt)
                else
                   reaper.SetProjectGrid(0,grid_t[i])
                end
                break
             end
           end
        end--]]
         
        if tri==1 and reaper.GetToggleCommandState(triplet)==0 then
           reaper.Main_OnCommand(triplet,0)
        end
  end
  
  -------------------------------------------MAIN-------------------------------------------------
  local function main()
      
      pro_name=reaper.GetProjectName(0)
      if pro_name=='' then pro_name='Unsaved project' end
      it_n=reaper.CountSelectedMediaItems(0)
      
      Start, End = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      ::begin::
      s,e=reaper.BR_GetArrangeView(0)
      if Start~=End then
         if s/(Start-(End-Start)*0.1)>0.99 and s/(Start-(End-Start)*0.1)<1.11 and 
            e/(End+(End-Start)*0.1)>0.99 and e/(End+(End-Start)*0.1)<1.11 then
            LoadScreenPosition()
         else
            SaveScreenPosition()
            reaper.BR_SetArrangeView(0,Start-(End-Start)*0.1,End+(End-Start)*0.1)
         end
         AdjustGrid()
      elseif it_n==1 then
         it=reaper.GetSelectedMediaItem(0,0)
         Start=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
         End=Start+reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
         goto begin
      elseif it_n>1 then
         cmd=reaper.NamedCommandLookup("_SWS_TOGZOOMIONLY")
         reaper.Main_OnCommand(cmd,0)
      end
  
  end
  
  reaper.defer(main)
