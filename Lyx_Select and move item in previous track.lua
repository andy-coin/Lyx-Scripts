
local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")

-----CUSTOM-----
skip_collapsed = true
ingerit_arm = true
--------------
local function GetAllFloatingFXWindows(track)

    local hwnds,names,pre_fxs,post_fxs
    
    hwnds,names= {},{}

    for fx = 1,reaper.TrackFX_GetRecCount(track) do
        local _,name,fx_in,hwnd,slot
        fx_in = fx-1 + 0x1000000
        hwnd = reaper.TrackFX_GetFloatingWindow(track,fx_in)
        _,name = reaper.TrackFX_GetFXName(track,fx_in)
        name=name:match(".-: (.*)%(.-%)")
        names[fx]=name
        slot = 1
        if  hwnd then
            for abi = 1,#names-1 do
                if name == names[abi] then
                   slot = slot + 1
                end
            end
            hwnds[#hwnds+1]={hwnd=hwnd,name=name,slot=slot,idx=fx_in}
        end
    end

    pre_fxs=hwnds

    hwnds,names= {},{}
    for fx = 1,reaper.TrackFX_GetCount(track) do
        local _,name,hwnd,slot
        hwnd = reaper.TrackFX_GetFloatingWindow(track,fx-1)
        _,name = reaper.TrackFX_GetFXName(track,fx-1)
        name=name:match(".-: (.*)%(.-%)")
        names[fx]=name
        slot = 1
        if  hwnd then
            for abi = 1,#names-1 do
                if name == names[abi] then
                   slot = slot + 1
                end
            end
            hwnds[#hwnds+1]={hwnd=hwnd,name=name,slot=slot,idx=fx-1}
        end
    end

    post_fxs=hwnds

    return pre_fxs,post_fxs
end
    
--------------
local function main()
    
    local tr,idx,target,parent,visible
    
    tr=api.gst(0,0)
    
    if  not tr then return end
    
    idx = api.gtv(tr,"IP_TRACKNUMBER")
    
    while idx > 1 do
        target = api.gt(0,idx-2)
        parent = r.HaveParent(target)
        if  skip_collapsed then
            visible = reaper.IsTrackVisible(target,false) and not (parent and api.gtv(parent,"I_FOLDERCOMPACT")==2)
        else
            visible = reaper.IsTrackVisible(target,false)
        end
        if  visible then
            api.sot(target)
            local mainHWND,windowHWND,_,ori_scroll,TCPY
            TCPY = api.gtv(target,"I_TCPY")
            if  TCPY  < 100 then
                mainHWND = reaper.GetMainHwnd()
                windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
                _,ori_scroll = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
                reaper.JS_Window_SetScrollPos( windowHWND, "v",math.floor( ori_scroll + TCPY - 100))
            elseif TCPY > 800 then
                api.cmd(40913,0)--scroll track into view
            end
            
            break
        else
            idx = idx-1
        end
    end
    
    if not target then return end
    
    if api.csi(0) == 0 then goto FX_WINDOW end


    do  --change item selection in same position
        api.pur(1)

        local min,max,starttime,endtime,save_time,restore_time

        min,max=r.GetProjectLength(true)
        starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        save_time    = (starttime ~= endtime and api.name("_SWS_SAVETIME2")) or 40020
        restore_time = (starttime ~= endtime and api.name("_SWS_RESTTIME2")) or 40020
        api.cmd(save_time,0)
        reaper.GetSet_LoopTimeRange2(0,true,false,min,max,false)
        api.cmd(40289,0) --unselect all items
        api.cmd(40718,0) --select all item in select track in time selection
        api.cmd(restore_time,0)
        
        api.pur(-1)
    end
    
    ::FX_WINDOW::
    --keep same FX window in same position if exsit
    r.SwitchFxWindow(target)

    record = reaper.TrackFX_GetInstrument(tr)~=-1 and api.gtv(tr,"I_RECARM")==1 and api.gtv(tr,'B_AUTO_RECARM') == 0
    Ins = reaper.TrackFX_GetInstrument(target)~=-1

    if  inherit_arm and record and Ins then
        api.stv(tr,"I_RECARM",0)
        api.stv(target,"I_RECARM",1)
        mon = (api.gtv(target,"I_RECINPUT")==1040 and 0) or api.gtv(tr,"I_RECMON")
        api.stv(tr,'I_RECMON',0)
        api.stv(target,"I_RECMON",mon)
    end 
    
end

main()
reaper.defer(function() end)


