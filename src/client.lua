-- ===========================================================
--  [CURE] Violence District  |  Kentod Cheat v1.0
--  Executor : Solara
-- ===========================================================
--  FITUR:
--    [1]      Toggle ESP
--             - Survivor : ESP Killer (merah) + ESP Generator (kuning)
--             - Killer   : ESP Survivor (hijau)
--    [2]      Toggle Teleport Menu (UP/DOWN pilih, ENTER konfirmasi)
--    [3]      Toggle Speed  (LEFT/RIGHT adjust nilai)
--    [INSERT] Toggle tampilan menu
-- ===========================================================
--  CATATAN KONFIGURASI:
--    Jika ESP tidak muncul, sesuaikan:
--      CFG.teamKiller / teamSurvivor  → nama Team di game
--      CFG.genNames                   → nama Generator di workspace
-- ===========================================================

-- ── SERVICES ────────────────────────────────────────────────
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

local LP = Players.LocalPlayer

-- ===========================================================
--  ACCESS CONTROL — Dynamic Whitelist (fetch dari GitHub)
--  Whitelist di-host terpisah di whitelist.lua. Tambah/hapus user
--  cukup edit file kecil itu, script utama ga perlu di-recompile/
--  re-obfuscate. Lihat SETUP_GITHUB_GUIDE.md untuk workflow.
-- ===========================================================

-- GANTI URL ini ke raw GitHub whitelist.lua kamu setelah upload.
-- Format: https://raw.githubusercontent.com/<USER>/<REPO>/refs/heads/main/whitelist.lua
local WHITELIST_URL = "https://raw.githubusercontent.com/artheirs/client-utils-vdpc/refs/heads/main/whitelist.lua"

-- Emergency owner fallback: kalau fetch whitelist gagal (GitHub down,
-- network block, dll), UserId di sini tetap di-allow supaya owner ga
-- ke-lock dari script-nya sendiri saat lagi testing/maintenance.
local OWNER_FALLBACK = { 8961991252 }  -- Cio

local function _fetchWhitelist()
    -- Cache-bust query supaya GitHub CDN ga return stale whitelist
    local url = WHITELIST_URL .. "?t=" .. tostring(os.time())
    local ok, body = pcall(function()
        return game:HttpGet(url, true)
    end)
    if not ok or type(body) ~= "string" or #body == 0 then
        return nil, "fetch failed"
    end
    local fn, errC = loadstring(body)
    if not fn then return nil, "compile: " .. tostring(errC) end
    local ok2, result = pcall(fn)
    if not ok2 or type(result) ~= "table" then
        return nil, "exec: " .. tostring(result)
    end
    return result, nil
end

local function _isAuthorized()
    local myId = LP.UserId

    -- 1. Coba whitelist live dari GitHub
    local list, err = _fetchWhitelist()
    if list then
        for _, id in ipairs(list) do
            if id == myId then return true, "live" end
        end
        return false, "live"
    end

    -- 2. Fetch gagal → cek emergency owner fallback (offline-safe)
    for _, id in ipairs(OWNER_FALLBACK) do
        if id == myId then return true, "fallback (" .. tostring(err) .. ")" end
    end
    return false, "fetch failed: " .. tostring(err)
end

local _ok, _src = _isAuthorized()
if not _ok then
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = "Artheirs Script",
            Text     = "Access Denied — UserId kamu tidak di whitelist",
            Duration = 10,
        })
    end)
    warn("[ARTHEIRS] Access denied for UserId " .. tostring(LP.UserId)
        .. " — reason: " .. tostring(_src))
    return
end


-- ── CONFIG ──────────────────────────────────────────────────
local CFG = {
    -- Keybind
    KEY_ESP     = Enum.KeyCode.One,
    KEY_TP      = Enum.KeyCode.Two,
    KEY_SPEED   = Enum.KeyCode.Three,
    KEY_FLY        = Enum.KeyCode.Four,
    KEY_NOCLIP     = Enum.KeyCode.Five,
    KEY_FULLBRIGHT = Enum.KeyCode.Six,
    KEY_AUTOREPAIR = Enum.KeyCode.Seven,
    KEY_AUTOESCAPE = Enum.KeyCode.Eight,
    KEY_AIMBOT     = Enum.KeyCode.Nine,

    -- State
    espEnabled   = true,  -- master switch (keybind [1] toggles ini)
    -- Sub-toggles untuk granular ESP control (UI di ESP tab)
    espKillerEnabled    = true,
    espSurvivorEnabled  = true,
    espGeneratorEnabled = true,
    espPalletEnabled    = false,
    tpOpen       = false,
    roleOverride = false,
    manualRole   = "Survivor",

    -- Speedhack
    speedEnabled = false,
    speedValue   = 30,
    speedMin     = 16,
    speedMax     = 200,
    speedStep    = 5,

    -- Camera FOV (POV adjust di tab Misc)
    fovValue   = 70,   -- Roblox default; >70 = wider POV, <70 = zoom in
    fovDefault = 70,
    fovMin     = 30,
    fovMax     = 120,
    fovStep    = 5,

    -- Streamproof (GUI invisible saat record OBS/Medal/ShadowPlay)
    streamproofEnabled = true,

    -- Fly / Noclip / Fullbright
    flyEnabled        = false,
    flySpeedMul       = 1.5,   -- pengali kecepatan fly dari speedValue
    noclipEnabled     = false,
    fullbrightEnabled = false,

    -- Auto Repair (auto-detect gen terdekat, tidak perlu toggle per gen)
    autoRepairEnabled = false,
    autoRepairRange   = 18,    -- jarak max ke generator (studs) buat hold mouse
    autoRepairTick    = 0.1,   -- interval cek (detik) — lebih responsive saat pindah gen

    -- No Skill Check (auto-tap Space saat SkillCheckPromptGui.Check Visible)
    -- Probe: GREAT zone hit ~0.82-0.88s after appearance → buff repairboost=1.03, skillcheckspeed=0.95
    noSkillCheckEnabled = false,
    skillCheckDelay     = 0.85,   -- detik, target GREAT/PERFECT zone
    skillCheckJitter    = 0.08,   -- ±jitter biar ga robotic

    -- Auto Escape (TP otomatis pas killer dekat saat lagi repair)
    autoEscapeEnabled = false,
    escapeDistance    = 40,    -- studs, killer dianggap "bahaya"
    escapeCooldown    = 3,     -- detik antar trigger TP
    escapeTick        = 0.2,   -- interval cek (detik)

    -- Aimbot (lock kamera ke target dalam FOV pixel radius)
    aimbotEnabled = false,
    aimbotFOV     = 120,       -- radius pixel dari center screen
    aimbotFOVMin  = 30,
    aimbotFOVMax  = 400,
    aimbotFOVStep = 10,

    -- Crosshair (always-on dot)
    crosshairSize = 4,         -- pixel

    -- Generator progress display (di ESP label)
    genProgressShow = true,

    -- Auto Rescue hooked teammate (TP + hold mouse di hook)
    autoRescueEnabled = false,
    rescueRange       = 12,    -- jarak max ke hook
    rescueCooldown    = 4,     -- detik antar trigger
    rescueTick        = 0.2,

    -- Auto Heal (self atau team yang darahnya berkurang/knockdown)
    autoHealEnabled = false,
    healRange       = 10,
    healSelfHpThreshold = 90,  -- heal diri sendiri kalau HP < 90% max
    healTick        = 0.3,

    -- Auto Unhook Self (saat karakter sendiri di-hook)
    autoUnhookEnabled = false,
    unhookTick        = 0.15,

    -- Auto Parry (saat killer attack lo dekat, equip Parry Dagger)
    -- Game parry window = 800ms; game cooldown 60s fail / 90s success
    -- HYBRID detection: pre-emptive (close+facing) + reactive (anim-event backup)
    autoParryEnabled       = false,
    parryRange             = 9,     -- range relaxed lagi (whitelist anim ID udah selektif)
    parryCooldown          = 2,     -- REACT mode: 2s cooldown (allow retry per encounter, no spam)
    parryTick              = 0.04,
    parryFacingDot         = 0.5,   -- relaxed (anim ID whitelist udah very selective)
    parryAnimWindow        = 0.3,   -- catch wind-up + react time
    -- Whitelist anim IDs dari probe (CanhKhietjztbZN killer combo).
    -- Wind-up anim — Action priority, len 1.50s — fire pertama di combo, 200-400ms before impact.
    parryWindupAnimIds = {
        -- TheCure killer (probe 1 = CanhKhietjztbZN player) + probe 5 (re-confirmed)
        ["135002183282873"] = true,  -- wind-up (Action, ~530ms before impact)
        ["121216847022485"] = true,  -- strike (Action2)
        ["137795837089724"] = true,  -- recovery (Action3)
        -- TheCure secondary attacks (dari probe 1)
        ["111223305405046"] = true,  -- combo B wind-up
        ["137504605181913"] = true,  -- close-range slam
        -- TheAbysswalker killer (probe 2) — confirmed via 2 HIT-MARKER timing match
        ["118907603246885"] = true,  -- wind-up (~500ms before impact, paling early)
        ["78432063483146"]  = true,  -- strike
        ["126626340093785"] = true,  -- impact/follow-through
        -- TheVeil killer (probe 3) — confirmed via 2 HIT-MARKER timing match
        ["122812055447896"] = true,  -- wind-up (~360ms before impact)
        ["78935059863801"]  = true,  -- strike
        ["119752564209631"] = true,  -- impact/follow-through
        -- TheSlasher killer (probe 4) — confirmed via 2 HIT-MARKER timing match
        ["110355011987939"] = true,  -- wind-up (~400ms before impact)
        ["139369275981139"] = true,  -- strike
        ["121571390309073"] = true,  -- impact/follow-through
    },
    parryDebug             = true,

    -- KILLER FEATURES ────────────────────────────────────
    -- Auto-Attack M1 (saat survivor melee range + facing)
    autoAttackEnabled = false,
    autoAttackRange   = 7,      -- studs melee range
    autoAttackFOV     = 0.45,   -- dot product threshold (0.45 ≈ 60° cone)
    autoAttackTick    = 0.08,

    -- Auto-Pickup downed survivor
    autoPickupEnabled = false,
    pickupRange       = 8,
    pickupTick        = 0.25,

    -- Auto-Hook (after carrying survivor, walk + interact at hook)
    autoHookEnabled = false,
    hookRange       = 6,
    hookTick        = 0.4,

    -- Generator Activity (show gens being repaired on killer ESP)
    genActivityEnabled = true,
    genActivityRange   = 8,     -- survivor in this range = gen "active"

    -- Anti-stun (signal-based, instant response — covers semua stun source)
    antiPalletStunEnabled  = false,
    antiFlashlightEnabled  = false,
    antiVaultStunEnabled   = false,
    antiShootStunEnabled   = false,
    antiStunTick           = 0.05,

    -- Auto-Break pallet (dropped pallet in range + facing → auto break)
    autoBreakPalletEnabled = false,
    breakPalletRange       = 8,
    breakPalletTick        = 0.3,

    -- God Mode (signal-based health reset)
    godModeEnabled = false,

    -- Warna
    colorKiller    = Color3.fromRGB(255, 80,  80),
    colorSurvivor  = Color3.fromRGB(80,  255, 80),
    colorGenerator = Color3.fromRGB(255, 220, 50),

    -- Nama Team di Violence District (edit jika perlu)
    teamKiller   = "Killers",
    teamSurvivor = "Survivors",

    -- Nama EXACT Generator Model di workspace (case-sensitive, edit jika perlu)
    genNames = {"Generator"},
}

-- ============================================================
--  STEP 1: ROLE DETECTION + CACHE
--  Cache di-update tiap ganti team atau respawn.
--  Tidak compute ulang di setiap frame → lebih efisien.
-- ============================================================
local roleCache = "Survivor"

local function computeRole()
    if LP.Team then
        local t  = LP.Team.Name
        local tl = t:lower()

        -- Exact match (paling aman)
        if t == CFG.teamKiller   then return "Killer"   end
        if t == CFG.teamSurvivor then return "Survivor" end

        -- Exact lower match untuk variasi umum
        if tl == "killer"   or tl == "killers"   then return "Killer"   end
        if tl == "survivor" or tl == "survivors" then return "Survivor" end

        -- Fallback ukuran team: Killer biasanya sendirian di teamnya (1 orang)
        -- Survivor berada di tim yang sama bersama survivor lain (>1 orang)
        local teamCount = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Team == LP.Team then teamCount += 1 end
        end
        if teamCount == 1 then return "Killer" end
        return "Survivor"
    end

    -- Belum ada team / masih di lobby
    return "Lobby"
end

local function getRole()
    if CFG.roleOverride then return CFG.manualRole end
    return roleCache
end

-- Update cache saat team berubah
LP:GetPropertyChangedSignal("Team"):Connect(function()
    roleCache = computeRole()
end)

-- Update cache saat respawn (delay 0.5 detik agar nilai sudah terset)
LP.CharacterAdded:Connect(function(char)
    task.delay(0.5, function()
        roleCache = computeRole()
        -- Pantau perubahan Role value di dalam character
        local rv = char:FindFirstChild("Role")
        if rv and rv:IsA("StringValue") then
            rv:GetPropertyChangedSignal("Value"):Connect(function()
                roleCache = computeRole()
            end)
        end
    end)
end)

-- Inisialisasi pertama
roleCache = computeRole()

-- ============================================================
--  STEP 2: HELPER — JARAK
-- ============================================================
local function getDistance(targetPos)
    local char = LP.Character
    if not char then return 0 end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return 0 end
    return math.floor((root.Position - targetPos).Magnitude)
end

-- ============================================================
--  STEP 3: ESP CORE
--  Pattern: create-once, update teks tiap frame.
--  BillboardGui disimpan di dalam BasePart target (hrp / part).
-- ============================================================
local function getOrCreateESP(part)
    local bb = part:FindFirstChild("_VD_ESP")
    if bb then return bb end

    bb                  = Instance.new("BillboardGui")
    bb.Name             = "_VD_ESP"
    bb.AlwaysOnTop      = true
    bb.Size             = UDim2.new(0, 140, 0, 40)
    bb.StudsOffset      = Vector3.new(0, 3.5, 0)
    bb.ResetOnSpawn     = false
    bb.LightInfluence   = 0
    bb.Enabled          = false

    local lbl                   = Instance.new("TextLabel")
    lbl.Name                    = "Label"
    lbl.Size                    = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency  = 1
    lbl.TextStrokeTransparency  = 0
    lbl.TextStrokeColor3        = Color3.new(0, 0, 0)
    lbl.Font                    = Enum.Font.GothamBold
    lbl.TextSize                = 13
    lbl.TextXAlignment          = Enum.TextXAlignment.Center
    lbl.Parent                  = bb

    bb.Parent = part
    return bb
end

local function showESP(part, color, text)
    if not part or not part.Parent then return end
    local bb  = getOrCreateESP(part)
    local lbl = bb:FindFirstChild("Label")
    if not lbl then return end
    lbl.TextColor3 = color
    lbl.Text       = text
    bb.Enabled     = true
end

local function hideESP(part)
    if not part then return end
    local bb = part:FindFirstChild("_VD_ESP")
    if bb then bb.Enabled = false end
end

-- ── Chams Highlight (body fill + outline, tembus tembok) ────
-- Pattern: create-once per Character, toggle Enabled & ganti color sesuai role.
-- Subtle: fill transparency 0.7 (tint ringan), outline 0 (jelas).
local function getOrCreateHL(char)
    if not char then return nil end
    local h = char:FindFirstChild("_VD_HL")
    if h then return h end

    h                     = Instance.new("Highlight")
    h.Name                = "_VD_HL"
    h.Adornee             = char
    h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillTransparency    = 0.7  -- subtle body tint
    h.OutlineTransparency = 0    -- outline tegas
    h.Enabled             = false
    h.Parent              = char
    return h
end

local function showHL(char, fillColor, outlineColor)
    local h = getOrCreateHL(char)
    if not h then return end
    h.FillColor    = fillColor
    h.OutlineColor = outlineColor
    h.Enabled      = true
end

local function hideHL(char)
    if not char then return end
    local h = char:FindFirstChild("_VD_HL")
    if h then h.Enabled = false end
end

-- ============================================================
--  STEP 4: GENERATOR SCANNER (cache 5 detik)
-- ============================================================
local genCache    = {}
local genLastScan = 0

local function getGenerators()
    local now = tick()
    if now - genLastScan < 5 then return genCache end
    genLastScan = now
    genCache    = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        -- Hanya Model (bukan sub-part), exact name match
        if not obj:IsA("Model") then continue end

        local matched = false
        for _, name in ipairs(CFG.genNames) do
            if obj.Name == name then matched = true break end
        end
        if not matched then continue end

        -- Satu entry per Model menggunakan PrimaryPart atau BasePart pertama
        local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        if part and not table.find(genCache, part) then
            table.insert(genCache, part)
        end
    end
    return genCache
end

-- ============================================================
--  STEP 5: TELEPORT
-- ============================================================
local function teleportTo(target)
    local myChar = LP.Character
    local tChar  = target.Character
    if not myChar or not tChar then return end

    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    local tRoot  = tChar:FindFirstChild("HumanoidRootPart")
    if not myRoot or not tRoot then return end

    myRoot.CFrame = tRoot.CFrame
end

-- ============================================================
--  STEP 6: ESP UPDATE LOOP
-- ============================================================
-- Tracker generator yang lagi di-highlight (persist across frames)
local lastGenModels = {}
local lastGenParts  = {}  -- track BillboardGui ESP labels supaya bisa di-hide saat Killer
-- Tracker pallet ESP
local lastPalletModels = {}
local lastPalletParts  = {}

-- Shared helpers table (1 local, hemat register vs 3 forward decl).
-- Diisi di section bawah (STEP 6.7/6.8). ESP loop akses via _H.fn(...).
local _H = {}

RunService.RenderStepped:Connect(function()
    local myRole = getRole()

    -- ── Player ESP + Chams ─────────────────────────────────
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end

        local char = p.Character
        if not char then continue end

        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")

        -- Guard: karakter belum siap atau sudah mati
        if not hrp or not hum or hum.Health <= 0 then
            if hrp then hideESP(hrp) end
            hideHL(char)
            continue
        end

        -- Tentukan role target berdasarkan team-nya
        local targetRole = "Survivor"
        if p.Team then
            local tn = p.Team.Name
            if tn == CFG.teamKiller or tn:lower():find("killer") then
                targetRole = "Killer"
            end
        end

        -- Show condition: master ON + sub-toggle by target role
        local subOn = (targetRole == "Killer"   and CFG.espKillerEnabled)
                   or (targetRole == "Survivor" and CFG.espSurvivorEnabled)
        local shouldShow = CFG.espEnabled and subOn
            and (
                (myRole == "Survivor" and targetRole == "Killer")
             or (myRole == "Survivor" and targetRole == "Survivor")
             or (myRole == "Killer"   and targetRole == "Survivor")
            )

        if shouldShow then
            local labelColor, chamsFill, chamsOutline
            local stateTag = ""
            if targetRole == "Killer" then
                labelColor   = CFG.colorKiller
                chamsFill    = Color3.fromRGB(255, 80, 80)
                chamsOutline = Color3.fromRGB(255,  0,  0)
            elseif _H.isPlayerHooked and _H.isPlayerHooked(p) then
                -- Hooked teammate → orange terang, label "HOOKED"
                labelColor   = Color3.fromRGB(255, 150, 50)
                chamsFill    = Color3.fromRGB(255, 140, 40)
                chamsOutline = Color3.fromRGB(255, 100,  0)
                stateTag     = " · HOOKED"
            elseif _H.isPlayerDowned and _H.isPlayerDowned(p) then
                -- Downed teammate → kuning
                labelColor   = Color3.fromRGB(255, 220, 80)
                chamsFill    = Color3.fromRGB(255, 220, 80)
                chamsOutline = Color3.fromRGB(220, 180,  0)
                stateTag     = " · DOWN"
            else
                labelColor   = CFG.colorSurvivor
                chamsFill    = Color3.fromRGB(80, 255, 100)
                chamsOutline = Color3.fromRGB( 0, 220,  0)
            end
            local dist = getDistance(hrp.Position)
            showESP(hrp, labelColor, p.DisplayName .. "\n[" .. dist .. "m]" .. stateTag)
            showHL(char, chamsFill, chamsOutline)
        else
            hideESP(hrp)
            hideHL(char)
        end
    end

    -- ── Generator ESP + Chams (khusus Survivor) ─────────────
    if myRole == "Survivor" and CFG.espEnabled and CFG.espGeneratorEnabled then
        local current = {}
        local currentParts = {}
        for _, part in ipairs(getGenerators()) do
            local dist  = getDistance(part.Position)
            local label = "Generator\n[" .. dist .. "m]"
            if CFG.genProgressShow then
                local pct = _H.getGenProgress and _H.getGenProgress(part)
                if pct then
                    label = label .. " · " .. math.floor(pct + 0.5) .. "%"
                end
            end
            showESP(part, CFG.colorGenerator, label)
            currentParts[part] = true

            -- Highlight whole generator model (tembus tembok, warna kuning)
            local model = part:FindFirstAncestorWhichIsA("Model")
            if model then
                showHL(model, Color3.fromRGB(255, 220, 50), Color3.fromRGB(255, 200, 0))
                current[model] = true
            end
        end
        -- Hide model lama yg ga ada di scan terbaru (jaga-jaga kalau gen di-destroy)
        for model in pairs(lastGenModels) do
            if not current[model] and model and model.Parent then
                hideHL(model)
            end
        end
        for part in pairs(lastGenParts) do
            if not currentParts[part] and part and part.Parent then
                hideESP(part)
            end
        end
        lastGenModels = current
        lastGenParts  = currentParts
    elseif myRole == "Killer" and CFG.espEnabled and CFG.espGeneratorEnabled and CFG.genActivityEnabled then
        -- Killer mode: hanya tampilkan gen yang lagi di-repair (ada survivor near)
        local current = {}
        local currentParts = {}
        for _, part in ipairs(getGenerators()) do
            local active = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Team and p.Team.Name == CFG.teamSurvivor then
                    local c = p.Character
                    local r = c and c:FindFirstChild("HumanoidRootPart")
                    if r and (r.Position - part.Position).Magnitude <= CFG.genActivityRange then
                        active = true
                        break
                    end
                end
            end
            if active then
                local dist = getDistance(part.Position)
                local label = "ACTIVE GEN\n[" .. dist .. "m]"
                if CFG.genProgressShow then
                    local pct = _H.getGenProgress and _H.getGenProgress(part)
                    if pct then label = label .. " · " .. math.floor(pct + 0.5) .. "%" end
                end
                showESP(part, Color3.fromRGB(255, 80, 80), label)
                currentParts[part] = true
                local model = part:FindFirstAncestorWhichIsA("Model")
                if model then
                    showHL(model, Color3.fromRGB(255, 80, 80), Color3.fromRGB(220, 0, 0))
                    current[model] = true
                end
            end
        end
        for model in pairs(lastGenModels) do
            if not current[model] and model and model.Parent then hideHL(model) end
        end
        for part in pairs(lastGenParts) do
            if not currentParts[part] and part and part.Parent then hideESP(part) end
        end
        lastGenModels = current
        lastGenParts  = currentParts
    else
        -- ESP off / no role → hide semua
        for model in pairs(lastGenModels) do
            if model and model.Parent then hideHL(model) end
        end
        for part in pairs(lastGenParts) do
            if part and part.Parent then hideESP(part) end
        end
        if next(lastGenModels) ~= nil then lastGenModels = {} end
        if next(lastGenParts)  ~= nil then lastGenParts  = {} end
    end

    -- ── Pallet ESP (cyan label + chams) ─────────────────────
    if CFG.espEnabled and CFG.espPalletEnabled and _H.getPalletParts then
        local currentP, currentParts = {}, {}
        for _, part in ipairs(_H.getPalletParts()) do
            if part and part.Parent then
                local dist  = getDistance(part.Position)
                showESP(part, Color3.fromRGB(120, 220, 255), "Pallet\n[" .. dist .. "m]")
                currentParts[part] = true
                local model = part:FindFirstAncestorWhichIsA("Model")
                if model then
                    showHL(model, Color3.fromRGB(120, 200, 255), Color3.fromRGB(60, 160, 230))
                    currentP[model] = true
                end
            end
        end
        for m in pairs(lastPalletModels or {}) do
            if not currentP[m] and m and m.Parent then hideHL(m) end
        end
        for p in pairs(lastPalletParts or {}) do
            if not currentParts[p] and p and p.Parent then hideESP(p) end
        end
        lastPalletModels = currentP
        lastPalletParts  = currentParts
    else
        for m in pairs(lastPalletModels or {}) do
            if m and m.Parent then hideHL(m) end
        end
        for p in pairs(lastPalletParts or {}) do
            if p and p.Parent then hideESP(p) end
        end
        lastPalletModels = {}
        lastPalletParts  = {}
    end

    -- ── Speedhack ────────────────────────────────────────────
    -- Tidak di-set setiap frame; pakai signal-based di STEP 6.6 di bawah.
end)

