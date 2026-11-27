-- 讀 Lyx_Reset swing grid.lua 裡的 reset_value，當作所有 swing 腳本的預設 swing feel
-- 用文字解析而不是 dofile，因為 dofile 會直接執行那支 reset 腳本
local dir = debug.getinfo(1).source:match("@?(.*[/\\])_lib[/\\]") or "./"
local f = io.open(dir.."Lyx_Reset swing grid.lua","r")
local v
if f then
    v = tonumber(f:read("a"):match("\nreset_value%s*=%s*([%d%.]+)"))
    f:close()
end
return v or 0.5
