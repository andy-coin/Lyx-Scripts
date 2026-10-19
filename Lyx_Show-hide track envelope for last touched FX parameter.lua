    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    -----CUSTOM-----
        env_lane = true
        hide_last_fx = true
        default_height = 250 --pixels

    --------------
    local function SetEnvVis(data,toggle)

        local Data,tr,fx,parm,env

        Data={}
        for value in data:gmatch("[^|]*") do
            Data[#Data+1] = tonumber(value)            
        end
        
        if #Data<5 then return end
        
        tr = api.gt(0,Data[1])
        fx = Data[4]
        parm = Data[5]


        if  Data[2]>=0 then --item FX
            local item,take
            item = api.gti(tr,Data[2])
            take = reaper.GetMediaItemTake(item,Data[3])
            env  = reaper.TakeFX_GetEnvelope(take,fx,parm,false)
        elseif Data[1]>=0 and tr then --track FX
            env = reaper.GetFXEnvelope(tr,fx,parm,false)
        end

        if  env then
            local br_env,active,visible,armed,lane,laneHeight,defaultShape,_,Type,faderScaling,arm,vis
            br_env = reaper.BR_EnvAlloc(env,false)
            active,visible,armed,lane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties(br_env)
            if  not toggle then 
                vis = not visible
            else
                vis = (toggle == 1 and true ) or false
            end
            reaper.BR_EnvSetProperties(br_env,active,vis,armed,lane,default_height,defaultShape,faderScaling) 
            reaper.BR_EnvFree(br_env,true)
        end

        api.ua()

    end

    --------------
    local function main()
        
       
        editor = reaper.MIDIEditor_GetActive()
        focus  = reaper.JS_Window_GetFocus()
        focus = reaper.JS_Window_GetParent(focus)
        if  editor and editor == focus then
            reaper.MIDIEditor_OnCommand(editor,40181)--move notes left one pixel
            return
        end
      
        reaper.PreventUIRefresh(1)
        
        local env

        trackzzz = r.SaveTracks()
        
        ret,trackidx,itemidx,takeidx,fxidx,parm = reaper.GetTouchedOrFocusedFX(0)
        FX_Data = trackidx.."|"..itemidx.."|"..takeidx.."|"..fxidx.."|"..parm

        last_FX_Data = api.load("last_touch_fx",pro_name)

        api.save("last_touch_fx",pro_name,FX_Data,false)

        api.cmd(41142,0)--Show/hide track/take envelope for last touched FX parameter
        api.cmd(41142,0)--Show/hide track/take envelope for last touched FX parameter

        if  last_FX_Data == FX_Data then
            SetEnvVis(FX_Data)
        else
            api.cmd(41142,0)--Show/hide track/take envelope for last touched FX parameter
            SetEnvVis(FX_Data,1) 
            if  hide_last_fx then
                SetEnvVis(last_FX_Data,0) 
            end
        end
        
        reaper.PreventUIRefresh(-1)
        
    end
    
    reaper.defer(main)
    --api.cmd(41142,0)--Show/hide track/take envelope for last touched FX parameter
    
