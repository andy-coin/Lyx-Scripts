  
   local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
   package.path = package.path..";"..script_path.."?.lua"
   local r=require("_Lyx_HOME")
  
  --------------
  local function main()

      if r.IsMidiEditorFocus(api.M()) then
         api.Mcmd(api.M(),40447)
         return 
      end

      retval,tr_n,it_n,fx_n = reaper.GetFocusedFX2()
      
      if retval==0 then 
         cmd=reaper.NamedCommandLookup("_RS88532f1a953d5e0d546426226abbb4c78ef6c36f")
         --reaper.Main_OnCommand(cmd,0)--mpl_Bypass all FX except instruments on selected tracks.lua
         return
      end
      
      if it_n==-1 then
         if tr_n==0 then
            tr=reaper.GetMasterTrack(0)
         else
            tr=reaper.GetTrack(0,tr_n-1)
         end
         bypass=reaper.TrackFX_GetEnabled(tr,fx_n)
         reaper.TrackFX_SetEnabled(tr,fx_n,not bypass)
      else
         if tr_n==0 then
            tr=reaper.GetMasterTrack(0)
         else
            tr=reaper.GetTrack(0,tr_n-1)
         end
         it=reaper.GetTrackMediaItem(tr,it_n)
         tk=reaper.GetActiveTake(it)
         bypass=reaper.TakeFX_GetEnabled(tk,fx_n)
         reaper.TakeFX_SetEnabled(tk,fx_n,not bypass)
      end  
      
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Toggle bypass focus FX",-1)
