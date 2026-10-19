    -- Color selected audio items by their source file: same file = same color.
    -- The color comes from the file name, so a file keeps its color every time you run this
    -- (handy before editing/comping: every take of one recording pass reads as one color).

    -----CUSTOM-----
    SATURATION = 0.55   -- 0..1
    BRIGHTNESS = 0.80   -- 0..1
    ----------------

    local function HashColor(str)
        local h = 5381
        for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967296 end
        -- hue from the hash, fixed saturation/brightness so every color is readable
        local hue = (h % 360) / 60
        local c = BRIGHTNESS * SATURATION
        local x = c * (1 - math.abs(hue % 2 - 1))
        local m = BRIGHTNESS - c
        local rgb = ({ {c,x,0}, {x,c,0}, {0,c,x}, {0,x,c}, {x,0,c}, {c,0,x} })[math.floor(hue) + 1]
        local function b(v) return math.floor((v + m) * 255 + 0.5) end
        return reaper.ColorToNative(b(rgb[1]), b(rgb[2]), b(rgb[3])) | 0x1000000
    end

    local function SourceName(take)
        local src = reaper.GetMediaItemTake_Source(take)
        if not src then return end
        src = reaper.GetMediaSourceParent(src) or src -- reversed / section sources
        local name = reaper.GetMediaSourceFileName(src)
        return name ~= "" and name:match("[^/\\]+$") or nil
    end

    local count = reaper.CountSelectedMediaItems(0)
    if count == 0 then return end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        local name = take and not reaper.TakeIsMIDI(take) and SourceName(take)
        if name then
            reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", HashColor(name))
        end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Color selected items by source file", -1)
