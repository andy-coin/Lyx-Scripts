    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    if not r.Need("SWS") then return end

    -----CUSTOM-----
        fix_laneH = false
        fixed_lane_height = 200
    
    local function main()
        
        local trz
        
        trz = r.SaveTracks()

        for abi=1, #trz do
            local track, tcph, SHOW
            local ENV = {}
            
            track = trz[abi]
            tcph= api.gtv(track ,"I_TCPH","",false) 
            
            for i=1,api.cte(track) do
                WORK = true
                local env=api.gte( track, i-1 )
                local br_env = reaper.BR_EnvAlloc( env, false )
                local act,vis,arm,inlane,laneH,def,_,_,_,_,fad = reaper.BR_EnvGetProperties(br_env)
                if  not (vis and inlane) then
                    SHOW = true
                    local env_height = (fix_laneH and fixed_lane_height) or tcph
                    reaper.BR_EnvSetProperties(br_env,act,true,arm,true,env_height,def,fad)
                else
                    reaper.BR_EnvFree(br_env,false)
                    api.sot(track)
                    api.cmd(40889,0) -- Hide all envelopes for tracks
                    break
                end
                reaper.BR_EnvFree(br_env,true)
                ENV[#ENV+1] = env
            end
            if not SHOW then
                for abi = 1, #ENV do
                    reaper.GetSetEnvelopeInfo_String(ENV[abi], "VISIBLE", "0", true)
                end
            end
        end

        reaper.TrackList_AdjustWindows(true)

        r.RestoreTracks(trz)
        
        api.ua()

        if not WORK then BBB("No active envelopes",2) end

    end       
    
    reaper.defer(main)
