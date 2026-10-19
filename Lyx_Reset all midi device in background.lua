	
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    ---setting---
    
    ID={3,     --Nuances Fader
	   15,    --Numa X piano
	   7,     --Stream Deck
	   }
    
    --type your midi device id above,seperate with ","
    

    --------------
    local function main()
		   
	   time=reaper.time_precise()
		 
	   if  Time-time<=-0.01 then
		  
		  for abi=1,#ID do
			 local bool,name = reaper.GetMIDIInputName(ID[abi],"")
		    
			 if  not Bool[ID[abi]] and bool then
				reaper.Main_OnCommand(41175,0)
				BBB(name.."  [Enable]")
			 elseif Bool[ID[abi]] and not bool then
				BBB(name.."  [Disable]")
			 end
			 Bool[ID[abi]]=bool
		  end
		  
		  Time=time
	    
	   end
		
	   reaper.defer(main)
	
    end
	
    Time=reaper.time_precise()
    Bool={}
    
    for abi=1,#ID do
	   Bool[ID[abi]] = reaper.GetMIDIInputName(ID[abi],"")
    end
    
    reaper.defer(main)
