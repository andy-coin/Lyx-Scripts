    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r = require("_Lyx_HOME")

    -----CUSTOM-----
    save = true

    -- Misc functions ------------------------------------------------------------------------------------------------------
    local function GetVisibleCCLanes (take)
        local visibleLanes = {}
        if take ~= nil then
            local takeGuid = "GUID " .. reaper.BR_GetMediaItemTakeGUID(take)
            local _, chunk = reaper.GetItemStateChunk(reaper.GetMediaItemTake_Item(take), "", false)
            local takeGuidLineFound = 0
            for line in chunk:gmatch("([^\n]*)\n?") do

                -- MIDI take chunk starts with GUID - mark when found
                if line == takeGuid then
                    takeGuidLineFound = 1
                else
                    if     takeGuidLineFound == 1 and line == "<SOURCE MIDI"      then takeGuidLineFound = 2
                    elseif takeGuidLineFound >= 2 and line.sub(line, 1, 1) == "<" then takeGuidLineFound = takeGuidLineFound + 1
                    elseif takeGuidLineFound >  2 and line == ">"                 then takeGuidLineFound = takeGuidLineFound - 1
                    elseif takeGuidLineFound == 2 and line == ">"                 then takeGuidLineFound = 0
                    end

                    -- We're inside MIDI take chunk, search for CC lanes data
                    if takeGuidLineFound == 2 then
                        local lineTokens = {}
                        for token in line:gmatch("[^%s]+") do
                            lineTokens[#lineTokens + 1] = token
                        end
                        -- CC lane found, save it
                        if #lineTokens > 0 and lineTokens[1] == "VELLANE" then
                            local newLane = {lane = tonumber(lineTokens[2]), height = tonumber(lineTokens[3])}
                            local saveLane = true
                            for _, lane in ipairs(visibleLanes) do if lane.lane == newLane.lane then saveLane = false break end end
                            if saveLane == true then
                                visibleLanes[#visibleLanes + 1] = newLane
                            end
                        end
                    end
                end
            end
        end
        return visibleLanes
    end

    -- Main ----------------------------------------------------------------------------------------------------------------
    local function Main ()
        
        local state = api.load('Midi_editor','move note state')
        
        if  state == '1' or state == 'ON' then
            api.Mcmd(api.M(),40183)--move note down
            return
        end
      
        reaper.Undo_BeginBlock()
        local midiEditor = reaper.MIDIEditor_GetActive()
        if  midiEditor ~= nil then
            local take = reaper.MIDIEditor_GetTake(midiEditor)
            if take then
                local visibleLanes = GetVisibleCCLanes(take)
                --api.cc()
                local cmd
                
                local last_lane = api.load('midi_cc_lane',tostring(take))
                last_lane = tonumber(last_lane) 
                if  #visibleLanes == 1 and visibleLanes[1].lane == -1 and visibleLanes[1].height == 0 then 
                
                    cmd = api.name('_FNG_ME_TOP_CC_LANE')
                    api.Mcmd(midiEditor,cmd)

                    cmd = api.name("_BR_ME_HIDE_ALL_NO_LAST_CLICKED")
                    api.Mcmd(midiEditor,cmd)

                    if  last_lane and save then
                        reaper.BR_MIDI_CCLaneReplace(midiEditor, 0, last_lane)
                    end
                    
                    cmd = api.name("_BR_ME_SET_CC_LANES_HEIGHT_200")
                    api.Mcmd(midiEditor,cmd)
                     
                else
                    cmd = api.name("_S&M_HIDECCLANES_ME")
                    api.Mcmd(midiEditor,cmd)-- SWS/S&M: Hide all CC lanes
                end

            end--]]
        end
        reaper.Undo_EndBlock("Show notes Velocity",-1)
    end

    reaper.defer(Main)
