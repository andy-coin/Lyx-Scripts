
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    local SwitchVersion=require("Lyx_Track versions alternative-switch to selected version")

    local function main()

        reaper.BR_GetMouseCursorContext()
        track=reaper.BR_GetMouseCursorContext_Track()
        if not track then return end
        
        local idx,first,last,low,high

        -- track with expanded fixed lanes: switch version instead of selecting
        if SwitchVersion(track) then return end

        idx   = api.gtv(track,"IP_TRACKNUMBER")
        
        if  api.cst(0)>0 then
            first = api.gtv(api.gst(0,0),"IP_TRACKNUMBER")
            last  = api.gtv(api.gst(0,api.cst(0)-1),"IP_TRACKNUMBER")
        else
            first = 1
            last = 1
        end
            
        if  idx<=first then
            low = idx
            high = first
        elseif idx>=last then
            low = last
            high = idx
        else
            local _,main_window,arrange,t,b,middle,first_tcpy,last_tcpy

            main_window = reaper.GetMainHwnd()
            arrange = reaper.JS_Window_FindChildByID(main_window,1000)
            _,_,t,_,b=reaper.JS_Window_GetRect(arrange)
            middle = math.floor(math.abs(t-b)/2)
            
            first_tcpy = api.gtv(api.gt(0,first-1),"I_TCPY") 
            last_tcpy  = api.gtv(api.gt(0,last-1),"I_TCPY")

            if  math.abs(middle-first_tcpy)<math.abs(middle-last_tcpy) then
                low  = first
                high = idx
            else
                low  = idx
                high = last
            end
        end

        reaper.Main_OnCommand(40297,0)
        for i=low,high do
            local tr=api.gt(0,i-1)
            if  reaper.IsTrackVisible(tr,false) then
                api.sts(tr,true) 
            end
        end

    end

    main()
    reaper.defer(function()end)
