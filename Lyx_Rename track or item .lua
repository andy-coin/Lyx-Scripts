    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()
        
        local _,detail,tr_n,it_n,ori_name,ok,csv,answer,gap
        
        win,_,det=reaper.BR_GetMouseCursorContext()
        it_n=reaper.CountSelectedMediaItems(0)
        tr_n=reaper.CountSelectedTracks(0)
        answer={}
        
        if  it_n==0 and tr_n==0 then return end
        
        gap=""
        for abi=1,20 do
            gap=gap.." "
        end
        
        if  (win=="tcp" and it_n>1 and tr_n==1 ) or 
            (win=="arrange" and it_n>tr_n) or
            (det=="item" or det=="item_stretch_marker" and it_n>0 ) then
                
            item=reaper.GetSelectedMediaItem(0,0)
            if not reaper.ValidatePtr2(0,item,"MediaItem*") then return end
            take=reaper.GetActiveTake(item)
            if not reaper.ValidatePtr2(0,take,"MediaItem_Take*") then return end
            
            _,ori_name=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false)
            ok, csv = r.GetUserInputs("Rename "..it_n.." items",5,
                                            gap..'Rename  :\30'..
                                            gap..'Replace text :\30'..gap..'Replace to :\30'..
                                            gap..'New text:\30'..gap..'Add before:\30'..
                                            'extrawidth=200\30separator=\30',ori_name)

            if not ok then return end
            
            for name in csv:gmatch("[^\30]*") do
                answer[#answer+1]=name
            end

            r.Undo("Rename items", function()
            for abi=1,it_n do
                local item,take,ori_name,new_name,pos
                item=reaper.GetSelectedMediaItem(0,abi-1)
                take=reaper.GetActiveTake(item)
                if not take then goto NEXT end
                _,ori_name=reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false)
                
                if  string.len(answer[2])>0 then
                    new_name=ori_name:gsub(ESCPattern(answer[2]),answer[3])
                elseif string.len(answer[4])>0 then 
                    pos=ori_name:find(answer[5]) or 0
                    new_name=( pos>0 and ori_name:sub(0,pos-1)..answer[4]..ori_name:sub(pos,-1)) or ori_name:sub(pos,-1)..answer[4]
                else
                    new_name=answer[1]
                end
                
                reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME",new_name,true)
                
                ::NEXT::
            
            end
            end)
            
        else
        
            track=reaper.GetSelectedTrack(0,0)
            _,ori_name=reaper.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
            
            first_tr=reaper.GetSelectedTrack(0,0)
            last_tr =reaper.GetSelectedTrack(0,reaper.CountSelectedTracks(0)-1)
            first_ip=math.floor(reaper.GetMediaTrackInfo_Value(first_tr,"IP_TRACKNUMBER"))
            last_ip=math.floor(reaper.GetMediaTrackInfo_Value(last_tr,"IP_TRACKNUMBER"))
            
            if  tr_n==1 then
                api.cmd(40696,0)--rename track
                return
                --num=tostring(first_ip)
            elseif first_ip+tr_n-1==last_ip then
                num=tostring(first_ip).."-"..tostring(last_ip)
            else
                num=""
                for abi=1,tr_n-1 do
                    num=num..tostring(math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack(0,abi-1),"IP_TRACKNUMBER"))).."."
                end
                num=num..tostring(math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetSelectedTrack(0,tr_n-1),"IP_TRACKNUMBER")))
            end
            
            ok, csv = r.GetUserInputs("Rename "..tr_n.." tracks",5,
                                            gap.."Rename  track  "..num.." :\30"..
                                            gap..'Replace text :\30'..gap..'Replace to :\30'..
                                            gap..'New text:\30'..gap..'Add before:\30'..
                                            'extrawidth=200\30separator=\30',ori_name)
            

            if  not ok then return end
            
            for name in csv:gmatch("[^\30]*") do
                answer[#answer+1]=name
            end

            r.Undo("Rename tracks", function()
            for abi=1,tr_n do
                local _,track,ori_name,new_name,pos
                track=reaper.GetSelectedTrack(0,abi-1)
                _,ori_name=reaper.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
                
                if  string.len(answer[2])>0 then
                    new_name=ori_name:gsub(ESCPattern(answer[2]),answer[3])
                elseif string.len(answer[4])>0 then
                    pos=ori_name:find(answer[5]) or 0
                    new_name=( pos>0 and ori_name:sub(0,pos-1)..answer[4]..ori_name:sub(pos,-1)) or ori_name:sub(pos,-1)..answer[4]
                else
                    new_name=answer[1]
                end
                reaper.GetSetMediaTrackInfo_String(track,"P_NAME",new_name,true)
            end
            end)
            
        end
    end 
    
    r.run(main)
    
