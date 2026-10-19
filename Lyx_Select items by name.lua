    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        first_item = api.gsi(0,0)
        if first_item then take = api.gat(first_item) end
        default_name = (take and api.gtkn(take)) or ''

        ok, csv = r.GetUserInputs("Select item with name included:",3,
        'Search name  :\30'..
        'IF in selected tracks? \30'..
        'Include Hidden? \30'..
        'extrawidth=200\30separator=\30',default_name..'\30yes\30yes')

        if not ok then return end

        ans={}
        for string in csv:gmatch('([^\\30])*') do
            ans[#ans+1]=string
        end

        SELECT = ans[2]=='yes'
        HIDE   = ans[3]=='yes'

        if  SELECT then
            for abi=1,api.cst(0) do
                tr = api.gst(0,abi-1)
                for abii=1,api.cti(tr) do
                    item = api.gti(0,abii-1)
                    name = r.GetItemName(item)
                    msg(name)
                end
            end
        else

        end
    end

    r.run(main)