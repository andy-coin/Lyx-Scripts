  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  local function main()
      
      local pos_A,pos_B=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
        
      grid_unit=(reaper.GetToggleCommandState(reaper.NamedCommandLookup("_SWS_AWTOGGLETRIPLET"))==1 and 1/3/2^5 ) or 1/2^5
      
      ret,measures_A,cml,beats_A,cdenom = reaper.TimeMap2_timeToBeats(0,pos_A)
      ret,measures_B,cml,beats_B,cdenom = reaper.TimeMap2_timeToBeats(0,pos_B)
      
      if r.is_divisible((beats_B-beats_A),(grid_unit)) then
          --msg("A")
          pos_C=reaper.TimeMap2_QNToTime(0,2*beats_B-beats_A)
      else
          --msg("B")
          pos_C=2*pos_B-pos_A
      end

      reaper.GetSet_LoopTimeRange2(0,true,false,pos_B,pos_C,false)
      
  end
  
  reaper.defer(main)