-- ============================================================
--  STEP 6.4: SPEEDHACK (signal-based, hindari set per frame)
-- ============================================================
local speedConn = nil
local function applySpeed()
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    if CFG.speedEnabled then
        if hum.WalkSpeed ~= CFG.speedValue then
            hum.WalkSpeed = CFG.speedValue
        end
    end
end
-- Trigger applySpeed saat WalkSpeed di-override game/lain
local function bindSpeedSignal()
    if speedConn then speedConn:Disconnect() end
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    speedConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(applySpeed)
    applySpeed()
end
LP.CharacterAdded:Connect(function()
    task.wait(0.2)
    bindSpeedSignal()
end)
if LP.Character then bindSpeedSignal() end

-- ============================================================
--  STEP 6.45: GOD MODE (signal-based health reset)
--  Saat Humanoid.HealthChanged drops below max → instant set ke MaxHealth.
--  Plus: set MaxHealth ke huge supaya damage instant ga bisa kill.
-- ============================================================
local gmConn = nil
local function bindGodMode()
    if gmConn then gmConn:Disconnect() gmConn = nil end
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    gmConn = hum.HealthChanged:Connect(function(newHealth)
        if not CFG.godModeEnabled then return end
        if newHealth < hum.MaxHealth then
            pcall(function() hum.Health = hum.MaxHealth end)
        end
    end)
    -- Set MaxHealth tinggi saat aktif (game biasanya tidak override property ini)
    if CFG.godModeEnabled then
        pcall(function() hum.MaxHealth = 1e9; hum.Health = hum.MaxHealth end)
    end
end
LP.CharacterAdded:Connect(function()
    task.wait(0.2)
    bindGodMode()
end)
if LP.Character then bindGodMode() end

-- Polling backup tiap 0.05s — jaga-jaga signal kebypass
task.spawn(function()
    while true do
        task.wait(0.05)
        if not CFG.godModeEnabled then continue end
        local c = LP.Character
        if not c then continue end
        local hum = c:FindFirstChild("Humanoid")
        if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
            pcall(function() hum.Health = hum.MaxHealth end)
        end
    end
end)

-- ============================================================
--  STEP 6.5: FLY / NOCLIP / INF JUMP
-- ============================================================
local flyBV, flyBG  -- BodyVelocity & BodyGyro untuk fly

local function attachFlyObjects()
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    if not flyBV or not flyBV.Parent then
        flyBV = Instance.new("BodyVelocity")
        flyBV.Name     = "_VD_FlyBV"
        flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        flyBV.Velocity = Vector3.zero
        flyBV.Parent   = hrp
    end
    if not flyBG or not flyBG.Parent then
        flyBG = Instance.new("BodyGyro")
        flyBG.Name      = "_VD_FlyBG"
        flyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        flyBG.P         = 9e4
        flyBG.D         = 1000
        flyBG.CFrame    = hrp.CFrame
        flyBG.Parent    = hrp
    end
end

local function removeFlyObjects()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
end

-- Noclip parts cache (avoid GetDescendants every frame)
local noclipParts = {}
local noclipConn  = nil

local function rebuildNoclipCache()
    noclipParts = {}
    local char = LP.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(noclipParts, part)
        end
    end
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then
            table.insert(noclipParts, d)
        end
    end)
end

LP.CharacterAdded:Connect(function()
    task.wait(0.2)
    rebuildNoclipCache()
end)
if LP.Character then rebuildNoclipCache() end

-- Loop Fly + Noclip
RunService.Stepped:Connect(function()
    local char = LP.Character
    if not char then return end

    -- Noclip (gunakan cache, bukan GetDescendants)
    if CFG.noclipEnabled then
        for i = #noclipParts, 1, -1 do
            local part = noclipParts[i]
            if part and part.Parent then
                if part.CanCollide then part.CanCollide = false end
            else
                table.remove(noclipParts, i)
            end
        end
    end

    -- Fly
    if CFG.flyEnabled and flyBV and flyBG then
        local cam = workspace.CurrentCamera
        local dir = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W)           then dir += cam.CFrame.LookVector  end
        if UIS:IsKeyDown(Enum.KeyCode.S)           then dir -= cam.CFrame.LookVector  end
        if UIS:IsKeyDown(Enum.KeyCode.A)           then dir -= cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D)           then dir += cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.new(0, 1, 0)   end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0)   end

        local speed = CFG.speedValue * CFG.flySpeedMul
        flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * speed or Vector3.zero
        flyBG.CFrame   = cam.CFrame
    end
end)

-- Re-attach fly objects saat respawn
LP.CharacterAdded:Connect(function()
    task.wait(0.3)
    if CFG.flyEnabled then attachFlyObjects() end
end)

-- ── Fullbright ──────────────────────────────────────────────
local Lighting = game:GetService("Lighting")
local fbBackup = nil  -- snapshot setting Lighting sebelum fullbright
local fbDisabledFX = {}  -- list FX yg di-disable supaya bisa di-restore

local fbAtmosphereBackup = {}  -- simpan nilai Density/Haze/Glare per Atmosphere

local function applyFullbright()
    -- Simpan dulu nilai original Lighting
    fbBackup = {
        Brightness     = Lighting.Brightness,
        ClockTime      = Lighting.ClockTime,
        FogEnd         = Lighting.FogEnd,
        FogStart       = Lighting.FogStart,
        GlobalShadows  = Lighting.GlobalShadows,
        Ambient        = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
    }
    Lighting.Brightness     = 2
    Lighting.ClockTime      = 14
    Lighting.FogEnd         = 1e6
    Lighting.FogStart       = 1e6
    Lighting.GlobalShadows  = false
    Lighting.Ambient        = Color3.fromRGB(178, 178, 178)
    Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)

    -- Disable PostEffect (Bloom, ColorCorrection, dll punya Enabled)
    fbDisabledFX = {}
    fbAtmosphereBackup = {}
    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("PostEffect") then
            if fx.Enabled then
                fx.Enabled = false
                table.insert(fbDisabledFX, fx)
            end
        elseif fx:IsA("Atmosphere") then
            -- Atmosphere ga punya Enabled — set Density/Haze/Glare ke 0
            table.insert(fbAtmosphereBackup, {
                obj     = fx,
                Density = fx.Density,
                Haze    = fx.Haze,
                Glare   = fx.Glare,
            })
            fx.Density = 0
            fx.Haze    = 0
            fx.Glare   = 0
        end
    end
end

local function restoreFullbright()
    if not fbBackup then return end
    for k, v in pairs(fbBackup) do
        Lighting[k] = v
    end
    for _, fx in ipairs(fbDisabledFX) do
        if fx and fx.Parent then fx.Enabled = true end
    end
    for _, atm in ipairs(fbAtmosphereBackup) do
        if atm.obj and atm.obj.Parent then
            atm.obj.Density = atm.Density
            atm.obj.Haze    = atm.Haze
            atm.obj.Glare   = atm.Glare
        end
    end
    fbBackup = nil
    fbDisabledFX = {}
    fbAtmosphereBackup = {}
end

-- ── Auto Repair ─────────────────────────────────────────────
-- Pas deket generator, otomatis hold left mouse button.
-- Skill check tetap harus di-pencet manual (atau missed, tergantung pilihan lu).
local VIM = game:GetService("VirtualInputManager")
local arHolding = false  -- state: lagi nge-hold mouse atau ga

local function arGetNearestGen()
    local char = LP.Character
    if not char then return nil, math.huge end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, math.huge end

    local nearest, dist = nil, math.huge
    for _, gen in ipairs(getGenerators()) do
        if gen and gen.Parent then
            local d = (gen.Position - hrp.Position).Magnitude
            if d < dist then
                nearest = gen
                dist    = d
            end
        end
    end
    return nearest, dist
end

-- Pakai mouse1press/mouse1release (executor global) — paling reliable.
-- Fallback ke VIM SendMouseButtonEvent kalau executor ga expose global ini.
local _mouse1press   = rawget(getfenv(), "mouse1press")   or mouse1press
local _mouse1release = rawget(getfenv(), "mouse1release") or mouse1release

local function rawPress()
    if _mouse1press then
        pcall(_mouse1press)
    else
        pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1) end)
    end
end

local function rawRelease()
    if _mouse1release then
        pcall(_mouse1release)
    else
        pcall(function() VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1) end)
    end
end

-- Setiap arPress selalu kirim release dulu → wait → press.
-- Ini replicate behavior toggle OFF→ON yang user laporkan work.
-- Tanpa release dulu, game tidak detect DOWN edge (mouse state stuck).
local function arPress()
    if arHolding then return end
    rawRelease()        -- clear stuck state
    task.wait(0.06)     -- gap supaya game detect release dulu
    arHolding = true
    rawPress()
end

local function arRelease()
    if not arHolding then return end
    arHolding = false
    rawRelease()
end

-- Track generator yang lagi di-press supaya bisa re-arm saat pindah gen
local arCurrentGen = nil

-- Cek jarak ke gen tertentu (untuk hysteresis: kalau gen lama masih dalam
-- range, jangan switch walau ada gen lain yang slightly lebih dekat)
local function arDistToGen(gen)
    if not gen or not gen.Parent then return math.huge end
    local char = LP.Character
    if not char then return math.huge end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return math.huge end
    return (gen.Position - hrp.Position).Magnitude
end

-- Detect WASD held → user mau gerak → batalin auto repair.
-- Space TIDAK termasuk supaya skill check (manual space) ga ganggu auto repair.
local function arIsMoving()
    return UIS:IsKeyDown(Enum.KeyCode.W)
        or UIS:IsKeyDown(Enum.KeyCode.A)
        or UIS:IsKeyDown(Enum.KeyCode.S)
        or UIS:IsKeyDown(Enum.KeyCode.D)
end

task.spawn(function()
    while true do
        task.wait(CFG.autoRepairTick)

        if not CFG.autoRepairEnabled then
            if arHolding then arRelease() end
            arCurrentGen = nil
            continue
        end

        -- User pencet WASD → release, skip. Begitu user diam lagi & masih
        -- in range gen, loop berikutnya bakal re-engage otomatis.
        if arIsMoving() then
            if arHolding then arRelease() end
            arCurrentGen = nil
            continue
        end

        -- Hysteresis: kalau lagi hold gen X dan masih dalam range, stick ke X
        -- (jangan flip ke gen lain yang slightly lebih dekat karena player gerak)
        if arCurrentGen and arHolding then
            local d = arDistToGen(arCurrentGen)
            if d <= CFG.autoRepairRange then
                -- Masih nemplok di gen yang sama → biarin hold, no-op
                continue
            end
            -- Gen lama out of range → release, lanjut cari gen baru
            arRelease()
            arCurrentGen = nil
        end

        -- Cari gen terdekat
        local gen, dist = arGetNearestGen()

        if not gen or dist > CFG.autoRepairRange then
            -- Tidak ada gen dalam range
            if arHolding then arRelease() end
            arCurrentGen = nil
        else
            -- Masuk range gen baru → press sekali saja (no re-arm cycle)
            if not arHolding then
                arPress()
            end
            arCurrentGen = gen
        end
    end
end)

-- Safety: release mouse pas respawn / character ganti
LP.CharacterAdded:Connect(function()
    arHolding    = false
    arCurrentGen = nil
end)

-- ── No Skill Check (defensive re-implementation 2026-06-10) ────────
-- Probe finding: PlayerGui.SkillCheckPromptGui.Check Frame Visible→true saat check.
-- Defensive vs sebelumnya:
--   • Inline do-block, no task.spawn yang yield di init
--   • FindFirstChild + DescendantAdded fallback (no chained WaitForChild)
--   • pcall wrap semua signal/API call
do
    local firingForCheck = false
    local attachedFrame  = nil

    local function attachListener(frame)
        if attachedFrame == frame then return end
        attachedFrame = frame
        local ok = pcall(function()
            frame:GetPropertyChangedSignal("Visible"):Connect(function()
                if not frame.Visible then
                    firingForCheck = false
                    return
                end
                if not CFG.noSkillCheckEnabled then return end
                if getRole() ~= "Survivor" then return end
                if firingForCheck then return end
                firingForCheck = true

                -- INSTANT fire — no delay. Suppress jump physics biar ga lift off gen.
                local char = LP.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                local savedJP, savedJH
                if hum then
                    savedJP = hum.JumpPower
                    savedJH = hum.JumpHeight
                    pcall(function() hum.JumpPower = 0 end)
                    pcall(function() hum.JumpHeight = 0 end)
                end
                pcall(function()
                    VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
                    task.wait(0.03)
                    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                end)
                if hum then
                    task.wait(0.08)
                    pcall(function() hum.JumpPower  = savedJP end)
                    pcall(function() hum.JumpHeight = savedJH end)
                end
            end)
        end)
        if not ok then attachedFrame = nil end  -- biar bisa retry next discovery
    end

    local function tryFind()
        local PG = LP:FindFirstChild("PlayerGui")
        if not PG then return end
        local promptGui = PG:FindFirstChild("SkillCheckPromptGui")
        if not promptGui then return end
        local frame = promptGui:FindFirstChild("Check")
        if frame then attachListener(frame) end
    end

    -- Coba immediate (kalau GUI udah ada di lobby)
    pcall(tryFind)

    -- Fallback: late-spawn watcher via PlayerGui.DescendantAdded
    pcall(function()
        local PG = LP:FindFirstChild("PlayerGui")
        if not PG then return end
        PG.DescendantAdded:Connect(function(d)
            if d.Name == "Check" and d.Parent and d.Parent.Name == "SkillCheckPromptGui" then
                attachListener(d)
            end
        end)
    end)
end

-- ── Auto Escape ────────────────────────────────────────────
-- Pas Survivor deket gen, kalau killer mendekat (< escapeDistance studs)
-- → TP ke generator AMAN: terjauh dari killer, bukan gen yang lagi kita repair,
--   dan minimal SAFE_DIST dari posisi killer.
local lastEscape = 0

local function isKillerPlayer(p)
    if not p.Team then return false end
    local tn = p.Team.Name
    return tn == CFG.teamKiller or tn:lower():find("killer")
end

local function findNearestKiller(myPos)
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if not isKillerPlayer(p) then continue end
        local c = p.Character
        if not c then continue end
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local d = (hrp.Position - myPos).Magnitude
        if d < bestD then bestD = d; best = p end
    end
    return best, bestD
end

-- Cari generator paling aman: terjauh dari killer + bukan gen yg lagi kita repair
local function findSafestGenerator(killerPos, currentGen)
    local best, bestD = nil, -1
    for _, part in ipairs(getGenerators()) do
        if part ~= currentGen then
            local d = (part.Position - killerPos).Magnitude
            if d > bestD then bestD = d; best = part end
        end
    end
    -- Fallback: kalau cuma ada 1 gen di map, terpaksa pakai itu
    if not best then
        for _, part in ipairs(getGenerators()) do
            local d = (part.Position - killerPos).Magnitude
            if d > bestD then bestD = d; best = part end
        end
    end
    return best, bestD
end

task.spawn(function()
    while true do
        task.wait(CFG.escapeTick)
        if not CFG.autoEscapeEnabled then continue end
        -- NO autoRepair requirement — proxy "lagi repair" = deket generator (manual atau auto)
        if getRole() ~= "Survivor" then continue end

        local now = tick()
        if now - lastEscape < CFG.escapeCooldown then continue end

        local char = LP.Character
        if not char then continue end
        local myRoot = char:FindFirstChild("HumanoidRootPart")
        if not myRoot then continue end

        -- Cek lagi deket gen (proxy aktif repair) + simpan gen yang lagi direpair
        local currentGen, genDist = arGetNearestGen()
        if genDist > CFG.autoRepairRange then continue end

        -- Cari killer terdekat
        local killer, kDist = findNearestKiller(myRoot.Position)
        if not killer or kDist > CFG.escapeDistance then continue end

        local killerPos = killer.Character.HumanoidRootPart.Position

        -- TP ke generator paling aman dari killer (skip gen yang sekarang direpair)
        local gen, safeDist = findSafestGenerator(killerPos, currentGen)
        if gen and safeDist > CFG.escapeDistance then
            -- Release mouse dulu biar ga nge-interact pas spawn
            arRelease()
            myRoot.CFrame = CFrame.new(gen.Position + Vector3.new(0, 5, 0))
            lastEscape = now
        end
    end
end)

-- ============================================================
--  STEP 6.7 - 6.11: SURVIVOR HELPERS + AUTO LOOPS
--  Wrapped in do...end supaya local-nya dilepas setelah block selesai
--  (hindari "Out of local registers, exceeded limit 200" error).
--  Forward-declared di file scope: getGenProgress, isPlayerHooked, isPlayerDowned.
-- ============================================================
do

-- ── STEP 6.7: GENERATOR PROGRESS DETECTION ─────────────────
local GEN_PROGRESS_NAMES = {
    "Progress","Repair","RepairProgress","Percent","Percentage",
    "Charge","Completion","Value"
}

local function normalizeProgress(v)
    if type(v) ~= "number" then return nil end
    if v < 0 then return 0 end
    if v <= 1 then return v * 100 end       -- 0-1 → 0-100
    if v <= 100 then return v end            -- already 0-100
    return math.min(100, v)                  -- 0-1000?
end

function _H.getGenProgress(genPart)
    if not genPart then return nil end
    local model = genPart:FindFirstAncestorWhichIsA("Model")
    if not model then return nil end

    -- 1. Coba Attribute
    for _, name in ipairs(GEN_PROGRESS_NAMES) do
        local v = model:GetAttribute(name)
        local n = normalizeProgress(v)
        if n then return n end
    end

    -- 2. Coba child ValueObject (direct)
    for _, name in ipairs(GEN_PROGRESS_NAMES) do
        local obj = model:FindFirstChild(name)
        if obj and (obj:IsA("NumberValue") or obj:IsA("IntValue")) then
            local n = normalizeProgress(obj.Value)
            if n then return n end
        end
    end

    -- 3. Scan descendant (max 50 untuk safety perf) — nama mengandung progress/repair
    local count = 0
    for _, d in ipairs(model:GetDescendants()) do
        count = count + 1
        if count > 50 then break end
        if d:IsA("NumberValue") or d:IsA("IntValue") then
            local ln = d.Name:lower()
            if ln:find("progress") or ln:find("repair") or ln:find("percent") then
                local n = normalizeProgress(d.Value)
                if n then return n end
            end
        end
    end

    return nil
end

-- ============================================================
--  STEP 6.8: HOOK DETECTION + HOOKED PLAYER STATE
-- ============================================================
local HOOK_NAMES = { "Hook", "MeatHook", "ShackleHook" }

-- Cache semua hook di workspace (refresh 5 detik)
local hookCache    = {}
local hookLastScan = 0

