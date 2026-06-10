-- ============================================================
--  VIOLENCE DISTRICT PROBE — SURVIVOR SIDE
--  Fokus: Auto Unhook (instant) + Auto Parry (klik kanan weapon)
--
--  CARA PAKAI:
--   1. Inject di Solara, JOIN sebagai SURVIVOR
--   2. Equip senjata beli (yang punya parry)
--   3. Skenario test:
--      a. Biarin killer attack lo SEKALI → manually right-click parry
--      b. Biarin killer hook lo → struggle dengan spam SPACE
--      c. Coba self-unhook manual (kalau game support)
--   4. Setelah scenario selesai, ketik di chat: /probe save
--   5. Paste hasil clipboard ke aku
-- ============================================================

local Players      = game:GetService("Players")
local UserInput    = game:GetService("UserInputService")
local LP           = Players.LocalPlayer
local PlayerGui    = LP:WaitForChild("PlayerGui")

-- ── Log buffer ──────────────────────────────────────────────
local LOG = {}
local START_TIME = tick()
local MAX_LINES = 3000

local function ts()
    return string.format("%6.2f", tick() - START_TIME)
end

local function log(tag, ...)
    if #LOG >= MAX_LINES then return end
    local args = {...}
    for i, v in ipairs(args) do args[i] = tostring(v) end
    local line = "[" .. ts() .. "] " .. tag .. " " .. table.concat(args, " ")
    table.insert(LOG, line)
    print("[VD-PROBE-S]", line)
end

log("INIT", "Player:", LP.Name, "Team:", LP.Team and LP.Team.Name or "nil")

-- ============================================================
--  1. REMOTE PROBE — multi-fallback resolver buat Solara
-- ============================================================
local _hookmm = hookmetamethod
                or (getgenv and getgenv().hookmetamethod)
                or (rawget(getfenv(), "hookmetamethod"))
local _getnc  = getnamecallmethod
                or (getgenv and getgenv().getnamecallmethod)
                or (rawget(getfenv(), "getnamecallmethod"))

