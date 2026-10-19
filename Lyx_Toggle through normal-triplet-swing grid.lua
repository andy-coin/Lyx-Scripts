
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
      
      triplet=reaper.NamedCommandLookup("_SWS_AWTOGGLETRIPLET")
      swing=reaper.NamedCommandLookup("_SWS_AWTOGGLESWING")
      Swing=reaper.NamedCommandLookup("_RS1da5aa836af30a1c8f6fba1f4b7c6a38f7084e9e")
      
      if  reaper.GetToggleCommandState(triplet)==0 and  reaper.GetToggleCommandState(swing)==0 then
          Act="Set grid mode to : Triplet"
          reaper.Main_OnCommand(triplet,0)
      elseif reaper.GetToggleCommandState(triplet)==1 and  reaper.GetToggleCommandState(swing)==0 then
          Act="Set grid mode to : Swing"
          reaper.Main_OnCommand(triplet,0)
          local _,grid = reaper.GetSetProjectGrid(0,false)--, optional number division, optional integer swingmode, optional number swingamt)
          reaper.Main_OnCommand(swing,0)
          reaper.GetSetProjectGrid(0,true,grid,1,0.6)
      elseif reaper.GetToggleCommandState(triplet)==0 and  reaper.GetToggleCommandState(swing)==1 then
          Act="Set grid mode to : Straight"
          reaper.Main_OnCommand(swing,0)
      end
      r.billboard(Act)
      return Act
  end
  
  reaper.Undo_BeginBlock()
  Act=main()
  reaper.Undo_EndBlock(Act,-1)
