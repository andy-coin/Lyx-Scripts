  
  r=reaper
  ---------------------SAVE INITIAL SELECTED TRACKS------------------------------------
  trackzzz={}
  local function SaveSelectedTracks (table)--trackzzz
    for i = 0, reaper.CountSelectedTracks(0)-1 do
      table[i+1] = reaper.GetSelectedTrack(0, i)
    end
  end
  
  ---------------------RESTORE INITIAL SELECTED TRACKS------------------------------------
  local function RestoreSelectedTracks (table)--trackzzz
    reaper.Main_OnCommand(40297,0)
    for _, track in ipairs(table) do
      reaper.SetTrackSelected(track, true)
    end
  end
  
  -----------------------SAVE INITIAL SELECTED ITEMS------------------------------------
  itemzzz = {}
  local function SaveSelectedItems (table)--itemzzz
    for i = 0, reaper.CountSelectedMediaItems(0)-1 do
      table[i+1] = reaper.GetSelectedMediaItem(0, i)
    end
  end
  
  ----------------------RESTORE INITIAL SELECTED ITEMS------------------------------------
  local function RestoreSelectedItems (table)--itemzzz
    reaper.Main_OnCommand(40289, 0) 
    for _, item in ipairs(table) do
      reaper.SetMediaItemSelected(item, true)
    end
  end
  
  ---------------------------------SUM------------------------------------------
  local function sum(table)
      local sum = 0
      for k,v in pairs(table) do
          sum = sum + v
      end
      return sum
  end
  
  --------------------------------------FolderData-------------------------------
  local function FolderData()
        
    tr_n = reaper.CountTracks(0)
    N = 0
    P = 0
    C = 0
    if tr_n == 0 then return N,P,C,tr_n end
    tr = {}
      for abi = 0 , tr_n-1 do
      tr[abi+1] = reaper.GetTrack(0,abi)
      reaper.SetOnlyTrackSelected(tr[abi+1],1)
        if nil == reaper.GetParentTrack(tr[abi+1]) 
        and 0 == reaper.GetMediaTrackInfo_Value(tr[abi+1],"I_FOLDERDEPTH") then
        N = N+1
        end
        if nil == reaper.GetParentTrack(tr[abi+1]) 
        and 1 == reaper.GetMediaTrackInfo_Value(tr[abi+1],"I_FOLDERDEPTH") then
        P = P+1
        end
        if nil ~= reaper.GetParentTrack(tr[abi+1]) 
        and 1 ~= reaper.GetMediaTrackInfo_Value(tr[abi+1],"I_FOLDERDEPTH") then
        C = C+1
        end
      end
    return N,P,C,tr_n 
  end
  
  --------------------------------FIND XYZ---------------------------------------
  local function mathXYz()
  
    cmd=reaper.NamedCommandLookup("_RSf13fa0197f030a309dba401a5fdcb796d0d312e0")
    reaper.Main_OnCommand(cmd,0)--save vertical zoom
    cmd=reaper.NamedCommandLookup("_SWS_SELNOTFOLDER")
    reaper.Main_OnCommand(cmd,0)--select non-folder track
    TR = reaper.CountTracks(0)
    
    tr_all={}
    tr_arm1={}
    for abi=0,reaper.CountSelectedTracks(0)-1 do
    tr_all[abi+1] = reaper.GetSelectedTrack(0,abi) 
    tr_arm1[abi+1] = reaper.GetMediaTrackInfo_Value(tr_all[abi+1],"I_RECARM")
    end
    
    cmd=reaper.NamedCommandLookup("_SWS_SELALLPARENTS2")
    reaper.Main_OnCommand(cmd,0)--select Only parent track
    tr_arm2={}
    for abi=0,reaper.CountSelectedTracks(0)-1 do
    tr_all[abi+1] = reaper.GetSelectedTrack(0,abi) 
    tr_arm2[abi+1] = reaper.GetMediaTrackInfo_Value(tr_all[abi+1],"I_RECARM")
    end
    A = sum(tr_arm1)+sum(tr_arm2)
    
