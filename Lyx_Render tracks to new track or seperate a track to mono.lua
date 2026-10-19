  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
  
      it_n=reaper.CountSelectedMediaItems(0)
      if it_n==0 then return end
      
      if it_n==1 then
         item=reaper.GetSelectedMediaItem(0,0)
         take=reaper.GetActiveTake(item)
         if not take then return end -- empty item: nothing to render
         if not reaper.TakeIsMIDI(take) then
            fx_n=reaper.TakeFX_GetCount(take)
            if fx_n==0 then
               cmd=r.ScriptID("ReaTeam Scripts/Items Editing/rodilab_Explode multichannel items to mono items in new tracks (without render).lua")
               reaper.Main_OnCommand(cmd,0)
               return
            end
         else
            midi=true
            notes=reaper.MIDI_CountEvts(take)
            tr=reaper.GetMediaItemTrack(item)
            instrument=reaper.TrackFX_GetInstrument(tr)
            if instrument==-1 and notes==0 then return end
         end
      end
      
      if midi then 
         reaper.Main_OnCommand(40894,0)
      else
         cmd=r.ScriptID("Scripts for render/Yanick_Mixdown selection (windowless).lua")
         reaper.Main_OnCommand(cmd,0)
      end
      
  end
  
  main()
  api.cmd(40913,0)--scroll to select track
  
