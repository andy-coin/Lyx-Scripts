  
  r=reaper
  
  local function main()
      
      local _,grid,swing,swingamt = reaper.GetSetProjectGrid(0,false)--, optional number division, optional integer swingmode, optional number swingamt)
      local triplet = ((1/grid)/3)%1==0
      
      if triplet then
         cmd=reaper.NamedCommandLookup("_SWS_AWTOGGLETRIPLET")
         reaper.Main_OnCommand(cmd,0)
      end
      
      local _,grid,swing,swingamt = reaper.GetSetProjectGrid(0,false)
      
      if swingamt ==0 then 
         swingamt=0.6
      end
      
      if swing ==1 then 
         reaper.GetSetProjectGrid(0,true,grid,0,swingamt)
      else 
         reaper.GetSetProjectGrid(0,true,grid,1,swingamt)
      end
      
  end
  
  reaper.defer(main)
