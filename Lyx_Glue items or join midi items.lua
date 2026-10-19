-- Join selected items without the render window.
--   MIDI items  : one new MIDI item per track & lane, holding every event that was audible
--                 in the old items (notes cut at item edges), originals removed.
--   audio items : pieces of the same file that still line up (e.g. after splitting) are healed
--                 into one item by stretching the first one; no new file is written.
--                 Audio that cannot be healed (different files, moved pieces) has no way to
--                 become one item without rendering: those fall back to REAPER's Glue (40362).
-- ponytail: looped MIDI items only keep their first pass; glue them natively if that matters.

local EPS = 1e-6

local function info(item)
    local take = reaper.GetActiveTake(item)
    local p = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    return { item = item, take = take, p = p, e = p + reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
             tr = reaper.GetMediaItem_Track(item), lane = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE"),
             midi = take and reaper.TakeIsMIDI(take) }
end

-- audio piece b continues a's file exactly where a's timeline says it should
local function healable(a, b)
    if not (a.take and b.take) then return false end
    if reaper.CountTakes(a.item) ~= 1 or reaper.CountTakes(b.item) ~= 1 then return false end
    if b.p > a.e + EPS then return false end -- gap
    local sa, sb = reaper.GetMediaItemTake_Source(a.take), reaper.GetMediaItemTake_Source(b.take)
    if reaper.GetMediaSourceFileName(sa) ~= reaper.GetMediaSourceFileName(sb) then return false end
    for _, k in ipairs({ "D_PLAYRATE", "D_PITCH", "D_VOL", "D_PAN", "I_CHANMODE" }) do
        if math.abs(reaper.GetMediaItemTakeInfo_Value(a.take, k) - reaper.GetMediaItemTakeInfo_Value(b.take, k)) > EPS then return false end
    end
    local rate = reaper.GetMediaItemTakeInfo_Value(a.take, "D_PLAYRATE")
    local da = reaper.GetMediaItemTakeInfo_Value(a.take, "D_STARTOFFS")
    local db = reaper.GetMediaItemTakeInfo_Value(b.take, "D_STARTOFFS")
    return math.abs((b.p - a.p) - (db - da) / rate) < 1e-4
end

local function HealAudio(run) -- returns items left that still need a real glue
    local keep, left = run[1], {}
    for i = 2, #run do
        local b = run[i]
        if healable(keep, b) then
            local e = math.max(keep.e, b.e)
            reaper.SetMediaItemInfo_Value(keep.item, "D_LENGTH", e - keep.p)
            if b.e >= keep.e then -- the later piece's fade-out becomes the end of the joined item
                reaper.SetMediaItemInfo_Value(keep.item, "D_FADEOUTLEN", reaper.GetMediaItemInfo_Value(b.item, "D_FADEOUTLEN"))
                reaper.SetMediaItemInfo_Value(keep.item, "D_FADEOUTLEN_AUTO", reaper.GetMediaItemInfo_Value(b.item, "D_FADEOUTLEN_AUTO"))
            end
            keep.e = e
            reaper.DeleteTrackMediaItem(b.tr, b.item)
        else
            left[#left + 1] = keep
            keep = b
        end
    end
    left[#left + 1] = keep
    return left
end

local function JoinMIDI(run)
    local s, e = run[1].p, run[1].e
    for _, it in ipairs(run) do e = math.max(e, it.e) end
    local new = reaper.CreateNewMIDIItemInProj(run[1].tr, s, e, false)
    local nt = reaper.GetActiveTake(new)
    reaper.SetMediaItemInfo_Value(new, "I_FIXEDLANE", run[1].lane)
    reaper.SetMediaItemInfo_Value(new, "I_CUSTOMCOLOR", reaper.GetMediaItemInfo_Value(run[1].item, "I_CUSTOMCOLOR"))
    reaper.GetSetMediaItemTakeInfo_String(nt, "P_NAME", select(2, reaper.GetSetMediaItemTakeInfo_String(run[1].take, "P_NAME", "", false)), true)

    local function ppq(t) return reaper.MIDI_GetPPQPosFromProjTime(nt, t) end
    for _, it in ipairs(run) do
        local tk = it.take
        local function time(x) return reaper.MIDI_GetProjTimeFromPPQPos(tk, x) end
        local _, nn, nc, nx = reaper.MIDI_CountEvts(tk)
        for i = 0, nn - 1 do
            local _, sel, mute, sp, ep, ch, pitch, vel = reaper.MIDI_GetNote(tk, i)
            local ts, te = time(sp), time(ep)
            if te > it.p + EPS and ts < it.e - EPS then -- audible part only, cut at the item edges
                reaper.MIDI_InsertNote(nt, sel, mute, ppq(math.max(ts, it.p)), ppq(math.min(te, it.e)), ch, pitch, vel, true)
            end
        end
        for i = 0, nc - 1 do
            local _, sel, mute, cp, msg, ch, m2, m3 = reaper.MIDI_GetCC(tk, i)
            local t = time(cp)
            if t >= it.p - EPS and t < it.e - EPS then
                local _, shape, tension = reaper.MIDI_GetCCShape(tk, i)
                reaper.MIDI_InsertCC(nt, sel, mute, ppq(t), msg, ch, m2, m3)
                local _, _, cnt = reaper.MIDI_CountEvts(nt) -- unsorted insert lands at the end
                reaper.MIDI_SetCCShape(nt, cnt - 1, shape, tension, true)
            end
        end
        for i = 0, nx - 1 do
            local _, sel, mute, xp, typ, msg = reaper.MIDI_GetTextSysexEvt(tk, i)
            local t = time(xp)
            if t >= it.p - EPS and t < it.e - EPS then
                reaper.MIDI_InsertTextSysexEvt(nt, sel, mute, ppq(t), typ, msg)
            end
        end
        reaper.DeleteTrackMediaItem(it.tr, it.item)
    end
    reaper.MIDI_Sort(nt)
    return new
end

local cnt = reaper.CountSelectedMediaItems(0)
if cnt < 2 then return end

-- group by track & lane, MIDI and audio apart
local groups, order = {}, {}
for i = 0, cnt - 1 do
    local it = info(reaper.GetSelectedMediaItem(0, i))
    if it.take then
        local key = tostring(it.tr) .. ":" .. it.lane .. ":" .. tostring(it.midi)
        if not groups[key] then groups[key] = {}; order[#order + 1] = key end
        table.insert(groups[key], it)
    end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local result, to_glue = {}, {}
for _, key in ipairs(order) do
    local run = groups[key]
    table.sort(run, function(a, b) return a.p < b.p end)
    if #run == 1 then
        result[#result + 1] = run[1].item
    elseif run[1].midi then
        result[#result + 1] = JoinMIDI(run)
    else
        local left = HealAudio(run)
        for _, it in ipairs(left) do
            if #left > 1 then to_glue[#to_glue + 1] = it.item else result[#result + 1] = it.item end
        end
    end
end

reaper.SelectAllMediaItems(0, false)
if #to_glue > 0 then -- audio that only a render can join
    for _, item in ipairs(to_glue) do reaper.SetMediaItemSelected(item, true) end
    reaper.Main_OnCommand(40362, 0) -- Item: Glue items (leaves the glued items selected)
end
for _, item in ipairs(result) do
    if reaper.ValidatePtr2(0, item, "MediaItem*") then reaper.SetMediaItemSelected(item, true) end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Join items", -1)
