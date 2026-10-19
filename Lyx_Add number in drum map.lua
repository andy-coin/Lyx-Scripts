    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    time = api.now()
    
    -- local function get_clipboard_text()
    --     local clip = io.popen('pbpaste','r')
    --     local result = clip:read('*all')
    --     clip:close()
    --     return result
    -- end
    
    -- action = get_clipboard_text()
    
    -- BBB(api.name(action))
    
    -- reaper.defer(function()end)

    lfs = require("lfs")
    directory = os.getenv("HOME")..'/Desktop/drum map/'

    local function formatFile(path)

        local file,content
        -- 讀取文件內容
        file = io.open(path, "r")
        
        content = file:read("*a") -- "*a"表示讀取整個文件
    
        content = content:gsub('^(%d*)','%1 %1|')
    
        file:close() -- 關閉文件
    
        -- 打開文件以寫入模式
        file = io.open(path, "w")
        -- 寫入更新後的內容
        file:write(content)
        file:close() -- 關閉文件
    
    end

    for file in lfs.dir(directory) do
        if  file:match("%.txt$") then
            local fullpath = directory .. "/" .. file
            formatFile(fullpath)
        end
    end

