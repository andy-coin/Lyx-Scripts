
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
--script_path=script_path:gsub("/MIDI Editor","")
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")

-----CUSTOM-----
    
    small  = 80
    normal = 160
    big    = 360
    
    size = {['80']=180, ['180'] = 400, ['400'] = 80}

local function main()
    
    api.mcw()
    env = api.mce() or api.gse()

    if  not env then r.billboard("No Select Envelope T_T") return end 

    free_env = reaper.BR_EnvAlloc(env,false)
    act,vis,arm,inlane,laneH,def,_,_,_,_,fad = reaper.BR_EnvGetProperties(free_env)
    laneH = size[tostring(laneH)]
    reaper.BR_EnvSetProperties(free_env,act,vis,arm,inlane,laneH or 180,def,fad)
    reaper.BR_EnvFree(free_env,true )
    
end

reaper.defer(main)
