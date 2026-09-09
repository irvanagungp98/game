-- Anime Dice | WindUI INSTANT Auto Roll + Auto Sell (MAX SPEED)
-- Run with a supported executor.
-- Menerima kunci dari Loader
local secret_key = ...

-- Jika kunci salah atau tidak ada (orang mencoba mengeksekusi manual), batalkan!
if secret_key ~= "KUNCI_RAHASIA_SCRIPT_SAYA_2026" then 
    return 
end

-- ==========================================
-- (Taruh kode script asli Anda di bawah sini)
-- ==========================================
print("Script berhasil dimuat secara aman!")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")

----------------------------------------------------------------
-- Persistent settings
----------------------------------------------------------------
local SETTINGS_FOLDER = "AnimeDice"
local SETTINGS_FILE = SETTINGS_FOLDER .. "/settings.json"
local defaultSettings = {
    autoRoll = false,
    autoSell = false,
    autoFarm = false,
    autoRebirth = false,
    autoBuyBestDice = false,
    autoClaimQuest = false,
    autoUpgrades = false,
    autoPotion = false,
    autoTrait = false,
    autoGrade = false,
    antiAfk = false,
    autoReconnect = false,
    fastTower = false,
    activeTower = false,
    equipBestTowerTeam = false,
    autoReceiveTrade = false,
    selectedRarities = { Common = true },
    chanceThreshold = 0,
    selectedPotions = { Luck = {}, Income = {}, Damage = {} },
    potionUseCount = 1,
    selectedTraitUnitKey = nil,
    selectedTraitNames = {},
    selectedGradeUnitKey = nil,
    selectedGradeNames = {},
    selectedTowerLevels = { Easy = true },
    webhookUrl = "",
    webhookRarities = {},
    activeWebhook = false,
}

local function copyTable(value)
    local result = {}
    for key, child in pairs(value) do
        result[key] = type(child) == "table" and copyTable(child) or child
    end
    return result
end

local settings = copyTable(defaultSettings)
if isfile and readfile and isfile(SETTINGS_FILE) then
    local ok, saved = pcall(function()
        return HttpService:JSONDecode(readfile(SETTINGS_FILE))
    end)
    if ok and type(saved) == "table" then
        for key, value in pairs(saved) do
            if defaultSettings[key] ~= nil and type(value) == type(defaultSettings[key]) then
                settings[key] = value
            end
        end
    end
    if type(saved) == "table" and type(saved.towerLevel) == "string" then
        settings.selectedTowerLevels = saved.towerLevel == "ALL"
            and { Easy = true, Medium = true, Hard = true, Infinity = true }
            or { [saved.towerLevel] = true }
    end
end

local function saveSettings()
    if not writefile then return end
    pcall(function()
        if makefolder and not (isfolder and isfolder(SETTINGS_FOLDER)) then
            makefolder(SETTINGS_FOLDER)
        end
        writefile(SETTINGS_FILE, HttpService:JSONEncode(settings))
    end)
end

-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- Require modules
local RollController = require(ReplicatedStorage.Framework.Features.Rolling.RollController)
local RollDice = ReplicatedStorage.Network.RollService.RF.RollDice
local BuffController = require(ReplicatedStorage.Framework.Features.Buffs.BuffController)
local EntryRegistry = require(ReplicatedStorage.Framework.Features.Inventory.EntryRegistry)
local Rarities = require(ReplicatedStorage.Framework.Other.Rarities)
local DataController = require(ReplicatedStorage.Framework.Features.Data.DataController)
local BoostController = require(ReplicatedStorage.Framework.Features.Inventory.Kinds.Boost.BoostController)
local Traits = require(ReplicatedStorage.Framework.Features.Traits.Traits)
local TraitRoll = ReplicatedStorage.Network.TraitService.RE.Roll
local Grades = require(ReplicatedStorage.Framework.Features.Grades.Grades)
local GradeRoll = ReplicatedStorage.Network.GradeService.RE.Roll
local NumberFormatter = require(ReplicatedStorage.Packages.NumberFormatter)
local Rebirths = require(ReplicatedStorage.Framework.Features.Rebirth.Rebirths)
local RebirthEvent = ReplicatedStorage.Network.RebirthService.RE.Rebirth
local Dice = require(ReplicatedStorage.Framework.Features.Rolling.Dice)
local Network = require(ReplicatedStorage.Packages.Network)
local BuyDiceSignal = Network.ClientComm.new(ReplicatedStorage.Network, false, "DiceShopService"):GetSignal("BuyDice")
local QuestConfig = require(ReplicatedStorage.Framework.Features.Quests.QuestConfig)
local ClaimQuestEvent = ReplicatedStorage.Network.QuestService.RE.Claim
local SellUtil = require(ReplicatedStorage.Framework.Features.Selling.SellUtil)
local ViewportUtil = require(ReplicatedStorage.Framework.Utils.ViewportUtil)
local Upgrades = require(ReplicatedStorage.Framework.Features.Upgrades.Upgrades)
local UpgradeTree = require(ReplicatedStorage.Framework.Features.Upgrades.TreeStructure)
local BuyUpgradeEvent = ReplicatedStorage.Network.RE.BuyUpgrade

-- Sell modules
local SellService = ReplicatedStorage.Network.SellService
local SellInventory = SellService.RF.SellInventory

----------------------------------------------------------------
-- HOOK: Roll Duration → 0.1s
----------------------------------------------------------------
local ROLL_DURATION_MIN = 0.1
local oldGetBuff = BuffController.GetBuff
BuffController.GetBuff = function(buffName)
    if buffName == "Roll Duration" then
        return ROLL_DURATION_MIN
    end
    return oldGetBuff(buffName)
end

if hookmetamethod then
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "GetBuff" and self == BuffController then
                local args = {...}
                if args[1] == "Roll Duration" then
                    return ROLL_DURATION_MIN
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
end

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local isAutoRolling = false
local isAutoSelling = false
local isAutoFarming = false
local isAutoRebirthing = false
local autoRebirthToken = 0
local isAutoBuyingBestDice = false
local autoBuyBestDiceToken = 0
local isAutoClaimingQuest = false
local autoClaimQuestToken = 0
local isAutoUpgrading = false
local autoUpgradeToken = 0
local activeRolls = 0
local MAX_PARALLEL = 8
local selectedRarities = settings.selectedRarities
local chanceThreshold = settings.chanceThreshold
local function selectionValues(selection)
    local values = {}
    for name, enabled in pairs(selection) do
        if enabled then table.insert(values, name) end
    end
    table.sort(values)
    return values
end

local uiReady = false
local autoSellToken = 0
local autoSellBusy = false
local isAutoUsingPotion = false
local autoPotionToken = 0
local potionUseCount = settings.potionUseCount
local selectedPotions = settings.selectedPotions
local nextPotionRequestAt = {}
local isAutoTraiting = false
local autoTraitToken = 0
local selectedTraitUnitKey = settings.selectedTraitUnitKey
local selectedTraitNames = settings.selectedTraitNames
local traitUnitByLabel = {}
local TraitUnitDropdown
local TraitStatus
local isAutoGrading = false
local autoGradeToken = 0
local selectedGradeUnitKey = settings.selectedGradeUnitKey
local selectedGradeNames = settings.selectedGradeNames
local gradeUnitByLabel = {}
local GradeUnitDropdown
local GradeStatus
local webhookUrl = settings.webhookUrl
local selectedWebhookRarities = settings.webhookRarities
local isWebhookActive = settings.activeWebhook
local webhookQueue = {}
local webhookWorkerRunning = false
local executorRequest = request or http_request or (syn and syn.request)
local screenshotFunctions = {}
local function addScreenshotFunction(name, candidate)
    if type(candidate) == "function" then
        table.insert(screenshotFunctions, { name = name, capture = candidate })
    end
end
addScreenshotFunction("getrenderimage", getrenderimage)
addScreenshotFunction("getscreenshot", getscreenshot)
addScreenshotFunction("screenshot", screenshot)
addScreenshotFunction("syn.getscreenshot", syn and syn.getscreenshot)
addScreenshotFunction("take_screenshot", take_screenshot)
addScreenshotFunction("capture_screen", capture_screen)
local WebhookStatus

local function setWebhookStatus(text)
    if WebhookStatus then WebhookStatus:SetDesc(text) end
end
local executorCrypt = crypt or (syn and syn.crypt)
local base64Decode = (executorCrypt and executorCrypt.base64 and executorCrypt.base64.decode)
    or (executorCrypt and executorCrypt.base64decode)
    or base64_decode
    or base64decode

-- Parse chance string: "1m" → 1000000, "1.2m" → 1200000, "500k" → 500000
local function parseChance(str)
    if type(str) == "number" then return str end
    if not str or str == "" then return 0 end
    str = str:lower():gsub(",", ""):gsub("%s+", "")

    local num, suffix = str:match("^([%d%.]+)(.*)$")
    if not num then return 0 end
    num = tonumber(num)
    if not num then return 0 end

    if suffix == "k" then return num * 1000
    elseif suffix == "m" then return num * 1000000
    elseif suffix == "b" then return num * 1000000000
    elseif suffix == "t" then return num * 1000000000000
    elseif suffix == "q" then return num * 1000000000000000
    else return num end
end

local function normalizeSelection(value)
    local selection = {}
    if type(value) == "string" then
        selection[value] = true
    elseif type(value) == "table" then
        local source = type(value.Value) == "table" and value.Value or value
        for key, selected in pairs(source) do
            if type(key) == "number" and type(selected) == "string" then
                selection[selected] = true
            elseif type(key) == "string" and selected == true then
                selection[key] = true
            end
        end
    end
    return selection
end

local potionLists = {
    Luck = {},
    Income = {},
    Damage = {},
}

for name, config in pairs(EntryRegistry.entriesOfKind("Boost")) do
    for category, list in pairs(potionLists) do
        if string.find(config.category, category, 1, true) then
            table.insert(list, name)
            break
        end
    end
end

for _, list in pairs(potionLists) do
    table.sort(list)
end

local function potionIsActiveOrQueued(name)
    local active = DataController.ActiveEntries[name]()
    if not active then return false end

    if type(active.startedAt) ~= "number" then
        return true
    end

    return type(active.remaining) == "number"
        and active.remaining > workspace:GetServerTimeNow() - active.startedAt
end

local function useSelectedPotions()
    local now = os.clock()
    local inventory = DataController.Inventory()

    for category, selection in pairs(selectedPotions) do
        for _, name in ipairs(potionLists[category]) do
            if selection[name]
                and now >= (nextPotionRequestAt[name] or 0)
                and not potionIsActiveOrQueued(name)
            then
                local entry = inventory[name]
                local useCount = entry and math.min(potionUseCount, entry.amount) or 0

                if useCount > 0 then
                    nextPotionRequestAt[name] = now + 2
                    for _ = 1, useCount do
                        BoostController.UseBoost(name)
                    end
                end
            end
        end
    end
