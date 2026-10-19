 
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
      
      local trz,tr,midi,fx
      
      trz=r.SaveTracks()
      
      if #trz==0 then return end
      
      for abi=1,#trz do
           
          tr=trz[abi]
          midi=api.gtv(tr,"I_RECINPUT")>=4096
          
          if  not midi then goto NEXT end
          
          abi=0
          time=api.now()
          
          repeat
              fx=abi+0x1000000
              _,name=reaper.TrackFX_GetFXName(tr,fx)
              if  name=="JS: MIDI Transpose Track" then
                  reaper.TrackFX_Delete(tr,fx)
              else
                  abi=abi+1
              end
          until abi>=reaper.TrackFX_GetRecCount(tr) or (api.now()-time)>0.1
          
          ::NEXT::
      end
  end
  
  main()
  reaper.defer(function() end)
