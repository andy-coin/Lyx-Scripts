        
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

        
    -- 定義搜尋目錄和檔案類型 / search folder and file type
    local dir = os.getenv("HOME").."/Downloads"

    -- 你要搜尋的檔案類型，例如 .wav 檔案 / file type to look for, e.g. .wav
    local ext = ".rar" 
    
    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r = require("_lib._Lyx_HOME")
    
    local function get_clipboard_text()
        local clip = io.popen('pbpaste','r')
        local result = clip:read('*all')
        clip:close()
        return result
        
    end
    
    url_list = {}
    
    local function count_files(directory, extension,only_number)
        
        -- 用於儲存找到的檔案 / files found
        local found_files = {}

        -- 獲取目錄中的所有檔案和資料夾 / list every file and folder in the directory
        local i = 0
        while true do
            -- 使用 reaper.EnumerateFiles 和 reaper.EnumerateSubdirectories 函數 / using reaper.EnumerateFiles and reaper.EnumerateSubdirectories
            local file = reaper.EnumerateFiles(directory, i)
            --local subdir = reaper.EnumerateSubdirectories(directory, i)

            -- 如果沒有更多檔案或資料夾，跳出迴圈 / stop when there are no more files or folders
            if not file then break end

            -- 檢查檔案是否符合指定的副檔名 / check the file extension
            if  file and file:match(extension .. "$") then
                table.insert(found_files, directory .. "/" .. file)
            end

            i = i + 1
        end
        
        if  only_number then
            return #found_files    
        else
            return found_files
        end
    end

    local function get_link(path)

        local file,content,new_content
        -- 讀取文件內容 / read the file
        
        file = io.open(path, "r")

        content = file:read("*a") -- "*a"表示讀取整個文件 / "*a" reads the whole file
        
        if not content then return end

        local url_list = {}
        
        for line in content:gmatch('[^\n]*') do

            url_list[#url_list+1] = line

        end
        
        return url_list
    
    end

    local function click_ok(time)

        if  api.now() - time < 5 then
            reaper.defer(function()click_ok(time)end)
        else
            os.execute([[osascript -e 'tell application "System Events" to keystroke return']])
        end

    end

    local function multi_download(last_RAR_n)

        local RAR_n = count_files(dir,ext,true)
        
        if  RAR_n ~= last_RAR_n or abi<=4 then
            
            
            os.execute("open "..url_list[abi])
            local part = url_list[abi]:match('part(%d*)')
            msg('downloading.. part'..part)
            local time = api.now() + part%7
            
            abi = abi + 1
            
            reaper.defer(function()click_ok(api.now())end)
        
        end
        
        if  abi > #url_list then 
            msg("COMOPLETE!")
            return
        end

        reaper.defer(function() multi_download(RAR_n) end)
        
    end
    
    function EditScript()
        
        action = get_clipboard_text()
        
    
        --BBB(api.name(action))
        --if true then return end
        
        if  action:find("Lyx") then
            action=action:gsub("Script: ","")
            script=script_path..action
            midi_script=script_path.."MIDI Editor/"..action
            script=ESCPattern(script,true)
            midi_script=ESCPattern(midi_script,true)
            os.execute('open '..script)
            os.execute('open '..midi_script)
        end
    end
       
    function download_machine()
    
        retval,path = reaper.GetUserFileNameForRead("","What do we crack now?",'txt')

        if  retval then
            abi = 1
            url_list = get_link(path)
            multi_download(count_files(dir,ext,true))
        end
      
    end
    
    local found_files = {}


    th = 10
    time = api.now()

    local function theme_refresher()

        if  api.now()-time > th then
            api.cmd(40382,0)
            api.cmd(40381,0)
            time = api.now()
            msg('change--'..math.ceil(time%3))
        end

        reaper.defer(func)

    end
    
    local function sub_string()

        --local retval,path = reaper.GetUserFileNameForRead("","What do we crack now?",'lua')
    
        local path = os.getenv("HOME")..'/Desktop/Coding Projects/Claude/ReaLive/Lyx_Realive.lua'
        --if retval then
            local file,content,func_names

            file = io.open(path, "r")
            content = file:read("*a")
            func_names={}

            for _, func_name in content:gmatch('[\r\n](local function )([%w_]+)%(') do
                
                func_names[#func_names+1]=func_name
                
            end

            for i=1, #func_names do
                local func = func_names[i]
                --content = content:gsub('([{=,;%*%-%+%.%s%(\n])('..func..'%()','%1FUNC.'..'%2')
                content = content:gsub('([^%w_])('..func..'%()','%1FUNC.'..'%2')
                --msg()
            end

            content = content:gsub('([\r\n]?)local function ','%1function ')
            content = content:gsub('FUNC%.FUNC%.','FUNC.')
            
            file = io.open(path, "w")
            file:write(content)
            file:close()

--        end

    end
    
    func = {theme_refresher,
            download_machine,
            EditScript,
            sub_string}
    
    func[3]()
  
