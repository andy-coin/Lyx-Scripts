    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        --local over    = api.name("_BR_OPTIONS_MARKER_Z_OVER_ITEMS")
        --local under   = api.name("_BR_OPTIONS_MARKER_Z_UNDER_ITEMS")
         
        local _,cur_Zorder    = reaper.get_config_var_string("rulerlayout")
        --local under   = api.name("_MARKER_Z_UNDER_ITEMS")
        
        --Zorder = (cur_Zorder ~= 352 and 352 ) or 256
        api.cc()
        --over = tonumber(cur_Zorder) & 96 ~= 0
        --msg(cur_Zorder )
        local Zorder = tostring(tonumber(cur_Zorder) ~ 96)
        --msg(Zorder,3 )
        reaper.SNM_SetStringConfigVar('rulerlayout',tostring(Zorder))
        --reaper.UpdateTimeline()

        --action = (toggle and under) or over

        --api.cmd(action,0)
    end

    reaper.defer(main)