local function getHooks()
    local now = tick()
    if now - hookLastScan < 5 and #hookCache > 0 then return hookCache end
    hookLastScan = now
    hookCache    = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            for _, name in ipairs(HOOK_NAMES) do
                if obj.Name == name or obj.Name:lower():find("hook") then
                    local part = obj:IsA("BasePart") and obj
                        or (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart"))
                    if part then
                        table.insert(hookCache, part)
                    end
                    break
                end
            end
        end
    end
    return hookCache
end

-- Detect apakah player p sedang ke-hook
-- Multi-strategy: cek attribute, cek state, cek distance ke hook + animasi
-- Pallet scanner shared (dipakai ESP loop + killer features)
local _palletCache, _palletLastScan = {}, 0
function _H.getPalletParts()
    local now = tick()
    if now - _palletLastScan < 5 and #_palletCache > 0 then return _palletCache end
    _palletLastScan = now
    _palletCache    = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            -- STRICT match: exact "Pallet" / "Palletwrong" (VD canonical names),
            -- BUKAN substring (sebelumnya catch truck/vehicle dengan "Pallet" anywhere in name).
            local n = obj.Name:lower()
            if n == "pallet" or n == "palletwrong" then
                -- VALIDATE struktur VD: must have Primary1/Primary2/PrimaryPartPallet child.
                -- Tanpa validation, model "Pallet" generic dari decoration map ke-include juga.
                local part = obj:FindFirstChild("PrimaryPartPallet")
                          or obj:FindFirstChild("Primary1")
                          or obj:FindFirstChild("Primary2")
                          or obj.PrimaryPart
                if part and part:IsA("BasePart") then
                    table.insert(_palletCache, part)
                end
            end
        end
    end
    return _palletCache
end

function _H.isPlayerHooked(p)
    if not p then return false end
    local c = p.Character
    if not c then return false end

    -- 1. Attribute pada character/humanoid
    for _, attrName in ipairs({"Hooked","IsHooked","OnHook","Hang","Hanging"}) do
        if c:GetAttribute(attrName) == true then return true end
    end
    local hum = c:FindFirstChild("Humanoid")
    if hum then
        for _, attrName in ipairs({"Hooked","IsHooked","OnHook"}) do
            if hum:GetAttribute(attrName) == true then return true end
        end
        -- 2. Humanoid state (PlatformStanding sering dipakai untuk hook/down)
        local ok, state = pcall(function() return hum:GetState() end)
        if ok and state == Enum.HumanoidStateType.PlatformStanding then
            -- PlatformStanding bisa jadi hook ATAU knockdown. Bedain pakai
            -- proximity ke hook part.
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then
                for _, h in ipairs(getHooks()) do
                    if h and h.Parent and (h.Position - hrp.Position).Magnitude < 4 then
                        return true
                    end
                end
            end
        end
    end

    -- 3. ValueObject child di character
    for _, name in ipairs({"Hooked","IsHooked","OnHook"}) do
        local v = c:FindFirstChild(name)
        if v and v:IsA("BoolValue") and v.Value then return true end
    end

    return false
end

-- Detect downed (knockdown, masih bisa diselamatkan tapi ga bisa repair)
function _H.isPlayerDowned(p)
    if not p then return false end
    local c = p.Character
    if not c then return false end
    local hum = c:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    -- 1. Attribute (game-specific)
    for _, attrName in ipairs({"Downed","KnockedDown","Crawling","IsDowned","Dying","Down","Knocked"}) do
        if c:GetAttribute(attrName) == true then return true end
        if hum:GetAttribute(attrName) == true then return true end
    end

    -- 2. Humanoid boolean properties (PlatformStand & Sit sering dipake game custom)
    if hum.PlatformStand == true then
        if not _H.isPlayerHooked(p) then return true end
    end
    if hum.Sit == true then return true end

    -- 3. State enum
    local ok, state = pcall(function() return hum:GetState() end)
    if ok then
        if state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.Ragdoll then
            return true
        end
        if state == Enum.HumanoidStateType.PlatformStanding then
            if not _H.isPlayerHooked(p) then return true end
        end
    end

    -- 4. WalkSpeed sangat rendah (crawl) — strong indicator
    if hum.WalkSpeed > 0 and hum.WalkSpeed < 5 then return true end

    -- 5. Animation track names (paling reliable kalau game pake animasi standar)
    local okA, tracks = pcall(function() return hum:GetPlayingAnimationTracks() end)
    if okA and tracks then
        for _, track in ipairs(tracks) do
            local anim = track.Animation
            if anim then
                local n = anim.Name:lower()
                if n:find("crawl") or n:find("down") or n:find("dying")
                or n:find("knock") or n:find("inject") or n:find("injure") then
                    return true
                end
            end
        end
    end

    -- 6. ValueObject child di character
    for _, name in ipairs({"Downed","IsDowned","Crawling","Knocked"}) do
        local v = c:FindFirstChild(name)
        if v and v:IsA("BoolValue") and v.Value then return true end
    end

    return false
end

-- Detect injured (HP < max, masih bisa jalan)
local function isPlayerInjured(p)
    if not p then return false end
    local c = p.Character
    if not c then return false end
    local hum = c:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return hum.Health < hum.MaxHealth * (CFG.healSelfHpThreshold / 100)
end

local function getCharRoot(p)
    local c = p and p.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
--  STEP 6.9: AUTO RESCUE (TP ke teammate hooked + hold mouse)
-- ============================================================
local lastRescue          = 0
local PER_TARGET_COOLDOWN = 15  -- detik, jangan rescue teammate yg sama dlm window ini
local rescuedAt           = {}  -- [UserId] = tick() saat terakhir di-rescue

task.spawn(function()
    while true do
        task.wait(CFG.rescueTick)
        if not CFG.autoRescueEnabled then continue end
        if getRole() ~= "Survivor" then continue end

        local now = tick()
        if now - lastRescue < CFG.rescueCooldown then continue end

        local myRoot = getCharRoot(LP)
        if not myRoot then continue end

        -- Cari teammate hooked terdekat — skip yg baru aja kita rescue
        local target, targetRoot, targetDist = nil, nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then continue end
            if isKillerPlayer(p) then continue end
            if not _H.isPlayerHooked(p) then continue end
            -- Per-target cooldown: skip kalau baru aja di-rescue
            -- (mencegah false-positive isPlayerHooked saat animasi unhook)
            local last = rescuedAt[p.UserId]
            if last and (now - last) < PER_TARGET_COOLDOWN then continue end
            local r = getCharRoot(p)
            if r then
                local d = (r.Position - myRoot.Position).Magnitude
                if d < targetDist then
                    target, targetRoot, targetDist = p, r, d
                end
            end
        end

        if not target then continue end

        -- Pastikan auto repair release dulu (jangan tahan mouse pas TP)
        if arHolding then arRelease() end

        -- TP ke depan teammate (offset sedikit biar ga overlap)
        myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)

        -- Hold mouse buat trigger unhook interaction
        task.wait(0.2)
        rawRelease(); task.wait(0.05); rawPress()
        task.wait(1.2)  -- durasi unhook biasanya ~1s
        rawRelease()

        rescuedAt[target.UserId] = tick()
        lastRescue = now
    end
end)

-- ============================================================
--  STEP 6.10: AUTO HEAL (self + team injured/downed)
-- ============================================================
local lastHeal = 0

task.spawn(function()
    while true do
        task.wait(CFG.healTick)
        if not CFG.autoHealEnabled then continue end
        if getRole() ~= "Survivor" then continue end

        -- Cooldown global supaya ga spam terus
        local now = tick()
        if now - lastHeal < 0.5 then continue end

        local myRoot = getCharRoot(LP)
        if not myRoot then continue end

        -- Priority: self injured > teammate downed > teammate injured
        local target, targetRoot = nil, nil

        -- 1. Self injured?
        if isPlayerInjured(LP) and not _H.isPlayerHooked(LP) then
            target, targetRoot = LP, myRoot
        end

        -- 2. Teammate downed/injured terdekat
        if not target then
            local bestDist = CFG.healRange * 4  -- mau TP juga, jadi range lebih luas
            for _, p in ipairs(Players:GetPlayers()) do
                if p == LP then continue end
                if isKillerPlayer(p) then continue end
                if _H.isPlayerHooked(p) then continue end  -- hook beda handler
                local needs = _H.isPlayerDowned(p) or isPlayerInjured(p)
                if not needs then continue end
                local r = getCharRoot(p)
                if r then
                    local d = (r.Position - myRoot.Position).Magnitude
                    if d < bestDist then
                        bestDist = d
                        target, targetRoot = p, r
                    end
                end
            end
        end

        if not target then continue end

        -- Kalau bukan diri sendiri & jauh, TP dekati
        if target ~= LP then
            local d = (targetRoot.Position - myRoot.Position).Magnitude
            if d > CFG.healRange then
                if arHolding then arRelease() end
                myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 2.5)
                task.wait(0.15)
            end
        end

        -- Hold mouse buat trigger heal interaction
        rawRelease(); task.wait(0.05); rawPress()
        task.wait(1.5)  -- durasi heal
        rawRelease()

        lastHeal = now
    end
end)

-- ============================================================
--  STEP 6.11: AUTO UNHOOK SELF — VD-specific
--  Dari probe log:
--    Hooked state: CHAR.Attribute "IsHooked" = true
--    Self-unhook trigger: LEFT-CLICK (mouse1) → anim 124706657239027
--    Per attempt: ~4% success, 1.2s anim, -20% HookedProgress penalty kalau gagal
--    Struggle: SPACE spam buat skill check / anti-camp charge
--  Strategy: spam LEFT-CLICK setiap 1.3s (cycle dengan anim) + SPACE spam continuous
-- ============================================================
local lastUnhookClick = 0
local UNHOOK_CLICK_INTERVAL = 1.3  -- ≥ anim length (1.2s)

local function isSelfHooked()
    local c = LP.Character
    if c and c:GetAttribute("IsHooked") == true then return true end
    -- Fallback ke detector lama
    return _H.isPlayerHooked and _H.isPlayerHooked(LP) or false
end

task.spawn(function()
    while true do
        task.wait(CFG.unhookTick)
        if not CFG.autoUnhookEnabled then continue end

        if isSelfHooked() then
            -- Spam SPACE buat skill check / struggle (cepet, tiap tick)
            pcall(function()
                VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
                task.wait(0.03)
                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
            -- Spam LEFT-CLICK self-unhook attempt (cycle 1.3s — match anim)
            local now = tick()
            if now - lastUnhookClick >= UNHOOK_CLICK_INTERVAL then
                lastUnhookClick = now
                local fired = false
                local _m1c = rawget(getfenv(), "mouse1click")
                local _m1p = rawget(getfenv(), "mouse1press")
                local _m1r = rawget(getfenv(), "mouse1release")
                if _m1c then
                    pcall(_m1c)
                    fired = true
                elseif _m1p and _m1r then
                    pcall(_m1p); task.wait(0.05); pcall(_m1r)
                    fired = true
                end
                if not fired then
                    pcall(function()
                        VIM:SendMouseButtonEvent(0, 0, 0, true,  game, 0)
                        task.wait(0.05)
                        VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    end)
                end
            end
        else
            -- Bukan ke-hook, pastikan release mouse kalau nyangkut
            if arHolding and not CFG.autoRepairEnabled then
                arRelease()
            end
        end
    end
end)

-- ============================================================
--  STEP 6.11b: AUTO PARRY — Survivor weapon parry
--  Trigger:  CHAR.Parry = false (cooldown clean)
--            + equip tool yang nama-nya match "Parry" (Parry Dagger)
--            + killer player dist ≤ parryRange (default 6m)
--            + tidak Knocked/Hooked/Carried
--  Aksi:     Fire RMB (mouse2) click → game set CHAR.Parry=true 800ms
-- ============================================================
local lastParryFire = 0

-- VD: Parrying Dagger di-attach sebagai Model (bukan Tool class) via Motor6D
-- ke character. Cari descendant apapun yg nama-nya match "parry".
local function hasParryWeapon()
    local c = LP.Character
    if c then
        for _, d in ipairs(c:GetDescendants()) do
            local n = d.Name:lower()
            if n:find("parry") then return true end  -- "Parry Dagger" or "Parrying Dagger"
        end
    end
    return false
end

-- Return (dist, killerHRP, myRoot) buat killer terdekat. dist=math.huge kalau ga ada.
local function nearestKillerInfo()
    local c = LP.Character
    local myRoot = c and c:FindFirstChild("HumanoidRootPart")
    if not myRoot then return math.huge, nil, nil end
    local bestD, bestHRP = math.huge, nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local team = p.Team and p.Team.Name or ""
        if not team:lower():find("killer") then continue end
        local pRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not pRoot then continue end
        local d = (myRoot.Position - pRoot.Position).Magnitude
        if d < bestD then bestD = d; bestHRP = pRoot end
    end
    return bestD, bestHRP, myRoot
end
local function nearestKillerDist()
    local d = nearestKillerInfo()
    return d
end

-- ── Killer animation tracker ────────────────────────────────
-- Fire parry HANYA saat killer baru mulai play animation (= attack swing),
-- bukan cuma karena deket. Window parry game 0.8s, jadi timing harus tepat.
local killerLastAnimTime = 0
local killerDistHistory  = {}  -- legacy (unused, kept buat scope safety)
-- Filter ANIM PRIORITY: walk/idle anims fire AnimationPlayed terus-menerus.
-- Cuma Action / Action4 priority = special action (swing, attack, ability) yang relevan buat parry trigger.
local function attachKillerAnimWatcher(p)
    if p == LP then return end
    local function attach(c)
        local hum = c:WaitForChild("Humanoid", 5)
        if not hum then return end
        hum.AnimationPlayed:Connect(function(track)
            local team = p.Team and p.Team.Name or ""
            if not team:lower():find("killer") then return end
            local anim = track and track.Animation
            if not anim then return end
            -- UNIVERSAL LMB DETECTOR — bypass whitelist (anim ID beda per killer character,
            -- gak realistic probe semua). Pakai signature universal: Action priority + CLOSE range.
            --   - LMB hit semua killer = fire Action priority anim DI close range (~3-5 studs)
            --   - Ranged special (Veil spear) = anim fires at FAR range → filtered out
            --   - Movement/chase anim = Movement/Core priority → filtered out
            --   - Long ability anims (>5s) = filtered out
            local prio = track.Priority
            local isActionPrio = (prio == Enum.AnimationPriority.Action
                              or prio == Enum.AnimationPriority.Action2
                              or prio == Enum.AnimationPriority.Action3
                              or prio == Enum.AnimationPriority.Action4)
            if not isActionPrio then return end
            local myChar = LP.Character
            local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local pRoot = c and c:FindFirstChild("HumanoidRootPart")
            if not (myHRP and pRoot) then return end
            local d = (myHRP.Position - pRoot.Position).Magnitude
            if d > 5 then return end  -- TIGHT: only count anims at CLOSE swing range
            local len = track.Length or 0
            if len > 5 then return end  -- drop very long anims (likely special ability)
            killerLastAnimTime = tick()
        end)
    end
    if p.Character then attach(p.Character) end
    p.CharacterAdded:Connect(function(c) task.wait(0.3); attach(c) end)
end
for _, p in ipairs(Players:GetPlayers()) do attachKillerAnimWatcher(p) end
Players.PlayerAdded:Connect(attachKillerAnimWatcher)

local function dbgParry(...)
    if CFG.parryDebug then print("[PARRY]", ...) end
end

-- One-time diagnostic dump (run sekali saat first iteration) — confirm executor function availability
task.spawn(function()
    task.wait(2)
    if CFG.parryDebug then
        print("[PARRY-DIAG] mouse2click=", tostring(rawget(getfenv(), "mouse2click")),
              "mouse2press=", tostring(rawget(getfenv(), "mouse2press")),
              "VIM=", tostring(VIM))
    end
end)

task.spawn(function()
    local lastLogReason = ""
    local function logReasonOnce(reason)
        if reason ~= lastLogReason then
            dbgParry("skip:", reason)
            lastLogReason = reason
        end
    end
    while true do
        task.wait(CFG.parryTick)
        if not CFG.autoParryEnabled then continue end

        local c = LP.Character
        if not c then logReasonOnce("no character") continue end
        if c:GetAttribute("Knocked")   == true then logReasonOnce("knocked")  continue end
        if c:GetAttribute("IsHooked")  == true then logReasonOnce("hooked")   continue end
        if c:GetAttribute("IsCarried") == true then logReasonOnce("carried")  continue end
        if c:GetAttribute("Parry")     == true then logReasonOnce("parry-window-active") continue end
        local now = tick()
        if now - lastParryFire < CFG.parryCooldown then continue end  -- silent skip, normal
        if not hasParryWeapon() then logReasonOnce("no-parry-weapon-equipped") continue end
        local kd, killerHRP, myRoot = nearestKillerInfo()
        if kd > CFG.parryRange or not killerHRP or not myRoot then
            if kd < 15 then dbgParry("killer dist=" .. string.format("%.1f", kd) .. " (range=" .. CFG.parryRange .. ")") end
            continue
        end
        -- 2-TIER DETECTION:
        --   TIER 1 STOP-DETECT: killer velocity < 3 studs/s (berhenti buat swing)
        --                       + kd ≤ 5.5 (in swing reach) + facing > 0.7 (hadap directly)
        --                       → fire pre-emptive saat killer STOP. Killer stand-and-hit selalu
        --                       berhenti sebelum swing — catch the STOP, parry window terbuka sebelum impact.
        --   TIER 2 ANIM: AnimationPlayed fresh + facing > 0.5 (whitelist/fallback dari watcher)
        --                → fallback buat fast attack tanpa stop.
        local nowT = tick()
        local animFresh = (nowT - killerLastAnimTime) < CFG.parryAnimWindow
        -- Facing dot
        local toMe = (myRoot.Position - killerHRP.Position)
        local toMeFlat = Vector3.new(toMe.X, 0, toMe.Z)
        local mag = toMeFlat.Magnitude
        local facingDot = 0
        if mag > 0.1 then
            local killerLook = killerHRP.CFrame.LookVector
            local lookFlat = Vector3.new(killerLook.X, 0, killerLook.Z).Unit
            facingDot = lookFlat:Dot(toMeFlat / mag)
        end
        -- Killer velocity (flat, abaikan jatuh/lompat)
        local kvel = killerHRP.AssemblyLinearVelocity
        local kspeedFlat = math.sqrt(kvel.X * kvel.X + kvel.Z * kvel.Z)
        -- REACT-ONLY (universal): anim watcher udah filter Action priority + kd ≤ 5 at anim moment.
        -- Fire SEKALI per swing event, bukan spam. Timing precise, no false positive saat camp/chase.
        local animDetect = animFresh and (facingDot > CFG.parryFacingDot)
        local fireMode = animDetect and "REACT" or nil
        if not fireMode then
            dbgParry("dist=" .. string.format("%.1f", kd)
                .. " spd=" .. string.format("%.1f", kspeedFlat)
                .. " anim=" .. tostring(animFresh)
                .. " face=" .. string.format("%.2f", facingDot))
            continue
        end
        lastLogReason = ""

        -- FIRE RMB CLICK (instant, bukan hold — game treat parry sbg single-shot reactive action)
        -- Previous session evidence: click DID trigger parry. Hold malah breakin input.
        lastParryFire = now
        dbgParry("FIRE [" .. fireMode .. "] → kd=" .. string.format("%.1f", kd)
            .. " spd=" .. string.format("%.1f", kspeedFlat)
            .. " face=" .. string.format("%.2f", facingDot))
        local _m2c   = rawget(getfenv(), "mouse2click")
        local _m2p   = rawget(getfenv(), "mouse2press")
        local _m2r   = rawget(getfenv(), "mouse2release")
        local fired = false
        -- Method 1: Solara mouse2click (atomic press-release, paling reliable)
        if _m2c then
            pcall(_m2c)
            fired = true
        elseif _m2p and _m2r then
            -- Method 1b: press + tiny gap + release biar register sebagai click bukan hold
            pcall(_m2p)
            task.wait(0.03)
            pcall(_m2r)
            fired = true
        end
        -- Method 2: VirtualInputManager fallback
        if not fired then
            pcall(function()
                VIM:SendMouseButtonEvent(0, 0, 1, true,  game, 0)
                task.wait(0.03)
                VIM:SendMouseButtonEvent(0, 0, 1, false, game, 0)
            end)
        end
    end
end)

end  -- ◀ END Survivor helpers + auto loops do-block

-- ============================================================
--  STEP 6.12 - 6.18: KILLER FEATURES (wrapped do-block)
--  Auto-Attack, Auto-Pickup, Auto-Hook, Anti-stuns, Auto-Break
-- ============================================================
do

-- ── Helpers ────────────────────────────────────────────────
local function getCharRoot(p)
    local c = p and p.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- SPACE key helper (untuk pickup, hook, break pallet di Violence District)
-- Multi-backend: keypress/keyrelease (executor global) → VIM:SendKeyEvent
local _keypress   = rawget(getfenv(), "keypress")   or keypress
local _keyrelease = rawget(getfenv(), "keyrelease") or keyrelease

local function spaceDown()
    if _keypress then
        pcall(_keypress, 0x20)  -- VK_SPACE
    end
    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game) end)
end

local function spaceUp()
    if _keyrelease then
        pcall(_keyrelease, 0x20)
    end
    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
end

-- Hold space untuk durasi tertentu (untuk interaksi hold-to-action)
local function holdSpace(duration)
    spaceUp(); task.wait(0.04)
    spaceDown()
    task.wait(duration or 1.0)
    spaceUp()
end

local function isFacing(myRoot, targetPos, threshold)
    if not myRoot then return false end
    local toTarget = targetPos - myRoot.Position
    if toTarget.Magnitude < 0.001 then return true end
    local myDir = myRoot.CFrame.LookVector
    return myDir:Dot(toTarget.Unit) >= (threshold or 0.45)
end

local function isKillerPlayer(p)
    if not p.Team then return false end
    local tn = p.Team.Name
    return tn == CFG.teamKiller or tn:lower():find("killer")
end

-- Pallet cache (5s refresh) — VD structure:
--   Model "Pallet"/"Palletwrong" children:
--     HumanoidRootPart (anchored, vertical reference — never tilts → distance ref)
--     Primary1/Primary2/PrimaryPartPallet MeshPart (un-anchored → tilt saat dropped)
-- Strategy: filter leaf model (yang punya HumanoidRootPart), simpan ref part + tilt part
local palletCache, palletLastScan = {}, 0
local function getPallets()
    local now = tick()
    if now - palletLastScan < 5 and #palletCache > 0 then return palletCache end
    palletLastScan = now
    palletCache    = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find("pallet") then
            local hrp = obj:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then  -- leaf only (skip parent container)
                local tilt = obj:FindFirstChild("Primary1")
                          or obj:FindFirstChild("Primary2")
                          or obj:FindFirstChild("PrimaryPartPallet")
                table.insert(palletCache, {model=obj, part=hrp, tilt=tilt})
            end
        end
    end
    return palletCache
end

-- Detect dropped pallet — VD tidak pakai attribute apa pun.
-- Standing pallet: Primary MeshPart UpVector.Y ≈ 1 (tegak)
-- Dropped pallet : Primary MeshPart UpVector.Y < 0.5 (tertidur horizontal)
local function isPalletDropped(palletData)
    local m = palletData.model
    if not m or not m.Parent then return false end
    -- Attribute fallback (future-proof kalau game update)
    for _, a in ipairs({"Dropped","IsDropped","Down","Broken"}) do
        if m:GetAttribute(a) == true then return true end
    end
    -- Tilt check pakai Primary MeshPart (HumanoidRootPart anchored → skip)
    if palletData.tilt and palletData.tilt:IsA("BasePart") then
        if palletData.tilt.CFrame.UpVector.Y < 0.5 then return true end
    end
    return false
end

-- Detect kalau LP lagi nge-carry survivor (untuk Auto-Hook)
local function isCarrying()
    local c = LP.Character
    if not c then return false end
    for _, a in ipairs({"Carrying","IsCarrying","HoldingSurvivor"}) do
        if c:GetAttribute(a) == true then return true end
    end
    local hum = c:FindFirstChild("Humanoid")
    if hum then
        for _, a in ipairs({"Carrying","IsCarrying"}) do
            if hum:GetAttribute(a) == true then return true end
        end
    end
    -- Fallback: cek apakah ada survivor character ke-attach ke kita
    -- (cek Motor6D ke survivor) — skip dulu, heuristic Attribute aja
    return false
end

