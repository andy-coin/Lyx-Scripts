
    --[[
        Set value / shape of the selected points of the selected envelope.
        The value is typed in the envelope's own unit:
          Volume (track / pre-FX / trim / send / take):  dB. "6" means -6 dB, "+6" means +6 dB, "-" = -inf
          Pan:    L/R percent. "L30", "30L" or "-30" = 30% left, "R30" or "30" = 30% right, "C" = center
          Width:  percent (-100..100)
          FX parameter: the unit the plugin shows (e.g. Hz for an EQ band, "1k" = 1000);
                  plugins that can't report their display values take % of the parameter range
          Anything else (tempo, pitch, ...): raw envelope value
    ]]

    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"

    -- "1.5k" -> 1500, "-inf" -> -huge, "Low shelf" -> nil
    local function parse_num(s)
        s = s:lower()
        if s:find("%-inf") then return -math.huge end
        local n, k = s:match("([-+]?%d*%.?%d+)%s*(k?)")
        n = tonumber(n)
        if n and k == "k" then n = n * 1000 end
        return n
    end

    -- "L30"/"30L"/"-30" -> -0.3, "R30"/"30" -> 0.3, "C" -> 0  (D_PAN convention: negative = left)
    local function parse_pan(s)
        s = s:upper():gsub("[%s%%]", "")
        if s == "C" then return 0 end
        local n = tonumber((s:gsub("[LR]", "")))
        if not n then return end
        if s:find("L") then n = -math.abs(n) elseif s:find("R") then n = math.abs(n) end
        return math.max(-1, math.min(1, n / 100))
    end

    -- Find the normalized (0..1) value whose displayed number is `target`.
    -- shown(norm) returns the plugin's displayed number; assumed monotonic (true for freq/gain/Q...).
    local function find_norm(shown, target)
        local a, b = shown(0), shown(1)
        if not a or not b or a == b then return end
        local up, lo, hi = b > a, 0, 1
        for _ = 1, 40 do
            local mid = (lo + hi) / 2
            local v = shown(mid)
            if not v then return end
            if (v < target) == up then lo = mid else hi = mid end
        end
        return (lo + hi) / 2
    end

    if not reaper then -- self-check: lua "Lyx_Set selected envelope points value.lua"
        assert(parse_num("1.00 kHz") == 1000 and parse_num("-3.5dB") == -3.5 and parse_num("-inf") == -math.huge)
        assert(parse_num("Low shelf") == nil)
        assert(parse_pan("L30") == -0.3 and parse_pan("30L") == -0.3 and parse_pan("-30") == -0.3)
        assert(parse_pan("R30") == 0.3 and parse_pan("30") == 0.3 and parse_pan("c") == 0 and parse_pan("L200") == -1)
        assert(parse_pan("abc") == nil)
        local hz = function(n) return 20 * 1000 ^ n end -- fake log-scaled 20 Hz..20 kHz
        assert(math.abs(hz(find_norm(hz, 1000)) - 1000) < 0.01)
        assert(find_norm(hz, 99999) > 0.9999) -- clamps to the end of the range
        assert(find_norm(function() return 5 end, 5) == nil)
        return print("Envelope value self-check OK")
    end

    local r=require("_lib._Lyx_HOME")

    SHAPE = { ['0']=1, ['1']=0, ['2']=3, ['3']=4, ['4']=2, ['5']=5}

    local VOL   = { VOLENV=1, VOLENV2=1, VOLENV3=1, AUXVOLENV=1, HWVOLENV=1 }
    local PAN   = { PANENV=1, PANENV2=1, AUXPANENV=1, HWPANENV=1 }
    local WIDTH = { WIDTHENV=1, WIDTHENV2=1 }

    -- Returns the prompt label and a function turning the typed text into a raw envelope value.
    local function converter(env)
        local tr, fx, param = reaper.Envelope_GetParentTrack(env)
        local obj, is_take = tr, false
        if not (tr and fx >= 0) then
            obj, fx, param = reaper.Envelope_GetParentTake(env)
            is_take = true
        end

        -- FX parameter envelope
        if obj and fx >= 0 then
            local P = is_take and "TakeFX_" or "TrackFX_"
            local fmt, ex, cur = reaper[P.."FormatParamValueNormalized"], reaper[P.."GetParamEx"], reaper[P.."GetParamNormalized"]
            local _, minv, maxv = ex(obj, fx, param)
            local function shown(norm)
                local ok, s = fmt(obj, fx, param, norm, "")
                return ok and parse_num(s) or nil
            end
            local function raw(norm) return minv + norm * (maxv - minv) end
            if shown(0) and shown(1) and shown(0) ~= shown(1) then
                local _, now = fmt(obj, fx, param, cur(obj, fx, param), "")
                local unit = now:gsub("^[^%a%%]*", ""):gsub("^k(%a)", "%1") -- "1.00 kHz" -> "Hz"
                return "Value"..(unit ~= "" and " ("..unit..")" or "").." :", function(s)
                    local n = parse_num(s)
                    local norm = n and find_norm(shown, n)
                    return norm and raw(norm)
                end
            end
            return "Value (% of range) :", function(s)
                local n = tonumber((s:gsub("[%s%%]", "")))
                return n and raw(math.max(0, math.min(100, n)) / 100)
            end
        end

        -- built-in envelopes, identified by their chunk tag (works in any language)
        local _, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
        local tag = chunk:match("^<(%u+%d*)") or ""

        if VOL[tag] then
            local mode = reaper.GetEnvelopeScalingMode(env)
            return "Volume (dB, auto negative, + for boost) :", function(s)
                local dB
                if s:find("^%s*%-%s*$") then dB = -math.huge
                else
                    dB = tonumber((s:gsub("%s", "")))
                    if not dB then return end
                    if not s:find("%+") then dB = -math.abs(dB) end
                end
                return reaper.ScaleToEnvelopeMode(mode, 10 ^ (dB / 20))
            end
        elseif PAN[tag] then
            -- REAPER stores some pan envelopes inverted (raw +1 = left); ask REAPER which way this one goes
            local sign = reaper.Envelope_FormatValue(env, 1):upper():find("L") and -1 or 1
            return "Pan (L100 .. C .. R100) :", function(s)
                local p = parse_pan(s)
                return p and p * sign
            end
        elseif WIDTH[tag] then
            return "Width (%) :", function(s)
                local n = tonumber((s:gsub("[%s%%]", "")))
                return n and math.max(-1, math.min(1, n / 100))
            end
        end
        return "Value (raw) :", function(s) return tonumber((s:gsub("%s", ""))) end
    end

    local function main()

        local env, Value, Shape, ai_idx

        env = api.gse()

        if not env then return end

        local label, to_raw = converter(env)

        local ret,csv=r.GetUserInputs(
                "Set Envelope Points",2,label.."\30Curve shape : \30extrawidth=175\30separator=\30",
                '\30 [0=⎍] , [1=／] , [2=⎛] , [3=⎠] , [4=∫] , [5=ß]\30')

        if not ret then return end

        local answer = {}
        for str in csv:gmatch("[^\30]*") do
            answer[#answer+1]= str
        end

        Shape = SHAPE[(answer[2] or ""):gsub("%s", "")]

        if  answer[1] and answer[1]:find("%S") then
            Value = to_raw(answer[1])
            if not Value then
                reaper.MB("Could not read the value \""..answer[1].."\".", "Set envelope points", 0)
                return
            end
        end

        if not Value and not Shape then return end

        r.Undo("Set selected envelope points value", function()
            ai_idx = api.cai(env)

            for abi = -1 ,ai_idx-1 do
                local p_idx = api.cep(env,abi)
                for abii = 0, p_idx-1 do
                    local retval, time, value, shape, tension, selected = api.gep(env, abi, abii)
                    if  retval and selected then
                        api.sep(env, abi, abii, time, Value or value, Shape or shape, tension, selected, true)
                    end
                end
                api.esp(env, abi)
            end
            api.ua()
        end)
    end

    api.cc()
    r.run(main)
