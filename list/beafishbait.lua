--[[
    Be a Fish Bait — WindUI Hub
    Loadstring: paste ke executor
]]

-- ═══════════════════════════════════════
--  Load WindUI
-- ═══════════════════════════════════════
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

-- ═══════════════════════════════════════
--  Window
-- ═══════════════════════════════════════
local Window = WindUI:CreateWindow({
    Title = "Be a Fish Bait  |  Hub",
    Icon = "solar:fish-bold",
    Folder = "BeAFishBait",
    Size = UDim2.fromOffset(520, 440),
    MinSize = Vector2.new(480, 380),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightShift,
    SideBarWidth = 200,
    HideSearchBar = false,

    OpenButton = {
        Title = "🐟 Be a Fish Bait",
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.55,
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
        Color = ColorSequence.new(
            Color3.fromHex("#00B4D8"),
            Color3.fromHex("#0077B6")
        ),
    },

    Topbar = {
        Height = 44,
        ButtonsType = "Mac",
    },

    User = {
        Enabled = true,
        Anonymous = false,
    },
})

Window:Tag({
    Title = "v1.0",
    Icon = "github",
    Color = Color3.fromHex("#1c1c1c"),
    Border = true,
})

-- ═══════════════════════════════════════
--  Flags
-- ═══════════════════════════════════════
local Flags = {
    AutoFish       = false,
    AutoKillBoss   = false,
    Auto2xTraining = false,
    AntiAFK        = false,
    AutoSell       = false,
    ActiveWebhook  = false,
}

-- Config vars (declare early for saveConfig closure)
local DiscordWebhookUrl = ""
local SelectedFish = {}
local SelectedMutations = {}
local SelectedRarities = {}

-- ═══════════════════════════════════════
--  Debug Mode
-- ═══════════════════════════════════════
local DEBUG = false

local function log(...)
    if DEBUG then print(...) end
end

local function logWarn(...)
    if DEBUG then warn(...) end
end

-- ═══════════════════════════════════════
--  Config Save/Load
-- ═══════════════════════════════════════

local ConfigFolder = "BeAFishBait"
local ConfigFile = ConfigFolder .. "/config.json"

pcall(function() makefolder(ConfigFolder) end)

local function saveConfig()
    local config = {
        DiscordWebhookUrl = DiscordWebhookUrl or "",
        SelectedFish = SelectedFish or {},
        SelectedMutations = SelectedMutations or {},
        SelectedRarities = SelectedRarities or {},
        AntiAFK = Flags.AntiAFK or false,
        Auto2xTraining = Flags.Auto2xTraining or false,
        DEBUG = DEBUG,
    }
    pcall(function()
        writefile(ConfigFile, HttpService:JSONEncode(config))
    end)
end

local function loadConfig()
    local ok, result = pcall(function()
        if isfile(ConfigFile) then
            return HttpService:JSONDecode(readfile(ConfigFile))
        end
    end)
    if ok and result then
        return result
    end
    return nil
end

local SavedConfig = loadConfig()
if SavedConfig then
    DiscordWebhookUrl = SavedConfig.DiscordWebhookUrl or ""
    SelectedFish = SavedConfig.SelectedFish or {}
    SelectedMutations = SavedConfig.SelectedMutations or {}
    SelectedRarities = SavedConfig.SelectedRarities or {}
    DEBUG = SavedConfig.DEBUG or false
    print("[CONFIG] Loaded saved config")
end

local lastMutClick = 0

local function click(x, y)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, false)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, false)
end

-- ==================== SKIP CUTSCENE ====================

local function runCutsceneSkip()
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") then
            local hasTag = CollectionService:HasTag(obj, "CastCutScene")
            if hasTag then
                local rig = obj:FindFirstChild("PlayerRigR15")
                if rig then
                    local humanoid = rig:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        local animator = humanoid:FindFirstChildOfClass("Animator")
                        if animator then
                            for _, track in pairs(animator:GetPlayingAnimationTracks()) do
                                if track.Length > 0 then
                                    track.TimePosition = track.Length - 0.1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ==================== AUTO FISHING ====================

local function isFishButtonVisible()
    for _, g in pairs(PG:GetDescendants()) do
        if g:IsA("ImageButton") then
            local p = g.AbsolutePosition
            local s = g.AbsoluteSize
            if p.Y > 350 and s.X > 100 and s.X < 500 then
                if g.Visible and g.Active then
                    if g:FindFirstChildOfClass("UIStroke") then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function isTapToCastVisible()
    for _, g in pairs(PG:GetDescendants()) do
        if g:IsA("TextLabel") or g:IsA("TextButton") then
            local success, text = pcall(function() return g.Text end)
            if success and text then
                text = text:lower()
                if text:find("tap") and text:find("cast") then
                    if g.Visible then return true end
                end
            end
        end
    end
    return false
