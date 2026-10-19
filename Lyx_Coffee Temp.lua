    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function coffee()

        _,csv = r.GetUserInputs("Coffee Temp", 3, "Target Temp:,Cold Water Temp:,Hot Water Temp:, separator=\31", "93\31".."27\31".."98")

        if not _ then return end
        
        local Temp={}
        
        csv=csv.."\31"

        for temp in csv:gmatch("(%d-)\31") do
            Temp[#Temp+1] = temp
        end

        target  = tonumber(Temp[1])
        cold    = tonumber(Temp[2])
        hot     = tonumber(Temp[3])

        cc = r.DIGI((hot-target)/(target-cold)*hot,1,true)

        reaper.ShowConsoleMsg("Coffee Temp:\n")
        reaper.ShowConsoleMsg("Hot  Water: "..hot.." cc\n")
        reaper.ShowConsoleMsg("Cold Water: "..tostring(cc).." cc")

    end

    r.run(coffee)