end

local function setAutoUsingPotion(enabled)
    autoPotionToken = autoPotionToken + 1
    local token = autoPotionToken
    isAutoUsingPotion = enabled
    if not enabled then return end

    task.spawn(function()
        while isAutoUsingPotion and autoPotionToken == token do
            useSelectedPotions()
            task.wait(0.5)
        end
    end)
end

local function sellMatchingUnits()
    if not isAutoSelling or autoSellBusy or not next(selectedRarities) then return end
    autoSellBusy = true

    local ok = pcall(function()
        local DataController = require(ReplicatedStorage.Framework.Features.Data.DataController)
        local inventory = DataController.Inventory()
        local plottedUnits = {}

        for _, slot in pairs(DataController.Slots()) do
            if slot.unitId then
                plottedUnits[slot.unitId] = true
            end
        end

        local keysToSell = {}
        for key, item in pairs(inventory) do
            local attributes = item and item.attributes
            if item and item.amount > 0 and attributes and not attributes.locked and not plottedUnits[key] then
                local config = EntryRegistry.getEntryConfig(item.name)
                if config and config.kind == "Unit" and selectedRarities[config.getRarity(attributes)] then
                    local unitChance = config.chance and config.chance(attributes) or 0
                    if chanceThreshold == 0 or unitChance < chanceThreshold then
                        table.insert(keysToSell, key)
                    end
                end
            end
        end

        if #keysToSell > 0 then
            SellInventory:InvokeServer(keysToSell)
        end
    end)

    autoSellBusy = false
    return ok
end

local function setAutoSelling(enabled)
    autoSellToken = autoSellToken + 1
    local token = autoSellToken
    isAutoSelling = enabled

    if not enabled then return end

    task.spawn(function()
        while isAutoSelling and autoSellToken == token do
            sellMatchingUnits()
            task.wait(0.25)
        end
    end)
end
----------------------------------------------------------------
-- WEBHOOK
----------------------------------------------------------------
local rarityColors = {
    Common = 0xADADAD,
    Uncommon = 0x31D100,
    Rare = 0x0064FF,
    Epic = 0x5000FC,
    Legendary = 0xFFAA00,
    Mythical = 0xFF0000,
    Divine = 0x4800FF,
    Exotic = 0x00E5FF,
    Celestial = 0xFF3CB4,
    ["Secret I"] = 0x7D3CFF,
    ["Secret II"] = 0x3C007D,
    Exclusive = 0xE97BFF,
}

local function validWebhookUrl(url)
    return type(url) == "string"
        and url:match("^https://[^/]*discord%.com/api/webhooks/%d+/[%w%-%_]+") ~= nil
end

local function postWebhook(payload, image)
    if not executorRequest then
        return false, "Executor does not support HTTP requests."
    end
    if not validWebhookUrl(webhookUrl) then
        return false, "Enter a valid Discord webhook URL."
    end

    local requestData
    if image then
        local boundary = "AnimeDice" .. HttpService:GenerateGUID(false):gsub("-", "")
        local payloadJson = HttpService:JSONEncode(payload)
        requestData = {
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
            Body = table.concat({
                "--", boundary, "\r\n",
                "Content-Disposition: form-data; name=\"payload_json\"\r\n",
                "Content-Type: application/json\r\n\r\n",
                payloadJson, "\r\n--", boundary, "\r\n",
                "Content-Disposition: form-data; name=\"files[0]\"; filename=\"" .. image.filename .. "\"\r\n",
                "Content-Type: " .. image.contentType .. "\r\n\r\n",
                image.bytes, "\r\n--", boundary, "--\r\n",
            }),
        }
    else
        requestData = {
            Url = webhookUrl,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload),
        }
    end

    local ok, response = pcall(executorRequest, requestData)
    if not ok then return false, tostring(response) end
    local status = response and tonumber(response.StatusCode or response.Status)
    return status == 200 or status == 204, "HTTP " .. tostring(status or "unknown")
end

local function detectImage(bytes)
    if type(bytes) ~= "string" then return nil end
    if bytes:sub(1, 8) == "\137PNG\r\n\26\n" then
        return { bytes = bytes, filename = "unit.png", contentType = "image/png" }
    end
    if bytes:sub(1, 3) == "\255\216\255" then
        return { bytes = bytes, filename = "unit.jpg", contentType = "image/jpeg" }
    end
end

local function normalizeImage(output)
    if type(output) == "table" then
        output = output.data or output.Data or output.body or output.Body or output.path or output.Path
    end
    if type(output) ~= "string" then return nil end
    local image = detectImage(output)
    if image then return image end
    if isfile and readfile and isfile(output) then
        image = detectImage(readfile(output))
        if image then return image end
    end
    local encoded = output:match("^data:image/[%w%+%-%.]+;base64,(.+)$") or output
    if base64Decode then
        local ok, bytes = pcall(base64Decode, encoded)
        if ok then return detectImage(bytes) end
    end
end
local function captureUnitImage(config, attributes)
    if not config or not config.model then return nil, "Unit model is unavailable." end
    if #screenshotFunctions == 0 then return nil, "Executor exposes no screenshot API." end

    local parent = gethui and gethui() or LocalPlayer:WaitForChild("PlayerGui")
    local screen = Instance.new("ScreenGui")
    screen.Name = "AnimeDiceWebhookCapture"
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 2147483647
    screen.Parent = parent

    local background = Instance.new("Frame")
    background.Size = UDim2.fromScale(1, 1)
    background.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
    background.BorderSizePixel = 0
    background.Parent = screen

    local viewport = Instance.new("ViewportFrame")
    viewport.AnchorPoint = Vector2.new(0.5, 0.5)
    viewport.Position = UDim2.fromScale(0.5, 0.5)
    viewport.Size = UDim2.fromScale(0.72, 0.82)
    viewport.BackgroundTransparency = 1
    viewport.Ambient = Color3.fromRGB(200, 200, 210)
    viewport.LightColor = Color3.new(1, 1, 1)
    viewport.LightDirection = Vector3.new(-1, -1, -1)
    viewport.Parent = background

    ViewportUtil.ApplyModelToViewport(viewport, config.model(attributes))
    game:GetService("RunService").RenderStepped:Wait()
    game:GetService("RunService").RenderStepped:Wait()

    local image
    local errors = {}
    for _, provider in ipairs(screenshotFunctions) do
        local outputPath = SETTINGS_FOLDER .. "/unit-capture.png"
        local ok, output = pcall(provider.capture, outputPath)
        if ok then image = normalizeImage(output) or normalizeImage(outputPath) end
        if not image then
            local retryOk, retryOutput = pcall(provider.capture)
            if retryOk then image = normalizeImage(retryOutput) or normalizeImage(outputPath) end
            if not ok and not retryOk then
                table.insert(errors, provider.name .. " failed: " .. tostring(output) .. " / " .. tostring(retryOutput))
            else
                table.insert(errors, provider.name .. " returned no PNG/JPEG data")
            end
        end
        if image then break end
    end
    screen:Destroy()
    return image, image and nil or table.concat(errors, "; ")
end

local function unitWebhookPayload(name, rarity, mutation, chance, price, image)
    local embed = {
        title = "New Unit Obtained",
        description = "A new unit has been added to **" .. LocalPlayer.DisplayName .. "'s** inventory.",
        color = rarityColors[rarity] or 0x5865F2,
        fields = {
            { name = "Name", value = tostring(name), inline = true },
            { name = "Rarity", value = tostring(rarity), inline = true },
            { name = "Mutation", value = tostring(mutation or "None"), inline = true },
            { name = "Chance", value = chance and ("1 in " .. NumberFormatter.FormatCompact(chance, 2)) or "Limited", inline = true },
            { name = "Unit Price", value = "$" .. NumberFormatter.FormatCompact(price), inline = true },
        },
        footer = { text = "Anime Dice • " .. LocalPlayer.Name },
        timestamp = DateTime.now():ToIsoDate(),
    }
    if image then embed.image = { url = "attachment://" .. image.filename } end
    return { username = "Anime Dice", embeds = { embed } }
end