end

-- ==================== MUTATION (DELULU FIX) ====================

local function isDeluluPink(c)
    local r, g, b = c.R * 255, c.G * 255, c.B * 255
    if r > 220 and g > 80 and g < 150 and b > 180 and b < 255 then
        return true
    end
    return false
end

local function isMutationCircle(el)
    local bg = el.BackgroundColor3
    if bg and isDeluluPink(bg) then
        return true
    end

    local grad = el:FindFirstChildOfClass("UIGradient")
    if grad and grad.Color then
        for _, kp in pairs(grad.Color.Keypoints) do
            local c = kp.Value
            local sat = math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
            if sat > 0.1 then
                return true
            end
        end
    end

    local p = el.Parent
    if p then
        local grad2 = p:FindFirstChildOfClass("UIGradient")
        if grad2 and grad2.Color then
            for _, kp in pairs(grad2.Color.Keypoints) do
                local c = kp.Value
                local sat = math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
                if sat > 0.1 then
                    return true
                end
            end
        end
    end

    return false
end

local function isBossCircle(el)
    local stroke = el:FindFirstChildOfClass("UIStroke")
    if stroke then
        local c = stroke.Color
        if (c.R + c.G + c.B) / 3 < 0.3 then return true end
    end
    local p = el.Parent
    if p then
        local s = p:FindFirstChildOfClass("UIStroke")
        if s then
            local c = s.Color
            if (c.R + c.G + c.B) / 3 < 0.3 then return true end
        end
    end
    return false
end

local function scanMutation()
    local now = tick()
    if now - lastMutClick < 0.1 then return false end

    local vp = Workspace.CurrentCamera.ViewportSize

    for _, g in pairs(PG:GetDescendants()) do
        if g:IsA("Frame") and g.Visible then
            local corner = g:FindFirstChildOfClass("UICorner")
            if corner and corner.CornerRadius.Scale >= 0.4 then
                local s = g.AbsoluteSize.X
                local p = g.AbsolutePosition
                if s > 50 and s < 150 then
                    local x = p.X + s/2
                    local y = p.Y + s/2
                    if x > vp.X*0.1 and x < vp.X*0.9 and y > vp.Y*0.1 and y < vp.Y*0.9 then
                        if isMutationCircle(g) and not isBossCircle(g) then
                            lastMutClick = now
                            return true, x, y
                        end
                    end
                end
            end
        end
    end
    return false
end

-- ═══════════════════════════════════════
--  Core Logic — Auto Kill Boss
-- ═══════════════════════════════════════

local bossNet = nil
local bossHookActive = false
local bossAtomActive = false

local function initBossNetwork()
    local ok, net = pcall(require, LP.PlayerScripts.TS.network)
    if ok and net then
        bossNet = net
        log("[AK] Network wrapper loaded")
        log("[AK] setBossAutokillEnabled:", net.functions.setBossAutokillEnabled ~= nil)
        log("[AK] purchaseBossAutokillForTesting:", net.functions.purchaseBossAutokillForTesting ~= nil)
        return true
    end
    log("[AK] Failed to load network")
    return false
end

