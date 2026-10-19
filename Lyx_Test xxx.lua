    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r = require("_Lyx_HOME")
    
    local dir = reaper.GetResourcePath().."/MIDINoteNames/"
    local SD3 = reaper.GetResourcePath().."/MIDINoteNames/SD3 - Standard.txt"
    local ext = ".txt" 
    
    local function get_clipboard_text()
        local clip = io.popen('pbpaste','r')
        local result = clip:read('*all')
        clip:close()
        return result
    end
    
    function EditScript()
        
        action = get_clipboard_text()
        
        --BBB(api.name(action))
        --if true then return end
        
        if  action:find("%.lua") then
            action=action:gsub("Script: ","")
            script=script_path..action
            midi_script=script_path.."MIDI Editor/"..action
            script=ESCPattern(script,true)
            midi_script=ESCPattern(midi_script,true)
            os.execute('open '..script)
            os.execute('open '..midi_script)
        end
    end

    local found_files = {}

    local function MidiNoteChart()

        local note_chart,notes,abi,octave,time
        note_chart = {}

        notes = {'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'}
        
        abi = 0
        octave = -2
        time = api.now()
        repeat 
            for abii = 1,12 do
                note_chart[tostring(abi)] = notes[abii]..tostring(octave)
                abi = abi+1
                if abi > 127 then return note_chart end
            end
            octave = octave + 1
        until abi > 127 or (api.now() - time ) > 1

    end

    Gsub_chart = {['Kick']='K ',['Snare']='S ',['Hi%-Hat']= 'H ',
                  ['Ride'] = 'R ',['Cymbal (%d?)']= 'C%1',
                  ['Racktom (%d?)'] = 'T%1',['Floortom (%d?)'] = 'F%1'}

    local function formatFile(path)

        local file,content,new_content
        -- 讀取文件內容
        file = io.open(path, "r")
        
        content = file:read("*a") -- "*a"表示讀取整個文件
        
        new_content = string.lower(content)

        for line in content:gmatch('[^\n]*') do
            n = line:match('%d*')
            if  n then
                line = line:gsub('^(%d+%s)','%1'..note_chart[n]..'\t| ')
            end
            new_content = new_content .. line .. '\n'
        end

        for k,v in pairs(Gsub_chart) do
            new_content = new_content:gsub(string.lower(k),v..'\t| ')
        end
        --msg(new_content)
        --if true then return end

        file:close() -- 關閉文件
    
        -- 打開文件以寫入模式
        file = io.open(path, "w")
        -- 寫入更新後的內容
        file:write(new_content)
        file:close() -- 關閉文件
    
    end

    local function f(path)

        content = ''
        
        line={}

        note_chart = {'C','C#','D','Eb','E','F','G#','G','Ab','A','Bb','B'}

        for abi = 0,127 do

            local note = abi%12+1
            local octave = math.ceil((abi+1)/12)-3
            local note_name = abi..' '..tostring(abi)..'\t|\t'..tostring(note_chart[note])..tostring(octave)
            line[#line+1] = note_name
        end

        for abi=#line,1,-1 do
            content = content .. line[abi]..'\n'
        end

        msg(content)
    
    end
    
    
    local function main()
        local files
        files = r.SearchFiles(dir,ext)
        note_chart = MidiNoteChart()

        for abi = 1, #files do
            formatFile(files[abi])
        end
        
        BBB('DONE!!!')
    end
    
    
    -- local t = {{1,'a',{false,{['id'] = '555'}}},'abc',325,['id'] = '555'}
    -- local text = serialize_beta(t)
    -- msg(t)
    -- msg('\n\n')
    -- msg(text)
    -- msg('\n\n')
    -- ta = unserialize_beta(text)
    -- msg(ta)
    
    api.cc()
    
    --formatFile(SD3)
    EditScript()
