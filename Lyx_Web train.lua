
  r=reaper
  
  local function main()
      
      version=reaper.GetAppVersion():gsub("/OSX64","")
      --reaper.ShowConsoleMsg(version)
      --reaper.ShowConsoleMsg(stop)
      version=math.floor(version:gsub("%.","")+1)
      download="https://www.reaper.fm/files/7.x/reaper"..version.."_universal.dmg"
      
      os.execute('open '..download)
      
      --[[retval,csv=reaper.GetUserInputs("Where r u going?",1,"Youtube keyword:,extrawidth=50","")
      
      if not retval or csv=="" then return end
      

      
      csv=csv:gsub("%s","+")
      if csv:find("#") then
         csv=csv:gsub("%#","")
         os.execute('open "" "https://www.youtube.com/results?search_query="'..csv..'"&sp=EgIIBQ%253D%253D"')
      elseif csv:find("!") then
         csv=csv:gsub("%!","")
         os.execute('open "" "https://www.youtube.com/results?searcsh_query="'..csv..'"&sp=EgQIBBAB"')
      else
         os.execute('open "" "https://www.youtube.com/results?search_query="'..csv )
      end--]]
  end
  
  reaper.defer(main)