-- ── STEP 6.12: AUTO-ATTACK (M1) ─────────────────────────────
local lastAttack = 0
task.spawn(function()
    while true do
        task.wait(CFG.autoAttackTick)
        if not CFG.autoAttackEnabled then continue end
        if getRole() ~= "Killer" then continue end

        local now = tick()
        if now - lastAttack < 0.5 then continue end  -- attack cooldown

        local myRoot = getCharRoot(LP)
        if not myRoot then continue end

        -- Cari survivor terdekat dalam range + facing (skip downed — buang waktu)
        local target, targetDist = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then continue end
            if isKillerPlayer(p) then continue end
            local r = getCharRoot(p)
            if not r then continue end
            local c = p.Character
            local hum = c and c:FindFirstChild("Humanoid")
            if not hum or hum.Health <= 0 then continue end
            -- Skip yang sudah down — fokus chase yang masih berdiri
            if _H.isPlayerDowned and _H.isPlayerDowned(p) then continue end
            -- Skip yang sudah hooked
            if _H.isPlayerHooked and _H.isPlayerHooked(p) then continue end
            local d = (r.Position - myRoot.Position).Magnitude
            if d <= CFG.autoAttackRange and isFacing(myRoot, r.Position, CFG.autoAttackFOV) then
                if d < targetDist then
                    target, targetDist = p, d
                end
            end
        end

        if target then
            -- Random jitter buat hindari pattern detection
            task.wait(math.random(30, 90) / 1000)
            -- Re-validate target masih valid setelah jitter (mungkin udah pindah/down/hooked)
            local rNow = getCharRoot(target)
            local cNow = target.Character
            local humNow = cNow and cNow:FindFirstChildOfClass("Humanoid")
            local stillValid = rNow and humNow and humNow.Health > 0
                and (not _H.isPlayerDowned or not _H.isPlayerDowned(target))
                and (not _H.isPlayerHooked or not _H.isPlayerHooked(target))
            if stillValid then
                local dNow = (rNow.Position - myRoot.Position).Magnitude
                if dNow <= CFG.autoAttackRange and isFacing(myRoot, rNow.Position, CFG.autoAttackFOV) then
                    rawRelease(); task.wait(0.04); rawPress()
                    task.wait(0.18)
                    rawRelease()
                    lastAttack = now
                end
            end
        end
    end
end)

-- ── STEP 6.13: AUTO-PICKUP (downed survivor) ────────────────
local lastPickup = 0
task.spawn(function()
    while true do
        task.wait(CFG.pickupTick)
        if not CFG.autoPickupEnabled then continue end
        if getRole() ~= "Killer" then continue end
        if isCarrying() then continue end  -- udah carrying

        local now = tick()
        if now - lastPickup < 1.5 then continue end

        local myRoot = getCharRoot(LP)
        if not myRoot then continue end

        -- Cari downed survivor terdekat
        local target, targetRoot, bestDist = nil, nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP or isKillerPlayer(p) then continue end
            if not _H.isPlayerDowned(p) then continue end
            local r = getCharRoot(p)
            if r then
                local d = (r.Position - myRoot.Position).Magnitude
                if d < bestDist and d <= CFG.pickupRange * 3 then
                    target, targetRoot, bestDist = p, r, d
                end
            end
        end

        if target then
            -- TP dekati kalau jauh
            if bestDist > CFG.pickupRange then
                -- Pakai world-space offset (downed survivor HRP miring → local offset bisa
                -- floating/underground). Approach dari sisi LP, facing target.
                local approach = myRoot.Position - targetRoot.Position
                local approachFlat = Vector3.new(approach.X, 0, approach.Z)
                if approachFlat.Magnitude < 0.1 then
                    approachFlat = Vector3.new(0, 0, 2)
                end
                local tpPos = targetRoot.Position + approachFlat.Unit * 2 + Vector3.new(0, 1, 0)
                local look  = Vector3.new(targetRoot.Position.X, tpPos.Y, targetRoot.Position.Z)
                myRoot.CFrame = CFrame.new(tpPos, look)
                task.wait(0.2)
            end
            -- Pickup di Violence District = hold SPACE
            holdSpace(1.2)
            lastPickup = now
        end
    end
end)

-- ── STEP 6.14: AUTO-HOOK (when carrying, go to nearest hook) ─
local lastHook = 0
task.spawn(function()
    while true do
        task.wait(CFG.hookTick)
        if not CFG.autoHookEnabled then continue end
        if getRole() ~= "Killer" then continue end
        if not isCarrying() then continue end

        local now = tick()
        if now - lastHook < 2 then continue end

        local myRoot = getCharRoot(LP)
        if not myRoot then continue end

        -- Build list semua hook + cek occupancy
        -- Hook dianggap "occupied" kalau ada survivor hooked dalam 4 studs.
        local hookedSurvivorPositions = {}
        for _, sp in ipairs(Players:GetPlayers()) do
            if sp ~= LP and not isKillerPlayer(sp)
              and _H.isPlayerHooked and _H.isPlayerHooked(sp) then
                local sr = getCharRoot(sp)
                if sr then table.insert(hookedSurvivorPositions, sr.Position) end
            end
        end

        local function isHookOccupied(hookPos)
            for _, pos in ipairs(hookedSurvivorPositions) do
                if (pos - hookPos).Magnitude < 4 then return true end
            end
            return false
        end

        -- Cari hook terdekat yang EMPTY
        local bestHook, bestDist = nil, math.huge
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") or obj:IsA("BasePart") then
                local ln = obj.Name:lower()
                if ln:find("hook") and not ln:find("crook") then
                    local part = obj:IsA("BasePart") and obj
                        or (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart"))
                    if part and not isHookOccupied(part.Position) then
                        local d = (part.Position - myRoot.Position).Magnitude
                        if d < bestDist then
                            bestHook, bestDist = part, d
                        end
                    end
                end
            end
        end

        if bestHook then
            -- TP berdiri di samping hook (approach dari sisi LP), facing hook.
            -- Sebelumnya TP ke +2 Y dengan lookAt ke hook → karakter floating + nunduk.
            local approach = myRoot.Position - bestHook.Position
            local approachFlat = Vector3.new(approach.X, 0, approach.Z)
            if approachFlat.Magnitude < 0.1 then
                approachFlat = Vector3.new(0, 0, 2)
            end
            local standPos = bestHook.Position + approachFlat.Unit * 2 + Vector3.new(0, 1.5, 0)
            local look     = Vector3.new(bestHook.Position.X, standPos.Y, bestHook.Position.Z)
            myRoot.CFrame  = CFrame.new(standPos, look)
            task.wait(0.25)
            -- Hook di Violence District = hold SPACE
            holdSpace(1.4)
            lastHook = now
        end
    end
end)

-- ── STEP 6.15: ANTI-STUN (signal-based, covers pallet/vault/shoot)
-- Reaksi <5ms karena pakai signal, bukan polling. Server-authoritative
-- masih bisa re-apply, tapi window stun-nya jadi minimal.
local function antiStunActive()
    return CFG.antiPalletStunEnabled
        or CFG.antiVaultStunEnabled
        or CFG.antiShootStunEnabled
        or CFG.antiFlashlightEnabled
end

local stunConns = {}
local function clearStunConns()
    for _, c in ipairs(stunConns) do pcall(function() c:Disconnect() end) end
    stunConns = {}
end

local function targetWalkSpeed()
    return CFG.speedEnabled and CFG.speedValue or 16
end

local function fixStunState(hum)
    if not hum then return end
    local char = hum.Parent
    -- VD-specific: reset IsStunned attribute kalau ke-set (pallet/flash/shoot signature)
    if char and (CFG.antiPalletStunEnabled or CFG.antiFlashlightEnabled or CFG.antiShootStunEnabled) then
        if char:GetAttribute("IsStunned") == true then
            pcall(function() char:SetAttribute("IsStunned", false) end)
        end
    end
    -- Destroy body movers kalau anti-stun apa pun aktif — vault knockback juga inject
    -- BodyVelocity di HRP, jadi gate-nya pakai antiStunActive() bukan subset pallet/flash/shoot.
    if char and antiStunActive() then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, d in ipairs(hrp:GetChildren()) do
                if d:IsA("BodyVelocity") or d:IsA("BodyForce") or d:IsA("BodyAngularVelocity") then
                    pcall(function() d:Destroy() end)
                end
            end
        end
    end
    -- Legacy safety nets
    if hum.PlatformStand then pcall(function() hum.PlatformStand = false end) end
    if hum.Sit then pcall(function() hum.Sit = false end) end
    if hum.WalkSpeed > 0 and hum.WalkSpeed < 12 then
        pcall(function() hum.WalkSpeed = targetWalkSpeed() end)
    end
end

-- VD stun mechanism (dari probe log):
--   Pallet/Flashlight/Shoot stun: char.Attribute "IsStunned" = true
--                                  + BodyVelocity di HumanoidRootPart
--                                  + StunAnimation id 75857500533792
--   Vault stun (survivor vault on killer): char.Attribute "Immobile" = true
--                                          + Animation "Vault" id 96839438835309
-- "Immobile" juga di-set saat killer SELF-ACTION (attack, kick pallet, carry).
-- Jadi Anti-Vault HANYA force Immobile=false saat Vault anim play.
local STUN_ANIM_IDS = {
    ["rbxassetid://75857500533792"] = true,  -- StunAnimation (pallet/flash/shoot)
}
local VAULT_ANIM_IDS = {
    ["rbxassetid://96839438835309"] = true,  -- Vault
}

local function removeStunBodyMovers(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    for _, d in ipairs(hrp:GetChildren()) do
        if d:IsA("BodyVelocity") or d:IsA("BodyForce") or d:IsA("BodyAngularVelocity") then
            pcall(function() d:Destroy() end)
        end
    end
end

-- ── Stun window: aktif 2s pasca-deteksi stun signal.
-- Heartbeat loop di bawah override walkspeed/attribute/body movers selama window
-- aktif → counter server replication yang re-apply stun state per tick (~30Hz).
local stunWindowUntil = 0
local function openStunWindow()
    stunWindowUntil = tick() + 2.0
end

local function attachAntiStun(char)
    clearStunConns()
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")

    -- ── 1. IsStunned attribute → force false + remove BodyVelocity
    -- (Pallet, Flashlight, Shoot stun — share signature)
    table.insert(stunConns, char:GetAttributeChangedSignal("IsStunned"):Connect(function()
        if getRole() ~= "Killer" then return end
        if not (CFG.antiPalletStunEnabled or CFG.antiFlashlightEnabled or CFG.antiShootStunEnabled) then return end
        if char:GetAttribute("IsStunned") == true then
            openStunWindow()  -- buka window override 2s
            pcall(function() char:SetAttribute("IsStunned", false) end)
            removeStunBodyMovers(char)
            pcall(function() hum.WalkSpeed = targetWalkSpeed() end)
        end
    end))

    -- ── 2. Immobile attribute → force false HANYA kalau Vault anim aktif
    -- (anti-false-positive untuk self-action attack/carry/kick)
    local vaultActive = false
    table.insert(stunConns, char:GetAttributeChangedSignal("Immobile"):Connect(function()
        if getRole() ~= "Killer" then return end
        if not CFG.antiVaultStunEnabled then return end
        if char:GetAttribute("Immobile") == true and vaultActive then
            pcall(function() char:SetAttribute("Immobile", false) end)
            removeStunBodyMovers(char)
            pcall(function() hum.WalkSpeed = targetWalkSpeed() end)
        end
    end))

    -- ── 3. Cancel stun/vault animations by ID
    table.insert(stunConns, hum.AnimationPlayed:Connect(function(track)
        if getRole() ~= "Killer" then return end
        if not track.Animation then return end
        local id = track.Animation.AnimationId
        -- StunAnimation (pallet/flash/shoot)
        if STUN_ANIM_IDS[id] and (CFG.antiPalletStunEnabled or CFG.antiFlashlightEnabled or CFG.antiShootStunEnabled) then
            pcall(function() track:Stop(0) end)
        end
        -- Vault anim — track flag selama anim play, cancel kalau anti-vault on
        if VAULT_ANIM_IDS[id] then
            vaultActive = true
            -- Capture connection biar bisa disconnect on Stopped → no listener leak
            local stoppedConn
            stoppedConn = track.Stopped:Connect(function()
                vaultActive = false
                if stoppedConn then
                    pcall(function() stoppedConn:Disconnect() end)
                    stoppedConn = nil
                end
            end)
            if CFG.antiVaultStunEnabled then
                pcall(function() track:Stop(0) end)
                if char:GetAttribute("Immobile") == true then
                    pcall(function() char:SetAttribute("Immobile", false) end)
                    removeStunBodyMovers(char)
                end
            end
        end
    end))

    -- ── 4. BodyVelocity injected into HRP (knock-back) → destroy instant
    if hrp then
        table.insert(stunConns, hrp.ChildAdded:Connect(function(c)
            if getRole() ~= "Killer" then return end
            if not (CFG.antiPalletStunEnabled or CFG.antiFlashlightEnabled or CFG.antiShootStunEnabled or CFG.antiVaultStunEnabled) then return end
            if c:IsA("BodyVelocity") or c:IsA("BodyForce") or c:IsA("BodyAngularVelocity") then
                pcall(function() c:Destroy() end)
                pcall(function() hum.WalkSpeed = targetWalkSpeed() end)
            end
        end))
    end

    -- ── 5. WalkSpeed dropped backup (kalau attribute miss)
    table.insert(stunConns, hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not antiStunActive() or getRole() ~= "Killer" then return end
        if hum.WalkSpeed > 0 and hum.WalkSpeed < 12 then
            pcall(function() hum.WalkSpeed = targetWalkSpeed() end)
        end
    end))
end

LP.CharacterAdded:Connect(function(c) task.wait(0.2); attachAntiStun(c) end)
if LP.Character then attachAntiStun(LP.Character) end

-- ── Heartbeat override aktif selama stun window (2s pasca-deteksi).
-- Frequency 60Hz biar lebih cepat dari server replication tick (~30Hz).
RunService.Heartbeat:Connect(function()
    if tick() >= stunWindowUntil then return end
    if not antiStunActive() then return end
    if getRole() ~= "Killer" then return end
    local c = LP.Character
    if not c then return end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return end
    if c:GetAttribute("IsStunned") == true then
        pcall(function() c:SetAttribute("IsStunned", false) end)
    end
    if h.WalkSpeed > 0 and h.WalkSpeed < 12 then
        pcall(function() h.WalkSpeed = targetWalkSpeed() end)
    end
    removeStunBodyMovers(c)
    local animator = c:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track.Animation and STUN_ANIM_IDS[track.Animation.AnimationId] then
                pcall(function() track:Stop(0) end)
            end
        end
    end
end)

-- Backup polling tiap 0.05s — jaga-jaga signal ke-bypass
task.spawn(function()
    while true do
        task.wait(CFG.antiStunTick)
        if not antiStunActive() then continue end
        if getRole() ~= "Killer" then continue end
        local c = LP.Character
        if not c then continue end
        local hum = c:FindFirstChild("Humanoid")
        if hum then fixStunState(hum) end
    end
end)

-- ── STEP 6.16: ANTI-FLASHLIGHT-BLIND (signal-based) ────────
-- Watch ChildAdded di Lighting/Camera/Character → instant disable + destroy
-- ColorCorrection/Blur/Bloom yang muncul sebagai blind effect.
local Lighting = game:GetService("Lighting")

local function killBlindEffect(ef)
    if not CFG.antiFlashlightEnabled then return end
    if getRole() ~= "Killer" then return end
    if ef:IsA("ColorCorrectionEffect") or ef:IsA("BlurEffect") or ef:IsA("BloomEffect") then
        pcall(function() ef.Enabled = false end)
        -- Destroy supaya server ga reapply
        pcall(function() ef:Destroy() end)
    end
end

local function watchContainer(container)
    if not container then return end
    container.ChildAdded:Connect(function(c) killBlindEffect(c) end)
    -- Scan existing
    for _, c in ipairs(container:GetChildren()) do killBlindEffect(c) end
end

watchContainer(Lighting)
if workspace.CurrentCamera then watchContainer(workspace.CurrentCamera) end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    watchContainer(workspace.CurrentCamera)
end)
LP.CharacterAdded:Connect(function(c) task.wait(0.2); watchContainer(c) end)
if LP.Character then watchContainer(LP.Character) end

-- Backup polling at 0.1s — kalau effect masuk via cara lain
task.spawn(function()
    while true do
        task.wait(0.1)
        if not CFG.antiFlashlightEnabled then continue end
        if getRole() ~= "Killer" then continue end
        for _, container in ipairs({Lighting, workspace.CurrentCamera, LP.Character}) do
            if container then
                for _, ef in ipairs(container:GetChildren()) do killBlindEffect(ef) end
            end
        end
    end
end)

-- ── STEP 6.17: AUTO-BREAK PALLET ────────────────────────────
local lastBreak = 0
task.spawn(function()
    while true do
        task.wait(CFG.breakPalletTick)
        if not CFG.autoBreakPalletEnabled then continue end
        if getRole() ~= "Killer" then continue end

        local now = tick()
        if now - lastBreak < 2.5 then continue end

        local myRoot = getCharRoot(LP)
        if not myRoot then continue end

        -- Scan pallets dalam range + facing + dropped state
        for _, palletData in ipairs(getPallets()) do
            local part = palletData.part
            if part and part.Parent then
                local d = (part.Position - myRoot.Position).Magnitude
                if d <= CFG.breakPalletRange
                  and isFacing(myRoot, part.Position, 0.55)
                  and isPalletDropped(palletData) then
                    -- Break pallet di Violence District = hold SPACE
                    holdSpace(1.0)
                    lastBreak = now
                    break
                end
            end
        end
    end
end)

end  -- ◀ END Killer features do-block

-- ── Aimbot ──────────────────────────────────────────────────
-- Lock kamera ke target body (HumanoidRootPart) dalam FOV pixel radius dari
-- center screen. Filter target: survivor → killer, killer → survivor.
-- Instant snap (no smoothing).
local Camera = workspace.CurrentCamera

local function getTargetRoleByTeam(p)
    if p.Team then
        local tn = p.Team.Name
        if tn == CFG.teamKiller or tn:lower():find("killer") then
            return "Killer"
        end
    end
    return "Survivor"
end

RunService.RenderStepped:Connect(function()
    if not CFG.aimbotEnabled then return end
    if not Camera then Camera = workspace.CurrentCamera end
    if not Camera then return end

    local myRole = getRole()
    if myRole ~= "Survivor" and myRole ~= "Killer" then return end

    local viewportSize = Camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)

    local bestTarget, bestDist = nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local c = p.Character
        if not c then continue end
        local hum = c:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        -- Filter role
        local targetRole = getTargetRoleByTeam(p)
        local valid = (myRole == "Survivor" and targetRole == "Killer")
                   or (myRole == "Killer"   and targetRole == "Survivor")
        if not valid then continue end

        -- Project ke screen
        local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        if not onScreen then continue end

        local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        if dist <= CFG.aimbotFOV and dist < bestDist then
            bestDist   = dist
            bestTarget = hrp
        end
    end

    if bestTarget then
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, bestTarget.Position)
    end
end)

-- ============================================================
--  STEP 7: GUI — Artheirs Script Modern Theme
-- ============================================================
local TweenService = game:GetService("TweenService")

-- ── Theme palette ────────────────────────────────────────────
local T = {
    -- Background layers
    bgDeep    = Color3.fromRGB(13, 14, 19),
    bgPanel   = Color3.fromRGB(20, 22, 28),
    bgHeader  = Color3.fromRGB(26, 28, 36),
    bgInput   = Color3.fromRGB(24, 26, 33),
    -- Buttons
    btnBase   = Color3.fromRGB(30, 33, 41),
    btnHover  = Color3.fromRGB(42, 46, 58),
    btnActive = Color3.fromRGB(50, 54, 68),
    -- Borders
    borderLo  = Color3.fromRGB(38, 42, 54),
    borderHi  = Color3.fromRGB(62, 68, 84),
    -- Text
    textPri   = Color3.fromRGB(232, 235, 245),
    textSec   = Color3.fromRGB(150, 156, 172),
    textDim   = Color3.fromRGB(95, 100, 115),
    -- Accents
    accent    = Color3.fromRGB(140, 120, 255),  -- primary purple
    accentDim = Color3.fromRGB(90, 75, 180),
    success   = Color3.fromRGB(110, 220, 150),
    danger    = Color3.fromRGB(255, 105, 110),
    warning   = Color3.fromRGB(255, 200, 90),
    info      = Color3.fromRGB(95, 210, 235),
}

local TWEEN_FAST   = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_NORMAL = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SLOW   = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(obj, info, props)
    TweenService:Create(obj, info, props):Play()
end

-- ── UI Helpers ───────────────────────────────────────────────
local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = p
    return c
end

local function stroke(p, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color           = color or T.borderLo
    s.Thickness       = thickness or 1
    s.Transparency    = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent          = p
    return s
end

local function gradient(p, c1, c2, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rotation or 90
    g.Parent = p
    return g
end

-- ── ScreenGui ───────────────────────────────────────────────
local SG = Instance.new("ScreenGui")
SG.Name           = "ArtheirsScript"
SG.ResetOnSpawn   = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset = true
-- ── Streamproof parent chain (toggleable via Misc tab) ────────
-- Function exposed via CFG._applyStreamproof biar checkbox di Misc bisa re-apply tanpa
-- nambah top-level local (script main chunk udah deket Luau 200-register limit).
do
    local function applyStreamproof()
        local parented = false
        if CFG.streamproofEnabled then
            -- 1) get_hidden_gui() — Solara TRUE streamproof container (WDA_EXCLUDEFROMCAPTURE)
            -- Inilah yang bikin GUI invisible di Medal/OBS/ShadowPlay capture.
            local _ghg = rawget(getfenv(), "get_hidden_gui")
            if typeof(_ghg) == "function" then
                local ok, hgui = pcall(_ghg)
                if ok and hgui then
                    local ok2 = pcall(function() SG.Parent = hgui end)
                    if ok2 and SG.Parent == hgui then parented = true end
                end
            end
            -- 2) gethui() — fallback container (protected dari GetChildren, mungkin streamproof)
            if not parented and typeof(gethui) == "function" then
                local ok, hui = pcall(gethui)
                if ok and hui then
                    local ok2 = pcall(function() SG.Parent = hui end)
                    if ok2 and SG.Parent == hui then parented = true end
                end
            end
            -- 3) syn.protect_gui — Synapse-style fallback
            if not parented and syn and typeof(syn.protect_gui) == "function" then
                pcall(function() syn.protect_gui(SG) end)
                pcall(function() SG.Parent = game:GetService("CoreGui") end)
                if SG.Parent and SG.Parent:IsA("CoreGui") then parented = true end
            end
            -- 4) protect_gui global (beberapa executor)
            if not parented and typeof(protect_gui) == "function" then
                pcall(function() protect_gui(SG) end)
                pcall(function() SG.Parent = game:GetService("CoreGui") end)
                if SG.Parent and SG.Parent:IsA("CoreGui") then parented = true end
            end
        end
        -- OFF, atau semua streamproof method gagal → CoreGui plain (keliatan saat record)
        if not parented then
            pcall(function() SG.Parent = game:GetService("CoreGui") end)
            if SG.Parent and SG.Parent:IsA("CoreGui") then parented = true end
        end
        -- Last resort
        if not parented then
            SG.Parent = LP.PlayerGui
        end
    end
    CFG._applyStreamproof = applyStreamproof  -- expose ke Misc tab toggle
    applyStreamproof()
