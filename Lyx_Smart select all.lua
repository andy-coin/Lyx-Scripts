    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    filter = false
    
    local function main()
        
        local Tn  = api.ct(0)
        local In  = api.ci(0)
        local Env = api.gse(0)
        
        if Tn==0 and In==0 and not Env then return end
        
        reaper.Undo_BeginBlock()
        win = api.mcw()

        if  Env then
            api.cmd(40332,0)
        elseif  win=="tcp" or win=="mcp" then
            api.cmd(40296,0)
        else
            if  In ~= 0 then
                api.cmd(40182,0)--select all items
                if filter then r.SelItemFilter() end
                -- abi = 0
                -- repeat
                --     local item = api.gsi(0,abi)
                --     local tr = api.git(item)
                --     if  api.gtv(tr,'C_LANESCOLLAPSED')~=0 and api.giv(item,'B_FIXEDLANE_HIDDEN')==1 then
                --         api.sis(item,false)
                --     else
                --         abi = abi +1
                --     end
                -- until abi == api.csi(0) or api.now()-time > 1
                reaper.UpdateArrange()
            else
                api.cmd(40296,0)
            end
        end
            
        reaper.Undo_EndBlock("Select all",-1)
    
    end
    
    time = api.now()
    main()