--reaper.ShowConsoleMsg(sum(tr_arm1)..","..sum(tr_arm2))

    
    reaper.Main_OnCommand(40296,0)--select all track
    tr_n=reaper.CountSelectedTracks(0)
    
    tr_all={}
    tcph_ori={}
    for abi=0,reaper.CountSelectedTracks(0)-1 do
    tr_all[abi+1] = reaper.GetSelectedTrack(0,abi)
    tcph_ori[abi+1] = reaper.GetMediaTrackInfo_Value(tr_all[abi+1],"I_TCPH")
    end
    TCPH_ori=sum(tcph_ori)
    
    reaper.Main_OnCommand(40727,0)--minimize all tracks
    reaper.Main_OnCommand(40111,0)--zoom in one times
    tcph_min1={}
    for abi=0,reaper.CountSelectedTracks(0)-1 do
    tcph_min1[abi+1] = reaper.GetMediaTrackInfo_Value(tr_all[abi+1],"I_TCPH")
    end
    TCPH_min1=sum(tcph_min1)-72*A
    
    if A == 0 then
    reaper.Main_OnCommand(40111,0)--zoom in one times
    else
    reaper.Main_OnCommand(40111,0)--zoom in one times
    reaper.Main_OnCommand(40111,0)--zoom in one times
    reaper.Main_OnCommand(40111,0)--zoom in one times
    reaper.Main_OnCommand(40111,0)--zoom in one times
    end
    
    tcph_min2={}
    for abi=0,reaper.CountSelectedTracks(0)-1 do
    tcph_min2[abi+1] = reaper.GetMediaTrackInfo_Value(tr_all[abi+1],"I_TCPH")
    end
    TCPH_min2=sum(tcph_min2)-91*A
    
    reaper.Main_OnCommand(40297,0)
    cmd=reaper.NamedCommandLookup("_SWS_SELALLPARENTS")
    reaper.Main_OnCommand(cmd,0)
    trp_n=reaper.CountSelectedTracks(0)
    TCPH=TCPH_min2-TCPH_min1
    
--reaper.ShowConsoleMsg(A..","..TCPH_min1..","..TCPH_min2..","..TCPH_ori..","..TCPH)
    
    X=0
    Y=0
    Z=0
      if A == 0 then
        abi=0 --Get uncollapsed tracks numer
        repeat
        
        TCPH=TCPH-25
        abi=abi+1
        Z=abi
        until TCPH <= 0
      elseif TR == A then
        X = 0 
        Y = 0
        Z = 0
        trc_n = 0
      else 
        abi=0 --Get uncollapsed tracks numer
        repeat
        TCPH=TCPH-44
        abi=abi+1
        Z=abi
        until TCPH <=0 
      end
      
      trc_n = tr_n-A-Z
      TCPH = TCPH_min1-47*Z-4*trc_n

--reaper.ShowConsoleMsg(TCPH..","..trc_n..","..Z)   
    
        if trc_n ~= 0 then -- if there are tracks been collapsed
           if TCPH == 0 then -- Get small tracks numer
              Y = 0
              X = trc_n
           else              -- Get tinY tracks numer
              abi=0
              repeat
              TCPH=TCPH-18
              abi=abi+1
              Y=abi
              until TCPH <= 0
              X=tr_n-Y-Z-A
          end
        end
    
    cmd=reaper.NamedCommandLookup("_RS3ecec63e4fa06da8eb9584127550d3be7ca508fa")
    reaper.Main_OnCommand(cmd,0)--load vertical zoom
    RestoreSelectedTracks (trackzzz)
    RestoreSelectedItems (itemzzz)

--reaper.ShowConsoleMsg(tr_n..","..A..","..X..","..Y..","..Z) 

    return TCPH_ori-4*X-22*Y,X,Y,Z,A
  end