local seenRemotes = {}
local function logRemote(remote, method, args)
    if not remote then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")
            or remote:IsA("UnreliableRemoteEvent")) then return end
    local path = remote:GetFullName()
    local key  = path .. "|" .. method
    seenRemotes[key] = (seenRemotes[key] or 0) + 1
    if seenRemotes[key] > 8 then return end  -- throttle
    local argStr = ""
    for i = 1, math.min(#args, 5) do
        local v = args[i]
        local s = typeof(v) .. ":" .. tostring(v):sub(1, 50)
        argStr = argStr .. " arg" .. i .. "=" .. s
    end
    log("REMOTE", method, path, argStr)
end

if _hookmm and _getnc then
    local oldNc
    oldNc = _hookmm(game, "__namecall", function(self, ...)
        local m = _getnc()
        if (m == "FireServer" or m == "InvokeServer")
           and typeof(self) == "Instance" then
            pcall(logRemote, self, m, {...})
        end
        return oldNc(self, ...)
    end)
    log("HOOK", "namecall installed via", tostring(_hookmm))
else
    log("HOOK", "FAIL — hookmetamethod=", tostring(_hookmm), "getnamecallmethod=", tostring(_getnc))
end

-- ============================================================
--  2. ANIMATION PROBE — animasi LP + animasi semua killer dalam range
-- ============================================================
local seenAnims = {}
local function watchAnimsLP(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    hum.AnimationPlayed:Connect(function(track)
        local a = track.Animation
        if not a then return end
        local key = "LP|" .. a.AnimationId
        if seenAnims[key] then return end
        seenAnims[key] = true
        log("ANIM-LP", "name=" .. a.Name, "id=" .. a.AnimationId)
    end)
end

local function watchAnimsOther(p)
    if p == LP then return end
    local function attach(c)
        local hum = c:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        hum.AnimationPlayed:Connect(function(track)
            local a = track.Animation
            if not a then return end
            local team = p.Team and p.Team.Name or ""
            local isKiller = team:lower():find("killer") ~= nil
            -- KILLER: NO DEDUP — log every fire dengan FULL metadata buat parry probe.
            -- NON-KILLER: dedup biar log gak spam.
            if not isKiller then
                local key = "O|" .. p.Name .. "|" .. a.AnimationId
                if seenAnims[key] then return end
                seenAnims[key] = true
            end
            local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            local pRoot  = c:FindFirstChild("HumanoidRootPart")
            local dist = (myRoot and pRoot) and (myRoot.Position - pRoot.Position).Magnitude or 999
            if isKiller or dist < 25 then
                local prio = tostring(track.Priority):gsub("Enum.AnimationPriority.", "")
                local len  = string.format("%.2f", track.Length or 0)
                log("ANIM-OTHER", p.Name, "killer=" .. tostring(isKiller),
                    "t=" .. string.format("%.3f", tick()),
                    "dist=" .. string.format("%.1f", dist),
                    "prio=" .. prio, "len=" .. len,
                    "name=" .. a.Name, "id=" .. a.AnimationId)
            end
        end)
    end
    if p.Character then attach(p.Character) end
    p.CharacterAdded:Connect(function(c) task.wait(0.3); attach(c) end)
end

if LP.Character then watchAnimsLP(LP.Character) end
LP.CharacterAdded:Connect(function(c) task.wait(0.3); watchAnimsLP(c) end)
for _, p in ipairs(Players:GetPlayers()) do watchAnimsOther(p) end
Players.PlayerAdded:Connect(watchAnimsOther)

-- ============================================================
--  3. CHARACTER ATTRIBUTE PROBE (cari ParryWindow, Hooked, etc)
-- ============================================================
local function watchCharAttrs(char)
    char.AttributeChanged:Connect(function(name)
        local v = char:GetAttribute(name)
        log("CHAR-ATTR", name, "=", tostring(v))
    end)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        hum.AttributeChanged:Connect(function(name)
            local v = hum:GetAttribute(name)
            log("HUM-ATTR", name, "=", tostring(v))
        end)
        -- Health changes (kalau attack landed)
        hum.HealthChanged:Connect(function(h)
            log("HEALTH", h, "/", hum.MaxHealth)
        end)
    end
    -- DescendantAdded — capture weld saat di-hook
    char.DescendantAdded:Connect(function(d)
        local cn = d.ClassName
        if cn == "Weld" or cn == "Motor6D" or cn:find("Body") then
            local p0 = d.Part0 and d.Part0.Parent and d.Part0.Parent.Name or "?"
            local p1 = d.Part1 and d.Part1.Parent and d.Part1.Parent.Name or "?"
            log("WELD+", cn, d.Name, "P0=" .. p0, "P1=" .. p1)
        end
    end)
end

if LP.Character then watchCharAttrs(LP.Character) end
LP.CharacterAdded:Connect(function(c) task.wait(0.3); watchCharAttrs(c) end)

-- ============================================================
--  4. INPUT PROBE — log SPACE & RIGHT-CLICK saat lo manual trigger
-- ============================================================
UserInput.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Space then
        log("INPUT", "SPACE pressed")
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        log("INPUT", "RIGHT-CLICK pressed (parry attempt)")
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        log("INPUT", "LEFT-CLICK pressed")
    end
end)

-- ============================================================
--  5. GUI / TOOL PROBE — capture parry UI prompt + weapon equip
-- ============================================================
PlayerGui.ChildAdded:Connect(function(c)
    log("GUI+", c.ClassName, c.Name)
end)

-- Watch tool equip (untuk weapon parry detection)
LP.Backpack.ChildAdded:Connect(function(t)
    if t:IsA("Tool") then log("BACKPACK+", t.Name) end
end)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.5)
    c.ChildAdded:Connect(function(t)
        if t:IsA("Tool") then
            log("TOOL-EQUIP", t.Name)
            -- Watch attributes on the tool
            t.AttributeChanged:Connect(function(name)
                log("TOOL-ATTR", t.Name, name, "=", tostring(t:GetAttribute(name)))
            end)
        end
    end)
end)
if LP.Character then
    for _, t in ipairs(LP.Character:GetChildren()) do
        if t:IsA("Tool") then log("TOOL-CURRENT", t.Name) end
    end
end

-- ============================================================
--  6. HOOK PROBE — heuristik LP hooked + dump struktur saat hooked
-- ============================================================
local wasHooked = false
local function checkHooked()
    local c = LP.Character
    if not c then return false end
    -- Cek attribute
    for _, attr in ipairs({"Hooked", "OnHook", "IsHooked", "Caged", "OnCage"}) do
        if c:GetAttribute(attr) == true then return true, "attr:" .. attr end
    end
    -- Cek weld ke Hook object
    for _, d in ipairs(c:GetDescendants()) do
        if (d:IsA("Weld") or d:IsA("Motor6D")) and d.Part0 and d.Part1 then
            local n0 = d.Part0.Parent and d.Part0.Parent.Name:lower() or ""
            local n1 = d.Part1.Parent and d.Part1.Parent.Name:lower() or ""
            if n0:find("hook") or n1:find("hook")
               or n0:find("cage") or n1:find("cage") then
                return true, "weld:" .. d.Part1.Parent.Name
            end
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(0.15)
        local hooked, reason = checkHooked()
        if hooked ~= wasHooked then
            log("HOOKSTATE", hooked and ("HOOKED reason=" .. tostring(reason)) or "FREED")
            if hooked then
                -- Dump full char state saat baru hooked
                local c = LP.Character
                log("HOOK-DUMP", "--- attributes ---")
                for k, v in pairs(c:GetAttributes()) do
                    log("  HOOK-ATTR", k, "=", tostring(v))
                end
                log("HOOK-DUMP", "--- children ---")
                for _, ch in ipairs(c:GetChildren()) do
                    log("  HOOK-CHILD", ch.ClassName, ch.Name)
                end
                -- Cari hook model di workspace
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("Model") and obj.Name:lower():find("hook") then
                        local hrp = obj:FindFirstChild("HumanoidRootPart")
                                 or obj:FindFirstChildWhichIsA("BasePart")
                        if hrp then
                            local myRoot = c:FindFirstChild("HumanoidRootPart")
                            local d = myRoot and (myRoot.Position - hrp.Position).Magnitude or 999
                            if d < 10 then
                                log("HOOK-OBJ", obj:GetFullName(), "dist=" .. string.format("%.1f", d))
                                for k, v in pairs(obj:GetAttributes()) do
                                    log("  HOOK-OBJ-ATTR", k, "=", tostring(v))
                                end
                            end
                        end
                    end
                end
            end
            wasHooked = hooked
        end
    end
