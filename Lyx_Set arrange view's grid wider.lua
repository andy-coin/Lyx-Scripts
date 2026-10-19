  
  r=reaper
  
  local function main()
      
      local _,grid,swing,swingamt = reaper.GetSetProjectGrid(0,false)--, optional number division, optional integer swingmode, optional number swingamt)
      local triplet = ((1/grid)/3)%1==0
      
      if grid<=0.5 and grid>=0.0078125 then
         if swing then
            reaper.GetSetProjectGrid(0,true,grid*2,swing,swingamt)
         else
            reaper.GetSetProjectGrid(0,true,grid*2,0)
         end
      else
         return 
      end

  end
  
  reaper.defer(main)