end

-- ── Main Panel ──────────────────────────────────────────────
local PANEL_W, PANEL_H = 240, 598  -- height nampung Auto Escape, Aimbot, Aimbot FOV ctrl
local Panel = Instance.new("Frame")
Panel.Name             = "Panel"
Panel.Size             = UDim2.new(0, PANEL_W, 0, PANEL_H)
Panel.Position         = UDim2.new(0, 16, 0, 44)
Panel.AnchorPoint      = Vector2.new(0, 0)
Panel.BackgroundColor3 = T.bgPanel
Panel.BorderSizePixel  = 0
Panel.Active           = true
Panel.Draggable        = true
Panel.Parent           = SG
corner(Panel, 12)
stroke(Panel, T.borderHi, 1, 0.35)
gradient(Panel,
    Color3.fromRGB(28, 30, 38),
    Color3.fromRGB(18, 20, 26),
    135)

-- Inner glow stroke (double border efek glassy)
local InnerGlow = Instance.new("Frame")
InnerGlow.Size = UDim2.new(1, -4, 1, -4)
InnerGlow.Position = UDim2.new(0, 2, 0, 2)
InnerGlow.BackgroundTransparency = 1
InnerGlow.BorderSizePixel = 0
InnerGlow.Parent = Panel
corner(InnerGlow, 10)
stroke(InnerGlow, Color3.fromRGB(70, 78, 100), 1, 0.7)

-- ═══ HEADER ═════════════════════════════════════════════════
local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1, 0, 0, 56)
Header.BackgroundColor3 = T.bgHeader
Header.BorderSizePixel  = 0
Header.Parent           = Panel
corner(Header, 12)
gradient(Header,
    Color3.fromRGB(32, 34, 44),
    Color3.fromRGB(22, 24, 32),
    90)

-- Cover bottom corners (biar ga rounded bawah)
local HeaderBot = Instance.new("Frame")
HeaderBot.Size = UDim2.new(1, 0, 0, 14)
HeaderBot.Position = UDim2.new(0, 0, 1, -14)
HeaderBot.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
HeaderBot.BackgroundTransparency = 0
HeaderBot.BorderSizePixel = 0
HeaderBot.ZIndex = 0
HeaderBot.Parent = Header

-- Divider line bawah header (accent gradient)
local HDiv = Instance.new("Frame")
HDiv.Size             = UDim2.new(1, -32, 0, 1)
HDiv.Position         = UDim2.new(0, 16, 1, 0)
HDiv.BackgroundColor3 = T.accent
HDiv.BackgroundTransparency = 0.5
HDiv.BorderSizePixel  = 0
HDiv.Parent           = Header
gradient(HDiv,
    Color3.fromRGB(140, 120, 255),
    Color3.fromRGB(95, 210, 235),
    0)

-- Accent dot (animated pulse)
local Dot = Instance.new("Frame")
Dot.Size             = UDim2.new(0, 8, 0, 8)
Dot.Position         = UDim2.new(0, 16, 0, 14)
Dot.BackgroundColor3 = T.accent
Dot.BorderSizePixel  = 0
Dot.Parent           = Header
corner(Dot, 4)

local DotGlow = Instance.new("Frame")
DotGlow.Size             = UDim2.new(0, 16, 0, 16)
DotGlow.Position         = UDim2.new(0, 12, 0, 10)
DotGlow.BackgroundColor3 = T.accent
DotGlow.BackgroundTransparency = 0.5
DotGlow.BorderSizePixel  = 0
DotGlow.ZIndex           = Dot.ZIndex - 1
DotGlow.Parent           = Header
corner(DotGlow, 8)

-- Pulse animation
task.spawn(function()
    while DotGlow and DotGlow.Parent do
        tween(DotGlow, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
            BackgroundTransparency = 0.9,
            Size = UDim2.new(0, 22, 0, 22),
            Position = UDim2.new(0, 9, 0, 7),
        })
        break
    end
end)

-- Brand
local Brand = Instance.new("TextLabel")
Brand.Size             = UDim2.new(1, -90, 0, 18)
Brand.Position         = UDim2.new(0, 32, 0, 9)
Brand.BackgroundTransparency = 1
Brand.Text             = "ARTHEIRS"
Brand.TextColor3       = T.textPri
Brand.Font             = Enum.Font.GothamBold
Brand.TextSize         = 15
Brand.TextXAlignment   = Enum.TextXAlignment.Left
Brand.Parent           = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size             = UDim2.new(1, -90, 0, 14)
Subtitle.Position         = UDim2.new(0, 32, 0, 28)
Subtitle.BackgroundTransparency = 1
Subtitle.Text             = "Script · Violence District"
Subtitle.TextColor3       = T.textSec
Subtitle.Font             = Enum.Font.Gotham
Subtitle.TextSize         = 10
Subtitle.TextXAlignment   = Enum.TextXAlignment.Left
Subtitle.Parent           = Header

-- Version pill
local Ver = Instance.new("Frame")
Ver.Size             = UDim2.new(0, 38, 0, 18)
Ver.Position         = UDim2.new(1, -50, 0, 12)
Ver.BackgroundColor3 = T.btnBase
Ver.BorderSizePixel  = 0
Ver.Parent           = Header
corner(Ver, 5)
stroke(Ver, T.accent, 1, 0.4)

local VerLbl = Instance.new("TextLabel")
VerLbl.Size                   = UDim2.new(1, 0, 1, 0)
VerLbl.BackgroundTransparency = 1
VerLbl.Text                   = "v2.0"
VerLbl.TextColor3             = T.accent
VerLbl.Font                   = Enum.Font.GothamBold
VerLbl.TextSize               = 10
VerLbl.Parent                 = Ver

-- ═══ BODY (container untuk semua tombol) ═════════════════════
local Body = Instance.new("Frame")
Body.Size             = UDim2.new(1, 0, 1, -56)
Body.Position         = UDim2.new(0, 0, 0, 56)
Body.BackgroundTransparency = 1
Body.Parent           = Panel

-- ── Tombol factory: modern w/ accent bar + hover tween ──────
local function makeBtn(labelText, posY, onClick, parent)
    parent = parent or Body
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, PANEL_W - 28, 0, 34)
    b.Position         = UDim2.new(0, 14, 0, posY)
    b.BackgroundColor3 = T.btnBase
    b.BorderSizePixel  = 0
    b.Text             = "    " .. labelText  -- indent buat ngasih ruang accent bar
    b.TextColor3       = T.textPri
    b.Font             = Enum.Font.GothamMedium
    b.TextSize         = 12
    b.TextXAlignment   = Enum.TextXAlignment.Left
    b.AutoButtonColor  = false
    b.Parent           = parent
    corner(b, 8)
    local bStroke = stroke(b, T.borderLo, 1, 0.4)

    -- Accent bar kiri (indicator state)
    local bar = Instance.new("Frame")
    bar.Name             = "AccentBar"
    bar.Size             = UDim2.new(0, 3, 0.55, 0)
    bar.Position         = UDim2.new(0, 6, 0.225, 0)
    bar.BackgroundColor3 = T.textDim
    bar.BorderSizePixel  = 0
    bar.Parent           = b
    corner(bar, 2)

    -- Hover effect (tween halus)
    b.MouseEnter:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
        tween(bStroke, TWEEN_FAST, {Transparency = 0.1, Color = T.borderHi})
    end)
    b.MouseLeave:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
        tween(bStroke, TWEEN_FAST, {Transparency = 0.4, Color = T.borderLo})
    end)
    -- Press feedback
    b.MouseButton1Down:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnActive})
    end)
    b.MouseButton1Up:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
    end)

    b.MouseButton1Click:Connect(onClick)
    return b
end

-- Helper buat update warna accent bar (toggle state visual)
local function setBtnAccent(btn, color)
    local bar = btn:FindFirstChild("AccentBar")
    if bar then tween(bar, TWEEN_NORMAL, {BackgroundColor3 = color}) end
end

-- ── Y POSITIONS (relative to Body) ──────────────────────────
local Y_ROLE        = 10
local Y_ESP         = 50
local Y_TP          = 90
local Y_FLY         = 130
local Y_NOCLIP      = 170
local Y_FULLBRIGHT  = 210
local Y_AUTOREPAIR  = 250
local Y_AUTOESCAPE  = 290
local Y_AIMBOT      = 330
-- Divider + speed section di bawah
local Y_DIVIDER     = 376
local Y_SPEED_LBL   = 388
local Y_SPEED       = 406
local Y_SPEED_CTRL  = 446
-- Aimbot FOV section
local Y_AIMBOT_LBL  = 486
local Y_AIMBOT_CTRL = 504

-- ── ROLE button ─────────────────────────────────────────────
local roleBtn = makeBtn("[ROLE]  Auto: " .. roleCache, Y_ROLE, function()
    if not CFG.roleOverride then
        CFG.roleOverride = true
        CFG.manualRole   = roleCache ~= "Unknown" and roleCache or "Survivor"
    end
    CFG.manualRole = CFG.manualRole == "Survivor" and "Killer" or "Survivor"
    roleBtn.Text = "    [ROLE]  Manual: " .. CFG.manualRole
    local c = CFG.manualRole == "Killer" and T.danger or T.success
    setBtnAccent(roleBtn, c)
end)

local function getRoleAccent(r)
    if r == "Killer"   then return T.danger end
    if r == "Survivor" then return T.success end
    return T.textDim
end
setBtnAccent(roleBtn, getRoleAccent(roleCache))

LP:GetPropertyChangedSignal("Team"):Connect(function()
    if not CFG.roleOverride then
        local r = computeRole()
        roleCache = r
        roleBtn.Text = "    [ROLE]  Auto: " .. r
        setBtnAccent(roleBtn, getRoleAccent(r))
    end
end)

-- ── ESP ─────────────────────────────────────────────────────
local espBtn = makeBtn("[1]  ESP : ON", Y_ESP, function()
    CFG.espEnabled = not CFG.espEnabled
    espBtn.Text = "    [1]  ESP : " .. (CFG.espEnabled and "ON" or "OFF")
    setBtnAccent(espBtn, CFG.espEnabled and T.accent or T.danger)
end)
setBtnAccent(espBtn, T.accent)  -- start: ON

-- ── TP ──────────────────────────────────────────────────────
local tpBtn
-- TpPanel forward-declare
local TpPanel, refreshTpList, tpList, tpSelIdx, updateTpHighlight, Scroll

tpBtn = makeBtn("[2]  Teleport Menu", Y_TP, function()
    CFG.tpOpen = not CFG.tpOpen
    if TpPanel then
        TpPanel.Visible = CFG.tpOpen
    end
    if CFG.tpOpen and refreshTpList then refreshTpList() end
    setBtnAccent(tpBtn, CFG.tpOpen and T.info or T.textDim)
end)

-- ── Fly / Noclip / Fullbright / AutoRepair ──────────────────
local flyBtn, noclipBtn, fullbrightBtn, autoRepairBtn

local function updateFlyBtn()
    flyBtn.Text = "    [4]  Fly : " .. (CFG.flyEnabled and "ON" or "OFF")
    setBtnAccent(flyBtn, CFG.flyEnabled and T.info or T.textDim)
end

local function updateNoclipBtn()
    noclipBtn.Text = "    [5]  Noclip : " .. (CFG.noclipEnabled and "ON" or "OFF")
    setBtnAccent(noclipBtn, CFG.noclipEnabled and T.info or T.textDim)
end

local function updateFullbrightBtn()
    fullbrightBtn.Text = "    [6]  Fullbright : " .. (CFG.fullbrightEnabled and "ON" or "OFF")
    setBtnAccent(fullbrightBtn, CFG.fullbrightEnabled and T.warning or T.textDim)
end

local function updateAutoRepairBtn()
    autoRepairBtn.Text = "    [7]  Auto Repair : " .. (CFG.autoRepairEnabled and "ON" or "OFF")
    setBtnAccent(autoRepairBtn, CFG.autoRepairEnabled and T.success or T.textDim)
end

local function toggleFly()
    CFG.flyEnabled = not CFG.flyEnabled
    if CFG.flyEnabled then attachFlyObjects() else removeFlyObjects() end
    updateFlyBtn()
end

local function toggleNoclip()
    CFG.noclipEnabled = not CFG.noclipEnabled
    if not CFG.noclipEnabled then
        local char = LP.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end
    end
    updateNoclipBtn()
end

local function toggleFullbright()
    CFG.fullbrightEnabled = not CFG.fullbrightEnabled
    if CFG.fullbrightEnabled then applyFullbright() else restoreFullbright() end
    updateFullbrightBtn()
end

local function toggleAutoRepair()
    CFG.autoRepairEnabled = not CFG.autoRepairEnabled
    updateAutoRepairBtn()
end

flyBtn        = makeBtn("[4]  Fly : OFF",        Y_FLY,        toggleFly)
noclipBtn     = makeBtn("[5]  Noclip : OFF",     Y_NOCLIP,     toggleNoclip)
fullbrightBtn = makeBtn("[6]  Fullbright : OFF", Y_FULLBRIGHT, toggleFullbright)
autoRepairBtn = makeBtn("[7]  Auto Repair : OFF",Y_AUTOREPAIR, toggleAutoRepair)

-- ── Auto Escape (toggle [8]) ─────────────────────────────────
local autoEscapeBtn
local function updateAutoEscapeBtn()
    autoEscapeBtn.Text = "    [8]  Auto Escape : " .. (CFG.autoEscapeEnabled and "ON" or "OFF")
    setBtnAccent(autoEscapeBtn, CFG.autoEscapeEnabled and T.success or T.textDim)
end
local function toggleAutoEscape()
    CFG.autoEscapeEnabled = not CFG.autoEscapeEnabled
    updateAutoEscapeBtn()
end
autoEscapeBtn = makeBtn("[8]  Auto Escape : OFF", Y_AUTOESCAPE, toggleAutoEscape)

-- ── Aimbot (toggle [9]) ──────────────────────────────────────
local aimbotBtn, aimbotFovLbl  -- forward declare
local function updateAimbotBtn()
    aimbotBtn.Text = "    [9]  Aimbot : " .. (CFG.aimbotEnabled and "ON" or "OFF") .. "  ·  " .. CFG.aimbotFOV
    setBtnAccent(aimbotBtn, CFG.aimbotEnabled and T.danger or T.textDim)
end
local function toggleAimbot()
    CFG.aimbotEnabled = not CFG.aimbotEnabled
    updateAimbotBtn()
end
aimbotBtn = makeBtn("[9]  Aimbot : OFF  ·  120", Y_AIMBOT, toggleAimbot)

-- ── DIVIDER + SPEED SECTION (bottom) ────────────────────────
local Divider = Instance.new("Frame")
Divider.Size             = UDim2.new(1, -28, 0, 1)
Divider.Position         = UDim2.new(0, 14, 0, Y_DIVIDER)
Divider.BackgroundColor3 = T.borderHi
Divider.BackgroundTransparency = 0.4
Divider.BorderSizePixel  = 0
Divider.Parent           = Body

local SpeedHeader = Instance.new("TextLabel")
SpeedHeader.Size             = UDim2.new(1, -28, 0, 14)
SpeedHeader.Position         = UDim2.new(0, 14, 0, Y_SPEED_LBL)
SpeedHeader.BackgroundTransparency = 1
SpeedHeader.Text             = "SPEED CONTROL"
SpeedHeader.TextColor3       = T.textSec
SpeedHeader.Font             = Enum.Font.GothamBold
SpeedHeader.TextSize         = 9
SpeedHeader.TextXAlignment   = Enum.TextXAlignment.Left
SpeedHeader.Parent           = Body

local speedBtn, speedValLbl

local function updateSpeedDisplay()
    speedBtn.Text = "    [3]  Speed : " .. (CFG.speedEnabled and "ON" or "OFF") .. "  ·  " .. CFG.speedValue
    setBtnAccent(speedBtn, CFG.speedEnabled and T.info or T.textDim)
    speedValLbl.Text = tostring(CFG.speedValue)
end

local function toggleSpeed()
    CFG.speedEnabled = not CFG.speedEnabled
    local char = LP.Character
    if char then
        local hum = char:FindFirstChild("Humanoid")
        if hum then
            hum.WalkSpeed = CFG.speedEnabled and CFG.speedValue or 16
        end
    end
    updateSpeedDisplay()
end

speedBtn = makeBtn("[3]  Speed : OFF  ·  30", Y_SPEED, toggleSpeed)

-- Baris kontrol -/value/+ (modern segmented control)
local function makeSpeedCtrl(label, posX, width, onClick)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, width, 0, 30)
    b.Position         = UDim2.new(0, posX,  0, Y_SPEED_CTRL)
    b.BackgroundColor3 = T.btnBase
    b.BorderSizePixel  = 0
    b.Text             = label
    b.TextColor3       = T.textPri
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 15
    b.AutoButtonColor  = false
    b.Parent           = Body
    corner(b, 7)
    local s = stroke(b, T.borderLo, 1, 0.4)
    b.MouseEnter:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
        tween(s, TWEEN_FAST, {Color = T.accent, Transparency = 0.2})
    end)
    b.MouseLeave:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
        tween(s, TWEEN_FAST, {Color = T.borderLo, Transparency = 0.4})
    end)
    b.MouseButton1Click:Connect(onClick)
    return b
end

-- Layout simetris: 14 + 42 + 8 + 106 + 8 + 42 = 220, end x = 226 (match regular btn)
makeSpeedCtrl("−", 14, 42, function()
    CFG.speedValue = math.max(CFG.speedMin, CFG.speedValue - CFG.speedStep)
    updateSpeedDisplay()
end)

speedValLbl = Instance.new("TextLabel")
speedValLbl.Size             = UDim2.new(0, 106, 0, 30)
speedValLbl.Position         = UDim2.new(0, 64, 0, Y_SPEED_CTRL)
speedValLbl.BackgroundColor3 = T.bgInput
speedValLbl.BorderSizePixel  = 0
speedValLbl.Text             = "30"
speedValLbl.TextColor3       = T.accent
speedValLbl.Font             = Enum.Font.GothamBold
speedValLbl.TextSize         = 14
speedValLbl.TextXAlignment   = Enum.TextXAlignment.Center
speedValLbl.Parent           = Body
corner(speedValLbl, 7)
stroke(speedValLbl, T.accentDim, 1, 0.3)

makeSpeedCtrl("+", 184, 42, function()
    CFG.speedValue = math.min(CFG.speedMax, CFG.speedValue + CFG.speedStep)
    updateSpeedDisplay()
end)

-- ── AIMBOT FOV section ──────────────────────────────────────
local AimbotFovHeader = Instance.new("TextLabel")
AimbotFovHeader.Size             = UDim2.new(1, -28, 0, 14)
AimbotFovHeader.Position         = UDim2.new(0, 14, 0, Y_AIMBOT_LBL)
AimbotFovHeader.BackgroundTransparency = 1
AimbotFovHeader.Text             = "AIMBOT FOV"
AimbotFovHeader.TextColor3       = T.textSec
AimbotFovHeader.Font             = Enum.Font.GothamBold
AimbotFovHeader.TextSize         = 9
AimbotFovHeader.TextXAlignment   = Enum.TextXAlignment.Left
AimbotFovHeader.Parent           = Body

local function updateAimbotFovDisplay()
    if aimbotFovLbl then aimbotFovLbl.Text = tostring(CFG.aimbotFOV) end
    updateAimbotBtn()  -- refresh button text supaya FOV ke-update di label tombol
end

local function makeAimbotCtrl(label, posX, width, onClick)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, width, 0, 30)
    b.Position         = UDim2.new(0, posX,  0, Y_AIMBOT_CTRL)
    b.BackgroundColor3 = T.btnBase
    b.BorderSizePixel  = 0
    b.Text             = label
    b.TextColor3       = T.textPri
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 15
    b.AutoButtonColor  = false
    b.Parent           = Body
    corner(b, 7)
    local s = stroke(b, T.borderLo, 1, 0.4)
    b.MouseEnter:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
        tween(s, TWEEN_FAST, {Color = T.danger, Transparency = 0.2})
    end)
    b.MouseLeave:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
        tween(s, TWEEN_FAST, {Color = T.borderLo, Transparency = 0.4})
    end)
    b.MouseButton1Click:Connect(onClick)
    return b
end

makeAimbotCtrl("−", 14, 42, function()
    CFG.aimbotFOV = math.max(CFG.aimbotFOVMin, CFG.aimbotFOV - CFG.aimbotFOVStep)
    updateAimbotFovDisplay()
end)

aimbotFovLbl = Instance.new("TextLabel")
aimbotFovLbl.Size             = UDim2.new(0, 106, 0, 30)
aimbotFovLbl.Position         = UDim2.new(0, 64, 0, Y_AIMBOT_CTRL)
aimbotFovLbl.BackgroundColor3 = T.bgInput
aimbotFovLbl.BorderSizePixel  = 0
aimbotFovLbl.Text             = "120"
aimbotFovLbl.TextColor3       = T.danger
aimbotFovLbl.Font             = Enum.Font.GothamBold
aimbotFovLbl.TextSize         = 14
aimbotFovLbl.TextXAlignment   = Enum.TextXAlignment.Center
aimbotFovLbl.Parent           = Body
corner(aimbotFovLbl, 7)
stroke(aimbotFovLbl, T.danger, 1, 0.4)

makeAimbotCtrl("+", 184, 42, function()
    CFG.aimbotFOV = math.min(CFG.aimbotFOVMax, CFG.aimbotFOV + CFG.aimbotFOVStep)
    updateAimbotFovDisplay()
end)

-- ── CROSSHAIR dot (center screen, always-on) ───────────────
local Crosshair = Instance.new("Frame")
Crosshair.Size             = UDim2.new(0, CFG.crosshairSize, 0, CFG.crosshairSize)
Crosshair.AnchorPoint      = Vector2.new(0.5, 0.5)
Crosshair.Position         = UDim2.new(0.5, 0, 0.5, 0)
Crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Crosshair.BorderSizePixel  = 0
Crosshair.ZIndex           = 50
Crosshair.Parent           = SG
corner(Crosshair, math.floor(CFG.crosshairSize / 2))