local function startWebhookWorker()
    if webhookWorkerRunning then return end
    webhookWorkerRunning = true
    task.spawn(function()
        while #webhookQueue > 0 do
            local item = table.remove(webhookQueue, 1)
            local image, captureError = captureUnitImage(item.config, item.attributes)
            local ok, postStatus = postWebhook(unitWebhookPayload(item.name, item.rarity, item.mutation, item.chance, item.price, image), image)
            if image and ok then
                setWebhookStatus("Last delivery: " .. item.name .. " with image (" .. #image.bytes .. " bytes).")
            elseif not image then
                setWebhookStatus("Image unavailable: " .. tostring(captureError))
            else
                setWebhookStatus("Discord upload failed: " .. tostring(postStatus))
            end
            task.wait(0.4)
        end
        webhookWorkerRunning = false
    end)
end

local function queueRollWebhooks(results)
    if not isWebhookActive or not validWebhookUrl(webhookUrl) then return end
    for _, result in ipairs(results) do
        local name = result.result
        local mutation = result.mutation
        local config = name and EntryRegistry.getEntryConfig(name)
        if config and config.kind == "Unit" then
            local attributes = { level = 1, mutation = mutation }
            local rarity = config.getRarity(attributes)
            if selectedWebhookRarities[rarity] then
                table.insert(webhookQueue, {
                    name = name,
                    mutation = mutation or "None",
                    rarity = rarity,
                    chance = config.chance and config.chance(attributes) or nil,
                    price = SellUtil.GetSellPrice(name, attributes),
                    config = config,
                    attributes = attributes,
                })
            end
        end
    end
    startWebhookWorker()
end

----------------------------------------------------------------
-- Hook roll function
----------------------------------------------------------------
local rollFunc = RollController.Roll

----------------------------------------------------------------
-- INSTANT ROLL
----------------------------------------------------------------
local function instantRoll()
    if activeRolls >= MAX_PARALLEL then return end
    activeRolls = activeRolls + 1

    task.spawn(function()
        local results, luck, rollCount, isCutscene, spinName = RollDice:InvokeServer()

        if results and #results > 0 then
            if rollFunc then
                pcall(rollFunc, results, luck, rollCount, true, spinName)
            end

            queueRollWebhooks(results)

        end

        activeRolls = activeRolls - 1
    end)
end

----------------------------------------------------------------
-- AUTO ROLL - MAX SPEED
----------------------------------------------------------------
local function startAutoRoll()
    for i = 1, MAX_PARALLEL do
        task.spawn(instantRoll)
    end

    task.spawn(function()
        while isAutoRolling do
            if activeRolls < MAX_PARALLEL then
                instantRoll()
            end
            task.wait()
        end
    end)
end

local function stopAutoRoll()
    isAutoRolling = false
    activeRolls = 0
end

----------------------------------------------------------------
-- AUTO FARMING - collect money from all slots (NO ANIMATION)
----------------------------------------------------------------
local CollectBalance = ReplicatedStorage.Network.PlotService.RE.CollectBalance
local PlotConfig = require(ReplicatedStorage.Framework.Features.Plot.PlotConfig)

-- Hide money animations while auto-farming.
-- Intercept parts parented to workspace.Debris before animation starts.
local function startMoneyBlocker()
    pcall(function()
        -- Hook Parent property via metatable
        local mt = getrawmetatable(game)
        local oldIndex = mt.__newindex

        setreadonly(mt, false)
        mt.__newindex = newcclosure(function(self, key, value)
            if isAutoFarming and key == "Parent" and typeof(value) == "Instance" then
                -- Detect money parts parented to Debris.
                if self:IsA("Part") and value.Name == "Debris" then
                    -- Hide before animation starts.
                    self.Transparency = 1
                    self.CanCollide = false
                    self.CanQuery = false
                    self.CanTouch = false
                    self.CastShadow = false

                    -- Disable trail & billboard
                    for _, child in ipairs(self:GetDescendants()) do
                        if child:IsA("Trail") then
                            child.Enabled = false
                        end
                        if child:IsA("BillboardGui") then
                            child.Enabled = false
                        end
                    end
                end
            end

            return oldIndex(self, key, value)
        end)
        setreadonly(mt, true)
    end)
end

-- MoneyController parents a cloned "Cash" CanvasGroup directly under Root.
-- Hide only that clone; HUD.Cash remains untouched inside HUD.
local cashAnimationConnection

local function removeCashAnimation(instance)
    if isAutoFarming and instance.Name == "Cash" and instance:IsA("CanvasGroup") then
        instance.Visible = false
        instance.GroupTransparency = 1
    end
end

local function startCashAnimationBlocker()
    local root = LocalPlayer.PlayerGui:WaitForChild("Root")

    for _, child in ipairs(root:GetChildren()) do
        removeCashAnimation(child)
    end

    if not cashAnimationConnection then
        cashAnimationConnection = root.ChildAdded:Connect(removeCashAnimation)
    end
end

local function startAutoFarming()
    startMoneyBlocker()
    startCashAnimationBlocker()

    task.spawn(function()
        while isAutoFarming do
            pcall(function()
                local DataController = require(ReplicatedStorage.Framework.Features.Data.DataController)
                local maxSlots = PlotConfig.GetMaxSlots()

                for slotId = 1, maxSlots do
                    if not isAutoFarming then break end

                    if DataController.Rebirth() >= PlotConfig.GetSlotRebirthRequirement(slotId) then
                        local slotData = DataController.Slots[tostring(slotId)]()
                        if slotData and slotData.balance > 0 then
                            CollectBalance:FireServer(slotId)
                        end
                    end
                end
            end)
            task.wait(1)
        end
    end)
end

local function stopAutoFarming()
    isAutoFarming = false
end

----------------------------------------------------------------
-- AUTO REBIRTH
----------------------------------------------------------------
local function setAutoRebirthing(enabled)
    autoRebirthToken = autoRebirthToken + 1
    isAutoRebirthing = enabled

    if not enabled then return end

    local token = autoRebirthToken
    task.spawn(function()
        while isAutoRebirthing and token == autoRebirthToken do
            local currentRebirth = DataController.Rebirth()
            local nextRebirth = Rebirths.GetNext(currentRebirth)

            if nextRebirth and DataController.Money() >= nextRebirth.cost then
                RebirthEvent:FireServer()
            end

            task.wait(0.5)
        end
    end)
end

----------------------------------------------------------------
-- AUTO BUY BEST DICE
----------------------------------------------------------------
local function getBestAffordableUnownedDice()
    local money = DataController.Money()
    local bestName
    local bestLuck = -math.huge

    for name, config in pairs(Dice.GetAll()) do
        if config.price and config.price <= money and not DataController.OwnedDice[name]() and config.luck > bestLuck then
            bestName = name
            bestLuck = config.luck
        end
    end

    return bestName
end

local function setAutoBuyingBestDice(enabled)
    autoBuyBestDiceToken = autoBuyBestDiceToken + 1
    isAutoBuyingBestDice = enabled

    if not enabled then return end

    local token = autoBuyBestDiceToken
    task.spawn(function()
        while isAutoBuyingBestDice and token == autoBuyBestDiceToken do
            local diceName = getBestAffordableUnownedDice()

            if diceName then
                BuyDiceSignal:Fire(diceName)
            end

            task.wait(0.5)
        end
    end)
end

----------------------------------------------------------------
-- AUTO CLAIM QUEST
----------------------------------------------------------------
local function getClaimableQuest()
    local now = workspace:GetServerTimeNow()

    for _, periodName in ipairs({ "Daily", "Weekly" }) do
        local periodData = DataController.Quests[periodName]()

        if periodData.expiresAt > now then
            for _, quest in ipairs(QuestConfig.Periods[periodName].quests) do
                if (periodData.progress[quest.id] or 0) >= quest.target and not periodData.claimed[quest.id] then
                    return periodName, quest.id, periodData.expiresAt
                end
            end
        end
    end
end

local function setAutoClaimingQuest(enabled)
    autoClaimQuestToken = autoClaimQuestToken + 1
    isAutoClaimingQuest = enabled

    if not enabled then return end

    local token = autoClaimQuestToken
    task.spawn(function()
        while isAutoClaimingQuest and token == autoClaimQuestToken do
            local periodName, questId, expiresAt = getClaimableQuest()

            if periodName then
                ClaimQuestEvent:FireServer(periodName, questId, expiresAt)
            end

            task.wait(0.25)
        end
    end)
end

----------------------------------------------------------------
-- AUTO UPGRADES
----------------------------------------------------------------
local function getAffordableAvailableUpgrade()
    local money = DataController.Money()
    local bestName
    local bestPrice = math.huge

    local function checkChildren(parentName)
        for _, name in ipairs(UpgradeTree.GetChildren(parentName)) do
            if DataController.Upgrades[name]() then
                checkChildren(name)
            else
                local config = Upgrades[name]
                if config and config.price <= money and config.price < bestPrice then
                    bestName = name
                    bestPrice = config.price
                end
            end
        end
    end

    checkChildren("Start")
    return bestName
end

local function setAutoUpgrading(enabled)
    autoUpgradeToken = autoUpgradeToken + 1
    isAutoUpgrading = enabled

    if not enabled then return end

    local token = autoUpgradeToken
    task.spawn(function()
        while isAutoUpgrading and token == autoUpgradeToken do
            local upgradeName = getAffordableAvailableUpgrade()

            if upgradeName then
                BuyUpgradeEvent:FireServer(upgradeName)
            end

            task.wait(0.2)
        end
    end)
end

----------------------------------------------------------------
-- FAST TOWER BATTLE
-- Speeds up tower battle UI tweens: cards, attacks, summons,
-- unit transitions, and health bars.
----------------------------------------------------------------
local TowerRoot = LocalPlayer.PlayerGui:WaitForChild("Root"):WaitForChild("Tower")
local TweenService = game:GetService("TweenService")
local TOWER_ANIMATION_SPEED = 0.15
local TowerController = require(ReplicatedStorage.Framework.Features.Towers.TowerController)
local TowerRefs = require(ReplicatedStorage.Framework.Features.Towers.TowerRefs)
local CompleteTowerFloor = ReplicatedStorage.Network.Towers.RF.CompleteTowerFloor
local sharedEnvironment = getgenv and getgenv() or _G
for _, key in ipairs({
    "__AnimeDiceFastTowerBattle",
    "__AnimeDiceFastTowerBattleV2",
    "__AnimeDiceFastTowerBattleV3",
}) do
    local legacyState = sharedEnvironment[key]
    if legacyState then
        legacyState.enabled = false
    end
end

local towerBattleState = sharedEnvironment.__AnimeDiceFastTowerBattleV4
if not towerBattleState then
    towerBattleState = {
        enabled = false,
        tweenInstalled = false,
        completionInstalled = false,
        nextRequestAt = 0,
        towerRoot = TowerRoot,
        speed = TOWER_ANIMATION_SPEED,
    }
    sharedEnvironment.__AnimeDiceFastTowerBattleV4 = towerBattleState
end
towerBattleState.enabled = false
towerBattleState.nextRequestAt = 0
towerBattleState.towerRoot = TowerRoot
towerBattleState.speed = TOWER_ANIMATION_SPEED

local function isInsideTower(instance)
    local towerRoot = towerBattleState.towerRoot
    while instance do
        if instance == towerRoot then
            return true
        end
        instance = instance.Parent
    end
    return false
end

local function getSequenceWaitTime(sequence)
    local waitTime = 0
    for index, event in ipairs(sequence) do
        if event.action == TowerRefs.Actions.floorStarted then
            local previous = sequence[index - 1]
            if index == 1 then
                waitTime = waitTime + (event.floor == 1
                    and TowerRefs.FloorStartedWaitTime.initial
                    or TowerRefs.FloorStartedWaitTime.transition)
            elseif previous and previous.action == TowerRefs.Actions.memberDefeated then
                waitTime = waitTime + TowerRefs.FloorStartedWaitTime.transition
            else
                waitTime = waitTime + TowerRefs.FloorStartedWaitTime.repeated
            end
        else
            waitTime = waitTime + (TowerRefs.ActionWaitTime[event.action] or 0)
        end
    end
    return waitTime
end

local function readUpvalues(fn)
    local bulkReader = getupvalues or (debug and debug.getupvalues)
    if bulkReader then
        local ok, values = pcall(bulkReader, fn)
        if ok and type(values) == "table" then
            return values
        end
    end

    local singleReader = getupvalue or (debug and debug.getupvalue)
    local values = {}
    if singleReader then
        for index = 1, 100 do
            local ok, first, second = pcall(singleReader, fn, index)
            if not ok or (first == nil and second == nil) then
                break
            end
            values[index] = second ~= nil and second or first
        end
    end
    return values
end

local function findFunctionUsingInstance(rootFunction, targetInstance)
    local visited = {}
    local function search(fn, depth)
        if visited[fn] or depth > 3 then
            return nil
        end
        visited[fn] = true

        local values = readUpvalues(fn)
        for _, value in pairs(values) do
            if value == targetInstance then
                return fn
            end
        end
        for _, value in pairs(values) do
            if type(value) == "function" then
                local found = search(value, depth + 1)
                if found then
                    return found
                end
            end
        end
    end
    return search(rootFunction, 0)
end

local function installTowerBattleHook()
    if towerBattleState.tweenInstalled then
        return true
    end
    if not hookmetamethod or not newcclosure or not getnamecallmethod then
        return false
    end

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = table.pack(...)

        if towerBattleState.enabled and self == TweenService and method == "Create" then
            local target = args[1]
            local tweenInfo = args[2]

            if typeof(target) == "Instance"
                and isInsideTower(target)
                and typeof(tweenInfo) == "TweenInfo"
            then
                local speed = towerBattleState.speed
                args[2] = TweenInfo.new(
                    math.max(tweenInfo.Time * speed, 0.016),
                    tweenInfo.EasingStyle,
                    tweenInfo.EasingDirection,
                    tweenInfo.RepeatCount,
                    tweenInfo.Reverses,
                    tweenInfo.DelayTime * speed
                )
                return oldNamecall(self, table.unpack(args, 1, args.n))
            end
        end

        return oldNamecall(self, ...)
    end))

    towerBattleState.tweenInstalled = true
    return true