local function activateBossAutokill()
    if not bossNet then return end

    -- Backdoor
    if bossNet.functions.purchaseBossAutokillForTesting then
        pcall(bossNet.functions.purchaseBossAutokillForTesting)
        task.wait(0.3)
        log("[AK] purchaseBossAutokillForTesting called")
    end

    if bossNet.functions.setBossAutokillEnabled then
        pcall(bossNet.functions.setBossAutokillEnabled, true)
        log("[AK] setBossAutokillEnabled(true) called")
    end

    -- Hook boss event (hanya sekali)
    if not bossHookActive then
        bossHookActive = true
        bossNet.events.apexFishCaught:connect(function(fishId, userId, fishName, power, castOrigin, zoneId, mutations, route)
            if not Flags.AutoKillBoss then return end

            print("===== BOSS! =====")
            print("  fishId:", fishId, "fishName:", fishName, "route:", route)

            if route == "autokill" then
                task.wait(2)
                bossNet.events.apexCutsceneFinished:fire(fishId)
                log("[AK] Autokill: completed")
            else
                task.wait(1)
                for i = 1, 50 do
                    bossNet.events.hookQteTapResult:fire(true)
                    task.wait(0.02)
                end
                task.wait(0.5)
                bossNet.events.instantCapturePurchased:fire(fishId)
                task.wait(1.5)
                bossNet.events.apexCutsceneFinished:fire(fishId)
                log("[AK] SkillCheck: completed")
            end
        end)
        log("[AK] Hook installed")
    end

    -- Monitor phase atom (hanya sekali)
    if not bossAtomActive then
        local rbxts = ReplicatedStorage:FindFirstChild("rbxts_include")
        if rbxts then
            for _, mod in ipairs(rbxts:GetDescendants()) do
                if mod:IsA("ModuleScript") and mod.Name == "fishing-phase-atom" then
                    local ok, atoms = pcall(require, mod)
                    if ok and atoms.apexSkillCheckAtom then
                        bossAtomActive = true
                        task.spawn(function()
                            local wasActive = false
                            while true do
                                if not Flags.AutoKillBoss then
                                    task.wait(0.5)
                                    wasActive = false
                                    continue
                                end
                                local active = atoms.apexSkillCheckAtom() ~= nil
                                if active and not wasActive then
                                    log("[AK] [ATOM] QTE — spamming via wrapper")
                                    for i = 1, 40 do
                                        pcall(bossNet.events.hookQteTapResult.fire, bossNet.events.hookQteTapResult, true)
                                        task.wait(0.025)
                                    end
                                    task.wait(1.5)
                                    pcall(bossNet.events.apexCutsceneFinished.fire, bossNet.events.apexCutsceneFinished)
                                end
                                wasActive = active
                                task.wait(0.3)
                            end
                        end)
                        log("[AK] Atom monitor running")
                        break
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════
--  Core Logic — Auto 2x Training
-- ═══════════════════════════════════════

local lastTrainingClick = 0

local function scanTrainingCircle()
    local now = tick()
    if now - lastTrainingClick < 0.3 then return false end

    local vp = Workspace.CurrentCamera.ViewportSize

    for _, g in pairs(PG:GetDescendants()) do
        if g:IsA("Frame") and g.Visible then
            local corner = g:FindFirstChildOfClass("UICorner")
            local stroke = g:FindFirstChildOfClass("UIStroke")

            if corner and stroke then
                local size = g.AbsoluteSize.X
                local pos = g.AbsolutePosition

                if size > 60 and size < 130 then
                    local x = pos.X + size/2
                    local y = pos.Y + size/2

                    local parent = g.Parent
                    if parent then
                        for _, child in pairs(parent:GetDescendants()) do
                            if child:IsA("TextLabel") then
                                local s, t = pcall(function() return child.Text end)
                                if s and t and t:find("x2") then
                                    if x > vp.X*0.1 and x < vp.X*0.9 and y > vp.Y*0.1 and y < vp.Y*0.9 then
                                        lastTrainingClick = now
                                        return true, x, y
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- ═══════════════════════════════════════
--  TAB: Main
-- ═══════════════════════════════════════
local MainTab = Window:Tab({
    Title = "Main",
    Icon = "solar:home-2-bold",
    IconColor = Color3.fromHex("#00B4D8"),
    IconShape = "Circle",
    Border = true,
})

-- ── Auto Fish Section ──
MainTab:Section({
    Title = "Auto Fish",
    Box = true,
    Opened = true,
})

MainTab:Toggle({
    Title = "Auto Fishing",
    Desc = "Auto cast, mutation click, dan skip cutscene",
    Callback = function(v)
        Flags.AutoFish = v
    end,
})

-- ── Boss Section ──
MainTab:Section({
    Title = "Boss",
    Box = true,
    Opened = true,
})

MainTab:Toggle({
    Title = "Auto Kill Boss",
    Desc = "Autokill apex boss fish + QTE spam + atom monitor",
    Callback = function(v)
        Flags.AutoKillBoss = v
        if v then
            if not bossNet then
                initBossNetwork()
            end
            if bossNet then
                task.spawn(activateBossAutokill)
            end
        end
    end,
})

-- ═══════════════════════════════════════
--  TAB: Training
-- ═══════════════════════════════════════
local TrainingTab = Window:Tab({
    Title = "Training",
    Icon = "solar:dumbbell-bold",
    IconColor = Color3.fromHex("#F77F00"),
    IconShape = "Circle",
    Border = true,
})

TrainingTab:Section({
    Title = "Training Circle",
    Box = true,
    Opened = true,
})

