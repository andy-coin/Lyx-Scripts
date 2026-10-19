    
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -----CUSTOM-----
    lane_hieght_mode = 2
        
        -- -1 stay original
        --  0 follow track height 
        --  1 fix_lane_height
        --  2 depends
    
    cycle = false
    fixed_lane_height = 275 -- false or number in pixels
    in_envelope_lane = false
    

    local function main()

        local tr, env_n, key, env, br_env, lane_height

        trzzz = r.SaveTracks()

        for abi = 1, #trzzz do
        
            tr = trzzz[abi]
            
            if not tr then goto NEXT end

            api.sot(tr)
            
            env_n = api.cte(tr)

            if env_n == 0 then BBB("No active envelope in track") goto NEXT end

            key = 0

            for abig = 1, env_n do
                env = api.gte(tr,abig-1)

                local ret, chunk = api.geC(env, "", false)
                local show = chunk:match("VIS 1")
                
                if  show then
                    if  cycle then
                        key = (abig == env_n and 0) or abig
                    else
                        key = (abig == env_n and nil) or abig
                    end
                    break
                end

            end
            
            api.cmd(40889,0) -- Envelope: Hide all envelopes for tracks

            if not key then return end
        
            env = api.gte(tr,key)
            
            br_env = api.brea(env,false)
            
            local active ,visible ,arm, inlane, laneH, def,_,_,_,_,fad = api.breg(br_env)
            
            tcph = api.gtv(tr,"I_TCPH")
            
            if lane_hieght_mode == -1 then
                lane_height = laneH
            elseif lane_hieght_mode == 2 then
                lane_height = ( tcph >= fixed_lane_height and tcph ) or fixed_lane_height
                in_envelope_lane = (tcph < fixed_lane_height and true) or false
            else
                lane_height = (tonumber(fixed_lane_height) and fixed_lane_height) or tcph
                lane_height = r.NumberCage(lane_height,30,1080,true)
            end

            api.bres(br_env,active,true,arm,in_envelope_lane,lane_height,def,fad)

            api.bref(br_env,true)

            ::NEXT::

        end

        api.ua()
        
        r.RestoreTracks(trzzz)

    end

    main()
