
  r=reaper
  
  --------------
  local function main()
      local hwnds = {}
  
      --for _, proj in ipairs(projects) do
      local master_track = reaper.GetMasterTrack(0)
      for fx = 0, reaper.TrackFX_GetCount(master_track) - 1 do
          local hwnd = reaper.TrackFX_GetFloatingWindow(master_track, fx)
          if hwnd then 
             bypass=reaper.TrackFX_GetEnabled(master_track,fx)
             reaper.TrackFX_SetEnabled(master_track,fx,not bypass)
          end
      end
      for t = 0, reaper.CountTracks(0) - 1 do
          local track = reaper.GetTrack(0, t)
          for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
              local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
              if hwnd then 
                 bypass=reaper.TrackFX_GetEnabled(track,fx)
                 reaper.TrackFX_SetEnabled(track,fx,not bypass)
              end
          end
          for fx = 0, reaper.TrackFX_GetRecCount(track) - 1 do
              local fx_in = fx + 0x1000000
              local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx_in)
              if hwnd then 
                 bypass=reaper.TrackFX_GetEnabled(track,fx_in)
                 reaper.TrackFX_SetEnabled(track,fx_in,not bypass)
              end
          end
      
          for i = 0, reaper.CountTrackMediaItems(track) - 1 do
              local item = reaper.GetTrackMediaItem(track, i)
              for tk = 0, reaper.GetMediaItemNumTakes(item) - 1 do
                  local take = reaper.GetMediaItemTake(item, tk)
                  if reaper.ValidatePtr(take, 'MediaItem_Take*') then
                      for fx = 0, reaper.TakeFX_GetCount(take) - 1 do
                          local hwnd = reaper.TakeFX_GetFloatingWindow(take, fx)
                          if hwnd then 
                             bypass=reaper.TakeFX_GetEnabled(take,fx)
                             reaper.TakeFX_SetEnabled(take,fx,not bypass)
                          end
                      end
                  end
              end
          end
      end
      --end
  end
  
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Toggle bypass all floating FX",-1)
