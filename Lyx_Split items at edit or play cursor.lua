
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    
    --------------
    local function ToggleItemGroups()
        
        local id={}
        
        for abi=1,api.csi(0) do
            local item=reaper.GetSelectedMediaItem(0,abi-1)
             if r.IsItemVisible(item) then
                id[#id+1]=reaper.GetMediaItemInfo_Value(item,"I_GROUPID")
             end
        end    
         
        _,id = r.KillTable(id)
    
        if  #id==1 and id[1]~=0 then
            reaper.Main_OnCommand(40033,0)--ungroup items
            reaper.Main_OnCommand(40032,0)--group items
        end
    end
    
    
    local function main()
        
        local E,new_items,items,editor
        
        E = (api.gps()%2==0 and api.gec()) or api.gpc()
        
        api.mcw()
        item = api.mci()
        if item and reaper.IsMediaItemSelected(item) then E = api.gec() end
        
        new_items = {}
        items = {}
        editor = api.M()
        
        api.ubb()
        
        if  editor and r.IsMidiEditorFocus(editor) then
            reaper.Main_OnCommand(40289,0)
            local take = api.Mgt(editor)
            if  take then
                local item = reaper.GetMediaItemTake_Item(take)
                items[1] = item
            end
        else
            for abi=1,api.csi(0) do
                local item = api.gsi(0,abi-1)
                if  r.IsItemVisible(item) then
                     items[#items+1] = item
                end
            end
        end
            
        for abi=1,#items do
            local item = items[abi]
            local new_item = reaper.SplitMediaItem(item,E)
            if  new_item then
                new_items[#new_items+1] = new_item
            end
        end
        
        if  #new_items > 0 then
            api.cmd(40289,0)
            for abi=1,#new_items do
                api.sis(new_items[abi],1)
            end
            api.ua()
            ToggleItemGroups()
        end
        api.ueb(0,'Split items at cursor',-1)
    end

    main()