end

local function installTowerCompletionHook()
    if towerBattleState.completionInstalled then
        return true
    end
    if not hookfunction then
        return false
    end

    local completionFunction = findFunctionUsingInstance(TowerController.startTower, CompleteTowerFloor)
    if not completionFunction then
        return false
    end
    local originalCompletion
    originalCompletion = hookfunction(completionFunction, function(...)
        if towerBattleState.enabled then
            local remaining = towerBattleState.nextRequestAt - os.clock()
            if remaining > 0 then
                task.wait(remaining)
            end
        end

        local result = table.pack(originalCompletion(...))
        if towerBattleState.enabled and result[1] == nil then
            for _ = 1, 20 do
                task.wait(0.01)
                result = table.pack(originalCompletion(...))
                if result[1] ~= nil then
                    break
                end
            end
        end

        if towerBattleState.enabled and type(result[1]) == "table" then
            towerBattleState.nextRequestAt = os.clock() + getSequenceWaitTime(result[1])
        end
        return table.unpack(result, 1, result.n)
    end)

    towerBattleState.completionInstalled = true
    return true
end


local function setFastTowerBattle(enabled)
    if enabled then
        local tweenReady = installTowerBattleHook()
        local completionReady = installTowerCompletionHook()
        if not tweenReady or not completionReady then
            towerBattleState.enabled = false
            return false
        end
    end

    towerBattleState.enabled = enabled
    towerBattleState.nextRequestAt = 0
    return true
end

local towerLevels = { "Easy", "Medium", "Hard", "Infinity" }
local towerByLevel = {
    Easy = "Dragon Tower",
    Medium = "Cursed Tower",
    Hard = "Pirate Tower",
    Infinity = "Infinity Tower",
}

towerBattleState.selectedLevels = settings.selectedTowerLevels
towerBattleState.equipBestTeam = false
towerBattleState.activeBattle = false
towerBattleState.battleToken = (towerBattleState.battleToken or 0) + 1

local EquipBestTowerTeam = ReplicatedStorage.Network.Towers.RE.EquipBestTowerTeam

local function getBestTowerTeam()
    local units = {}
    for key, item in pairs(DataController.Inventory()) do
        local config = item and EntryRegistry.getEntryConfig(item.name)
        if config and config.kind == "Unit" then
            table.insert(units, {
                key = key,
                damage = config.damage(item.attributes),
            })
        end
    end

    table.sort(units, function(left, right)
        return left.damage == right.damage and left.key < right.key or left.damage > right.damage
    end)

    local team = {}
    for index = 1, TowerRefs.MAX_TEAM_SIZE do
        team[index] = units[index] and units[index].key or nil
    end
    return team
end

local function equipBestTowerTeamAndWait(token)
    if not towerBattleState.equipBestTeam then return true end

    local expectedTeam = getBestTowerTeam()
    EquipBestTowerTeam:FireServer()

    local deadline = os.clock() + 2
    repeat
        local matches = true
        for index = 1, TowerRefs.MAX_TEAM_SIZE do
            if DataController.TowerTeam[index]() ~= expectedTeam[index] then
                matches = false
                break
            end
        end
        if matches then return true end
        task.wait(0.05)
    until os.clock() >= deadline
        or not towerBattleState.activeBattle
        or towerBattleState.battleToken ~= token

    return false
end

local function waitForTowerSessionEnd(token)
    local hiddenButton = TowerRoot:WaitForChild("Hidden")
    while towerBattleState.activeBattle
        and towerBattleState.battleToken == token
        and not hiddenButton.Visible
    do
        task.wait()
    end
    while towerBattleState.activeBattle
        and towerBattleState.battleToken == token
        and hiddenButton.Visible
    do
        task.wait(0.1)
    end
end

local function setEquipBestTowerTeam(enabled)
    towerBattleState.equipBestTeam = enabled
    if enabled then
        EquipBestTowerTeam:FireServer()
    end
end

local function hideTowerBattle()
    local hiddenButton = TowerRoot:WaitForChild("Hidden")
    while towerBattleState.activeBattle and not hiddenButton.Visible do
        task.wait()
    end

    if not towerBattleState.activeBattle then return end
    if firesignal then
        firesignal(hiddenButton.Activated)
    elseif getconnections then
        for _, connection in ipairs(getconnections(hiddenButton.Activated)) do
            connection:Fire()
        end
    end
end

local function setActiveTowerBattle(enabled)
    towerBattleState.battleToken = towerBattleState.battleToken + 1
    local token = towerBattleState.battleToken
    towerBattleState.activeBattle = enabled

    if not enabled then return end

    task.spawn(function()
        local selectedIndex = 1

        while towerBattleState.activeBattle and towerBattleState.battleToken == token do
            local selectedLevels = {}
            for _, level in ipairs(towerLevels) do
                if towerBattleState.selectedLevels[level] then
                    table.insert(selectedLevels, level)
                end
            end

            if #selectedLevels == 0 then
                selectedIndex = 1
                task.wait(0.5)
            else
                if selectedIndex > #selectedLevels then selectedIndex = 1 end
                local towerName = towerByLevel[selectedLevels[selectedIndex]]

                equipBestTowerTeamAndWait(token)
                if not towerBattleState.activeBattle or towerBattleState.battleToken ~= token then break end

                local started = TowerController.startTower(towerName)
                if started then
                    task.spawn(hideTowerBattle)
                    selectedIndex = selectedIndex % #selectedLevels + 1
                    waitForTowerSessionEnd(token)
                else
                    task.wait(0.5)
                end
            end
        end
    end)
end


----------------------------------------------------------------
-- ANTI AFK
----------------------------------------------------------------
local ANTI_AFK_INTERVAL = 600
local antiAfkEnvironment = getgenv and getgenv() or _G

local function keepAlive()
    local camera = workspace.CurrentCamera
    if not camera then return end

    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero, camera.CFrame)
    end)
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
    end)
end

local function setAntiAfk(enabled)
    antiAfkEnvironment.__AnimeDiceAntiAfkToken = (antiAfkEnvironment.__AnimeDiceAntiAfkToken or 0) + 1
    local token = antiAfkEnvironment.__AnimeDiceAntiAfkToken
    antiAfkEnvironment.__AnimeDiceAntiAfkActive = enabled

    if not enabled then return end

    task.spawn(function()
        keepAlive()
        while antiAfkEnvironment.__AnimeDiceAntiAfkActive
            and antiAfkEnvironment.__AnimeDiceAntiAfkToken == token
        do
            task.wait(ANTI_AFK_INTERVAL)
            if not antiAfkEnvironment.__AnimeDiceAntiAfkActive
                or antiAfkEnvironment.__AnimeDiceAntiAfkToken ~= token
            then
                break
            end
            keepAlive()
        end
    end)
end

----------------------------------------------------------------
-- AUTO RECONNECT
----------------------------------------------------------------
local reconnectEnvironment = getgenv and getgenv() or _G

