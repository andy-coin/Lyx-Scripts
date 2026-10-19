
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    local function main()
        
        api.cmd(42957,0)--select item under razor area
        razor,razorMap = r.GetRazorEdits(true)

        itemz={}
        if  razor then
            for abi=1,#razorMap.item do

                item = razorMap.item[abi]
                if  api.iis(item) then
                    if  item then
                        new_item = reaper.SplitMediaItem(item,razorMap.min)
                        if  new_item then
                            reaper.SplitMediaItem(new_item,razorMap.max)
                            itemz[#itemz+1] = new_item
                        else
                            new_item = reaper.SplitMediaItem(item,razorMap.max)
                            itemz[#itemz+1] = item
                        end
                    end
                end
            end
        end

        r.RestoreItems(itemz)
    end

    api.ubb()
    api.cmd(api.name("_SWS_SMARTSPLIT"),0)
    --main()
    api.ueb(0,"Split media items at razor area edges",-1)