--mathXYz()
  
  -----------------------------------Folder State---------------------------------------
  local function FolderState()
    
    SaveSelectedTracks (trackzzz)
    SaveSelectedItems (itemzzz)
    
    cmd = reaper.NamedCommandLookup("_SWS_SELRECARM")
    reaper.Main_OnCommand(cmd,0)--select Only rec-arm track
    A = reaper.CountSelectedTracks(0)
    
    if A then
      tr_arm={}
      tcph_arm={}
      for abi=0,reaper.CountSelectedTracks(0)-1 do
      tr_arm[abi+1] = reaper.GetSelectedTrack(0,abi)
      tcph_arm[abi+1] = reaper.GetMediaTrackInfo_Value(tr_arm[abi+1],"I_TCPH")
      end
      TCPH_arm=sum(tcph_arm)
    end
    
    --reaper.Main_OnCommand(40296,0)--select all track
    tr_n = reaper.CountTracks(0)
    if tr_n == 0 then return 0,0,0,0 end
    
    cmd = reaper.NamedCommandLookup("_SWS_SELALLPARENTS")
    reaper.Main_OnCommand(cmd,0)--select Only parent track
  
    P_tr_n = reaper.CountSelectedTracks(0)
  
    if P_tr_n then 
      P_tr = {}
      P_Ste = {}
      C_tr_n = {}
      small = {}
      tinY = {}
      
      for abi = 0, P_tr_n-1 do
        P_tr[abi+1] = reaper.GetSelectedTrack(0,abi)
        reaper.SetOnlyTrackSelected(P_tr[abi+1],1)
        P_Ste[abi+1] = reaper.GetMediaTrackInfo_Value(P_tr[abi+1],"I_FOLDERCOMPACT")
        cmd = reaper.NamedCommandLookup("_SWS_SELCHILDREN")
        reaper.Main_OnCommand(cmd,0)--select Only children
        C_tr_n[abi+1] = reaper.CountSelectedTracks(0)
        if 1 == P_Ste[abi+1] then small[abi+1] = C_tr_n[abi+1]*22
        elseif 2 == P_Ste[abi+1] then tinY[abi+1] = C_tr_n[abi+1]*4
        end
        cmd = reaper.NamedCommandLookup("_SWS_SELALLPARENTS")
        reaper.Main_OnCommand(cmd,0)--select Only parent track
      end
      
      SMALL = sum(small)
      TINY = sum(tinY)
      SMALL_tr_n = SMALL/22
      TINY_tr_n = TINY/4
    else
      SMALL_tr_n = 0
      TINY_tr_n = 0
    end
    
    reaper.Main_OnCommand(40296,0)--select all track
    
    
    tr_all={}
    tcph_ori={}
    for abi=0,reaper.CountSelectedTracks(0)-1 do
    tr_all[abi+1] = reaper.GetSelectedTrack(0,abi)
    tcph_ori[abi+1] = reaper.GetMediaTrackInfo_Value(tr_all[abi+1],"I_TCPH")
    end
    TCPH_ori=sum(tcph_ori)
    
    TCPH = TCPH_ori-TINY-SMALL-TCPH_arm
    
--reaper.ShowConsoleMsg(TCPH.."|"..TINY_tr_n.."|"..SMALL_tr_n.."|"..tr_n-A.."|"..A)   
    
    RestoreSelectedTracks (trackzzz)
    RestoreSelectedItems (itemzzz)
    return TCPH,TINY_tr_n,SMALL_tr_n,tr_n-TINY_tr_n-SMALL_tr_n-A,A
  end
  
  ----------------------------------MAIN ACTION------------------------------------
  function main()
  
    SaveSelectedTracks (trackzzz)
    SaveSelectedItems (itemzzz)
    tr_n = reaper.CountTracks(0)
    if tr_n == 0 then return end
    
    TCPH,X,Y,Z,A=FolderState()
    