local function setAutoReconnect(enabled)
    reconnectEnvironment.__AnimeDiceReconnectToken = (reconnectEnvironment.__AnimeDiceReconnectToken or 0) + 1
    reconnectEnvironment.__AnimeDiceReconnectEnabled = enabled
    reconnectEnvironment.__AnimeDiceReconnectBusy = false
    local token = reconnectEnvironment.__AnimeDiceReconnectToken

    if reconnectEnvironment.__AnimeDiceReconnectConnection then
        reconnectEnvironment.__AnimeDiceReconnectConnection:Disconnect()
        reconnectEnvironment.__AnimeDiceReconnectConnection = nil
    end
    if not enabled then return end

    local function clickReconnectButton()
        local ok, promptGui = pcall(CoreGui.FindFirstChild, CoreGui, "RobloxPromptGui")
        if not ok or not promptGui then return false end
        for _, descendant in ipairs(promptGui:GetDescendants()) do
            if descendant:IsA("GuiButton") and descendant.Visible
                and descendant.AbsoluteSize.X > 0 and descendant.AbsoluteSize.Y > 0
            then
                local labels = { descendant.Name }
                if descendant:IsA("TextButton") then table.insert(labels, descendant.Text) end
                for _, child in ipairs(descendant:GetDescendants()) do
                    if child:IsA("TextLabel") or child:IsA("TextButton") then
                        table.insert(labels, child.Text)
                    end
                end
                local reconnectButton = false
                for _, label in ipairs(labels) do
                    if string.find(string.lower(label), "reconnect", 1, true) then
                        reconnectButton = true
                        break
                    end
                end
                if reconnectButton then
                    local center = descendant.AbsolutePosition + descendant.AbsoluteSize / 2
                    GuiService.SelectedObject = descendant
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                    VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                    GuiService.SelectedObject = nil
                    return true
                end
            end
        end
        return false
    end

    local function reconnect()
        if reconnectEnvironment.__AnimeDiceReconnectBusy
            or not reconnectEnvironment.__AnimeDiceReconnectEnabled
            or reconnectEnvironment.__AnimeDiceReconnectToken ~= token
        then return end
        reconnectEnvironment.__AnimeDiceReconnectBusy = true

        task.spawn(function()
            while reconnectEnvironment.__AnimeDiceReconnectEnabled
                and reconnectEnvironment.__AnimeDiceReconnectToken == token
            do
                -- Joining same JobId after disconnect commonly fails with error 773.
                -- Prefer Roblox's own Reconnect button; fallback joins a fresh server.
                if not clickReconnectButton() then
                    local ok, err = pcall(TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
                    if not ok then warn("[Anime Dice] Auto Reconnect failed: " .. tostring(err)) end
                end
                task.wait(3)
            end
            if reconnectEnvironment.__AnimeDiceReconnectToken == token then
                reconnectEnvironment.__AnimeDiceReconnectBusy = false
            end
        end)
    end

    reconnectEnvironment.__AnimeDiceReconnectConnection = GuiService.ErrorMessageChanged:Connect(function(message)
        if type(message) == "string" and message ~= "" then reconnect() end
    end)
end
----------------------------------------------------------------
-- AUTO TRAIT
----------------------------------------------------------------
local traitNames = {}
for name in pairs(Traits) do
    table.insert(traitNames, name)
end
table.sort(traitNames, function(left, right)
    return (Traits[left].order or math.huge) < (Traits[right].order or math.huge)
end)

local function setTraitStatus(text)
    if TraitStatus then
        TraitStatus:SetDesc(text)
    end
end

local function refreshTraitUnits()
    local labels = {}
    local nextUnitByLabel = {}
    local selectedLabel

    for key, item in pairs(DataController.Inventory()) do
        local config = item and EntryRegistry.getEntryConfig(item.name)
        if config and config.kind == "Unit" then
            local attributes = item.attributes or {}
            local level = attributes.level or 1
            local grade = attributes.grade or "None"
            local trait = attributes.trait or "None"
            local earning = 0
            if config.income then
                local ok, value = pcall(config.income, attributes)
                if ok and type(value) == "number" then
                    earning = value
                end
            end
            local label = table.concat({
                item.name,
                tostring(level),
                NumberFormatter.FormatCompact(earning),
                grade,
                trait,
            }, " | ")
            while nextUnitByLabel[label] do
                label = label .. "*"
            end
            nextUnitByLabel[label] = key
            if key == selectedTraitUnitKey then selectedLabel = label end
            table.insert(labels, label)
        end
    end

    table.sort(labels)
    traitUnitByLabel = nextUnitByLabel
    if not selectedLabel then
        selectedTraitUnitKey = nil
        settings.selectedTraitUnitKey = nil
        saveSettings()
    end
    if TraitUnitDropdown then
        TraitUnitDropdown:Refresh(labels)
        TraitUnitDropdown:Select(selectedLabel)
    end
    setTraitStatus(#labels .. " units found. Select a unit and target trait.")
end

local function setAutoTraiting(enabled)
    autoTraitToken = autoTraitToken + 1
    local token = autoTraitToken
    isAutoTraiting = enabled

    if not enabled then
        setTraitStatus("Auto Trait stopped.")
        return
    end
    if not selectedTraitUnitKey or not next(selectedTraitNames) then
        isAutoTraiting = false
        setTraitStatus("Select a unit and at least one target trait first.")
        return
    end

    local unitKey = selectedTraitUnitKey
    local targetTraits = copyTable(selectedTraitNames)
    task.spawn(function()
        local rolls = 0
        setTraitStatus("Searching for: " .. table.concat(selectionValues(targetTraits), ", ") .. "...")

        while isAutoTraiting and autoTraitToken == token do
            local unit = DataController.Inventory[unitKey]()
            if not unit then
                setTraitStatus("Unit not found. Press Refresh.")
                break
            end

            local currentTrait = unit.attributes and unit.attributes.trait
            if currentTrait and targetTraits[currentTrait] then
                setTraitStatus("Success: " .. currentTrait .. " after " .. rolls .. " rolls.")
                break
            end
            local rerollEntry = DataController.Inventory["Trait Reroll"]()
            if not rerollEntry or rerollEntry.amount < 1 then
                setTraitStatus("Stopped: no Trait Rerolls left.")
                break
            end
            rolls = rolls + 1
            setTraitStatus("Roll " .. rolls .. ": " .. (currentTrait or "None") .. " | targets: " .. table.concat(selectionValues(targetTraits), ", "))
            TraitRoll:FireServer(unitKey, true)
            task.wait(0.26)
            local requestStartedAt = os.clock()
            repeat
                task.wait(0.05)
                local updatedUnit = DataController.Inventory[unitKey]()
                local updatedTrait = updatedUnit and updatedUnit.attributes and updatedUnit.attributes.trait
                if updatedTrait ~= currentTrait then
                    break
                end
            until os.clock() - requestStartedAt >= 1
        end

        if autoTraitToken == token then
            isAutoTraiting = false
        end
    end)
end

----------------------------------------------------------------
-- AUTO GRADE
----------------------------------------------------------------
local gradeNames = {}
for name in pairs(Grades) do
    table.insert(gradeNames, name)
end
table.sort(gradeNames, function(left, right)
    return (Grades[left].order or math.huge) < (Grades[right].order or math.huge)
end)

local function selectedGradeList(selection)
    local names = {}
    for _, name in ipairs(gradeNames) do
        if selection[name] then
            table.insert(names, name)
        end
    end
    return names
end

local function setGradeStatus(text)
    if GradeStatus then
        GradeStatus:SetDesc(text)
    end
end

local function refreshGradeUnits()
    local labels = {}
    local nextUnitByLabel = {}
    local selectedLabel

    for key, item in pairs(DataController.Inventory()) do
        local config = item and EntryRegistry.getEntryConfig(item.name)
        if config and config.kind == "Unit" then
            local attributes = item.attributes or {}
            local level = attributes.level or 1
            local grade = attributes.grade or "None"
            local trait = attributes.trait or "None"
            local earning = 0
            if config.income then
                local ok, value = pcall(config.income, attributes)
                if ok and type(value) == "number" then
                    earning = value
                end
            end
            local label = table.concat({
                item.name,
                tostring(level),
                NumberFormatter.FormatCompact(earning),
                grade,
                trait,
            }, " | ")
            while nextUnitByLabel[label] do
                label = label .. "*"
            end
            nextUnitByLabel[label] = key
            if key == selectedGradeUnitKey then selectedLabel = label end
            table.insert(labels, label)
        end
    end

    table.sort(labels)
    gradeUnitByLabel = nextUnitByLabel
    if not selectedLabel then
        selectedGradeUnitKey = nil
        settings.selectedGradeUnitKey = nil
        saveSettings()
    end
    if GradeUnitDropdown then
        GradeUnitDropdown:Refresh(labels)
        GradeUnitDropdown:Select(selectedLabel)
    end
    setGradeStatus(#labels .. " units found. Select a unit and target grade.")
end

local function setAutoGrading(enabled)
    autoGradeToken = autoGradeToken + 1
    local token = autoGradeToken
    isAutoGrading = enabled

    if not enabled then
        setGradeStatus("Auto Grade stopped.")
        return
    end
    if not selectedGradeUnitKey or not next(selectedGradeNames) then
        isAutoGrading = false
        setGradeStatus("Select a unit and at least one target grade first.")
        return
    end

    local unitKey = selectedGradeUnitKey
    local targetGrades = selectedGradeNames
    local targetText = table.concat(selectedGradeList(targetGrades), ", ")
    task.spawn(function()
        local rolls = 0
        setGradeStatus("Searching for grades " .. targetText .. "...")

        while isAutoGrading and autoGradeToken == token do
            local unit = DataController.Inventory[unitKey]()
            if not unit then
                setGradeStatus("Unit not found. Press Refresh.")
                break
            end

            local currentGrade = unit.attributes and unit.attributes.grade
            if currentGrade and targetGrades[currentGrade] then
                setGradeStatus("Success: grade " .. currentGrade .. " after " .. rolls .. " rolls.")
                break
            end

            local gems = DataController.Inventory["Gems"]()
            if not gems or gems.amount < 1 then
                setGradeStatus("Stopped: no Gems left.")
                break
            end

            local currentConfig = currentGrade and Grades[currentGrade]
            local skipProtected = currentConfig and currentConfig.protected == true
            rolls = rolls + 1
            setGradeStatus("Roll " .. rolls .. ": " .. (currentGrade or "None") .. " to targets " .. targetText)
            GradeRoll:FireServer(unitKey, skipProtected)
            task.wait(0.26)

            local requestStartedAt = os.clock()
            repeat
                task.wait(0.05)
                local updatedUnit = DataController.Inventory[unitKey]()
                local updatedGrade = updatedUnit and updatedUnit.attributes and updatedUnit.attributes.grade
                if updatedGrade ~= currentGrade then
                    break
                end
            until os.clock() - requestStartedAt >= 1
        end

        if autoGradeToken == token then
            isAutoGrading = false
        end
    end)
end


 


local function setupTradeItem()
    local TradeConfig = require(ReplicatedStorage.Framework.Features.Trading.TradeConfig)
    local TradeRemotes = ReplicatedStorage.Network.TradeService.RE
    local RequestTradeEvent = TradeRemotes.RequestTrade
    local RespondToTradeEvent = TradeRemotes.RespondToRequest
    local ChangeTradeOfferEvent = TradeRemotes.ChangeOffer
    local AdvanceTradeEvent = TradeRemotes.AdvanceTrade
    local CancelTradeEvent = TradeRemotes.CancelTrade
    local SetTradeRequestsEnabledEvent = TradeRemotes.SetTradeRequestsEnabled
    local TradeEvent = TradeRemotes.TradeEvent

----------------------------------------------------------------
-- TRADE ITEM
----------------------------------------------------------------
local selectedTradePlayer
local selectedTradeItemKey
local tradeItemAmount = 1
local isActiveTrading = false
local isAutoReceivingTrade = settings.autoReceiveTrade
local tradeMode
local tradePartner
local tradeState
local tradeToken = 0
local tradeStarted = false
local tradeOfferComplete = false
local tradeReadyRequestAt = 0
local tradeAcceptRequestAt = 0
local lastTradeAdvanceAt = 0
local tradeAdvanceWorkerToken = 0
local tradePlayerByLabel = {}
local tradeItemByLabel = {}
local TradePlayerDropdown
local TradeItemDropdown
local ActiveTradeToggle
local TradeStatus
local suppressActiveTradeToggle = false
local autoReceivePollToken = 0

local function setTradeStatus(text)
    if TradeStatus then TradeStatus:SetDesc(text) end
end

local function tradePlayerLabel(player)
    return player.DisplayName .. " (@" .. player.Name .. ") [" .. player.UserId .. "]"
end

local function tradeItemLabel(key, item)
    return item.name .. " x" .. tostring(item.amount) .. " [" .. key .. "]"
end

local function refreshTradeChoices()
    local playerLabels = {}
    local nextPlayerByLabel = {}
    local selectedPlayerLabel
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local label = tradePlayerLabel(player)
            nextPlayerByLabel[label] = player
            table.insert(playerLabels, label)
            if player == selectedTradePlayer then selectedPlayerLabel = label end
        end
    end
    table.sort(playerLabels)
    tradePlayerByLabel = nextPlayerByLabel
    if not selectedPlayerLabel then selectedTradePlayer = nil end
    if TradePlayerDropdown then
        TradePlayerDropdown:Refresh(playerLabels)
        TradePlayerDropdown:Select(selectedPlayerLabel)
    end

    local itemLabels = {}
    local nextItemByLabel = {}
    local selectedItemLabel
    for key, item in pairs(DataController.Inventory()) do
        local config = item and EntryRegistry.getEntryConfig(item.name)
        if item and item.amount > 0
            and config and config.kind ~= "Unit"
            and not table.find(TradeConfig.UNTRADEABLE_ENTRIES, item.name)
        then
            local label = tradeItemLabel(key, item)
            nextItemByLabel[label] = key
            table.insert(itemLabels, label)
            if key == selectedTradeItemKey then selectedItemLabel = label end
        end
    end
    table.sort(itemLabels)
    tradeItemByLabel = nextItemByLabel
    if not selectedItemLabel then selectedTradeItemKey = nil end
    if TradeItemDropdown then
        TradeItemDropdown:Refresh(itemLabels)
        TradeItemDropdown:Select(selectedItemLabel)
    end

    setTradeStatus("Refreshed: " .. #playerLabels .. " player(s), " .. #itemLabels .. " tradable item stack(s).")
end

local function stopActiveTrade(status, cancelServerTrade)
    tradeToken = tradeToken + 1
    isActiveTrading = false
    tradeMode = nil
    tradePartner = nil
    tradeState = nil
    tradeStarted = false
    if cancelServerTrade then CancelTradeEvent:FireServer() end
    if ActiveTradeToggle then
        suppressActiveTradeToggle = true
        ActiveTradeToggle:Set(false)
        suppressActiveTradeToggle = false
    end
    setTradeStatus(status)
    task.defer(refreshTradeChoices)
end

local function validateOutgoingTrade()
    if not selectedTradePlayer or selectedTradePlayer.Parent ~= Players then
        return nil, "Select an online player first."
    end
    local item = selectedTradeItemKey and DataController.Inventory[selectedTradeItemKey]()
    if not item then return nil, "Select an available item first." end
    local config = EntryRegistry.getEntryConfig(item.name)
    if not config or config.kind == "Unit" then
        return nil, "Units are not available in Select Item."
    end
    if table.find(TradeConfig.UNTRADEABLE_ENTRIES, item.name) then
        return nil, item.name .. " cannot be traded."
    end
    if tradeItemAmount < 1 or tradeItemAmount > item.amount then
        return nil, "Amount must be between 1 and " .. tostring(item.amount) .. "."
    end
    return item
end

local advanceAutomatedTrade

local function automateOutgoingOffer(token, item, itemKey, amount)
    task.spawn(function()
        local deadline = os.clock() + 8
        while token == tradeToken and isActiveTrading and tradeMode == "outgoing" and not tradeState do
            if os.clock() >= deadline then
                stopActiveTrade("Failed: trade screen did not start. Request may be declined or expired.", false)
                return
            end
            task.wait(0.05)
        end
        if token ~= tradeToken or not isActiveTrading or tradeMode ~= "outgoing" then return end

        setTradeStatus("Trade opened with " .. tradePartner.DisplayName .. ". Adding " .. amount .. "x " .. item.name .. "...")
        for count = 1, amount do
            ChangeTradeOfferEvent:FireServer(itemKey, 1)
            setTradeStatus("Adding offer: " .. count .. "/" .. amount .. " " .. item.name .. ".")
            task.wait(0.12)
        end

        local syncDeadline = os.clock() + 3
        while token == tradeToken and isActiveTrading do
            local offered = tradeState and tradeState.ownOffer and tradeState.ownOffer[itemKey] or 0
            if offered == amount then
                tradeOfferComplete = true
                setTradeStatus("Offer ready: " .. amount .. "x " .. item.name .. ". Waiting for both players to become ready.")
                advanceAutomatedTrade()
                return
            end
            if os.clock() >= syncDeadline then
                stopActiveTrade("Failed: server did not synchronize full item amount.", true)
                return
            end
            task.wait(0.05)
        end
    end)
end

advanceAutomatedTrade = function()
    if not tradeState or not tradeMode then return end
    local now = os.clock()

    if tradeState.phase == "Offer" then
        local shouldReady = tradeMode == "outgoing" and tradeOfferComplete
            or tradeMode == "incoming" and tradeState.otherReady
        if shouldReady and not tradeState.ownReady and now >= tradeReadyRequestAt then
            tradeReadyRequestAt = now + 0.3
            lastTradeAdvanceAt = now
            AdvanceTradeEvent:FireServer()
            setTradeStatus(tradeMode == "outgoing"
                and "Offer submitted. Waiting for " .. tradePartner.DisplayName .. " to press Ready."
                or "Sender is ready. Automatically pressing Ready.")
        elseif tradeState.ownReady and not tradeState.otherReady then
            setTradeStatus("Ready. Waiting for " .. tradePartner.DisplayName .. " to press Ready.")
        end
    elseif tradeState.phase == "Confirm" then
        if tradeState.ownAccepted then
            if not tradeState.otherAccepted then
                setTradeStatus("Accepted. Waiting for " .. tradePartner.DisplayName .. " to accept.")
            end
            return
        end

        tradeAdvanceWorkerToken = tradeAdvanceWorkerToken + 1
        local workerToken = tradeAdvanceWorkerToken
        local tradeSessionToken = tradeToken
        task.spawn(function()
            while workerToken == tradeAdvanceWorkerToken
                and tradeSessionToken == tradeToken
                and tradeState
                and tradeState.phase == "Confirm"
                and not tradeState.ownAccepted
            do
                local waitTime = 0.2 - (os.clock() - lastTradeAdvanceAt)
                if waitTime > 0 then task.wait(waitTime) end
                if workerToken ~= tradeAdvanceWorkerToken
                    or tradeSessionToken ~= tradeToken
                    or not tradeState
                    or tradeState.phase ~= "Confirm"
                    or tradeState.ownAccepted
                then
                    break
                end
                lastTradeAdvanceAt = os.clock()
                AdvanceTradeEvent:FireServer()
                setTradeStatus("Accept sent. Waiting for server confirmation and " .. tradePartner.DisplayName .. ".")
                task.wait(0.3)
            end
        end)
    elseif tradeState.phase == "Countdown" then
        local state = tradeState
        local token = tradeToken
        task.spawn(function()
            while token == tradeToken and tradeState == state and state.phase == "Countdown" do
                local remaining = math.max(0, math.ceil((state.countdownEndsAt or 0) - workspace:GetServerTimeNow()))
                setTradeStatus("Both accepted. Trade completes in " .. remaining .. " second(s).")
                task.wait(0.1)
            end
        end)
    end
end
local function startAutoReceiveWatcher()
    autoReceivePollToken = autoReceivePollToken + 1
    local token = autoReceivePollToken
    if not isAutoReceivingTrade then return end

    task.spawn(function()
        local notification = LocalPlayer.PlayerGui:WaitForChild("Root")
            :WaitForChild("Trading"):WaitForChild("TradeNotification")
        while isAutoReceivingTrade and autoReceivePollToken == token do
            if notification.Visible and not tradeMode then
                tradeToken = tradeToken + 1
                tradeMode = "incoming"
                tradePartner = nil
                tradeStarted = false
                setTradeStatus("Incoming trade popup detected. Sending automatic Accept response.")
                RespondToTradeEvent:FireServer(true)
            end
            task.wait(0.1)
        end
    end)
end

TradeEvent.OnClientEvent:Connect(function(eventName, payload)
    if eventName == "RequestReceived" then
        if isAutoReceivingTrade and not tradeMode then
            tradeToken = tradeToken + 1
            local token = tradeToken
            tradeMode = "incoming"
            tradePartner = payload.player
            tradeStarted = false
            RespondToTradeEvent:FireServer(true)
            task.delay(4, function()
                if token == tradeToken and tradeMode == "incoming" and not tradeStarted then
                    stopActiveTrade("Auto Receive failed: trade did not start.", false)
                end
            end)
        elseif isAutoReceivingTrade then
            setTradeStatus("Incoming request ignored because another automated trade is active.")
        end
        return
    end

    if eventName == "RequestSent" and tradeMode == "outgoing" then
        setTradeStatus("Request sent to " .. payload.player.DisplayName .. ". Waiting for receiver to accept.")
        return
    end

    if eventName == "RequestExpired" and tradeMode == "outgoing" then
        stopActiveTrade("Request expired before receiver accepted.", false)
        return
    end

    if eventName == "Started" and tradeMode == "incoming" and (not tradePartner or payload.partner == tradePartner) then
        tradePartner = payload.partner
        tradeStarted = true
        tradeState = nil
        tradeReadyRequestAt = 0
        lastTradeAdvanceAt = 0
        tradeAdvanceWorkerToken = tradeAdvanceWorkerToken + 1
        tradeAcceptRequestAt = 0
        setTradeStatus("Incoming trade started with " .. tradePartner.DisplayName .. ". Waiting for sender offer and Ready.")
        return
    end

    if eventName == "Started" and tradeMode == "outgoing" and payload.partner == tradePartner then
        tradeStarted = true
        tradeState = nil
        tradeReadyRequestAt = 0
        lastTradeAdvanceAt = 0
        tradeAdvanceWorkerToken = tradeAdvanceWorkerToken + 1
        tradeAcceptRequestAt = 0
        setTradeStatus("Trade started with " .. tradePartner.DisplayName .. ". Waiting for synchronized state.")
        return
    end
    if eventName == "Updated" and tradeMode and payload.partner == tradePartner then
        tradeState = payload
        advanceAutomatedTrade()
        return
    end

    if eventName == "Ended" and tradeMode then
        local reason = tostring(payload.reason or "Ended")
        stopActiveTrade("Trade ended: " .. reason .. ".", false)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    if player == selectedTradePlayer then
        selectedTradePlayer = nil
        if tradeMode == "outgoing" then stopActiveTrade("Selected player left the server.", false) end
    end
    task.defer(refreshTradeChoices)
end)
Players.PlayerAdded:Connect(function()
    task.defer(refreshTradeChoices)
end)

    local api = {}

    function api.BindControls(playerDropdown, itemDropdown, activeToggle, status)
        TradePlayerDropdown = playerDropdown
        TradeItemDropdown = itemDropdown
        ActiveTradeToggle = activeToggle
        TradeStatus = status
    end

    function api.SelectPlayer(value)
        local label = type(value) == "table" and (value.Value or value[1]) or value
        selectedTradePlayer = tradePlayerByLabel[label]
        setTradeStatus(selectedTradePlayer
            and "Selected receiver: " .. selectedTradePlayer.DisplayName .. "."
            or "Select a receiver.")
    end

    function api.SelectItem(value)
        local label = type(value) == "table" and (value.Value or value[1]) or value
        selectedTradeItemKey = tradeItemByLabel[label]
        local item = selectedTradeItemKey and DataController.Inventory[selectedTradeItemKey]()
        setTradeStatus(item
            and ("Selected item: " .. item.name .. " x" .. item.amount .. ".")
            or "Select an item.")
    end

    function api.SetAmount(text)
        local amount = tonumber(text)
        if amount and amount % 1 == 0 and amount >= 1 then
            tradeItemAmount = amount
            setTradeStatus("Trade amount set to " .. amount .. ".")
        else
            tradeItemAmount = 0
            setTradeStatus("Invalid amount. Enter a whole number of at least 1.")
        end
    end

    function api.SetActive(state)
        if suppressActiveTradeToggle or not uiReady then return end
        local enabled = type(state) == "table" and state.Value == true or state == true
        if not enabled then
            if isActiveTrading or tradeMode == "outgoing" then
                stopActiveTrade("Outgoing trade cancelled.", true)
            end
            return
        end

        if tradeMode then
            stopActiveTrade("Cannot start: another automated trade is active.", false)
            return
        end
        local item, validationError = validateOutgoingTrade()
        if not item then
            stopActiveTrade("Cannot start: " .. validationError, false)
            return
        end

        tradeToken = tradeToken + 1
        local token = tradeToken
        local player = selectedTradePlayer
        local itemKey = selectedTradeItemKey
        local amount = tradeItemAmount
        isActiveTrading = true
        tradeMode = "outgoing"
        tradePartner = player
        tradeState = nil
        tradeStarted = false
        tradeOfferComplete = false
        tradeReadyRequestAt = 0
        tradeAcceptRequestAt = 0
        setTradeStatus("Sending trade request to " .. player.DisplayName .. " for " .. amount .. "x " .. item.name .. ".")
        RequestTradeEvent:FireServer(player)
        automateOutgoingOffer(token, item, itemKey, amount)
    end

    function api.SetAutoReceive(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        isAutoReceivingTrade = enabled
        settings.autoReceiveTrade = enabled
        saveSettings()
        autoReceivePollToken = autoReceivePollToken + 1
        if not uiReady then return end
        SetTradeRequestsEnabledEvent:FireServer(enabled)
        startAutoReceiveWatcher()
        setTradeStatus(enabled
            and "Auto Receive enabled. Monitoring TradeEvent and incoming trade popup."
            or "Auto Receive disabled.")
    end

    function api.Restore()
        if settings.autoReceiveTrade then
            SetTradeRequestsEnabledEvent:FireServer(true)
            startAutoReceiveWatcher()
        end
    end

    api.Refresh = refreshTradeChoices
    return api
end

local TradeItemAutomation = setupTradeItem()

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local Window = WindUI:CreateWindow({
    Title = "Anime Dice",
    Icon = "dice-5",
    Author = "Premium",
    Folder = "AnimeDice",
    Size = UDim2.new(0, 560, 0, 340),
    ToggleKey = Enum.KeyCode.RightControl,
    Theme = "Dark",
    OpenButton = {
        Title = "Anime Dice",
        Icon = "dice-5",
        Position = UDim2.new(0.5, 0, 0, 60),
        OnlyIcon = false,
        OnlyMobile = false,
        Draggable = true,
        Scale = 1,
        StrokeThickness = 2,
        CornerRadius = UDim.new(1, 0),
        Color = ColorSequence.new(
            Color3.fromHex("#40c9ff"),
            Color3.fromHex("#e81cff")
        ),
    },
})

----------------------------------------------------------------
-- TAB: Roll
----------------------------------------------------------------
local RollTab = Window:Tab({
    Title = "Roll",
    Icon = "dice-5",
})


RollTab:Toggle({
    Title = "Instant Auto Roll",
    Value = settings.autoRoll,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoRoll = enabled
        saveSettings()
        if not uiReady then return end
        isAutoRolling = enabled
        if enabled then
            startAutoRoll()
        else
            stopAutoRoll()
        end
    end,
})

----------------------------------------------------------------
-- TAB: Sell
----------------------------------------------------------------
local SellTab = Window:Tab({
    Title = "Sell",
    Icon = "coins",
})

-- Rarity list from game config
local rarityList = {
    "Common",
    "Uncommon",
    "Rare",
    "Epic",
    "Legendary",
    "Mythical",
    "Divine",
    "Exotic",
    "Celestial",
    "Secret I",
    "Secret II",
    "Exclusive",
}


SellTab:Dropdown({
    Title = "Select Rarity",
    Values = rarityList,
    Value = selectionValues(selectedRarities),
    Multi = true,
    Callback = function(value)
        selectedRarities = normalizeSelection(value)
        settings.selectedRarities = selectedRarities
        saveSettings()
        local names = {}
        for rarity in pairs(selectedRarities) do
            table.insert(names, rarity)
        end
        table.sort(names)
        local display = #names > 0 and table.concat(names, ", ") or "None"
        WindUI:Notify({
            Title = "Auto Sell",
            Content = "Selected rarities: " .. display,
            Duration = 2,
        })
    end,
})


SellTab:Input({
    Title = "Max Chance (sell below)",
    Placeholder = "Example: 1m, 500k, 2.5m",
    Value = tostring(chanceThreshold > 0 and chanceThreshold or ""),
    Callback = function(text)
        local parsed = parseChance(text)
        chanceThreshold = parsed
        settings.chanceThreshold = parsed
        saveSettings()
        if parsed > 0 then
            WindUI:Notify({
                Title = "Auto Sell",
                Content = "Chance filter: " .. text .. " (" .. parsed .. ")",
                Duration = 2,
            })
        else
            WindUI:Notify({
                Title = "Auto Sell",
                Content = "Chance filter disabled.",
                Duration = 2,
            })
        end
    end,
})

SellTab:Toggle({
    Title = "Auto Sell Unit",
    Value = settings.autoSell,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoSell = enabled
        saveSettings()
        if uiReady then setAutoSelling(enabled) end
    end,
})

----------------------------------------------------------------
-- TAB: Trait
----------------------------------------------------------------
local TraitTab = Window:Tab({
    Title = "Trait",
    Icon = "sparkles",
})

TraitUnitDropdown = TraitTab:Dropdown({
    Title = "Select Unit",
    Values = {},
    AllowNone = true,
    SearchBarEnabled = true,
    MenuWidth = 480,
    Callback = function(value)
        local label = type(value) == "table" and (value.Value or value[1]) or value
        selectedTraitUnitKey = traitUnitByLabel[label]
        settings.selectedTraitUnitKey = selectedTraitUnitKey
        saveSettings()
        setTraitStatus(selectedTraitUnitKey and "Selected unit: " .. label or "Select a unit.")
    end,
})

TraitTab:Dropdown({
    Title = "Select Trait",
    Values = traitNames,
    AllowNone = true,
    Multi = true,
    Value = selectionValues(selectedTraitNames),
    Callback = function(value)
        selectedTraitNames = normalizeSelection(value)
        settings.selectedTraitNames = selectedTraitNames
        saveSettings()
        local targets = selectionValues(selectedTraitNames)
        setTraitStatus(#targets > 0 and "Selected targets: " .. table.concat(targets, ", ") or "Select at least one target trait.")
    end,
})

TraitTab:Button({
    Title = "Refresh",
    Callback = refreshTraitUnits,
})

TraitTab:Toggle({
    Title = "Auto Trait",
    Value = settings.autoTrait,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoTrait = enabled
        saveSettings()
        if uiReady then setAutoTraiting(enabled) end
    end,
})

TraitStatus = TraitTab:Paragraph({
    Title = "Status",
    Desc = "Select a unit and target trait.",
})

refreshTraitUnits()

----------------------------------------------------------------
-- TAB: Grades
----------------------------------------------------------------
local GradesTab = Window:Tab({
    Title = "Grades",
    Icon = "award",
})

GradeUnitDropdown = GradesTab:Dropdown({
    Title = "Select Unit",
    Values = {},
    AllowNone = true,
    SearchBarEnabled = true,
    MenuWidth = 560,
    Callback = function(value)
        local label = type(value) == "table" and (value.Value or value[1]) or value
        selectedGradeUnitKey = gradeUnitByLabel[label]
        settings.selectedGradeUnitKey = selectedGradeUnitKey
        saveSettings()
        setGradeStatus(selectedGradeUnitKey and "Selected unit: " .. label or "Select a unit.")
    end,
})

GradesTab:Dropdown({
    Title = "Select Grades",
    Values = gradeNames,
    Multi = true,
    AllowNone = true,
    Value = selectedGradeList(selectedGradeNames),
    Callback = function(value)
        selectedGradeNames = normalizeSelection(value)
        settings.selectedGradeNames = selectedGradeNames
        saveSettings()
        local names = selectedGradeList(selectedGradeNames)
        setGradeStatus(#names > 0 and "Selected targets: " .. table.concat(names, ", ") or "Select target grades.")
    end,
})

GradesTab:Button({
    Title = "Refresh",
    Callback = refreshGradeUnits,
})

GradesTab:Toggle({
    Title = "Auto Grade",
    Value = settings.autoGrade,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoGrade = enabled
        saveSettings()
        if uiReady then setAutoGrading(enabled) end
    end,
})

GradeStatus = GradesTab:Paragraph({
    Title = "Status",
    Desc = "Select a unit and target grade.",
})

refreshGradeUnits()

----------------------------------------------------------------
-- TAB: Potion
----------------------------------------------------------------
local PotionTab = Window:Tab({
    Title = "Potion",
    Icon = "flask-conical",
})

local function addPotionDropdown(category)
    PotionTab:Dropdown({
        Title = "Select Potion " .. category,
        Values = potionLists[category],
        Value = selectionValues(selectedPotions[category]),
        Multi = true,
        AllowNone = true,
        Callback = function(value)
            selectedPotions[category] = normalizeSelection(value)
            settings.selectedPotions = selectedPotions
            saveSettings()
        end,
    })
end

addPotionDropdown("Luck")
addPotionDropdown("Income")
addPotionDropdown("Damage")

PotionTab:Input({
    Title = "Use Count",
    Placeholder = "1",
    Value = tostring(potionUseCount),
    Callback = function(text)
        potionUseCount = math.max(1, math.floor(tonumber(text) or 1))
        settings.potionUseCount = potionUseCount
        saveSettings()
    end,
})

PotionTab:Toggle({
    Title = "Auto Use",
    Value = settings.autoPotion,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoPotion = enabled
        saveSettings()
        if not uiReady then return end
        setAutoUsingPotion(enabled)
        WindUI:Notify({
            Title = "Auto Use Potion",
            Content = enabled and "Enabled." or "Disabled.",
            Duration = 2,
        })
    end,
})

----------------------------------------------------------------
-- TAB: Rebirth
----------------------------------------------------------------
local RebirthTab = Window:Tab({
    Title = "Rebirth",
    Icon = "refresh-cw",
})

RebirthTab:Toggle({
    Title = "Auto Rebirth",
    Value = settings.autoRebirth,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoRebirth = enabled
        saveSettings()
        if not uiReady then return end
        setAutoRebirthing(enabled)
    end,
})

----------------------------------------------------------------
-- TAB: Shop Dice
----------------------------------------------------------------
local ShopDiceTab = Window:Tab({
    Title = "Shop Dice",
    Icon = "shopping-cart",
})

ShopDiceTab:Toggle({
    Title = "Auto Buy Best Dice",
    Value = settings.autoBuyBestDice,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoBuyBestDice = enabled
        saveSettings()
        if not uiReady then return end
        setAutoBuyingBestDice(enabled)
    end,
})

----------------------------------------------------------------
-- TAB: Quest
----------------------------------------------------------------
local QuestTab = Window:Tab({
    Title = "Quest",
    Icon = "clipboard-check",
})

QuestTab:Toggle({
    Title = "Auto Claim Quest",
    Value = settings.autoClaimQuest,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoClaimQuest = enabled
        saveSettings()
        if not uiReady then return end
        setAutoClaimingQuest(enabled)
    end,
})

----------------------------------------------------------------
-- TAB: Upgrades
----------------------------------------------------------------
local UpgradesTab = Window:Tab({
    Title = "Upgrades",
    Icon = "trending-up",
})

UpgradesTab:Toggle({
    Title = "Auto Upgrades",
    Value = settings.autoUpgrades,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoUpgrades = enabled
        saveSettings()
        if not uiReady then return end
        setAutoUpgrading(enabled)
    end,
})

----------------------------------------------------------------
-- TAB: Farming
----------------------------------------------------------------
local FarmingTab = Window:Tab({
    Title = "Farming",
    Icon = "coins",
})


FarmingTab:Toggle({
    Title = "Auto Farming",
    Value = settings.autoFarm,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoFarm = enabled
        saveSettings()
        if not uiReady then return end
        isAutoFarming = enabled
        if enabled then startAutoFarming() else stopAutoFarming() end
    end,
})

----------------------------------------------------------------
-- TAB: Towers
----------------------------------------------------------------
local TowersTab = Window:Tab({
    Title = "Towers",
    Icon = "castle",
})

TowersTab:Dropdown({
    Title = "Select Tower Level",
    Values = towerLevels,
    Value = selectionValues(settings.selectedTowerLevels),
    Multi = true,
    AllowNone = true,
    Callback = function(value)
        local selected = normalizeSelection(value)
        towerBattleState.selectedLevels = selected
        settings.selectedTowerLevels = selected
        saveSettings()
    end,
})

TowersTab:Toggle({
    Title = "Equip Best Team",
    Value = settings.equipBestTowerTeam,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.equipBestTowerTeam = enabled
        saveSettings()
        if not uiReady then return end
        setEquipBestTowerTeam(enabled)
    end,
})

TowersTab:Toggle({
    Title = "Active Tower Battle",
    Value = settings.activeTower,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.activeTower = enabled
        saveSettings()
        if not uiReady then return end
        setActiveTowerBattle(enabled)
    end,
})


TowersTab:Toggle({
    Title = "Fast Tower Battle",
    Value = settings.fastTower,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.fastTower = enabled
        saveSettings()
        if uiReady then setFastTowerBattle(enabled) end
    end,
})

----------------------------------------------------------------
-- TAB: Trade Item
----------------------------------------------------------------
local TradeItemTab = Window:Tab({
    Title = "Trade Item",
    Icon = "handshake",
})
local TradeItemControls = {}

TradeItemControls.Player = TradeItemTab:Dropdown({
    Title = "Select Player",
    Values = {},
    AllowNone = true,
    SearchBarEnabled = true,
    Callback = TradeItemAutomation.SelectPlayer,
})

TradeItemControls.Item = TradeItemTab:Dropdown({
    Title = "Select Item",
    Values = {},
    AllowNone = true,
    SearchBarEnabled = true,
    MenuWidth = 560,
    Callback = TradeItemAutomation.SelectItem,
})

TradeItemTab:Input({
    Title = "How Many Item",
    Placeholder = "1",
    Value = "1",
    Callback = TradeItemAutomation.SetAmount,
})

TradeItemTab:Button({
    Title = "Refresh",
    Callback = TradeItemAutomation.Refresh,
})

TradeItemControls.Active = TradeItemTab:Toggle({
    Title = "Active Trade",
    Value = false,
    Callback = TradeItemAutomation.SetActive,
})

TradeItemTab:Toggle({
    Title = "Auto Receive",
    Value = settings.autoReceiveTrade,
    Callback = TradeItemAutomation.SetAutoReceive,
})

TradeItemControls.Status = TradeItemTab:Paragraph({
    Title = "Trade Status",
    Desc = "Press Refresh, then select receiver, item, and amount.",
})

TradeItemAutomation.BindControls(
    TradeItemControls.Player,
    TradeItemControls.Item,
    TradeItemControls.Active,
    TradeItemControls.Status
)
TradeItemAutomation.Refresh()

----------------------------------------------------------------
-- TAB: Webhook
----------------------------------------------------------------
local WebhookTab = Window:Tab({
    Title = "Webhook",
    Icon = "webhook",
})

WebhookTab:Input({
    Title = "Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Value = webhookUrl,
    Callback = function(text)
        webhookUrl = tostring(text or ""):match("^%s*(.-)%s*$")
        settings.webhookUrl = webhookUrl
        saveSettings()
    end,
})

WebhookTab:Dropdown({
    Title = "Select Rarity",
    Values = rarityList,
    Value = selectionValues(selectedWebhookRarities),
    Multi = true,
    AllowNone = true,
    Callback = function(value)
        selectedWebhookRarities = normalizeSelection(value)
        settings.webhookRarities = selectedWebhookRarities
        saveSettings()
    end,
})

WebhookTab:Button({
    Title = "Test Webhook",
    Callback = function()
        task.spawn(function()
            local sampleName, sampleConfig
            for name, config in pairs(EntryRegistry.entriesOfKind("Unit")) do
                if not config.variant then
                    sampleName, sampleConfig = name, config
                    break
                end
            end
            local attributes = { level = 1 }
            local image, captureError = sampleConfig and captureUnitImage(sampleConfig, attributes)
            local payload = sampleConfig and unitWebhookPayload(
                sampleName,
                sampleConfig.getRarity(attributes),
                "None",
                sampleConfig.chance and sampleConfig.chance(attributes) or nil,
                SellUtil.GetSellPrice(sampleName, attributes),
                image
            ) or { content = "Anime Dice webhook connected." }
            local ok, message = postWebhook(payload, image)
            setWebhookStatus(image
                and (ok and ("Test image sent (" .. #image.bytes .. " bytes).") or "Image upload failed: " .. message)
                or "Test image unavailable: " .. tostring(captureError))
            WindUI:Notify({
                Title = "Webhook Test",
                Content = ok and "Connected successfully." or "Connection failed: " .. message,
                Duration = 4,
            })
        end)
    end,
})

WebhookTab:Toggle({
    Title = "Active Webhook",
    Value = settings.activeWebhook,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        if enabled and not validWebhookUrl(webhookUrl) then
            isWebhookActive = false
            settings.activeWebhook = false
            saveSettings()
            WindUI:Notify({
                Title = "Webhook",
                Content = "Enter a valid Discord webhook URL first.",
                Duration = 4,
            })
            return
        end
        isWebhookActive = enabled
        settings.activeWebhook = enabled
        saveSettings()
    end,
})

WebhookStatus = WebhookTab:Paragraph({
    Title = "Image Status",
    Desc = #screenshotFunctions > 0
        and ("Detected " .. #screenshotFunctions .. " screenshot API(s). Waiting for a unit.")
        or "No screenshot API detected. Unit images cannot be captured by this executor.",
})

----------------------------------------------------------------
-- TAB: Setting
----------------------------------------------------------------
local SettingTab = Window:Tab({
    Title = "Settings",
    Icon = "settings",
})

local SettingSection = SettingTab

SettingSection:Toggle({
    Title = "Anti AFK",
    Icon = "shield",
    Value = settings.antiAfk,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.antiAfk = enabled
        saveSettings()
        if not uiReady then return end
        setAntiAfk(enabled)
        WindUI:Notify({
            Title = "Anti AFK",
            Content = enabled and "ON" or "OFF",
            Duration = 2,
        })
    end,
})

SettingSection:Toggle({
    Title = "Auto Reconnect",
    Icon = "rotate-cw",
    Value = settings.autoReconnect,
    Callback = function(state)
        local enabled = type(state) == "table" and state.Value == true or state == true
        settings.autoReconnect = enabled
        saveSettings()
        if not uiReady then return end
        setAutoReconnect(enabled)
        WindUI:Notify({
            Title = "Auto Reconnect",
            Content = enabled and "ON" or "OFF",
            Duration = 2,
        })
    end,
})

----------------------------------------------------------------
-- Restore enabled features after every control exists
----------------------------------------------------------------
uiReady = true

if settings.autoRoll then
    isAutoRolling = true
    startAutoRoll()
end
if settings.autoSell then setAutoSelling(true) end
if settings.autoPotion then setAutoUsingPotion(true) end
if settings.autoRebirth then setAutoRebirthing(true) end
if settings.autoBuyBestDice then setAutoBuyingBestDice(true) end
if settings.autoClaimQuest then setAutoClaimingQuest(true) end
if settings.autoUpgrades then setAutoUpgrading(true) end
if settings.autoFarm then
    isAutoFarming = true
    startAutoFarming()
end
if settings.equipBestTowerTeam then setEquipBestTowerTeam(true) end
if settings.fastTower and not setFastTowerBattle(true) then
    settings.fastTower = false
    saveSettings()
end
if settings.activeTower then setActiveTowerBattle(true) end
if settings.antiAfk then setAntiAfk(true) end
if settings.autoReconnect then setAutoReconnect(true) end
if settings.autoTrait then setAutoTraiting(true) end
if settings.autoGrade then setAutoGrading(true) end
TradeItemAutomation.Restore()

-- CreateWindow opens asynchronously after 0.06s; close after that startup task finishes.
task.delay(0.1, function()
    Window:Close()
end)
