
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    --------------
    local function GetWindow(name)
        local title = reaper.JS_Localize(name, "common")
        local arr = reaper.new_array({}, 1024)
        reaper.JS_Window_ArrayFind(title, true, arr)
        local adr = arr.table()
        for j = 1, #adr do
            local hwnd = reaper.JS_Window_HandleFromAddress(adr[j])
            -- verify window by checking if it also has a specific child.
            --if reaper.JS_Window_FindChildByID(hwnd, 1045) then -- 1045:ID of volume control in media explorer.
                return hwnd
            --end 
        end
    end

    local function defer(midi)

        if  api.gps(0)==0 then
            if  api.gtc(40036) == 1 then
                api.cmd(40036, 0)--toggle auto_scroll
            end
            reaper.RefreshToolbar2(0,40036)
            if  midi and not api.M() and reaper.GetToggleCommandStateEx(32060, 40640) == 1 then 
                api.Mcmd(midi, 40640) -- midi editor Timebase: Toggle sync to arrange view
                reaper.RefreshToolbar2(32060, 40640)
                reaper.RefreshToolbar2(32060, 40750)
            end
        else
            reaper.defer(function()defer(midi)end)
        end
    end
    
    --------------
    local function main()
        
        hwnd = GetWindow("Video Window")
        focus=reaper.JS_Window_GetFocus()
        
        if hwnd and focus==hwnd then
            --tval, val = reaper.BR_Win32_GetPrivateProfileString( "reaper_video", "fullscreen", "",  reaper.get_ini_file() )
            --reaper.JS_WindowMessage_Send(hwnd, "WM_LBUTTONDBLCLK", 1,1,0,0)
            --return
        end
        
        local P, Start, End, in_view, playing, auto_scroll
        
        P = api.gpc()
        Start, End=reaper.GetSet_ArrangeView2(0,false,0,0,0,0)
        in_view = P > Start and P < End
        
        playing = api.gps() == 1 or api.gps() == 5
        
        midi_editor = api.M()

        reaper.RefreshToolbar2(0,40036)
        
        if  playing then
            if  in_view then
                api.cmd(40036, 0)--toggle auto_scroll
            else
                api.cmd(api.name("_SWS_HSCROLLPLAY10"),0)
                if api.gtc(40036) == 0 then api.cmd(40036, 0) end
                api.cmd(40434,0)--move edit cursor to play cursor
            end
            defer(midi_editor)
        else
            --api.cmd(40036, 0)--toggle auto_scroll
            if  in_view then
                -- PASS
            else
                -- PASS
            end
            api.cmd(api.name("_SWS_HSCROLL50"),0)
            if  midi_editor then
                api.Mcmd(midi_editor, 40640) -- midi editor Timebase: Toggle sync to arrange view
            end
            return
        end

        auto_scroll = api.gtc(40036)

        reaper.RefreshToolbar2(0,40036)
        
        
        if  midi_editor then 
            if  reaper.GetToggleCommandStateEx(32060, 40640) ~= auto_scroll then
                api.Mcmd(midi_editor, 40640) -- midi editor Timebase: Toggle sync to arrange view
            end
            reaper.RefreshToolbar2(32060, 40640)
            reaper.RefreshToolbar2(32060, 40750)
        end
        
        api.ua()
        
        state = (auto_scroll == 1 and "ON") or "OFF"

        BBB("Auto-scroll " .. state )

    end

    reaper.defer(main)
