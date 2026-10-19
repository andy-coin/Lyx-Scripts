
local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
package.path = package.path..";"..script_path.."?.lua"
local r=require("_Lyx_HOME")

-----CUSTOM-----
move = true
seek = false
min_step = 0.01 -- second

local function main()

    local _,trzzz,trzz,items,cursor,same_pos,Start, End,clear, Points,last_e
        
    r.SelItemFilter()
    r.SelTrackFilter()
    
    trzzz = r.SaveTracks()
    items = r.SaveItems()
    cursor = api.gec()
    
    if  #items == 0 then
        api.cmd(40421,0)--select all itemms in tracks
        r.SelItemFilter()
        items = r.SaveItems()
        clear = true
    end

    trzz = {}
    Points = {}
    last_e = 0

    if  #trzzz == 1 and clear then
        local item,p,e
        for abi=1, #items do
            item = items[abi]
            p = api.giv(item,'D_POSITION')
            e = p + api.giv(item,'D_LENGTH')
            p = math.max(last_e,p)
            Points[p] = {item}
            last_e = e
            Points[e] = {item}
        end
    else
        for abi = 1, #items do
            local item,tr,last_tr,p,e
            item = items[abi]
            tr = api.git(item)
            p = api.giv(item,'D_POSITION')
            e = p + api.giv(item,'D_LENGTH')

            if  not Points[p] then Points[p] = {} end
            if  not Points[e] then Points[e] = {} end
            
            if  last_tr and last_tr == tr then
                p = math.max(last_e,p)
            end
            
            Points[p][#Points[p]+1] = item
            Points[e][#Points[e]+1] = item
            
            trzz[abi] = tr

            last_tr = tr
            last_e = e

        end
    end
    
    local keys = {}
    local Edges = {}
    
    for key in pairs(Points) do
        table.insert(keys,key)
    end

    table.sort(keys,function(a, b) return a > b end)
    same_pos,keys = r.KillTable(keys)

    for abi=1,#keys do
        local time = keys[abi]
        Edges[abi]={time = time,items = Points[time]}
    end

    _,trzz = r.KillTable(trzz)

    if  #trzz == 0 and #trzzz == 0 then
        api.cmd(41167,0) -- move cursor right to nearest item
    else
        for abi = 1, #Edges do
            local point = Edges[abi]
            if  point.time < cursor and math.abs(point.time - cursor ) > min_step then
                api.sec(point.time,move,seek)
                local inbound = cursor >= api.giv(api.gsi(0,0),'D_POSITION') and cursor <= (api.giv(api.gsi(0,0),'D_POSITION') + api.giv(api.gsi(0,0),'D_LENGTH'))
                if  inbound and ((#trzzz == 1 and #items == 1 ) or (#Points[point.time] == #trzz )) then
                    api.cmd(api.name('_RSe043f2271c12e34ade23d20d0fa4694a7d526ae3'),0)--select next item in track
                end
                break
            end
        end
    end

    if clear then api.cmd(40289,0) end

end

api.cc()
main()
reaper.defer(function()end)
