  
   local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
   package.path = package.path..";"..script_path.."?.lua"
   local r=require("_lib._Lyx_HOME")
  
  --------------
  -- Find a floating FX window: returns 'track',track,fx or 'take',take,fx (nil if none)
  local function FirstFloatingFX()
      for t = 0, reaper.CountTracks(0) do
          local tr = (t == 0 and reaper.GetMasterTrack(0)) or reaper.GetTrack(0,t-1)
          for fx = 0, reaper.TrackFX_GetCount(tr)-1 do
              if reaper.TrackFX_GetFloatingWindow(tr,fx) then return 'track',tr,fx end
          end
          for fx = 0, reaper.TrackFX_GetRecCount(tr)-1 do
              if reaper.TrackFX_GetFloatingWindow(tr,fx+0x1000000) then return 'track',tr,fx+0x1000000 end
          end
      end
      for i = 0, reaper.CountMediaItems(0)-1 do
          local it = reaper.GetMediaItem(0,i)
          for k = 0, reaper.CountTakes(it)-1 do
              local tk = reaper.GetTake(it,k)
              if tk then
                  for fx = 0, reaper.TakeFX_GetCount(tk)-1 do
                      if reaper.TakeFX_GetFloatingWindow(tk,fx) then return 'take',tk,fx end
                  end
              end
          end
      end
  end

  --------------
  local function main()

      if r.IsMidiEditorFocus(api.M()) then
         api.Mcmd(api.M(),40447)
         return 
      end

      local retval,tr_n,it_n,fx_n = reaper.GetFocusedFX2()
      local kind,obj,fx

      if retval & 3 ~= 0 then
         local tr = (tr_n==0 and reaper.GetMasterTrack(0)) or reaper.GetTrack(0,tr_n-1)
         if tr and it_n==-1 then
            kind,obj,fx = 'track',tr,fx_n
         elseif tr then
            local it = reaper.GetTrackMediaItem(tr,it_n)
            local tk = it and reaper.GetTake(it,fx_n>>16)
            if tk then kind,obj,fx = 'take',tk,fx_n & 0xFFFF end
         end
         -- not focused any more (retval & 4): only use it if its window is still floating
         if kind and retval & 4 ~= 0 then
            local float = (kind=='track' and reaper.TrackFX_GetFloatingWindow(obj,fx)) or
                          (kind=='take' and reaper.TakeFX_GetFloatingWindow(obj,fx))
            if not float then kind = nil end
         end
      end

      -- no focused FX window: fall back to any floating FX window
      if not kind then kind,obj,fx = FirstFloatingFX() end

      if kind=='track' then
         reaper.TrackFX_SetEnabled(obj,fx,not reaper.TrackFX_GetEnabled(obj,fx))
      elseif kind=='take' then
         reaper.TakeFX_SetEnabled(obj,fx,not reaper.TakeFX_GetEnabled(obj,fx))
      end
      
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Toggle bypass focus FX",-1)