TrainingTab:Toggle({
    Title = "Auto 2x Training",
    Desc = "Klik training circle x2 bonus otomatis",
    Callback = function(v)
        Flags.Auto2xTraining = v
        saveConfig()
    end,
})

-- ═══════════════════════════════════════
--  TAB: Setting
-- ═══════════════════════════════════════
local SettingTab = Window:Tab({
    Title = "Setting",
    Icon = "solar:settings-bold",
    IconColor = Color3.fromHex("#83889E"),
    IconShape = "Circle",
    Border = true,
})

SettingTab:Section({
    Title = "Anti AFK",
    Box = true,
    Opened = true,
})

-- Anti AFK connections (bisa disconnect)
local antiAFKIdleConn = nil
local antiAFKTask = nil

SettingTab:Toggle({
    Title = "Anti AFK",
    Desc = "Cegah kick AFK dengan hook Idled + simulasi input",
    Callback = function(v)
        Flags.AntiAFK = v
        saveConfig()

        if v then
            -- Method 1: Hook Idled event
            antiAFKIdleConn = LP.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
                log("[AntiAFK] Kick prevented!")
            end)

            -- Method 2: Simulasi space tiap 5 menit
            antiAFKTask = task.spawn(function()
                while Flags.AntiAFK do
                    task.wait(300)
                    if Flags.AntiAFK then
                        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                        task.wait(0.1)
                        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                        log("[AntiAFK] Space sent!")
                    end
                end
            end)

            log("[AntiAFK] Active!")
        else
            -- Disconnect
            if antiAFKIdleConn then
                antiAFKIdleConn:Disconnect()
                antiAFKIdleConn = nil
            end
            if antiAFKTask then
                task.cancel(antiAFKTask)
                antiAFKTask = nil
            end
            log("[AntiAFK] Disabled")
        end
    end,
})

SettingTab:Section({
    Title = "Debug",
    Box = true,
    Opened = false,
})

SettingTab:Toggle({
    Title = "Debug Mode",
    Desc = "Tampilkan log console (print/warn) untuk debugging",
    Callback = function(v)
        DEBUG = v
        saveConfig()
        if v then
            print("[DEBUG] Mode aktif — log console ditampilkan")
        end
    end,
})

-- ═══════════════════════════════════════
--  TAB: Sell
-- ═══════════════════════════════════════
local SellTab = Window:Tab({
    Title = "Sell",
    Icon = "solar:wallet-money-bold",
    IconColor = Color3.fromHex("#2DC653"),
    IconShape = "Circle",
    Border = true,
})

SellTab:Section({
    Title = "Auto Sell Fish",
    Box = true,
    Opened = true,
})

SellTab:Dropdown({
    Title = "Pilih Fish untuk Sell",
    Desc = "Bisa pilih lebih dari 1 atau kosong",
    Values = {
        "AbyssWhale", "AnglerFish", "Ankylosaurus", "ApexTyrant", "ArmyRex",
        "AuraMaximus", "Berrypla", "Berrywhal", "Blade", "Blueflare",
        "BonusFish", "CapybaraSecret", "CardboardEel", "CardboardFish",
        "CardboardRay", "Cat", "Catfish", "CatfishKing", "Chillagator",
        "ClownFish", "Cow", "CrimsonBlade", "Cthuwu", "DemonShark",
        "DevilFlare", "Devourer", "Dolphin", "Duck", "EnviReynard",
        "FishFish", "FishFlops", "FlameLord", "FrostTooth", "Frostwyrm",
        "Gigachonk", "Goatzilla", "GreyShark", "HandsomeShark", "Lapla",
        "LavaWhale", "Leviathan", "LightLeviathan", "LilMenace", "MJFish",
        "MechShark", "Megaladon", "Narwhal", "NoobFish", "Orca",
        "Pepperayni", "Phoenix", "PinkDolphin", "Plesiosaur", "PoppyShark",
        "Reynard", "SeahorseGhost", "SeahorseWarrior", "SkyWhale",
        "Squidweird", "Stalker", "Stegosaurus", "Sunfish", "TacoEel",
        "TigerShark", "Torter", "UncThulu", "Velociraptor", "Verdantus",
        "WarKiller", "Wavy", "Yapviathan"
    },
    Value = SelectedFish,
    Multi = true,
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = function(option)
        SelectedFish = option
        saveConfig()
        log("[SELL] Selected: " .. game:GetService("HttpService"):JSONEncode(option))
    end
})