-- ── FOV ring (visible cuma pas Aimbot ON, size = aimbotFOV*2) ──
local FovRing = Instance.new("Frame")
FovRing.Size                   = UDim2.new(0, CFG.aimbotFOV * 2, 0, CFG.aimbotFOV * 2)
FovRing.AnchorPoint            = Vector2.new(0.5, 0.5)
FovRing.Position               = UDim2.new(0.5, 0, 0.5, 0)
FovRing.BackgroundTransparency = 1
FovRing.BorderSizePixel        = 0
FovRing.Visible                = false
FovRing.ZIndex                 = 49
FovRing.Parent                 = SG
-- Circle via UICorner 50%
local fovCornerInst = Instance.new("UICorner")
fovCornerInst.CornerRadius = UDim.new(0.5, 0)
fovCornerInst.Parent = FovRing
-- Outline stroke (danger color)
local fovStroke = Instance.new("UIStroke")
fovStroke.Color        = T.danger
fovStroke.Thickness    = 1
fovStroke.Transparency = 0.3
fovStroke.Parent       = FovRing

-- Sync loop: visibility + size FovRing follow state
task.spawn(function()
    local lastVis, lastFov = false, -1
    while task.wait(0.1) do
        if FovRing and FovRing.Parent then
            if CFG.aimbotEnabled ~= lastVis then
                lastVis = CFG.aimbotEnabled
                FovRing.Visible = CFG.aimbotEnabled
            end
            if CFG.aimbotFOV ~= lastFov then
                lastFov = CFG.aimbotFOV
                FovRing.Size = UDim2.new(0, CFG.aimbotFOV * 2, 0, CFG.aimbotFOV * 2)
            end
        end
    end
end)

-- ═══ TELEPORT PANEL ══════════════════════════════════════════
TpPanel = Instance.new("Frame")
TpPanel.Name             = "TpPanel"
TpPanel.Size             = UDim2.new(0, 230, 0, 280)
TpPanel.Position         = UDim2.new(0, PANEL_W + 30, 0, 44)
TpPanel.BackgroundColor3 = T.bgPanel
TpPanel.BorderSizePixel  = 0
TpPanel.Visible          = false
TpPanel.Active           = true
TpPanel.Draggable        = true
TpPanel.Parent           = SG
corner(TpPanel, 12)
stroke(TpPanel, T.borderHi, 1, 0.35)
gradient(TpPanel,
    Color3.fromRGB(28, 30, 38),
    Color3.fromRGB(18, 20, 26),
    135)

local TpHeader = Instance.new("Frame")
TpHeader.Size             = UDim2.new(1, 0, 0, 38)
TpHeader.BackgroundColor3 = T.bgHeader
TpHeader.BorderSizePixel  = 0
TpHeader.Parent           = TpPanel
corner(TpHeader, 12)

local TpHeaderBot = Instance.new("Frame")
TpHeaderBot.Size = UDim2.new(1, 0, 0, 12)
TpHeaderBot.Position = UDim2.new(0, 0, 1, -12)
TpHeaderBot.BackgroundColor3 = T.bgHeader
TpHeaderBot.BorderSizePixel = 0
TpHeaderBot.Parent = TpHeader

local TpDiv = Instance.new("Frame")
TpDiv.Size             = UDim2.new(1, -32, 0, 1)
TpDiv.Position         = UDim2.new(0, 16, 1, 0)
TpDiv.BackgroundColor3 = T.info
TpDiv.BackgroundTransparency = 0.5
TpDiv.BorderSizePixel  = 0
TpDiv.Parent           = TpHeader

local TpDot = Instance.new("Frame")
TpDot.Size             = UDim2.new(0, 6, 0, 6)
TpDot.Position         = UDim2.new(0, 16, 0.5, -3)
TpDot.BackgroundColor3 = T.info
TpDot.BorderSizePixel  = 0
TpDot.Parent           = TpHeader
corner(TpDot, 3)

local TpTitleLbl = Instance.new("TextLabel")
TpTitleLbl.Size                   = UDim2.new(1, -30, 1, 0)
TpTitleLbl.Position               = UDim2.new(0, 28, 0, 0)
TpTitleLbl.BackgroundTransparency = 1
TpTitleLbl.Text                   = "TELEPORT TO PLAYER"
TpTitleLbl.TextColor3             = T.textPri
TpTitleLbl.Font                   = Enum.Font.GothamBold
TpTitleLbl.TextSize               = 12
TpTitleLbl.TextXAlignment         = Enum.TextXAlignment.Left
TpTitleLbl.Parent                 = TpHeader

Scroll = Instance.new("ScrollingFrame")
Scroll.Size                = UDim2.new(1, -16, 1, -50)
Scroll.Position            = UDim2.new(0, 8, 0, 44)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel     = 0
Scroll.ScrollBarThickness  = 3
Scroll.ScrollBarImageColor3 = T.accent
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
Scroll.Parent              = TpPanel

local ListLayout = Instance.new("UIListLayout")
ListLayout.FillDirection = Enum.FillDirection.Vertical
ListLayout.SortOrder     = Enum.SortOrder.Name
ListLayout.Padding       = UDim.new(0, 5)
ListLayout.Parent        = Scroll

local ListPad = Instance.new("UIPadding")
ListPad.PaddingTop    = UDim.new(0, 4)
ListPad.PaddingLeft   = UDim.new(0, 2)
ListPad.PaddingRight  = UDim.new(0, 2)
ListPad.Parent        = Scroll

tpList   = {}
tpSelIdx = 1

updateTpHighlight = function(newIdx)
    if tpList[tpSelIdx] and tpList[tpSelIdx].button.Parent then
        local prev = tpList[tpSelIdx].button
        tween(prev, TWEEN_NORMAL, {BackgroundColor3 = T.btnBase})
        local pStroke = prev:FindFirstChildOfClass("UIStroke")
        if pStroke then tween(pStroke, TWEEN_NORMAL, {Color = T.borderLo, Transparency = 0.4}) end
    end
    tpSelIdx = newIdx
    if tpList[tpSelIdx] and tpList[tpSelIdx].button.Parent then
        local cur = tpList[tpSelIdx].button
        tween(cur, TWEEN_NORMAL, {BackgroundColor3 = T.btnHover})
        local cStroke = cur:FindFirstChildOfClass("UIStroke")
        if cStroke then tween(cStroke, TWEEN_NORMAL, {Color = T.accent, Transparency = 0.1}) end
        local btnPos = cur.AbsolutePosition.Y
        local scrollTop = Scroll.AbsolutePosition.Y
        local scrollBot = scrollTop + Scroll.AbsoluteSize.Y
        if btnPos < scrollTop then
            Scroll.CanvasPosition = Vector2.new(0, Scroll.CanvasPosition.Y - 38)
        elseif btnPos + 34 > scrollBot then
            Scroll.CanvasPosition = Vector2.new(0, Scroll.CanvasPosition.Y + 38)
        end
    end
end

refreshTpList = function()
    for _, c in ipairs(Scroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    tpList   = {}
    tpSelIdx = 1

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end

        local btn = Instance.new("TextButton")
        btn.Name             = p.Name
        btn.Size             = UDim2.new(1, -4, 0, 34)
        btn.BackgroundColor3 = T.btnBase
        btn.BorderSizePixel  = 0
        btn.Text             = "  " .. p.DisplayName
        btn.TextColor3       = T.textPri
        btn.Font             = Enum.Font.GothamMedium
        btn.TextSize         = 12
        btn.TextXAlignment   = Enum.TextXAlignment.Left
        btn.AutoButtonColor  = false
        btn.Parent           = Scroll
        corner(btn, 7)
        local s = stroke(btn, T.borderLo, 1, 0.4)

        btn.MouseEnter:Connect(function()
            tween(btn, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
        end)
        btn.MouseLeave:Connect(function()
            if tpList[tpSelIdx] and tpList[tpSelIdx].button ~= btn then
                tween(btn, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
            end
        end)

        local entry = {player = p, button = btn}
        table.insert(tpList, entry)

        local idx = #tpList
        btn.MouseButton1Click:Connect(function()
            updateTpHighlight(idx)
            teleportTo(p)
        end)
    end

    if #tpList > 0 then
        tween(tpList[1].button, TWEEN_NORMAL, {BackgroundColor3 = T.btnHover})
        local s1 = tpList[1].button:FindFirstChildOfClass("UIStroke")
        if s1 then tween(s1, TWEEN_NORMAL, {Color = T.accent, Transparency = 0.1}) end
    end
end

Players.PlayerAdded:Connect(function()
    if CFG.tpOpen then refreshTpList() end
end)
Players.PlayerRemoving:Connect(function()
    if CFG.tpOpen then refreshTpList() end
end)

-- ═══ MENU TOGGLE PILL (selalu terlihat) ══════════════════════
local MenuToggle = Instance.new("TextButton")
MenuToggle.Name             = "MenuToggle"
MenuToggle.Size             = UDim2.new(0, 130, 0, 28)
MenuToggle.Position         = UDim2.new(0, 16, 0, 10)
MenuToggle.BackgroundColor3 = T.bgHeader
MenuToggle.BorderSizePixel  = 0
MenuToggle.Text             = "  ●  ARTHEIRS  ▾"
MenuToggle.TextColor3       = T.textPri
MenuToggle.Font             = Enum.Font.GothamBold
MenuToggle.TextSize         = 12
MenuToggle.TextXAlignment   = Enum.TextXAlignment.Left
MenuToggle.AutoButtonColor  = false
MenuToggle.Active           = true
MenuToggle.Parent           = SG
corner(MenuToggle, 8)
local mtStroke = stroke(MenuToggle, T.accent, 1, 0.3)

MenuToggle.MouseEnter:Connect(function()
    tween(MenuToggle, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
    tween(mtStroke, TWEEN_FAST, {Transparency = 0})
end)
MenuToggle.MouseLeave:Connect(function()
    tween(MenuToggle, TWEEN_FAST, {BackgroundColor3 = T.bgHeader})
    tween(mtStroke, TWEEN_FAST, {Transparency = 0.3})
end)

-- ── Panel open/close (instant toggle, no animation) ─────────
local function setPanelOpen(open)
    Panel.Visible   = open
    MenuToggle.Text = open and "  ●  ARTHEIRS  ▾" or "  ●  ARTHEIRS  ▸"
end

local panelOpen = true
MenuToggle.MouseButton1Click:Connect(function()
    panelOpen = not panelOpen
    setPanelOpen(panelOpen)
end)

-- INSERT key juga toggle menu
UIS.InputBegan:Connect(function(input, _)
    if input.KeyCode == Enum.KeyCode.Insert then
        panelOpen = not panelOpen
        setPanelOpen(panelOpen)
    end
end)

-- Panel langsung visible pas script load (no slide animation)
Panel.Size    = UDim2.new(0, PANEL_W, 0, PANEL_H)
Panel.Visible = true

-- ═══ FPS COUNTER (top-right) ═════════════════════════════════
local FpsBox = Instance.new("Frame")
FpsBox.Size             = UDim2.new(0, 92, 0, 28)
FpsBox.Position         = UDim2.new(1, -108, 0, 16)
FpsBox.AnchorPoint      = Vector2.new(0, 0)
FpsBox.BackgroundColor3 = T.bgHeader
FpsBox.BorderSizePixel  = 0
FpsBox.Parent           = SG
corner(FpsBox, 8)
stroke(FpsBox, T.borderHi, 1, 0.4)
gradient(FpsBox,
    Color3.fromRGB(32, 34, 44),
    Color3.fromRGB(22, 24, 32),
    90)

local FpsDot = Instance.new("Frame")
FpsDot.Size             = UDim2.new(0, 6, 0, 6)
FpsDot.Position         = UDim2.new(0, 10, 0.5, -3)
FpsDot.BackgroundColor3 = T.success
FpsDot.BorderSizePixel  = 0
FpsDot.Parent           = FpsBox
corner(FpsDot, 3)

local FpsLbl = Instance.new("TextLabel")
FpsLbl.Size                   = UDim2.new(1, -22, 1, 0)
FpsLbl.Position               = UDim2.new(0, 22, 0, 0)
FpsLbl.BackgroundTransparency = 1
FpsLbl.Text                   = "60 FPS"
FpsLbl.TextColor3             = T.textPri
FpsLbl.Font                   = Enum.Font.GothamBold
FpsLbl.TextSize               = 11
FpsLbl.TextXAlignment         = Enum.TextXAlignment.Left
FpsLbl.Parent                 = FpsBox

-- FPS sampling (smoothing tiap 0.5 detik biar ga flicker)
local fpsFrames, fpsSum = 0, 0
RunService.RenderStepped:Connect(function(dt)
    fpsFrames += 1
    fpsSum    += dt
    if fpsSum >= 0.5 then
        local fps = math.floor(fpsFrames / fpsSum + 0.5)
        FpsLbl.Text = fps .. " FPS"
        -- Dot color sesuai performance
        local target
        if     fps >= 50 then target = T.success
        elseif fps >= 30 then target = T.warning
        else                  target = T.danger
        end
        tween(FpsDot, TWEEN_FAST, {BackgroundColor3 = target})
        fpsFrames, fpsSum = 0, 0
    end
end)

-- ═══ TOAST NOTIFICATION (top-center) ═════════════════════════
-- Slide-in dari atas, hold, slide-out. Auto-destroy.
local function showToast(title, subtitle, duration)
    duration = duration or 3
    local toast = Instance.new("Frame")
    toast.Size             = UDim2.new(0, 300, 0, 62)
    toast.AnchorPoint      = Vector2.new(0.5, 0)
    toast.Position         = UDim2.new(0.5, 0, 0, -80)
    toast.BackgroundColor3 = T.bgPanel
    toast.BorderSizePixel  = 0
    toast.Parent           = SG
    corner(toast, 12)
    stroke(toast, T.accent, 1, 0.2)
    gradient(toast,
        Color3.fromRGB(32, 34, 44),
        Color3.fromRGB(20, 22, 28),
        135)

    -- Accent dot dengan glow
    local glow = Instance.new("Frame")
    glow.Size             = UDim2.new(0, 18, 0, 18)
    glow.Position         = UDim2.new(0, 12, 0.5, -9)
    glow.BackgroundColor3 = T.accent
    glow.BackgroundTransparency = 0.6
    glow.BorderSizePixel  = 0
    glow.Parent           = toast
    corner(glow, 9)

    local dot = Instance.new("Frame")
    dot.Size             = UDim2.new(0, 8, 0, 8)
    dot.Position         = UDim2.new(0, 17, 0.5, -4)
    dot.BackgroundColor3 = T.accent
    dot.BorderSizePixel  = 0
    dot.Parent           = toast
    corner(dot, 4)

    -- Title
    local tlbl = Instance.new("TextLabel")
    tlbl.Size                   = UDim2.new(1, -50, 0, 20)
    tlbl.Position               = UDim2.new(0, 38, 0, 12)
    tlbl.BackgroundTransparency = 1
    tlbl.Text                   = title
    tlbl.TextColor3             = T.textPri
    tlbl.Font                   = Enum.Font.GothamBold
    tlbl.TextSize               = 13
    tlbl.TextXAlignment         = Enum.TextXAlignment.Left
    tlbl.Parent                 = toast

    -- Subtitle
    local slbl = Instance.new("TextLabel")
    slbl.Size                   = UDim2.new(1, -50, 0, 16)
    slbl.Position               = UDim2.new(0, 38, 0, 32)
    slbl.BackgroundTransparency = 1
    slbl.Text                   = subtitle or ""
    slbl.TextColor3             = T.textSec
    slbl.Font                   = Enum.Font.Gotham
    slbl.TextSize               = 11
    slbl.TextXAlignment         = Enum.TextXAlignment.Left
    slbl.Parent                 = toast

    -- Slide-in dari atas
    tween(toast, TWEEN_SLOW, {Position = UDim2.new(0.5, 0, 0, 24)})

    -- Hold, slide-out, destroy
    task.delay(duration, function()
        tween(toast, TWEEN_NORMAL, {Position = UDim2.new(0.5, 0, 0, -80)})
        task.wait(0.3)
        if toast and toast.Parent then toast:Destroy() end
    end)
end

-- ════════════════════════════════════════════════════════════
-- ▼ AXON-STYLE WINDOW (Multi-tab + Sidebar + Components)
-- ════════════════════════════════════════════════════════════

-- Map: featureName → updateVisualFn (dipakai keybind buat sync checkbox)
local checkboxUpdaters = {}

-- ── Checkbox factory ────────────────────────────────────────
-- (label kiri, square box kanan; click toggle, fill saat ON)
local function makeCheckbox(parent, posY, label, getter, setter)
    local cont = Instance.new("Frame")
    cont.Size                  = UDim2.new(1, 0, 0, 44)
    cont.Position              = UDim2.new(0, 0, 0, posY)
    cont.BackgroundColor3      = T.bgInput
    cont.BackgroundTransparency= 0.6
    cont.BorderSizePixel       = 0
    cont.Parent                = parent
    corner(cont, 8)

    -- Padding internal
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft  = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent       = cont

    -- Label kiri
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -36, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = label
    lbl.TextColor3             = T.textPri
    lbl.Font                   = Enum.Font.GothamMedium
    lbl.TextSize               = 13
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.TextYAlignment         = Enum.TextYAlignment.Center
    lbl.Parent                 = cont

    -- Box kanan
    local box = Instance.new("TextButton")
    box.Size              = UDim2.new(0, 22, 0, 22)
    box.Position          = UDim2.new(1, -26, 0.5, -11)
    box.BackgroundColor3  = T.btnBase
    box.BorderSizePixel   = 0
    box.Text              = ""
    box.AutoButtonColor   = false
    box.Parent            = cont
    corner(box, 5)
    local boxStroke = stroke(box, T.borderLo, 1.5, 0.2)

    -- Check icon
    local check = Instance.new("TextLabel")
    check.Size                   = UDim2.new(1, 0, 1, 0)
    check.BackgroundTransparency = 1
    check.Text                   = "✓"
    check.TextColor3             = Color3.fromRGB(255, 255, 255)
    check.Font                   = Enum.Font.GothamBold
    check.TextSize               = 14
    check.Visible                = false
    check.Parent                 = box

    local function updateVisual(on)
        if on then
            tween(box, TWEEN_FAST, {BackgroundColor3 = T.accent})
            tween(boxStroke, TWEEN_FAST, {Color = T.accent, Transparency = 0})
            check.Visible = true
        else
            tween(box, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
            tween(boxStroke, TWEEN_FAST, {Color = T.borderLo, Transparency = 0.2})
            check.Visible = false
        end
    end

    box.MouseButton1Click:Connect(function()
        local newVal = not getter()
        setter(newVal)
        updateVisual(newVal)
    end)

    updateVisual(getter())
    return cont, updateVisual
end

-- ── Slider factory ──────────────────────────────────────────
-- (label kiri atas, numeric kanan atas, track bawah dengan thumb drag)
local function makeSlider(parent, posY, label, minV, maxV, step, getter, setter)
    local cont = Instance.new("Frame")
    cont.Size                  = UDim2.new(1, 0, 0, 50)
    cont.Position              = UDim2.new(0, 0, 0, posY)
    cont.BackgroundTransparency= 1
    cont.Parent                = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -60, 0, 18)
    lbl.Position               = UDim2.new(0, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = label
    lbl.TextColor3             = T.textPri
    lbl.Font                   = Enum.Font.GothamMedium
    lbl.TextSize               = 12
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = cont

    local valBox = Instance.new("Frame")
    valBox.Size              = UDim2.new(0, 50, 0, 20)
    valBox.Position          = UDim2.new(1, -50, 0, 0)
    valBox.BackgroundColor3  = T.bgInput
    valBox.BorderSizePixel   = 0
    valBox.Parent            = cont
    corner(valBox, 5)
    stroke(valBox, T.borderLo, 1, 0.4)

    local valLbl = Instance.new("TextLabel")
    valLbl.Size                   = UDim2.new(1, 0, 1, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Text                   = tostring(getter())
    valLbl.TextColor3             = T.accent
    valLbl.Font                   = Enum.Font.GothamBold
    valLbl.TextSize               = 11
    valLbl.TextXAlignment         = Enum.TextXAlignment.Center
    valLbl.Parent                 = valBox

    local track = Instance.new("Frame")
    track.Size              = UDim2.new(1, 0, 0, 5)
    track.Position          = UDim2.new(0, 0, 0, 32)
    track.BackgroundColor3  = T.bgInput
    track.BorderSizePixel   = 0
    track.Parent            = cont
    corner(track, 3)

    local initP = math.clamp((getter() - minV) / (maxV - minV), 0, 1)

    local fill = Instance.new("Frame")
    fill.Size              = UDim2.new(initP, 0, 1, 0)
    fill.BackgroundColor3  = T.accent
    fill.BorderSizePixel   = 0
    fill.Parent            = track
    corner(fill, 3)

    local thumb = Instance.new("Frame")
    thumb.Size                  = UDim2.new(0, 14, 0, 14)
    thumb.Position              = UDim2.new(initP, -7, 0.5, -7)
    thumb.BackgroundColor3      = T.textPri
    thumb.BorderSizePixel       = 0
    thumb.Parent                = track
    corner(thumb, 7)
    stroke(thumb, T.accent, 1.5, 0)

    local dragging = false

    local function setValue(v)
        v = math.clamp(math.floor(v / step + 0.5) * step, minV, maxV)
        setter(v)
        local p = (v - minV) / (maxV - minV)
        fill.Size      = UDim2.new(p, 0, 1, 0)
        thumb.Position = UDim2.new(p, -7, 0.5, -7)
        valLbl.Text    = tostring(v)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local mouseX = input.Position.X
            local trackAbsX = track.AbsolutePosition.X
            local trackW = track.AbsoluteSize.X
            local p = math.clamp((mouseX - trackAbsX) / trackW, 0, 1)
            setValue(minV + p * (maxV - minV))
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
       and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local mouseX = input.Position.X
        local trackAbsX = track.AbsolutePosition.X
        local trackW = track.AbsoluteSize.X
        local p = math.clamp((mouseX - trackAbsX) / trackW, 0, 1)
        setValue(minV + p * (maxV - minV))
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return cont, setValue
end

-- ── Section header factory ──────────────────────────────────
local function makeSectionHeader(parent, posY, text)
    local cont = Instance.new("Frame")
    cont.Size                  = UDim2.new(1, 0, 0, 30)
    cont.Position              = UDim2.new(0, 0, 0, posY)
    cont.BackgroundTransparency= 1
    cont.Parent                = parent

    -- Accent bar kiri (modern touch)
    local bar = Instance.new("Frame")
    bar.Size                   = UDim2.new(0, 3, 0, 14)
    bar.Position               = UDim2.new(0, 0, 0, 4)
    bar.BackgroundColor3       = T.accent
    bar.BorderSizePixel        = 0
    bar.Parent                 = cont
    corner(bar, 2)

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -12, 0, 18)
    lbl.Position               = UDim2.new(0, 12, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = T.textPri
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = 11
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = cont

    local line = Instance.new("Frame")
    line.Size                  = UDim2.new(1, 0, 0, 1)
    line.Position              = UDim2.new(0, 0, 1, -2)
    line.BackgroundColor3      = T.borderLo
    line.BackgroundTransparency= 0.55
    line.BorderSizePixel       = 0
    line.Parent                = cont
    return cont
end

-- ════════════════════════════════════════════════════════════
-- ▼ MAIN WINDOW
-- ════════════════════════════════════════════════════════════
local WIN_W, WIN_H        = 660, 480
local SIDEBAR_W           = 160
local TITLEBAR_H          = 50
local CONTENT_W           = WIN_W - SIDEBAR_W

local Window = Instance.new("Frame")
Window.Name             = "Window"
Window.Size             = UDim2.new(0, WIN_W, 0, WIN_H)
Window.Position         = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2)
Window.BackgroundColor3 = T.bgPanel
Window.BorderSizePixel  = 0
Window.Active           = true
Window.Draggable        = true
Window.Visible          = false  -- show setelah semua tab di-build
Window.Parent           = SG
corner(Window, 12)
stroke(Window, T.borderHi, 1, 0.35)

-- ── Title bar ───────────────────────────────────────────────
local TITLE_BLACK = Color3.fromRGB(10, 11, 15)

local WTitleBar = Instance.new("Frame")
WTitleBar.Size             = UDim2.new(1, 0, 0, TITLEBAR_H)
WTitleBar.BackgroundColor3 = TITLE_BLACK
WTitleBar.BorderSizePixel  = 0
WTitleBar.Parent           = Window
corner(WTitleBar, 12)

-- Cover bottom rounded corners (biar full flat hitam dari atas ke divider)
local WTitleBot = Instance.new("Frame")
WTitleBot.Size             = UDim2.new(1, 0, 0, 14)
WTitleBot.Position         = UDim2.new(0, 0, 1, -14)
WTitleBot.BackgroundColor3 = TITLE_BLACK
WTitleBot.BorderSizePixel  = 0
WTitleBot.Parent           = WTitleBar

local WTitleDiv = Instance.new("Frame")
WTitleDiv.Size                  = UDim2.new(1, 0, 0, 1)
WTitleDiv.Position              = UDim2.new(0, 0, 1, 0)
WTitleDiv.BackgroundColor3      = T.borderHi
WTitleDiv.BackgroundTransparency= 0.5
WTitleDiv.BorderSizePixel       = 0
WTitleDiv.Parent                = WTitleBar

-- ── Header brand — accent dot + gradient text + shimmer underline
-- Wrap dalam do-block biar 12+ locals di sini ga makan register slot parent function
-- (Luau limit 200 local registers per function)
do
-- Color palette: purple → cyan slide
local BRAND_PURPLE = Color3.fromRGB(167, 139, 250)
local BRAND_CYAN   = Color3.fromRGB(96, 165, 250)

-- Accent dot (pulse animation)
local WAccent = Instance.new("Frame")
WAccent.Size              = UDim2.new(0, 8, 0, 8)
WAccent.Position          = UDim2.new(0, 18, 0, 15)
WAccent.BackgroundColor3  = BRAND_PURPLE
WAccent.BorderSizePixel   = 0
WAccent.Parent            = WTitleBar
local accCorner = Instance.new("UICorner")
accCorner.CornerRadius    = UDim.new(1, 0)
accCorner.Parent          = WAccent
-- Soft glow ring around dot
local accGlow = Instance.new("Frame")
accGlow.Size              = UDim2.new(0, 14, 0, 14)
accGlow.Position          = UDim2.new(0, -3, 0, -3)
accGlow.BackgroundColor3  = BRAND_PURPLE
accGlow.BackgroundTransparency = 0.7
accGlow.BorderSizePixel   = 0
accGlow.ZIndex            = 0
accGlow.Parent            = WAccent
local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius   = UDim.new(1, 0)
glowCorner.Parent         = accGlow

-- Brand text with horizontal purple→cyan gradient
local WBrand = Instance.new("TextLabel")
WBrand.Size                   = UDim2.new(0, 200, 0, 18)
WBrand.Position               = UDim2.new(0, 34, 0, 9)
WBrand.BackgroundTransparency = 1
WBrand.Text                   = "Artheirs"
WBrand.TextColor3             = Color3.fromRGB(255, 255, 255)
WBrand.Font                   = Enum.Font.GothamBold
WBrand.TextSize               = 16
WBrand.TextXAlignment         = Enum.TextXAlignment.Left
WBrand.TextYAlignment         = Enum.TextYAlignment.Center
WBrand.Parent                 = WTitleBar
local brandGradient = Instance.new("UIGradient")
brandGradient.Color           = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    BRAND_PURPLE),
    ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(232, 222, 255)),
    ColorSequenceKeypoint.new(1,    BRAND_CYAN),
})
brandGradient.Parent          = WBrand

-- Subtitle
local WSub = Instance.new("TextLabel")
WSub.Size                   = UDim2.new(0, 200, 0, 14)
WSub.Position               = UDim2.new(0, 34, 0, 28)
WSub.BackgroundTransparency = 1
WSub.Text                   = "Violence District"
WSub.TextColor3             = T.textSec
WSub.Font                   = Enum.Font.Gotham
WSub.TextSize               = 10
WSub.TextXAlignment         = Enum.TextXAlignment.Left
WSub.TextYAlignment         = Enum.TextYAlignment.Center
WSub.Parent                 = WTitleBar

-- Shimmer underline — gradient slide L→R infinite loop
local WUnderline = Instance.new("Frame")
WUnderline.Size                  = UDim2.new(0, 70, 0, 2)
WUnderline.Position              = UDim2.new(0, 34, 0, 44)
WUnderline.BackgroundColor3      = Color3.fromRGB(255, 255, 255)
WUnderline.BorderSizePixel       = 0
WUnderline.Parent                = WTitleBar
local underCorner = Instance.new("UICorner")
underCorner.CornerRadius         = UDim.new(1, 0)
underCorner.Parent               = WUnderline
local underGradient = Instance.new("UIGradient")
underGradient.Color              = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    BRAND_PURPLE),
    ColorSequenceKeypoint.new(0.5,  BRAND_CYAN),
    ColorSequenceKeypoint.new(1,    BRAND_PURPLE),
})
underGradient.Transparency       = NumberSequence.new({
    NumberSequenceKeypoint.new(0,    1),
    NumberSequenceKeypoint.new(0.25, 0.2),
    NumberSequenceKeypoint.new(0.75, 0.2),
    NumberSequenceKeypoint.new(1,    1),
})
underGradient.Parent             = WUnderline