end)

-- ============================================================
--  7. KILLER PROXIMITY PROBE — log saat killer dekat (attack range)
-- ============================================================
task.spawn(function()
    local lastWarn = 0
    while true do
        task.wait(0.5)
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myRoot then continue end
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then continue end
            local team = p.Team and p.Team.Name or ""
            if not team:lower():find("killer") then continue end
            local pRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if not pRoot then continue end
            local d = (myRoot.Position - pRoot.Position).Magnitude
            if d < 12 and (tick() - lastWarn > 2) then
                log("KILLER-NEAR", p.Name, "dist=" .. string.format("%.1f", d))
                lastWarn = tick()
            end
        end
    end
end)

-- ============================================================
--  7.5 HIT-MARKER HOTKEY (F8) — manual sync buat parry probe
--  Tekan F8 setiap kali killer NGE-HIT lo (saat damage taken / animation impact).
--  Marker akan logged dengan timestamp + nearest killer dist.
--  Cross-reference: anim event yang fire 200-500ms SEBELUM marker = wind-up swing.
-- ============================================================
do
    local UIS = game:GetService("UserInputService")
    UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        -- F10 = save log (alternative ke /probe save kalo akun gak bisa chat)
        -- F9 dihindari karena conflict dengan Roblox dev console default key.
        if input.KeyCode == Enum.KeyCode.F10 then
            local content = table.concat(LOG, "\n")
            local saved = false
            if writefile then
                pcall(function()
                    writefile("Artheirs_VD_Survivor_Probe.log", content)
                    saved = true
                end)
            end
            if setclipboard then pcall(function() setclipboard(content) end) end
            log("SAVE", "via=F9", "lines=" .. #LOG, "file=" .. (saved and "OK" or "FAIL"))
            print("[VD-PROBE-S] === LOG SAVED VIA F9 ===")
            print("[VD-PROBE-S] File:", saved and "workspace/Artheirs_VD_Survivor_Probe.log" or "writefile unavailable")
            return
        end
        if input.KeyCode == Enum.KeyCode.F8 then
            local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            local bestD, bestName = 999, "none"
            if myRoot then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p == LP then continue end
                    local team = p.Team and p.Team.Name or ""
                    if not team:lower():find("killer") then continue end
                    local pRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                    if not pRoot then continue end
                    local d = (myRoot.Position - pRoot.Position).Magnitude
                    if d < bestD then bestD = d; bestName = p.Name end
                end
            end
            log("HIT-MARKER", "t=" .. string.format("%.3f", tick()),
                "killer=" .. bestName, "dist=" .. string.format("%.1f", bestD))
            print("[VD-PROBE-S] >>> HIT-MARKER recorded <<<")
        end
    end)
end

-- ============================================================
--  8. SAVE COMMAND
-- ============================================================
LP.Chatted:Connect(function(msg)
    if msg:lower() == "/probe save" then
        local content = table.concat(LOG, "\n")
        local saved = false
        if writefile then
            pcall(function()
                writefile("Artheirs_VD_Survivor_Probe.log", content)
                saved = true
            end)
        end
        if setclipboard then pcall(function() setclipboard(content) end) end
        log("SAVE", "lines=" .. #LOG, "file=" .. (saved and "OK" or "FAIL"),
            "clipboard=" .. tostring(setclipboard ~= nil))
        print("[VD-PROBE-S] === LOG SAVED ===")
        print("[VD-PROBE-S] File:", saved and "workspace/Artheirs_VD_Survivor_Probe.log" or "writefile unavailable")
    end
end)

-- ============================================================
print("=========================================================")
print("[VD-PROBE-S] Probe Survivor aktif. Scenario WAJIB:")
print("[VD-PROBE-S]  1. Equip weapon parry (yang lo beli di shop)")
print("[VD-PROBE-S]  2. Biarin killer attack lo SEKALI → klik kanan manual buat parry")
print("[VD-PROBE-S]  3. Biarin killer attack lagi → JANGAN parry (kena hit normal)")
print("[VD-PROBE-S]  4. Biarin di-hook → spam SPACE struggle ~5 detik")
print("[VD-PROBE-S]  5. (Opsional) klik kanan / tekan tombol unhook self kalau ada")
print("[VD-PROBE-S]")
print("[VD-PROBE-S] Setelah scenario kelar, ketik di chat: /probe save")
print("=========================================================")