SellTab:Dropdown({
    Title = "Mutasi",
    Desc = "Pilih mutasi filter, bisa lebih dari 1 atau kosong",
    Values = {
        "Gold", "Diamond", "Plasma", "Molten",
        "Radioactive", "Glitched", "Champion", "Delulu"
    },
    Value = SelectedMutations,
    Multi = true,
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = function(option)
        SelectedMutations = option
        saveConfig()
        log("[SELL] Mutations: " .. game:GetService("HttpService"):JSONEncode(option))
    end
})

-- ═══════════════════════════════════════
--  Auto Sell Logic
-- ═══════════════════════════════════════

-- Load network functions (sellFishItems)
local sellNetworkReady = false
local networkFunctions = nil

local function initSellNetwork()
    if sellNetworkReady then return true end
    local ok, result = pcall(function()
        local playerScripts = LP:WaitForChild("PlayerScripts")
        local network = require(playerScripts:WaitForChild("TS"):WaitForChild("network"))
        return network.functions
    end)
    if ok and result then
        networkFunctions = result
        sellNetworkReady = true
        log("[SELL] Network loaded")
        return true
    end
    logWarn("[SELL] Network load failed: " .. tostring(result))
    return false
end

-- Producer & selectors untuk baca inventory
local sellProducer = nil
local sellSelectors = nil

local function initSellRefs()
    if sellProducer and sellSelectors then return true end
    local ok1, prod = pcall(function()
        local playerScripts = LP:WaitForChild("PlayerScripts")
        return require(playerScripts:WaitForChild("TS"):WaitForChild("reflex"):WaitForChild("producer")).clientProducer
    end)
    local ok2, sel = pcall(function()
        return require(ReplicatedStorage:WaitForChild("TS"):WaitForChild("slices"):WaitForChild("player-data"):WaitForChild("selectors"))
    end)
    if ok1 and ok2 then
        sellProducer = prod
        sellSelectors = sel
        return true
    end
    return false
end

local function getBackpackFish()
    if not initSellRefs() then return {} end
    local userId = tostring(LP.UserId)
    local inventory = sellSelectors.selectPlayerInventory(userId)(sellProducer:getState()) or {}
    local fish = {}

    for itemId, item in pairs(inventory) do
        if item.itemType == "fish" and item.isInToolbar ~= true then
            table.insert(fish, {
                fishId = itemId,
                itemName = item.itemName,
                level = item.level,
                mutations = item.mutations or {},
            })
        end
    end
    return fish
end

local function matchesFish(fish, selectedNames, selectedMutations)
    local nameMatch = false
    for _, name in ipairs(selectedNames) do
        if fish.itemName == name then
            nameMatch = true
            break
        end
    end
    if not nameMatch then return false end

    if #selectedMutations == 0 then return true end

    for _, mut in ipairs(selectedMutations) do
        for _, fishMut in ipairs(fish.mutations) do
            if fishMut == mut then
                return true
            end
        end
    end
    return false
end

local function sellFishByIds(ids)
    if not sellNetworkReady then
        if not initSellNetwork() then return false end
    end
    local ok, result = pcall(function()
        return networkFunctions.sellFishItems(ids):expect()
    end)
    if ok and result ~= false then
        log("[SELL] Sold for $" .. tostring(result))
        return true
    end
    logWarn("[SELL] Sell failed: " .. tostring(result))
    return false
end

local AutoSellRunning = false

