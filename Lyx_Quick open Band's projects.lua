  
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -- 定義搜尋目錄和檔案類型
    local default_dir = "/Users/andy/Desktop/Reaper Projects"

    -- 你要搜尋的檔案類型，例如 .wav 檔案
    local file_extension = ".RPP" 
    
    local found_files = {}

    -- 開始搜尋檔案
    local function search_files(directory, extension)

        -- 用於儲存找到的檔案

        -- 獲取目錄中的所有檔案和資料夾
        local i = 0
        while true do
            -- 使用 reaper.EnumerateFiles 和 reaper.EnumerateSubdirectories 函數
            local file = reaper.EnumerateFiles(directory, i)
            local subdir = reaper.EnumerateSubdirectories(directory, i)

            -- 如果沒有更多檔案或資料夾，跳出迴圈
            if not file and not subdir then break end

            -- 檢查檔案是否符合指定的副檔名
            if  file and file:match(extension .. "$") then
                table.insert(found_files, directory .. "/" .. file)
            end

            -- 如果是資料夾，遞迴搜尋
            if  subdir then
                search_files(directory .. "/" .. subdir, extension)
            end

            i = i + 1
        end
        
        return found_files
    end

    local function main()

        local exclude_projects,ret,csv,search_dir,projects,answer,dir,excludes
        
        exclude_projects = api.load("Last Open Projects Tabs","Last Open Projects Tabs")

        exclude_projects = (exclude_projects ~='' and exclude_projects) or '台北Acoustic,那行那看acoustic,陽台Acoustic,樂園Acoustic'

        ret,csv=r.GetUserInputs("Which band are you gonna practice?",2,
                                     "0.13月終了 or 1.看日早晚 or 2.林昱君\30Exclude Projects:extrawidth=325\30separator=\30",
                                     '看日早晚\30'..exclude_projects..'\30'
                                    )
        
        if not ret then return end 
        
        answer = {}
        for str in csv:gmatch("[^\30]*") do
            answer[#answer+1]= str
        end
        
        api.save("Last Open Projects Tabs","Last Open Projects Tabs",answer[2],true)

        dir = answer[1]

        excludes = {}
        for project in answer[2]:gmatch("[^,]*") do
            excludes[#excludes+1] = project
        end

        if  dir == '13' or dir == '0' then
            search_dir = default_dir..'/#Undecimber'
        elseif dir == '看日早晚' or dir == '1'then
            search_dir = default_dir..'/看日早晚'
        elseif dir == '君君' or dir == '2' then
            search_dir = default_dir..'/林昱君live'
        end
        
        if not search_dir then return end
        
        search_files(search_dir,file_extension)

        for abi=1,#found_files do    

            local project = found_files[abi]

            for abii=1,#excludes do
                if  project:match(excludes[abii]) then
                    table.remove(excludes,abii)
                    goto NEXT
                end
            end

            if reaper.GetProjectName(0)=="" then
               os.execute('open '..found_files[abi])
               reaper.Main_openProject(found_files[abi])
            else 
               reaper.Main_OnCommand(41929,0) -- New project tab (ignore default template)
               reaper.Main_openProject(found_files[abi])
            end
            
            ::NEXT::
        end
          
        reaper.Main_OnCommand(40861,0)--next project tab
          
    end 
    


    r.run(main)
