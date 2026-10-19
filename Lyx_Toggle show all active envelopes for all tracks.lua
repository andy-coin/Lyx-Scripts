    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")   
    
    -----CUSTOM-----
    envelope_lane = 3
    
    -- 0 ALL in envelope lane;
    -- 1 ALL in track lane;
    -- 2 only track UNDER MOUSE in envelope lane;
    -- 3 every SELECTED tracks in envelope lane;
    
    dim = 1.3 -- color dim intensity

    --------------
    local function ChangeColor(change)
        
        local midi,audio,video,gray,peak
        midi=18313493
        audio=18696831  
        video=28685749
        gray=23093344
        peak=16777215
        
        
        
        local function DimColor(color,dim)
            
            local r,g,b
            
            r,g,b=reaper.ColorFromNative(color)

            return reaper.ColorToNative(math.floor(r/dim),math.floor(g/dim),math.floor(b/dim))
        
        end

        local function DimTheme(dim)

            local DIM = {'col_tr1_peaks','col_tr2_peaks','col_peaksedge','col_peaksedge2','col_peaksedgesel','col_peaksedgesel2','col_tr1_ps2','col_tr2_ps2','col_tr1_bg','col_tr2_bg','selcol_tr1_bg','selcol_tr2_bg','col_arrangebg',}
            local ORI = {14606046, 14606046, 16777215, 16777215,'col_arrangebg','col_tr1_bg','col_tr2_bg','selcol_tr1_bg','selcol_tr2_bg',}

            for abi=1,4 do
                local color = reaper.GetThemeColor(DIM[abi])
                reaper.SetThemeColor(DIM[abi],(dim and 0) or ORI[abi],0)
            end
        end

        if  change then
            r.GetSetColor("envelope view",false)
            for abi=1,reaper.CountMediaItems(0) do
                local item =reaper.GetMediaItem(0,abi-1)
                local color=reaper.GetMediaItemInfo_Value(item,"I_CUSTOMCOLOR")
                if  color == 0 then 
                    local tr=reaper.GetMediaItemTrack(item)
                    color = api.gtv(tr,"I_CUSTOMCOLOR")
                    color=( (color~=12599296 and color~=0 ) and color) or 18696831
                end
                local color = DimColor(color,dim)
                reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",color|0x1000000)
            end

            reaper.SetExtState("color_tint",pro_name,0,false)
            DimTheme(true)
            
        else
            
            r.GetSetColor("envelope view",true)
            reaper.SetExtState("color_tint",pro_name,-1,false)
            DimTheme(false)
            
        end
        
        reaper.UpdateArrange()
    
    end
    
    local function SetEnvStates()
        
        api.pur(1)

        for abi = 1, reaper.CountTracks(0) do
            local track = reaper.GetTrack(0,abi-1)
            if  track then 
                for abii = 1,reaper.CountTrackEnvelopes( track ) do
                    local _,env,chunk,points,active
                    env = reaper.GetTrackEnvelope( track, abii-1 )
                    if not env then goto Next end
                    _,chunk = api.geC(env,'',false)   
                    
                    points = 0
                    for _ in chunk:gmatch('PT') do
                        points = points + 1
                        if  points >= 2 then active = true break end
                    end
                    
                    
                    if  envelope_lane == 0 then --and active then
                        chunk = chunk:gsub('VIS [01] [01] 1','VIS 1 0 1')
                    
                    elseif envelope_lane == 1 then
                        chunk = chunk:gsub('VIS [01] [01] 1','VIS 1 1 1')
                        chunk = chunk:gsub('LANEHEIGHT (%d-) 0','LANEHEIGHT 80 0')
                    
                    elseif envelope_lane == 2 then
                        api.mcw()
                        if  track == api.mct() then
                            chunk = chunk:gsub('VIS [01] [01] 1','VIS 1 1 1')
                            chunk = chunk:gsub('LANEHEIGHT (%d-) 0','LANEHEIGHT 160 0')
                        else
                            chunk = chunk:gsub('VIS [01] [01] 1','VIS 1 0 1')
                        end
                    elseif envelope_lane == 3 then
                        if  reaper.IsTrackSelected(track) then
                            chunk = chunk:gsub('VIS [01] [01] 1','VIS 1 1 1')
                            chunk = chunk:gsub('LANEHEIGHT (%d-) 0','LANEHEIGHT 160 0')
                        else
                            chunk = chunk:gsub('VIS [01] [01] 1','VIS 1 0 1')
                        end
                    end
                    api.seC(env,chunk,false)
                    ::Next::
                end
            end
        end 
        api.ua()
        api.pur(-1)

    end
    
    -----

    local function main()
        
        r.SaveItems(true)

        local toggle = reaper.GetExtState("color_tint",pro_name,false) == '1'

        if  r.CheckEnvVisible() then -- visible
            ChangeColor(toggle)
            api.cmd(41150,0)--hide all envelopes for all tracks
        else
            
            api.cmd(41149,0) --Envelope: Show all envelopes for all tracks
            
            if not r.CheckEnvVisible() then return end
            
            ChangeColor(not toggle)
            SetEnvStates()
        end
        
        r.RestoreItems(true)
        
    end
    
    ------excute main-------
    api.ubb()
    reaper.defer(main)
    api.ueb(0,'Toggle show all active envelopes for all tracks',-1)
