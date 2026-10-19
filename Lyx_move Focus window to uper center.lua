


command_id = reaper.NamedCommandLookup("_RS5ce49ff3cc16bba39459fc9fc6025b9737e5f94a")--Save mouse position_slot 1.lua
reaper.Main_OnCommand(command_id,0)

command_id = reaper.NamedCommandLookup("_RSec5aaed89f1f3da64897356954c2fcf967331ff8")--restore mouse position_slot 3.lua
reaper.Main_OnCommand(command_id,0)

command_id = reaper.NamedCommandLookup("_BR_MOVE_WINDOW_TO_MOUSE_H_M_V_M")
reaper.Main_OnCommand(command_id,0)

command_id = reaper.NamedCommandLookup("_RS6ad2422dd039130de2a504423d12078442f47ca6")--restore mouse position_slot 1.lua
reaper.Main_OnCommand(command_id,0)
