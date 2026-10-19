    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
        max_limit=nil
        min_limit=nil

    --------------
    local function scroll()  
        local track_tcpy = api.gtv(api.gst(0,0),"I_TCPY")
        local mainHWND = reaper.GetMainHwnd()
        local windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
        local _,scroll_position = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
        reaper.JS_Window_SetScrollPos( windowHWND, "v",scroll_position+track_tcpy-math.floor(TCP_max*0.2))
    end
    
    --------------
    local function SaveVerticalZoom(TR_code,TR_TCPH)

        local mainHWND,windowHWND,_,scroll_position
        mainHWND = reaper.GetMainHwnd()
        windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
        _,scroll_position = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
        
        TR_code[#TR_code+1]=scroll_position

        TR_TCPH = serialize(TR_TCPH)
        TR_code = serialize(TR_code)
        
        reaper.SetExtState("Global Vertical Zoom",pro_name.."__TR_TCPH",TR_TCPH,false)
        reaper.SetExtState("Global Vertical Zoom",pro_name.."__TR_Code",TR_code,false)

    end

    --------------
    local function LoadVerticalZoom()

        --
        local TR_code,TR_TCPH,code,TCPH,trz,tcph,scroll
        
        TR_code = reaper.GetExtState("Global Vertical Zoom",pro_name.."__TR_Code")
        TR_TCPH = reaper.GetExtState("Global Vertical Zoom",pro_name.."__TR_TCPH")
        
        code=unserialize(TR_code)
        TCPH=unserialize(TR_TCPH)
        
        if type(code[#code])=="number" then
            scroll=code[#code]
            table.remove(code)
        end

        if  type(TCPH[#TCPH])=="boolean" then
            reaper.SetExtState("editor_toggle",pro_name,1)
            table.remove(TCPH)
        end
        
        trz={}
        for abi=1,#code do
            trz[#trz+1]=reaper.BR_GetMediaTrackByGUID(0,code[abi])
            if  not TCPH[abi+1] or TCPH[abi]~=TCPH[abi+1] then
                r.SameTCPH(trz,TCPH[abi],false)
                trz={}
            end
        end
        
        local mainHWND = reaper.GetMainHwnd()
        local windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
        reaper.JS_Window_SetScrollPos( windowHWND, "v", scroll or 0 )

    end

    -----------------------------------Folder State---------------------------------------
    local function FolderState()
        
        local single,tcph_ori,TR_guid ={},{},{}
        local small,tiny,TCPH = 0,0,0
        
        for abi=1,reaper.CountTracks(0) do 
            local tr=reaper.GetTrack(0,abi-1)
            if  not reaper.IsTrackVisible(tr,false) then goto tail end
            local parent=r.HaveParent(tr)
            if  parent then
                size=reaper.GetMediaTrackInfo_Value(parent,"I_FOLDERCOMPACT")
                if  size==1 then
                    small=small+1
                    goto tail
                elseif size==2 then
                    tiny=tiny+1
                    goto tail
                end
            end
            single[#single+1]=tr
            if  api.gtv(tr,"C_LANESCOLLAPSED")==0 then
                reaper.SetOnlyTrackSelected(tr)
                reaper.Main_OnCommand(43100,0)--small lane
            end
            _,TR_guid[#TR_guid+1] = reaper.GetSetMediaTrackInfo_String(tr,"GUID","",false)
            tcph_ori[#tcph_ori+1] = reaper.GetMediaTrackInfo_Value(tr,"I_TCPH")
            TCPH=TCPH+tcph_ori[#tcph_ori]
            ::tail::
        end
        
        r.Reorder(TR_guid,tcph_ori)

        return TCPH,single,small,tiny,TR_guid,tcph_ori
        
    end
    
    ----------------------------------MAIN ACTION------------------------------------
    local function main(editor)

        if api.ct(0) == 0 then return end
        
        local TCPH,X,Y,Z,TR_code,tcph_ori,space,tcph,best,dis
        
        r.SaveTracks(true)

        TCPH,X,Y,Z,TR_code,tcph_ori=FolderState()

        space = max-min*Y-fold*Z
        tcph = math.floor(TCPH/#X) 
        best = math.max(min,math.min(max,math.floor(space/#X)))
         
        dis=best-tcph
        
        if  math.abs(dis) > 1 then 
                      
            SaveVerticalZoom(TR_code,tcph_ori)
            
            r.SameTCPH(X,best,false)

            if  #X*best<TCP_max then
                api.cmd(api.name("_XENAKIOS_TVPAGEHOME"),0)--scroll to top
            else
                scroll()
            end
            
        else
            LoadVerticalZoom()
        end
        r.RestoreTracks(true)
        
        reaper.UpdateArrange()
        
    end    
    
    --------------------
    ------EXECUTE-------
    --------------------
    
    TCP_max,TCP_min,fold=r.GetTCP_Size()
    
    min=(type(min_limit)=="number" and r.NumberCage(min_limit,TCP_min,40,true)) or TCP_min
    max=(type(max_limit)=="number" and r.NumberCage(max_limit,40,TCP_max,true)) or TCP_max

    main()
    reaper.defer(function() end)