--reaper.ShowConsoleMsg(tcph.."|"..best.."|"..times.."|"..Toggle.."|")    
      
      a=-1
      if TCPH == 22*Z+72*A then
      a=0
      elseif TCPH == 47*Z+72*A then
      a=1
      elseif TCPH == 72*(Z+A) then
      a=2
      elseif TCPH == 91*(Z+A) then
      a=3
      elseif TCPH == 111*(Z+A) then
      a=4
      elseif TCPH == 131*(Z+A) then
      a=5
      elseif TCPH == 151*(Z+A) then
      a=6
      elseif TCPH == 171*(Z+A) then
      a=7
      elseif TCPH == 191*(Z+A) then
      a=8
      elseif TCPH == 211*(Z+A) then
      a=9
      else
      a=-1
      end
      
      tr_n = tr_n-X-Y
      
      if tr_n > 25 then
      tr_n = tr_n+Y/10
      elseif tr_n <= 25 and tr_n > 16 then
      tr_n = tr_n+Y/9
      elseif tr_n <= 16 and tr_n > 13 then
      tr_n = tr_n+Y/8
      elseif tr_n <= 13 and tr_n > 11 then
      tr_n = tr_n+Y/7
      elseif tr_n <= 11 and tr_n > 9 then
      tr_n = tr_n+Y/6
      elseif tr_n == 9 then
      tr_n = tr_n+Y/5
      elseif tr_n == 8 then
      tr_n = tr_n+Y/4
      elseif tr_n == 7 then
      tr_n = tr_n+Y/3
      elseif tr_n == 6 then
      tr_n = tr_n+Y/2
      elseif tr_n <= 5 then
      tr_n = tr_n+Y
      end 
      
      b=0
      if tr_n > 25 then
      b=0
      elseif tr_n <= 25 and tr_n > 16 then
      b=1
      elseif tr_n <= 16 and tr_n > 13 then
      b=2
      elseif tr_n <= 13 and tr_n > 11 then
      b=3
      elseif tr_n <= 11 and tr_n > 9 then
      b=4
      elseif tr_n == 9 then
      b=5
      elseif tr_n == 8 then
      b=6
      elseif tr_n == 7 then
      b=7
      elseif tr_n == 6 then
      b=8
      elseif tr_n <= 5 then
      b=9
      end 
      
      if a == -1 then 
      Toggle = 0
      elseif a >= 0 and a ~= b then
      Toggle = 0
      elseif a>=0 and a == b then
      Toggle = 1
      end
      
--reaper.ShowConsoleMsg(a..","..b)
      if Toggle == 0 then
      
         cmd=reaper.NamedCommandLookup("_RSbbc6e16de5912b97c704f60c4a64fbcdc595c345")
         reaper.Main_OnCommand(cmd,0)--save vertical zoom
         reaper.Main_OnCommand(40727,0)--minimize all tracks
           
           if b ~= 0 then
              if b > 2 then
                abi=0
                repeat
                reaper.Main_OnCommand(40111,0)--veertical zoom in
                abi = abi + 1
                until abi == b+2
              else
                abi=0
                repeat
                reaper.Main_OnCommand(40111,0)--vertical zoom in
                abi = abi + 1
                until abi == b
              end
           end
  
         reaper.Main_OnCommand(40913,0)--scrool track into view
         
      elseif Toggle == 1 then
         
         reaper.Main_OnCommand(40111,0)--increase track height a bit
         cmd=reaper.NamedCommandLookup("_RS98551301a3b5bc3cf73319b6ca698c97724b74df")
         reaper.Main_OnCommand(cmd,0)--load vertical zoom
            
      end
    RestoreSelectedTracks (trackzzz)
    RestoreSelectedItems (itemzzz)
  end
  
reaper.defer(main)


    
    
    
    
