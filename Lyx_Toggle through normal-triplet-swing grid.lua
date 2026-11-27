
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_lib._Lyx_HOME")
  local DEFAULT_SWING=require("_lib._Lyx_SwingDefault")
  
  -- 離開 Swing 時記住當下的 swing feel，下次進 Swing 還原（Move swing grid later/earlier 調的值）
  local EXT, KEY = "Lyx_SwingGrid", "swingamt"
  local function save_swing()
      local _,_,_,amt = reaper.GetSetProjectGrid(0,false)
      if amt ~= 0 then reaper.SetProjExtState(0,EXT,KEY,tostring(amt)) end
  end

  local function main()
      
      triplet=reaper.NamedCommandLookup("_SWS_AWTOGGLETRIPLET")
      swing=reaper.NamedCommandLookup("_SWS_AWTOGGLESWING")
      
      if  reaper.GetToggleCommandState(triplet)==0 and  reaper.GetToggleCommandState(swing)==0 then
          Act="Set grid mode to : Triplet"
          reaper.Main_OnCommand(triplet,0)
      elseif reaper.GetToggleCommandState(triplet)==1 and  reaper.GetToggleCommandState(swing)==0 then
          Act="Set grid mode to : Swing"
          reaper.Main_OnCommand(triplet,0)
          local _,grid = reaper.GetSetProjectGrid(0,false)--, optional number division, optional integer swingmode, optional number swingamt)
          reaper.Main_OnCommand(swing,0)
          local amt = tonumber(select(2,reaper.GetProjExtState(0,EXT,KEY))) or DEFAULT_SWING
          reaper.GetSetProjectGrid(0,true,grid,1,amt)
          Act = Act..string.format(" (%.2f)",amt)
      elseif reaper.GetToggleCommandState(triplet)==0 and  reaper.GetToggleCommandState(swing)==1 then
          Act="Set grid mode to : Straight"
          save_swing()
          reaper.Main_OnCommand(swing,0)
      else -- both on: back to straight
          Act="Set grid mode to : Straight"
          save_swing()
          reaper.Main_OnCommand(triplet,0)
          reaper.Main_OnCommand(swing,0)
      end
      r.billboard(Act)
      return Act
  end
  
  reaper.Undo_BeginBlock()
  Act=main()
  reaper.Undo_EndBlock(Act,-1)
