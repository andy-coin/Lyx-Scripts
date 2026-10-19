
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    P = api.gec()

    for abi=1,api.csi(0) do
        item = api.gsi(0,abi-1)
        api.siv(item,'D_POSITION',P)
    end