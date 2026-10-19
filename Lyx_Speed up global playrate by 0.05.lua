   
   local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
   --script_path=script_path:gsub("/MIDI Editor","")
   package.path = package.path..";"..script_path.."?.lua"
   local r=require("_Lyx_HOME")
   
   local function main()
         
         local rate=reaper.Master_GetPlayRate(0)
         
         rate = rate + 0.05
         
         if rate == 0 then return end
         
         reaper.CSurf_OnPlayRateChange(rate)
         
         Act="Set master playrate to "..tostring(rate).."%"
   
   end
   
   reaper.Undo_BeginBlock()
   main()
   reaper.Undo_EndBlock(Act,-1)