-- Animate shimmer offset L→R repeat
task.spawn(function()
    while WUnderline.Parent do
        underGradient.Offset = Vector2.new(-1, 0)
        local t = TweenService:Create(
            underGradient,
            TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {Offset = Vector2.new(1, 0)}
        )
        t:Play()
        t.Completed:Wait()
        task.wait(0.4)
    end
end)

-- Animate accent dot pulse (transparency + scale via glow)
task.spawn(function()
    while WAccent.Parent do
        local t1 = TweenService:Create(
            accGlow,
            TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {BackgroundTransparency = 0.4, Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(0, -5, 0, -5)}
        )
        t1:Play(); t1.Completed:Wait()
        local t2 = TweenService:Create(
            accGlow,
            TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {BackgroundTransparency = 0.85, Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, -3, 0, -3)}
        )
        t2:Play(); t2.Completed:Wait()
    end
end)
end  -- ◀ END header brand do-block (frees ~12 register slots)

-- Window controls (close button kanan atas)
local function makeWindowCtrl(text, posX, onClick)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 26, 0, 22)
    b.Position         = UDim2.new(1, posX, 0, 10)
    b.BackgroundColor3 = T.btnBase
    b.BorderSizePixel  = 0
    b.Text             = text
    b.TextColor3       = T.textSec
    b.Font             = Enum.Font.GothamBold
    b.TextSize         = 12
    b.AutoButtonColor  = false
    b.Parent           = WTitleBar
    corner(b, 5)
    b.MouseEnter:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
    end)
    b.MouseLeave:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
    end)
    b.MouseButton1Click:Connect(onClick)
    return b
end

makeWindowCtrl("−", -64, function()
    Window.Visible = false
    MenuToggle.Text = "  ●  ARTHEIRS  ▸"
end)
makeWindowCtrl("✕", -32, function()
    Window.Visible = false
    MenuToggle.Text = "  ●  ARTHEIRS  ▸"
end)

-- ── Sidebar ─────────────────────────────────────────────────
local WSidebar = Instance.new("Frame")
WSidebar.Size             = UDim2.new(0, SIDEBAR_W, 1, -TITLEBAR_H)
WSidebar.Position         = UDim2.new(0, 0, 0, TITLEBAR_H)
WSidebar.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
WSidebar.BorderSizePixel  = 0
WSidebar.Parent           = Window

local WSideDiv = Instance.new("Frame")
WSideDiv.Size                  = UDim2.new(0, 1, 1, 0)
WSideDiv.Position              = UDim2.new(1, -1, 0, 0)
WSideDiv.BackgroundColor3      = T.borderLo
WSideDiv.BackgroundTransparency= 0.4
WSideDiv.BorderSizePixel       = 0
WSideDiv.Parent                = WSidebar

-- ── Content area ────────────────────────────────────────────
local WContent = Instance.new("Frame")
WContent.Size                  = UDim2.new(0, CONTENT_W, 1, -TITLEBAR_H)
WContent.Position              = UDim2.new(0, SIDEBAR_W, 0, TITLEBAR_H)
WContent.BackgroundTransparency= 1
WContent.Parent                = Window

local WContentPad = Instance.new("UIPadding")
WContentPad.PaddingLeft   = UDim.new(0, 28)
WContentPad.PaddingRight  = UDim.new(0, 28)
WContentPad.PaddingTop    = UDim.new(0, 22)
WContentPad.PaddingBottom = UDim.new(0, 22)
WContentPad.Parent        = WContent

-- ── Tab heading (besar di atas content area) ───────────────
local WTabHeading = Instance.new("TextLabel")
WTabHeading.Size                   = UDim2.new(1, 0, 0, 28)
WTabHeading.BackgroundTransparency = 1
WTabHeading.Text                   = "Survivor"
WTabHeading.TextColor3             = T.textPri
WTabHeading.Font                   = Enum.Font.GothamBold
WTabHeading.TextSize               = 22
WTabHeading.TextXAlignment         = Enum.TextXAlignment.Left
WTabHeading.Parent                 = WContent

-- Subtitle/breadcrumb di bawah heading
local WTabSub = Instance.new("TextLabel")
WTabSub.Size                   = UDim2.new(1, 0, 0, 14)
WTabSub.Position               = UDim2.new(0, 0, 0, 30)
WTabSub.BackgroundTransparency = 1
WTabSub.Text                   = "Violence District · Configure features"
WTabSub.TextColor3             = T.textDim
WTabSub.Font                   = Enum.Font.Gotham
WTabSub.TextSize               = 11
WTabSub.TextXAlignment         = Enum.TextXAlignment.Left
WTabSub.Parent                 = WContent

-- ── Tab body container (di bawah heading) — ScrollingFrame supaya muat banyak fitur
local WTabBody = Instance.new("ScrollingFrame")
WTabBody.Size                  = UDim2.new(1, 0, 1, -58)
WTabBody.Position              = UDim2.new(0, 0, 0, 58)
WTabBody.BackgroundTransparency= 1
WTabBody.BorderSizePixel       = 0
WTabBody.ScrollBarThickness    = 4
WTabBody.ScrollBarImageColor3  = T.borderHi
WTabBody.CanvasSize            = UDim2.new(0, 0, 0, 600)  -- auto-fit via tab content
WTabBody.AutomaticCanvasSize   = Enum.AutomaticSize.Y
WTabBody.ScrollingDirection    = Enum.ScrollingDirection.Y
WTabBody.Parent                = WContent

-- ════════════════════════════════════════════════════════════
-- ▼ SIDEBAR ITEMS + TAB CONTAINERS
-- ════════════════════════════════════════════════════════════
local tabs = {}    -- name → {Item, Content, SetActive, Heading}
local currentTab = nil

local function switchTab(name)
    if currentTab == name then return end
    if currentTab and tabs[currentTab] then
        tabs[currentTab].Content.Visible = false
        tabs[currentTab].SetActive(false)
    end
    currentTab = name
    if tabs[name] then
        tabs[name].Content.Visible = true
        tabs[name].SetActive(true)
        WTabHeading.Text = tabs[name].Heading or name
    end
end

local function makeSidebarItem(name, posY)
    local btn = Instance.new("TextButton")
    btn.Size              = UDim2.new(1, -20, 0, 36)
    btn.Position          = UDim2.new(0, 10, 0, posY)
    btn.BackgroundColor3  = Color3.fromRGB(15, 17, 22)
    btn.BorderSizePixel   = 0
    btn.Text              = "    " .. name
    btn.TextColor3        = T.textSec
    btn.Font              = Enum.Font.GothamMedium
    btn.TextSize          = 13
    btn.TextXAlignment    = Enum.TextXAlignment.Left
    btn.AutoButtonColor   = false
    btn.Parent            = WSidebar
    corner(btn, 6)

    -- Active bar kiri
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(0, 3, 0.55, 0)
    bar.Position         = UDim2.new(0, 0, 0.225, 0)
    bar.BackgroundColor3 = T.accent
    bar.BorderSizePixel  = 0
    bar.Visible          = false
    bar.Parent           = btn
    corner(bar, 2)

    btn.MouseEnter:Connect(function()
        if not btn:GetAttribute("Active") then
            tween(btn, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
        end
    end)
    btn.MouseLeave:Connect(function()
        if not btn:GetAttribute("Active") then
            tween(btn, TWEEN_FAST, {BackgroundColor3 = Color3.fromRGB(15, 17, 22)})
        end
    end)

    local function setActive(active)
        btn:SetAttribute("Active", active)
        bar.Visible = active
        if active then
            tween(btn, TWEEN_NORMAL, {BackgroundColor3 = T.btnHover, TextColor3 = T.textPri})
        else
            tween(btn, TWEEN_NORMAL, {BackgroundColor3 = Color3.fromRGB(15, 17, 22), TextColor3 = T.textSec})
        end
    end

    return btn, setActive
end

-- Sidebar category label
local function makeSidebarLabel(text, posY)
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, -20, 0, 16)
    lbl.Position               = UDim2.new(0, 18, 0, posY)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = T.textDim
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = 10
    lbl.TextXAlignment         = Enum.TextXAlignment.Left
    lbl.Parent                 = WSidebar
end

-- Tab content frame factory
local function makeTabContent()
    local f = Instance.new("Frame")
    f.Size                  = UDim2.new(1, 0, 1, 0)
    f.BackgroundTransparency= 1
    f.Visible               = false
    f.Parent                = WTabBody
    return f
end

-- ── Build sidebar layout ────────────────────────────────────
-- Wrap dalam do-block: _t,_t2,_t3,_t4 cuma kepake di loop ini → scope-isolate biar
-- ga makan slot register parent chunk (Luau limit 200)
do
-- GAMEPLAY section
makeSidebarLabel("GAMEPLAY", 16)
local _t = {
    {name="Survivor", y=40, heading="Survivor"},
    {name="Killer",   y=84, heading="Killer"},
}

-- VISUALS section
makeSidebarLabel("VISUALS", 138)
local _t2 = {
    {name="ESP",    y=162, heading="ESP"},
}

-- COMBAT section
makeSidebarLabel("COMBAT", 204)
local _t3 = {
    {name="Combat",   y=228, heading="Combat"},
}

-- MISC section
makeSidebarLabel("MISC", 270)
local _t4 = {
    {name="Misc", y=294, heading="Misc"},
}

local sidebarItems = {}
for _, t in ipairs(_t)  do table.insert(sidebarItems, t) end
for _, t in ipairs(_t2) do table.insert(sidebarItems, t) end
for _, t in ipairs(_t3) do table.insert(sidebarItems, t) end
for _, t in ipairs(_t4) do table.insert(sidebarItems, t) end

for _, t in ipairs(sidebarItems) do
    local content = makeTabContent()
    local item, setActive = makeSidebarItem(t.name, t.y)
    item.MouseButton1Click:Connect(function() switchTab(t.name) end)
    tabs[t.name] = {Item=item, Content=content, SetActive=setActive, Heading=t.heading}
end
end  -- ◀ END sidebar build do-block (frees 5 register slots)

-- ── User widget at bottom of sidebar — wrap juga (4 W* locals, closure-safe)
do
local WUser = Instance.new("Frame")
WUser.Size             = UDim2.new(1, -20, 0, 46)
WUser.Position         = UDim2.new(0, 10, 1, -58)
WUser.BackgroundColor3 = T.bgHeader
WUser.BorderSizePixel  = 0
WUser.Parent           = WSidebar
corner(WUser, 7)
stroke(WUser, T.borderLo, 1, 0.5)

local WUserDot = Instance.new("Frame")
WUserDot.Size             = UDim2.new(0, 8, 0, 8)
WUserDot.Position         = UDim2.new(0, 10, 0.5, -4)
WUserDot.BackgroundColor3 = T.success
WUserDot.BorderSizePixel  = 0
WUserDot.Parent           = WUser
corner(WUserDot, 4)

local WUserName = Instance.new("TextLabel")
WUserName.Size                   = UDim2.new(1, -28, 0, 14)
WUserName.Position               = UDim2.new(0, 24, 0, 6)
WUserName.BackgroundTransparency = 1
WUserName.Text                   = LP.DisplayName or LP.Name
WUserName.TextColor3             = T.textPri
WUserName.Font                   = Enum.Font.GothamBold
WUserName.TextSize               = 11
WUserName.TextXAlignment         = Enum.TextXAlignment.Left
WUserName.Parent                 = WUser

local WUserRole = Instance.new("TextLabel")
WUserRole.Size                   = UDim2.new(1, -28, 0, 12)
WUserRole.Position               = UDim2.new(0, 24, 0, 20)
WUserRole.BackgroundTransparency = 1
WUserRole.Text                   = "[" .. roleCache .. "] Violence..."
WUserRole.TextColor3             = T.textSec
WUserRole.Font                   = Enum.Font.Gotham
WUserRole.TextSize               = 9
WUserRole.TextXAlignment         = Enum.TextXAlignment.Left
WUserRole.Parent                 = WUser

-- Sync user widget role saat berubah (closure capture WUserRole as upvalue)
LP:GetPropertyChangedSignal("Team"):Connect(function()
    task.wait(0.1)
    WUserRole.Text = "[" .. (CFG.roleOverride and CFG.manualRole or roleCache) .. "] Violence..."
end)
end  -- ◀ END user widget do-block (frees 4 register slots)

-- ── Default active tab ─────────────────────────────────────
switchTab("Survivor")

-- ════════════════════════════════════════════════════════════
-- ▼ HIDE OLD UI + REROUTE MenuToggle/INSERT KE NEW WINDOW
-- ════════════════════════════════════════════════════════════
Panel.Visible = false  -- hide old menu panel
TpPanel.Visible = false  -- hide old TP panel (akan dipake di Teleport tab)

-- Reroute setPanelOpen ke new Window
setPanelOpen = function(open)
    Window.Visible = open
    MenuToggle.Text = open and "  ●  ARTHEIRS  ▾" or "  ●  ARTHEIRS  ▸"
end

-- Initial state: Window visible
Window.Visible = true

-- ════════════════════════════════════════════════════════════
-- ▼ STEP 2: TAB CONTENT (populate semua 6 tabs)
-- ════════════════════════════════════════════════════════════

-- Slider updater table (sync ke CFG)
local sliderUpdaters = {}

-- toggleEsp helper (sebelumnya inline di espBtn click handler)
local function toggleEsp()
    CFG.espEnabled = not CFG.espEnabled
    -- Update old hidden button (silent)
    if espBtn then
        espBtn.Text = "    [1]  ESP : " .. (CFG.espEnabled and "ON" or "OFF")
        setBtnAccent(espBtn, CFG.espEnabled and T.accent or T.danger)
    end
end

-- Wrapper: makeCheckbox yang bind ke CFG[cfgKey] + panggil toggleFn
local function makeCheckboxFor(parent, posY, label, cfgKey, toggleFn)
    return makeCheckbox(parent, posY, label,
        function() return CFG[cfgKey] end,
        function(v)
            if CFG[cfgKey] ~= v then
                toggleFn()
            end
        end)
end

-- ──────────────────────────────────────────────────────────
-- ▶ TAB: Survivor  (do...end wrap untuk hemat local register slots)
-- ──────────────────────────────────────────────────────────
do
local sTab = tabs["Survivor"].Content

makeSectionHeader(sTab, 0, "REPAIR")
-- Mini-do wraps untuk free local registers segera (hindari overflow di role buttons)
do
    local _, u = makeCheckboxFor(sTab, 38, "Auto Repair Generators",   "autoRepairEnabled", toggleAutoRepair)
    checkboxUpdaters.autoRepair = u
end
do
    local _, u = makeCheckboxFor(sTab, 92, "No Skill Check (auto-tap Space GREAT zone)", "noSkillCheckEnabled",
        function() CFG.noSkillCheckEnabled = not CFG.noSkillCheckEnabled end)
    checkboxUpdaters.noSkillCheck = u
end
do
    local _, u = makeCheckboxFor(sTab, 146, "Auto Escape (when killer near)", "autoEscapeEnabled", toggleAutoEscape)
    checkboxUpdaters.autoEscape = u
end

makeSectionHeader(sTab, 212, "RESCUE & HEAL")
do
    local _, u = makeCheckboxFor(sTab, 250, "Auto Rescue Hooked Teammate", "autoRescueEnabled",
        function() CFG.autoRescueEnabled = not CFG.autoRescueEnabled end)
    checkboxUpdaters.autoRescue = u
end
do
    local _, u = makeCheckboxFor(sTab, 304, "Auto Heal (self & team)", "autoHealEnabled",
        function() CFG.autoHealEnabled = not CFG.autoHealEnabled end)
    checkboxUpdaters.autoHeal = u
end
do
    local _, u = makeCheckboxFor(sTab, 358, "Auto Unhook Self", "autoUnhookEnabled",
        function() CFG.autoUnhookEnabled = not CFG.autoUnhookEnabled end)
    checkboxUpdaters.autoUnhook = u
end
do
    local _, u = makeCheckboxFor(sTab, 412, "Auto Parry (weapon RMB)", "autoParryEnabled",
        function() CFG.autoParryEnabled = not CFG.autoParryEnabled end)
    checkboxUpdaters.autoParry = u