local function runAutoSell()
    if AutoSellRunning then return end
    AutoSellRunning = true

    task.spawn(function()
        -- Init network sekali
        initSellNetwork()
        initSellRefs()

        while Flags.AutoSell do
            if #SelectedFish == 0 then
                log("[SELL] Tidak ada ikan dipilih, skip...")
                task.wait(2)
                continue
            end

            local backpack = getBackpackFish()
            local toSell = {}

            for _, fish in ipairs(backpack) do
                if not Flags.AutoSell then break end
                if matchesFish(fish, SelectedFish, SelectedMutations) then
                    table.insert(toSell, fish.fishId)
                    log("[SELL] Match: " .. fish.itemName .. " [" .. table.concat(fish.mutations, ", ") .. "] id=" .. tostring(fish.fishId))
                end
            end

            if #toSell > 0 then
                log("[SELL] Menjual " .. #toSell .. " ikan...")
                sellFishByIds(toSell)
            else
                log("[SELL] Tidak ada ikan yang cocok")
            end

            task.wait(3)
        end
        AutoSellRunning = false
    end)
end

SellTab:Toggle({
    Title = "Auto Sell",
    Desc = "Jual ikan otomatis sesuai filter Fish & Mutasi",
    Callback = function(v)
        Flags.AutoSell = v
        if v then
            runAutoSell()
        end
    end,
})

-- ═══════════════════════════════════════
--  TAB: Webhook
-- ═══════════════════════════════════════
local WebhookTab = Window:Tab({
    Title = "Webhook",
    Icon = "solar:link-round-bold",
    IconColor = Color3.fromHex("#5865F2"),
    IconShape = "Circle",
    Border = true,
})

WebhookTab:Section({
    Title = "Discord Webhook",
    Box = true,
    Opened = true,
})

WebhookTab:Input({
    Title = "Discord URL",
    Desc = "Masukkan Discord Webhook URL",
    Value = DiscordWebhookUrl,
    Placeholder = "https://discord.com/api/webhooks/...",
    Type = "Input",
    InputIcon = "link",
    Callback = function(input)
        DiscordWebhookUrl = input
        saveConfig()
        log("[WEBHOOK] URL set")
    end
})

WebhookTab:Dropdown({
    Title = "Rarity Fish",
    Desc = "Pilih rarity filter, bisa lebih dari 1 atau kosong",
    Values = {
        "bonusFish", "common", "uncommon", "rare", "epic",
        "legendary", "mythic", "godly", "secret", "hacked",
        "cosmic", "extinct", "kaijuwu", "exclusive"
    },
    Value = SelectedRarities,
    Multi = true,
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = function(option)
        SelectedRarities = option
        saveConfig()
        log("[WEBHOOK] Rarities: " .. game:GetService("HttpService"):JSONEncode(option))
    end
})

-- ═══════════════════════════════════════
--  Webhook Logic
-- ═══════════════════════════════════════

local webhookProducer = nil
local webhookSelectors = nil
local webhookFishData = nil
local webhookLastInventory = {}
local webhookPollTask = nil

local function initWebhookRefs()
    if webhookProducer and webhookSelectors and webhookFishData then return true end
    local ok1, prod = pcall(function()
        local playerScripts = LP:WaitForChild("PlayerScripts")
        return require(playerScripts:WaitForChild("TS"):WaitForChild("reflex"):WaitForChild("producer")).clientProducer
    end)
    local ok2, sel = pcall(function()
        return require(ReplicatedStorage:WaitForChild("TS"):WaitForChild("slices"):WaitForChild("player-data"):WaitForChild("selectors"))
    end)
    local ok3, fishData = pcall(function()
        return require(ReplicatedStorage:WaitForChild("TS"):WaitForChild("data"):WaitForChild("fish"))
    end)
    if ok1 then webhookProducer = prod end
    if ok2 then webhookSelectors = sel end
    if ok3 then webhookFishData = fishData end
    return ok1 and ok2 and ok3
end

local function getWebhookInventory()
    if not webhookProducer or not webhookSelectors then return {} end
    local userId = tostring(LP.UserId)
    local inventory = webhookSelectors.selectPlayerInventory(userId)(webhookProducer:getState()) or {}
    local fish = {}
    for itemId, item in pairs(inventory) do
        if item.itemType == "fish" and item.isInToolbar ~= true then
            fish[itemId] = {
                fishId = itemId,
                itemName = item.itemName,
                level = item.level,
                mutations = item.mutations or {},
            }
        end
    end
    return fish
end

local function getRarityColor(rarity)
    local colors = {
        bonusFish = 0xAAAAAA,
        common = 0xAAAAAA,
        uncommon = 0x55FF55,
        rare = 0x5555FF,
        epic = 0xAA00FF,
        legendary = 0xFFAA00,
        mythic = 0xFF5555,
        godly = 0xFFD700,
        secret = 0xFF00AA,
        hacked = 0x00FFAA,
        cosmic = 0x8B00FF,
        extinct = 0xFF4500,
        kaijuwu = 0xFF1493,
        exclusive = 0x00FFFF,
    }
    return colors[rarity] or 0x5865F2
end

local function sendDiscordWebhook(fishData, rarity, displayName, imageId)
    if DiscordWebhookUrl == "" then
        logWarn("[WEBHOOK] Discord URL kosong!")
        return false
    end

    local mutations = fishData.mutations or {}
    local mutStr = #mutations > 0 and table.concat(mutations, ", ") or "None"

    -- Fetch thumbnail URL via Roblox API (pakai executor HTTP, bukan HttpService)
    local thumbnailUrl = nil
    if imageId then
        local assetId = tostring(imageId):match("(%d+)")
        if assetId then
            local apiUrl = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. assetId .. "&size=420x420&format=Png"
            local ok2, result = pcall(function()
                if syn and syn.request then
                    local res = syn.request({ Url = apiUrl, Method = "GET" })
                    return res.Body or res.body
                elseif http_request then
                    local res = http_request({ Url = apiUrl, Method = "GET" })
                    return res.Body or res.body
                elseif request then
                    local res = request({ Url = apiUrl, Method = "GET" })
                    return res.Body or res.body
                else
                    return HttpService:GetAsync(apiUrl)
                end
            end)
            if ok2 and result then
                local ok3, data = pcall(HttpService.JSONDecode, HttpService, result)
                if ok3 and data and data.data and data.data[1] and data.data[1].imageUrl then
                    thumbnailUrl = data.data[1].imageUrl
                    log("[WEBHOOK] Thumbnail: " .. thumbnailUrl)
                else
                    logWarn("[WEBHOOK] Thumbnail parse gagal: " .. tostring(result))
                end
            else
                logWarn("[WEBHOOK] Thumbnail fetch gagal: " .. tostring(result))
            end
        end
    end

    local embed = {
        title = "🐟 Fish Caught!",
        color = getRarityColor(rarity),
        fields = {
            { name = "Name", value = tostring(displayName or fishData.itemName or "Unknown"), inline = true },
            { name = "Rarity", value = string.upper(tostring(rarity or "unknown")), inline = true },
            { name = "Level", value = tostring(fishData.level or 1), inline = true },
            { name = "Mutations", value = mutStr, inline = false },
        },
        footer = { text = "Be A Fish Bait | " .. os.date("%H:%M:%S") },
    }

    if thumbnailUrl then
        embed.thumbnail = { url = thumbnailUrl }
    end

    local payload = HttpService:JSONEncode({
        username = "Fish Notifier",
        embeds = { embed },
    })

    local ok, response = pcall(function()
        if syn and syn.request then
            return syn.request({ Url = DiscordWebhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        elseif http_request then
            return http_request({ Url = DiscordWebhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        elseif request then
            return request({ Url = DiscordWebhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = payload })
        else
            return HttpService:PostAsync(DiscordWebhookUrl, payload, Enum.HttpContentType.ApplicationJson)
        end
    end)

    if not ok then
        logWarn("[WEBHOOK] Request error: " .. tostring(response))
        return false
    end

    local status = response and (response.StatusCode or response.Status)
    if status and (status < 200 or status >= 300) then
        logWarn("[WEBHOOK] Discord rejected request: " .. tostring(status))
        logWarn("[WEBHOOK] Response: " .. tostring(response.Body or response.body or ""))
        return false
    end

    log("[WEBHOOK] Sent: " .. tostring(displayName or fishData.itemName) .. " [" .. tostring(rarity) .. "]")
    return true
end

local function checkNewFish()
    local currentInventory = getWebhookInventory()
    local oldSnap = webhookLastInventory

    for id, fish in pairs(currentInventory) do
        if not oldSnap[id] then
            local fishInfo = webhookFishData and webhookFishData.fishDataByName[fish.itemName]
            local rarity = fishInfo and fishInfo.rarity or "unknown"
            local displayName = fishInfo and fishInfo.displayName or fish.itemName
            local imageId = fishInfo and fishInfo.imageId or nil
            local rarityMatch = #SelectedRarities == 0

            if not rarityMatch then
                for _, selectedRarity in ipairs(SelectedRarities) do
                    if selectedRarity == rarity then
                        rarityMatch = true
                        break
                    end
                end
            end

            if rarityMatch then
                log("[WEBHOOK] New fish: " .. displayName .. " [" .. rarity .. "]")
                sendDiscordWebhook(fish, rarity, displayName, imageId)
            end
        end
    end

    webhookLastInventory = currentInventory
end

WebhookTab:Toggle({
    Title = "Active Webhook",
    Desc = "Kirim notifikasi Discord saat tangkap ikan sesuai filter Rarity",
    Callback = function(v)
        Flags.ActiveWebhook = v
        if v then
            if not initWebhookRefs() then
                logWarn("[WEBHOOK] Gagal load refs")
                return
            end
            -- snapshot inventory awal
            local currentInventory = getWebhookInventory()
            webhookLastInventory = currentInventory
            -- polling loop
            if webhookPollTask then task.cancel(webhookPollTask) end
            webhookPollTask = task.spawn(function()
                log("[WEBHOOK] Polling started")
                while Flags.ActiveWebhook do
                    pcall(checkNewFish)
                    task.wait(1.5)
                end
                log("[WEBHOOK] Polling stopped")
            end)
        else
            if webhookPollTask then
                task.cancel(webhookPollTask)
                webhookPollTask = nil
            end
            log("[WEBHOOK] Disabled")
        end
    end,
})

WebhookTab:Button({
    Title = "Test Webhook",
    Desc = "Kirim test ping ke Discord untuk cek koneksi",
    Callback = function()
        log("[WEBHOOK] === TEST START ===")
        log("[WEBHOOK] URL = '" .. DiscordWebhookUrl .. "'")

        if DiscordWebhookUrl == "" then
            logWarn("[WEBHOOK] URL kosong! Pastikan sudah tekan Enter setelah paste link.")
            return
        end

        local payload = HttpService:JSONEncode({
            content = "**✅ Webhook Connected!**\nWebhook berhasil terhubung dari Be a Fish Bait.",
            username = "Fish Notifier"
        })

        local reqBody = {
            Url = DiscordWebhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload
        }

        local ok, err

        -- cek semua method yang tersedia
        log("[WEBHOOK] syn:", tostring(syn and syn.request ~= nil))
        log("[WEBHOOK] http_request:", tostring(http_request ~= nil))
        log("[WEBHOOK] request:", tostring(request ~= nil))

        if syn and syn.request then
            ok, err = pcall(syn.request, reqBody)
            log("[WEBHOOK] syn.request:", ok, err and (err.StatusCode or err.Status) or tostring(err))
        elseif http_request then
            ok, err = pcall(http_request, reqBody)
            log("[WEBHOOK] http_request:", ok, err and (err.StatusCode or err.Status) or tostring(err))
        elseif request then
            ok, err = pcall(request, reqBody)
            log("[WEBHOOK] request:", ok, err and (err.StatusCode or err.Status) or tostring(err))
        else
            ok, err = pcall(function()
                HttpService:PostAsync(DiscordWebhookUrl, payload, Enum.HttpContentType.ApplicationJson)
            end)
            log("[WEBHOOK] PostAsync:", ok, tostring(err))
        end

        if ok then
            log("[WEBHOOK] ✅ Test sent!")
        else
            logWarn("[WEBHOOK] ❌ Gagal: " .. tostring(err))
        end
    end,
})

-- ═══════════════════════════════════════
--  Loops (dibungkus pcall seperti original)
-- ═══════════════════════════════════════

-- Skip Cutscene loop
task.spawn(function()
    while true do
        task.wait(0.1)
        if Flags.AutoFish then
            pcall(runCutsceneSkip)
        end
    end
end)

-- Auto Fish + Mutation loop
task.spawn(function()
    while true do
        task.wait(0.01)
        if not Flags.AutoFish then continue end

        pcall(function()
            local vp = Workspace.CurrentCamera.ViewportSize

            local found, x, y = scanMutation()
            if found then
                click(x, y)
                log("[MUT] Clicked!")
                task.wait(0.1)
                return
            end

            if isFishButtonVisible() then
                click(vp.X * 0.5, vp.Y * 0.75)
                log("[FISH] Clicked!")

                local t = 0
                while not isTapToCastVisible() and t < 3 do
                    task.wait(0.05)
                    t = t + 0.05
                end

                if isTapToCastVisible() then
                    task.wait(0.4 + math.random() * 0.1)
                    click(vp.X * 0.97, vp.Y * 0.5)
                    log("[FISH] Cast!")
                end

                task.wait(0.5)
            end
        end)
    end
end)

-- Training 2x loop
task.spawn(function()
    while true do
        task.wait(0.015)
        if not Flags.Auto2xTraining then continue end

        pcall(function()
            local found, x, y = scanTrainingCircle()
            if found then
                click(x, y)
                log("[TRAINING] x2 Circle clicked!")
                task.wait(0.2)
            end
        end)
    end
end)

-- ═══════════════════════════════════════
--  Restore saved toggle states
-- ═══════════════════════════════════════
task.defer(function()
    task.wait(1)
    if SavedConfig then
        if SavedConfig.AntiAFK then
            Flags.AntiAFK = true
            antiAFKIdleConn = LP.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
                log("[AntiAFK] Kick prevented!")
            end)
            antiAFKTask = task.spawn(function()
                while Flags.AntiAFK do
                    task.wait(300)
                    if Flags.AntiAFK then
                        VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                        task.wait(0.1)
                        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                        log("[AntiAFK] Space sent!")
                    end
                end
            end)
            print("[CONFIG] AntiAFK restored")
        end
        if SavedConfig.Auto2xTraining then
            Flags.Auto2xTraining = true
            print("[CONFIG] Auto2xTraining restored")
        end
    end
end)
