
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    ---setting---

    NAMES={"Nuances Fader",
           "Numa X",
           "Stream Deck",
           }

    --type part of your MIDI device names above (as shown in Preferences > MIDI Inputs), separate with ","


    --------------
    local function Present(keyword)
        for dev=0, reaper.GetNumMIDIInputs()-1 do
            local ok,name = reaper.GetMIDIInputName(dev,"")
            if  ok and name:find(keyword,1,true) then return true, name end
        end
        return false
    end

    local function main()

	   time=reaper.time_precise()

	   if  Time-time<=-0.01 then

		  local reset = false
		  for abi=1,#NAMES do
			 local bool,name = Present(NAMES[abi])

			 if  not Bool[abi] and bool then
				reset = true
				BBB(name.."  [Enable]")
			 elseif Bool[abi] and not bool then
				BBB(NAMES[abi].."  [Disable]")
			 end
			 Bool[abi]=bool
		  end
		  if  reset then reaper.Main_OnCommand(41175,0) end -- reset all MIDI devices, once per check

		  Time=time

	   end

	   reaper.defer(main)

    end

    Time=reaper.time_precise()
    Bool={}

    for abi=1,#NAMES do
	   Bool[abi] = Present(NAMES[abi])
    end

    reaper.defer(main)