end

makeSectionHeader(sTab, 476, "ROLE")
local roleLbl = Instance.new("TextLabel")
roleLbl.Size                   = UDim2.new(1, 0, 0, 18)
roleLbl.Position               = UDim2.new(0, 0, 0, 514)
roleLbl.BackgroundTransparency = 1
roleLbl.Text                   = "Current: " .. (CFG.roleOverride and ("Manual " .. CFG.manualRole) or ("Auto " .. roleCache))
roleLbl.TextColor3             = T.textPri
roleLbl.Font                   = Enum.Font.GothamMedium
roleLbl.TextSize               = 12
roleLbl.TextXAlignment         = Enum.TextXAlignment.Left
roleLbl.Parent                 = sTab

-- Role override: 3 button row (Auto / Survivor / Killer)
local function makeRoleBtn(text, posX, color, onClick)
    local b = Instance.new("TextButton")
    b.Size              = UDim2.new(0, 88, 0, 34)
    b.Position          = UDim2.new(0, posX, 0, 546)
    b.BackgroundColor3  = T.btnBase
    b.BorderSizePixel   = 0
    b.Text              = text
    b.TextColor3        = T.textSec
    b.Font              = Enum.Font.GothamBold
    b.TextSize          = 10
    b.AutoButtonColor   = false
    b.Parent            = sTab
    corner(b, 6)
    local s = stroke(b, T.borderLo, 1, 0.4)
    b.MouseEnter:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
    end)
    b.MouseLeave:Connect(function()
        tween(b, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
    end)
    b.MouseButton1Click:Connect(onClick)
    return b, s
end

local roleButtons = {}
local function updateRoleDisplay()
    roleLbl.Text = "Current: " .. (CFG.roleOverride and ("Manual " .. CFG.manualRole) or ("Auto " .. roleCache))
    -- Highlight selected button
    for key, data in pairs(roleButtons) do
        local active = (key == "Auto" and not CFG.roleOverride)
                    or (key == "Survivor" and CFG.roleOverride and CFG.manualRole == "Survivor")
                    or (key == "Killer"   and CFG.roleOverride and CFG.manualRole == "Killer")
        if active then
            tween(data.btn,   TWEEN_NORMAL, {BackgroundColor3 = data.color})
            tween(data.btn,   TWEEN_NORMAL, {TextColor3 = T.textPri})
            tween(data.stroke,TWEEN_NORMAL, {Color = data.color, Transparency = 0})
        else
            tween(data.btn,   TWEEN_NORMAL, {BackgroundColor3 = T.btnBase})
            tween(data.btn,   TWEEN_NORMAL, {TextColor3 = T.textSec})
            tween(data.stroke,TWEEN_NORMAL, {Color = T.borderLo, Transparency = 0.4})
        end
    end
end

local autoB, autoS = makeRoleBtn("AUTO", 0, T.accent, function()
    CFG.roleOverride = false
    updateRoleDisplay()
end)
local survB, survS = makeRoleBtn("SURVIVOR", 98, T.success, function()
    CFG.roleOverride = true
    CFG.manualRole = "Survivor"
    updateRoleDisplay()
end)
local killB, killS = makeRoleBtn("KILLER", 196, T.danger, function()
    CFG.roleOverride = true
    CFG.manualRole = "Killer"
    updateRoleDisplay()
end)
roleButtons.Auto     = {btn=autoB, stroke=autoS, color=T.accent}
roleButtons.Survivor = {btn=survB, stroke=survS, color=T.success}
roleButtons.Killer   = {btn=killB, stroke=killS, color=T.danger}
updateRoleDisplay()

-- Auto-update saat role berubah dari team detection
LP:GetPropertyChangedSignal("Team"):Connect(function()
    task.wait(0.1)
    if not CFG.roleOverride then updateRoleDisplay() end
end)

end  -- ◀ END Survivor tab scope

-- ──────────────────────────────────────────────────────────
-- ▶ TAB: Killer (placeholder)
-- ──────────────────────────────────────────────────────────
do
local kTab = tabs["Killer"].Content

makeSectionHeader(kTab, 0, "OFFENSIVE")
do
    local _, u = makeCheckboxFor(kTab, 38, "Auto-Attack (M1) — melee + facing", "autoAttackEnabled",
        function() CFG.autoAttackEnabled = not CFG.autoAttackEnabled end)
    checkboxUpdaters.autoAttack = u
end
do
    local _, u = makeCheckboxFor(kTab, 92, "Auto-Pickup Downed Survivor", "autoPickupEnabled",
        function() CFG.autoPickupEnabled = not CFG.autoPickupEnabled end)
    checkboxUpdaters.autoPickup = u
end
do
    local _, u = makeCheckboxFor(kTab, 146, "Auto-Hook (after carrying)", "autoHookEnabled",
        function() CFG.autoHookEnabled = not CFG.autoHookEnabled end)
    checkboxUpdaters.autoHook = u
end
do
    local _, u = makeCheckboxFor(kTab, 200, "Auto-Break Pallet", "autoBreakPalletEnabled",
        function() CFG.autoBreakPalletEnabled = not CFG.autoBreakPalletEnabled end)
    checkboxUpdaters.autoBreakPallet = u
end

makeSectionHeader(kTab, 264, "ANTI-COUNTER (best-effort)")
do
    local _, u = makeCheckboxFor(kTab, 302, "Anti-Pallet-Stun", "antiPalletStunEnabled",
        function() CFG.antiPalletStunEnabled = not CFG.antiPalletStunEnabled end)
    checkboxUpdaters.antiPalletStun = u
end
do
    local _, u = makeCheckboxFor(kTab, 356, "Anti-Flashlight-Blind", "antiFlashlightEnabled",
        function() CFG.antiFlashlightEnabled = not CFG.antiFlashlightEnabled end)
    checkboxUpdaters.antiFlashlight = u
end
do
    local _, u = makeCheckboxFor(kTab, 410, "Anti-Vault-Stun", "antiVaultStunEnabled",
        function() CFG.antiVaultStunEnabled = not CFG.antiVaultStunEnabled end)
    checkboxUpdaters.antiVaultStun = u
end
do
    local _, u = makeCheckboxFor(kTab, 464, "Anti-Shoot-Stun (survivor gun)", "antiShootStunEnabled",
        function() CFG.antiShootStunEnabled = not CFG.antiShootStunEnabled end)
    checkboxUpdaters.antiShootStun = u
end

makeSectionHeader(kTab, 528, "AWARENESS")
do
    local _, u = makeCheckboxFor(kTab, 566, "Generator Repair Activity (red highlight)", "genActivityEnabled",
        function() CFG.genActivityEnabled = not CFG.genActivityEnabled end)
    checkboxUpdaters.genActivity = u
end

end  -- ◀ END Killer tab scope

-- ──────────────────────────────────────────────────────────
-- ▶ TAB: ESP
-- ──────────────────────────────────────────────────────────
do
local eTab = tabs["ESP"].Content

makeSectionHeader(eTab, 0, "ESP TARGETS")
do
    local _, u = makeCheckboxFor(eTab, 38, "ESP Killer (merah)", "espKillerEnabled",
        function() CFG.espKillerEnabled = not CFG.espKillerEnabled end)
    checkboxUpdaters.espKiller = u
end
do
    local _, u = makeCheckboxFor(eTab, 92, "ESP Survivor (hijau / orange-HOOKED / kuning-DOWN)", "espSurvivorEnabled",
        function() CFG.espSurvivorEnabled = not CFG.espSurvivorEnabled end)
    checkboxUpdaters.espSurvivor = u
end
do
    local _, u = makeCheckboxFor(eTab, 146, "ESP Generator (kuning + progress %)", "espGeneratorEnabled",
        function() CFG.espGeneratorEnabled = not CFG.espGeneratorEnabled end)
    checkboxUpdaters.espGenerator = u
end
do
    local _, u = makeCheckboxFor(eTab, 200, "ESP Pallet (cyan)", "espPalletEnabled",
        function() CFG.espPalletEnabled = not CFG.espPalletEnabled end)
    checkboxUpdaters.espPallet = u
end

makeSectionHeader(eTab, 264, "VISUALS")
do
    local _, u = makeCheckboxFor(eTab, 302, "Fullbright", "fullbrightEnabled", toggleFullbright)
    checkboxUpdaters.fullbright = u
end

end  -- ◀ END ESP tab scope

-- ──────────────────────────────────────────────────────────
-- ▶ TAB: Misc (god mode + movement + abilities + teleport list)
-- ──────────────────────────────────────────────────────────
do
local mTab = tabs["Misc"].Content

makeSectionHeader(mTab, 0, "GENERAL")
do
    local _, u = makeCheckboxFor(mTab, 38, "God Mode (infinite health)", "godModeEnabled",
        function()
            CFG.godModeEnabled = not CFG.godModeEnabled
            local char = LP.Character
            if char then
                local hum = char:FindFirstChild("Humanoid")
                if hum then
                    if CFG.godModeEnabled then
                        pcall(function() hum.MaxHealth = 1e9; hum.Health = hum.MaxHealth end)
                    else
                        -- Aggressive reset: disconnect listener + force MaxHealth restore
                        if gmConn then pcall(function() gmConn:Disconnect() end); gmConn = nil end
                        pcall(function()
                            hum.MaxHealth = 100
                            hum.Health    = math.min(hum.Health, 100)
                        end)
                        -- Force-release semua mouse button kalau nyangkut dari interaksi godmode
                        pcall(function()
                            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)  -- LMB up
                            VIM:SendMouseButtonEvent(0, 0, 1, false, game, 0)  -- RMB up
                        end)
                        if rawget(getfenv(), "mouse1release") then pcall(mouse1release) end
                        if rawget(getfenv(), "mouse2release") then pcall(mouse2release) end
                        arHolding = false
                        -- Re-bind listener tapi state godmode off (siap kalau toggle on lagi)
                        task.wait(0.1)
                        bindGodMode()
                    end
                end
            end
        end)
    checkboxUpdaters.godMode = u
end

makeSectionHeader(mTab, 102, "MOVEMENT")
do
    local _, spdSlider = makeSlider(mTab, 140, "WalkSpeed", CFG.speedMin, CFG.speedMax, CFG.speedStep,
        function() return CFG.speedValue end,
        function(v)
            CFG.speedValue = v
            if speedValLbl then speedValLbl.Text = tostring(v) end
            if speedBtn    then updateSpeedDisplay() end
            if CFG.speedEnabled then
                local char = LP.Character
                if char then
                    local hum = char:FindFirstChild("Humanoid")
                    if hum then hum.WalkSpeed = v end
                end
            end
        end)
    sliderUpdaters.speed = spdSlider
end
do
    local _, u = makeCheckboxFor(mTab, 202, "Speed Enabled", "speedEnabled", toggleSpeed)
    checkboxUpdaters.speed = u
end

makeSectionHeader(mTab, 266, "ABILITIES")
do
    local _, u = makeCheckboxFor(mTab, 304, "Fly", "flyEnabled", toggleFly)
    checkboxUpdaters.fly = u
end
do
    local _, u = makeCheckboxFor(mTab, 358, "Noclip", "noclipEnabled", toggleNoclip)
    checkboxUpdaters.noclip = u
end

makeSectionHeader(mTab, 422, "CAMERA")
do
    local _, fovSlider = makeSlider(mTab, 460, "Field of View", CFG.fovMin, CFG.fovMax, CFG.fovStep,
        function() return CFG.fovValue end,
        function(v)
            CFG.fovValue = v
            pcall(function()
                local cam = workspace.CurrentCamera
                if cam then cam.FieldOfView = v end
            end)
        end)
    sliderUpdaters.fov = fovSlider

    -- Hold FOV terhadap game-side overrides; idle saat user pakai default
    RunService.RenderStepped:Connect(function()
        if CFG.fovValue == CFG.fovDefault then return end
        local cam = workspace.CurrentCamera
        if cam and math.abs(cam.FieldOfView - CFG.fovValue) > 0.05 then
            pcall(function() cam.FieldOfView = CFG.fovValue end)
        end
    end)
end

makeSectionHeader(mTab, 524, "PRIVACY")
do
    local _, u = makeCheckboxFor(mTab, 562, "Streamproof (invisible saat record)", "streamproofEnabled",
        function()
            CFG.streamproofEnabled = not CFG.streamproofEnabled
            if CFG._applyStreamproof then pcall(CFG._applyStreamproof) end
        end)
    checkboxUpdaters.streamproof = u
end

makeSectionHeader(mTab, 626, "TELEPORT TO PLAYER")

-- Container untuk player list (di-refresh saat player join/leave atau switchTab)
local tpContainer = Instance.new("Frame")
tpContainer.Size                  = UDim2.new(1, 0, 0, 240)
tpContainer.Position              = UDim2.new(0, 0, 0, 664)
tpContainer.BackgroundTransparency= 1
tpContainer.Parent                = mTab

local tpLayout = Instance.new("UIListLayout")
tpLayout.FillDirection = Enum.FillDirection.Vertical
tpLayout.Padding       = UDim.new(0, 6)
tpLayout.Parent        = tpContainer

local function refreshMiscTpList()
    for _, c in ipairs(tpContainer:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local btn = Instance.new("TextButton")
        btn.Size              = UDim2.new(1, -8, 0, 36)
        btn.BackgroundColor3  = T.btnBase
        btn.BorderSizePixel   = 0
        btn.Text              = "  " .. p.DisplayName
        btn.TextColor3        = T.textPri
        btn.Font              = Enum.Font.GothamMedium
        btn.TextSize          = 12
        btn.TextXAlignment    = Enum.TextXAlignment.Left
        btn.AutoButtonColor   = false
        btn.Parent            = tpContainer
        corner(btn, 6)
        local s = stroke(btn, T.borderLo, 1, 0.4)
        btn.MouseEnter:Connect(function()
            tween(btn, TWEEN_FAST, {BackgroundColor3 = T.btnHover})
            tween(s,   TWEEN_FAST, {Color = T.accent, Transparency = 0.1})
        end)
        btn.MouseLeave:Connect(function()
            tween(btn, TWEEN_FAST, {BackgroundColor3 = T.btnBase})
            tween(s,   TWEEN_FAST, {Color = T.borderLo, Transparency = 0.4})
        end)
        btn.MouseButton1Click:Connect(function() teleportTo(p) end)
    end
end

refreshMiscTpList()
Players.PlayerAdded:Connect(refreshMiscTpList)
Players.PlayerRemoving:Connect(refreshMiscTpList)

-- Hook switchTab biar refresh list pas pindah ke Misc
local _origSwitchTabMisc = switchTab
switchTab = function(name)
    _origSwitchTabMisc(name)
    if name == "Misc" then refreshMiscTpList() end
end

end  -- ◀ END Misc tab scope

-- ──────────────────────────────────────────────────────────
-- ▶ TAB: Combat
-- ──────────────────────────────────────────────────────────
do
local cTab = tabs["Combat"].Content

makeSectionHeader(cTab, 0, "AIMBOT")
local _, aimUpd = makeCheckboxFor(cTab, 38, "Aimbot (lock kamera ke target)", "aimbotEnabled", toggleAimbot)
checkboxUpdaters.aimbot = aimUpd

local _, fovSlider = makeSlider(cTab, 100, "FOV (pixel radius)", CFG.aimbotFOVMin, CFG.aimbotFOVMax, CFG.aimbotFOVStep,
    function() return CFG.aimbotFOV end,
    function(v)
        CFG.aimbotFOV = v
        if aimbotFovLbl then aimbotFovLbl.Text = tostring(v) end
        if aimbotBtn    then updateAimbotBtn() end
    end)
sliderUpdaters.aimbot = fovSlider

-- Info text
local aimInfo = Instance.new("TextLabel")
aimInfo.Size                   = UDim2.new(1, 0, 0, 16)
aimInfo.Position               = UDim2.new(0, 0, 0, 134)
aimInfo.BackgroundTransparency = 1
aimInfo.Text                   = "FOV ring visible at center screen when ON"
aimInfo.TextColor3             = T.textDim
aimInfo.Font                   = Enum.Font.Gotham
aimInfo.TextSize               = 10
aimInfo.TextXAlignment         = Enum.TextXAlignment.Left
aimInfo.Parent                 = cTab

end

-- ──────────────────────────────────────────────────────────
-- ▶ Teleport tab MOVED ke Misc tab (lihat above)
-- ──────────────────────────────────────────────────────────

-- ──────────────────────────────────────────────────────────
-- ▶ SYNC LOOP: keep checkbox + slider sync dgn CFG (untuk keybind triggers)
-- ──────────────────────────────────────────────────────────
do    
local syncMap = {
    esp          = "espEnabled",
    espKiller    = "espKillerEnabled",
    espSurvivor  = "espSurvivorEnabled",
    espGenerator = "espGeneratorEnabled",
    espPallet    = "espPalletEnabled",
    fly        = "flyEnabled",
    noclip     = "noclipEnabled",
    fullbright = "fullbrightEnabled",
    autoRepair = "autoRepairEnabled",
    autoEscape = "autoEscapeEnabled",
    autoRescue = "autoRescueEnabled",
    autoHeal   = "autoHealEnabled",
    autoUnhook = "autoUnhookEnabled",
    autoParry  = "autoParryEnabled",
    aimbot     = "aimbotEnabled",
    speed      = "speedEnabled",
    godMode    = "godModeEnabled",
    -- Killer
    autoAttack       = "autoAttackEnabled",
    autoPickup       = "autoPickupEnabled",
    autoHook         = "autoHookEnabled",
    autoBreakPallet  = "autoBreakPalletEnabled",
    antiPalletStun   = "antiPalletStunEnabled",
    antiFlashlight   = "antiFlashlightEnabled",
    antiVaultStun    = "antiVaultStunEnabled",
    antiShootStun    = "antiShootStunEnabled",
    genActivity      = "genActivityEnabled",
}
local lastSync = {}
task.spawn(function()
    while task.wait(0.1) do
        -- Checkboxes
        for name, key in pairs(syncMap) do
            local cur = CFG[key]
            if lastSync[name] ~= cur then
                lastSync[name] = cur
                local u = checkboxUpdaters[name]
                if u then u(cur) end
            end
        end
        -- Sliders
        if sliderUpdaters.speed and lastSync.speedValue ~= CFG.speedValue then
            lastSync.speedValue = CFG.speedValue
            sliderUpdaters.speed(CFG.speedValue)
        end
        if sliderUpdaters.aimbot and lastSync.aimbotFOV ~= CFG.aimbotFOV then
            lastSync.aimbotFOV = CFG.aimbotFOV
            sliderUpdaters.aimbot(CFG.aimbotFOV)
        end
    end
end)

end

-- Welcome toast pas script load
task.delay(0.5, function()
    showToast("ARTHEIRS SCRIPT LOADED ✓", "v2.0  ·  Violence District", 3.5)
end)

-- ============================================================
--  STEP 8: KEYBINDS
-- ============================================================
UIS.InputBegan:Connect(function(input, gameProcessed)
    local key = input.KeyCode

    -- ── Tombol 1/2/3 : blok saat mengetik di chat ──────────
    if not gameProcessed then
        if key == CFG.KEY_ESP then
            CFG.espEnabled = not CFG.espEnabled
            espBtn.Text    = "    [1]  ESP : " .. (CFG.espEnabled and "ON" or "OFF")
            setBtnAccent(espBtn, CFG.espEnabled and T.accent or T.danger)

        elseif key == CFG.KEY_TP then
            -- Switch ke Teleport tab + pastikan Window visible
            if not Window.Visible then
                Window.Visible = true
                MenuToggle.Text = "  ●  ARTHEIRS  ▾"
                panelOpen = true
            end
            switchTab("Teleport")

        elseif key == CFG.KEY_SPEED then
            toggleSpeed()

        elseif key == CFG.KEY_FLY then
            toggleFly()

        elseif key == CFG.KEY_NOCLIP then
            toggleNoclip()

        elseif key == CFG.KEY_FULLBRIGHT then
            toggleFullbright()

        elseif key == CFG.KEY_AUTOREPAIR then
            toggleAutoRepair()

        elseif key == CFG.KEY_AUTOESCAPE then
            toggleAutoEscape()

        elseif key == CFG.KEY_AIMBOT then
            toggleAimbot()
        end
    end

    -- ── Arrow keys : aktif kapanpun (tidak blok saat chat) ─
    -- Navigasi teleport (UP/DOWN) — hanya saat TP menu terbuka
    if key == Enum.KeyCode.Up and CFG.tpOpen and #tpList > 0 then
        local newIdx = tpSelIdx - 1
        if newIdx < 1 then newIdx = #tpList end
        updateTpHighlight(newIdx)

    elseif key == Enum.KeyCode.Down and CFG.tpOpen and #tpList > 0 then
        local newIdx = tpSelIdx + 1
        if newIdx > #tpList then newIdx = 1 end
        updateTpHighlight(newIdx)

    -- Konfirmasi teleport (ENTER) — hanya saat TP menu terbuka
    elseif key == Enum.KeyCode.Return and CFG.tpOpen then
        if tpList[tpSelIdx] then
            teleportTo(tpList[tpSelIdx].player)
        end

    -- Adjust speed (LEFT/RIGHT) — aktif kapanpun
    elseif key == Enum.KeyCode.Left then
        CFG.speedValue = math.max(CFG.speedMin, CFG.speedValue - CFG.speedStep)
        updateSpeedDisplay()

    elseif key == Enum.KeyCode.Right then
        CFG.speedValue = math.min(CFG.speedMax, CFG.speedValue + CFG.speedStep)
        updateSpeedDisplay()
    end
end)

-- ============================================================
--  STEP 9: INIT
-- ============================================================
print("[Artheirs] Script loaded ✓")
print("[Artheirs] Team  : " .. (LP.Team and LP.Team.Name or "nil (belum assign)"))
print("[Artheirs] Role  : " .. getRole())
print("[Artheirs] [1] ESP  |  [2] Teleport  |  [3] Speed  |  INSERT = Toggle Menu")
print("[Artheirs] [4] Fly  |  [5] Noclip   |  [6] Fullbright  |  [7] Auto Repair")
print("[Artheirs] [8] Auto Escape   |  [9] Aimbot")
print("[Artheirs] Teleport: UP/DOWN pilih, ENTER konfirmasi")
print("[Artheirs] Speed   : LEFT/RIGHT adjust nilai")
print("[Artheirs] Fly     : WASD = gerak, SPACE = naik, LCTRL = turun")
print("[Artheirs] AutoRepair: deket generator (<12 studs) → auto hold left mouse")
print("[Artheirs] AutoEscape: Survivor + AutoRepair ON + killer dekat → TP ke safest survivor")
print("[Artheirs] Aimbot  : lock kamera ke target dalam FOV pixel radius (adjust via menu)")
