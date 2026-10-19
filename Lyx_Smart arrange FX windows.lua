
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    layout_options = {"horizontal","vertical"}

    -- Configuration
    local Config = {
        layout = layout_options[1], -- 1=horizontal, 2=vertical
        window_gap = 5, -- pixels
        edge_limits = { -- share of the screen kept free on each side (0..1)
            left = 0.18,
            right = 0,
            top = 0.13,
            bottom = 0,
        },
        overlap_threshold = 30,
        center_plugins = {       -- plugins that should be centered
            "Melodyne (Celemony)"
        },
        exclude_plugins = {},    -- plugins to exclude from management
    }
    
    --------------
    local function GetAllFloatingFXWindows()
        
        local hwnds,center_hwnds = {},{}
        
        local function SortPlugin(hwnd,name)
            
            local string
            
            for abi=1,#Config.exclude_plugins do
                string=ESCPattern(Config.exclude_plugins[abi])
                if  name:match(string) then
                    return
                end
            end
            
            hwnds[#hwnds+1]=hwnd
        end
        
        local master_track,ins
        
        master_track = reaper.GetMasterTrack(0)
        
        for fx = 0, reaper.TrackFX_GetCount(master_track) - 1 do
            local hwnd,pass,_,name
            hwnd = reaper.TrackFX_GetFloatingWindow(master_track,fx)
            if  hwnd then
                _,name = reaper.TrackFX_GetFXName(master_track,fx)
                SortPlugin(hwnd,name)
            end
        end
        
        for t = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, t)
            local ins=reaper.TrackFX_GetInstrument(track)

            for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
                local hwnd,pass,_,name
                hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
                if  hwnd then
                    _,name = reaper.TrackFX_GetFXName(track,fx)
                    SortPlugin(hwnd,name)
                end
            end

            for fx = 0, reaper.TrackFX_GetRecCount(track) - 1 do
                local fx_in,hwnd,pass,_,name
                fx_in = fx + 0x1000000
                hwnd = reaper.TrackFX_GetFloatingWindow(track,fx_in)
                if  hwnd then
                    _,name=reaper.TrackFX_GetFXName(track,fx_in)
                    SortPlugin(hwnd,name)
                end
            end
        
            for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                for tk = 0, reaper.GetMediaItemNumTakes(item) - 1 do
                    local take = reaper.GetMediaItemTake(item, tk)
                    for fx = 0, reaper.TakeFX_GetCount(take) - 1 do
                        local hwnd,pass_,name
                        hwnd = reaper.TakeFX_GetFloatingWindow(take,fx)
                        if  hwnd then
                            _,name=reaper.TakeFX_GetFXName(take,fx)
                            SortPlugin(hwnd,name)
                        end
                    end
                end
            end
        end
                
        local total_area = 0

        local windows = {}

        for abi=1,#hwnds do

            local _,left, top, right, bottom = reaper.JS_Window_GetRect(hwnds[abi])
            local width = right - left
            local height = math.abs(top - bottom)
            local area = width * height
    
            total_area = total_area + area

            table.insert(windows,{
                        hwnd = hwnds[abi],
                        left = left, right = right, top = top, bottom = bottom,
                        width = width, height = height, area = area, 
                        })
        end

        return windows,total_area
    end

    --------------
    local function arrangeWindows(windows, total_area, screen_width, screen_height)

        local screen_area, start_x, start_y, right_edge, top_edge, bottom_edge
        
        -- screen-relative space: x from the left, y = height above the screen bottom
        local E = Config.edge_limits
        right_edge = screen_width * (1 - E.right)
        top_edge   = screen_height * (1 - E.top)
        bottom_edge = screen_height * E.bottom
        
        screen_area = (right_edge - screen_width * E.left) * (top_edge - bottom_edge)
        
        start_x = screen_width * E.left
        start_y = top_edge
        
        
        if  screen_area > total_area then
            if  Config.layout == 'horizontal' then
                local x, y, leader
                x = start_x
                y = start_y
                leader = 1
                for abi =1, #windows do
                    local re
                    ::RE::
                    windows[abi].left = x
                    windows[abi].top  = y
                    x = x + windows[abi].width + Config.window_gap
                    if  x > right_edge and not re then
                        x = start_x
                        y = windows[leader].top - windows[leader].height - Config.window_gap
                        re = true
                        leader = abi
                        goto RE
                    end
                end
            elseif Config.layout == 'vertical' then
                
                local x, y, leader
                x = start_x
                y = start_y
                leader = 1
                for abi =1, #windows do
                    local re
                    ::RE::
                    windows[abi].left = x
                    windows[abi].top  = y
                    y = y - windows[abi].height - Config.window_gap
                    if  y < bottom_edge and not re then
                        y = start_y
                        x = windows[leader].left + windows[leader].width + Config.window_gap
                        re = true
                        leader = abi
                        goto RE
                    end
                end
            end

        end

        return windows

    end

    local function main()

        local width, height, x0, y0 = r.GetScreenResolution() -- REAPER's monitor, native coords
        local mac = reaper.GetOS():find("OS")                -- macOS: native y grows upward
        
        local windows, total_area = GetAllFloatingFXWindows()
        
        if #windows == 0 then return end
        
        local new_layout = arrangeWindows(windows, total_area, width, height)
        
        for abi=1, #new_layout do
            local w = new_layout[abi]
            -- SetPosition wants the lower edge on macOS, the top edge (counted downward) on Windows/Linux
            local y = (mac and y0 + w.top - w.height) or (y0 + height - w.top)
            reaper.JS_Window_SetPosition(w.hwnd, math.floor(x0 + w.left), math.floor(y),
                                         math.floor(w.width), math.floor(w.height))
        end

        api.ua()
    end

    reaper.defer(main)

