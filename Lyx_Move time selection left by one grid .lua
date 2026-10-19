  
  r=reaper
  
  --------------
  local function OneStep(pos)
      
      reaper.Main_OnCommand(40755, 0) -- Snapping: Save snap state
      reaper.Main_OnCommand(40754, 0) -- Snapping: Enable snap

      local grid_duration
      if reaper.GetToggleCommandState( 41885 ) == 1 then -- Toggle framerate grid
        grid_duration = 0.4/reaper.TimeMap_curFrameRate( 0 )
      else
        local _, division = reaper.GetSetProjectGrid( 0, 0, 0, 0, 0 )
        local tmsgn_cnt = reaper.CountTempoTimeSigMarkers( 0 )
        local _, tempo
        if tmsgn_cnt == 0 then
          tempo = reaper.Master_GetTempo()
        else
          local active_tmsgn = reaper.FindTempoTimeSigMarker( 0, pos )
          _, _, _, _, tempo = reaper.GetTempoTimeSigMarker( 0, active_tmsgn )
        end
        grid_duration = 60/tempo * division -- = 1/4 grid on purpose: small probe steps so SnapToGrid lands on the next line
      end
      
      local grid, n, start = pos, 0, pos
      while (grid >= pos) and n < 64 do -- n: safety cap so it can never hang
          pos = pos - grid_duration
          grid = reaper.SnapToGrid(0, pos)
          n = n + 1
      end
      
      reaper.Main_OnCommand(40756, 0) -- Snapping: Restore snap state
      if grid >= start then return -1 end -- no earlier grid line (project start): main() stops
      return grid
  end
  
  --------------
  local function main()
      
      pos_a,pos_b=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
      
      if pos_a==pos_b then return end
      
      pos_a=OneStep(pos_a)
      if pos_a<0 then return end
      pos_b=OneStep(pos_b)
      
      reaper.GetSet_LoopTimeRange2(0,true,false,pos_a,pos_b,false)
      
  end
  
  reaper.defer(main)
