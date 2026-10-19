    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    -- Track versions on REAPER 7 fixed lanes: play the lane under the mouse
    -- and show its lane name in the track name ("Vox   [ Take 3 ]").
    -- Also used by "Lyx_Click with shift add tracks selection" (require'd, returns SwitchVersion).
    -- (old folder-track version system removed; it is in git history)
    local function SwitchVersion(track)
        if not track then return false end
        local lane_n = api.gtv(track,"I_NUMFIXEDLANES")
        if lane_n <= 1 or api.gtv(track,"C_LANESCOLLAPSED") ~= 0 then return false end

        api.cmd(40297,0)--unselect all tracks
        api.cmd(42478,0)--play lanes under mouse
        for abi=1,lane_n do
            if  api.gtv(track,"C_LANEPLAYS:"..(abi-1))==1 then
                local _,tr_name=api.ts(track,"P_NAME","",false)
                local _,lane_name=api.ts(track,"P_LANENAME:"..(abi-1),"",false)
                api.ts(track,"P_NAME",tr_name:gsub("(   %[ .* %])","").."   [ "..lane_name..' ]',true)
                break
            end
        end
        return true
    end

    if ... then return SwitchVersion end -- loaded with require by another script

    reaper.BR_GetMouseCursorContext()
    reaper.Undo_BeginBlock()
    SwitchVersion(reaper.BR_GetMouseCursorContext_Track())
    reaper.Undo_EndBlock("Switch to selected track version",-1)
