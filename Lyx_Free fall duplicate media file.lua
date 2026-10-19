
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    -----CUSTOM-----
    energe_loss = 0.73

    local function main()
    
        local P,VOL,item,items,item_track,last_duration,last_ratio,ret,csv
        
        if  api.csi(0) ~= 1 or api.gps(0) ~= 0 then return end

        last_duration = api.load('Free fall duplicate','duration')
        last_ratio = api.load('Free fall duplicate','ratio')
        last_duration =  ( last_duration ~= '' and last_duration ) or 1
        last_ratio = (last_ratio ~= '' and last_ratio ) or 0.75

        ret,csv=r.GetUserInputs("Free fall duplicate",2,"Start duration : \30Bounce ratio(0<x<1) :\30note :\30extrawidth=103\30separator=\30",
        last_duration ..'\30' ..  last_ratio ..'\30')
        if not ret then return end 

        item = api.gsi(0,0)
        P = api.giv(item,'D_POSITION')
        E = P + api.giv(item,'D_LENGTH')
        VOL = api.giv(item,'D_VOL')

        local answer = {}
        for str in csv:gmatch("[^\30]*") do
            answer[#answer+1]= str
        end

        local keywords = {'duration','ratio'}

        for abi=1,#answer do
            api.save('Free fall duplicate',keywords[abi],answer[abi],false)
        end
        
        local unit,duration,ratio,default_chan,velocity,note
        if  answer[1]:find('%a') then
            unit = answer[1]:sub(-1,-1)
            duration = tonumber(answer[1]:sub(1,-2))
        else
            unit = 's'
            duration = tonumber(answer[1])
        end

        if  unit =='q' then
            local qn = api.Ttq(0,P)
            duration = api.Tqt(0,qn+1)-P
        end

        ratio = r.NumberCage(answer[2],0.01,0.99,false) or 0.75
        if not duration then return end

        api.ubb()
        --api.pur(1)
        r.SaveTracks(true)

        item_track = api.git(item)
        api.sot(item_track)
        api.cmd(40698,0)--copy item
        
        local count,time

        time = api.now()
        count = 0
        items = {}

        while (VOL > 0.03125 and duration > 0.001 and (api.now()-time) < 1) do -- 20ms
            P = P + duration
            api.sec(P,false,false)
            api.cmd(41748,0)--paste item
            item = api.gsi(0,0)
            items[#items+1]=item
            VOL = VOL * energe_loss
            api.siv(item,'D_VOL',VOL)
            duration = duration * math.sqrt(ratio)^(count)
            count = count + 1
        end


        
        r.RestoreItems(items)
        --api.cmd(api.name('_RS9ed33197231dc7055acf47dc97feac41a2de5edc'),0)
        api.ua()
        r.RestoreTracks(true)
        --api.pur(-1)
        api.ueb(0,'Free fall duplicate media items',-1)
    end

    
    r.run(main)
    
