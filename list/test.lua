local bootstrapGui
local bootstrapLabel
local function setBootstrapStatus(message, failed)
	warn("[RollAGnome] " .. message)
	if not bootstrapGui then
		pcall(function()
			local player = game:GetService("Players").LocalPlayer
			local parent = player and (player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10))
			if not parent then
				return
			end
			bootstrapGui = Instance.new("ScreenGui")
			bootstrapGui.Name = "RollAGnomeBootstrap"
			bootstrapGui.ResetOnSpawn = false
			bootstrapGui.IgnoreGuiInset = true
			bootstrapGui.DisplayOrder = 1000000
			bootstrapGui.Parent = parent
			bootstrapLabel = Instance.new("TextLabel")
			bootstrapLabel.AnchorPoint = Vector2.new(0.5, 0)
			bootstrapLabel.Position = UDim2.new(0.5, 0, 0, 18)
			bootstrapLabel.Size = UDim2.new(0.9, 0, 0, 54)
			bootstrapLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
			bootstrapLabel.BackgroundTransparency = 0.1
			bootstrapLabel.TextColor3 = Color3.new(1, 1, 1)
			bootstrapLabel.TextScaled = true
			bootstrapLabel.TextWrapped = true
			bootstrapLabel.Font = Enum.Font.GothamBold
			bootstrapLabel.Parent = bootstrapGui
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 10)
			corner.Parent = bootstrapLabel
		end)
	end
	if bootstrapLabel then
		bootstrapLabel.BackgroundColor3 = failed and Color3.fromRGB(130, 32, 32) or Color3.fromRGB(20, 20, 24)
		bootstrapLabel.Text = message
	end
end

setBootstrapStatus("Starting. Waiting for game...")
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local startupStage = "initialization"

-- Delta cloneref errors on non-Instance values used by some UI dependencies.
-- Keep normal Instance behavior; pass other values through unchanged.
local executorEnvironment = type(getgenv) == "function" and getgenv() or _G
local originalCloneRef = executorEnvironment.cloneref
local originalCloneReference = executorEnvironment.clonereference
local function safeCloneRef(value)
	if typeof(value) ~= "Instance" then
		return value
	end
	local clone = type(originalCloneRef) == "function" and originalCloneRef or originalCloneReference
	if type(clone) ~= "function" then
		return value
	end
	local ok, result = pcall(clone, value)
	return ok and result or value
end
executorEnvironment.cloneref = safeCloneRef
executorEnvironment.clonereference = safeCloneRef
local function enablePluginCapability()
	local synTable = rawget(executorEnvironment, "syn") or syn
	local setters = {
		setthreadidentity,
		setidentity,
		set_thread_identity,
		setthreadcontext,
		type(synTable) == "table" and synTable.set_thread_identity or nil,
	}
	for _, setter in pairs(setters) do
		if type(setter) == "function" and pcall(setter, 3) then
			return true
		end
	end
	return false
end

local bootstrapOk, bootstrapError = xpcall(function()
	startupStage = "game modules"
-- Auto roll loop for Roll A Gnome.
-- Roll: Network:InvokeServer("Roll"). Result appears as a model in Plot.RNG.Preview.
-- Auto-buy target = roll -> find target model in preview -> activate ProximityPrompt "Buy".
-- Network:InvokeServer("Purchase") is for Item Shop only, not RNG result purchases.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local LibraryModule = ReplicatedStorage:WaitForChild("Library", 30)
assert(LibraryModule, "Library module not found. Execute inside Roll A Gnome after joining a server.")
local Library = require(LibraryModule)
local Network = assert(Library.get("Network"), "Network module unavailable")
local ReplicationModule = ReplicatedStorage:WaitForChild("Replication", 30)
assert(ReplicationModule, "Replication module not found")
local Replication = require(ReplicationModule)
local Mutations = assert(Library.get("Mutations"), "Mutations module unavailable")

	startupStage = "WindUI download"
	setBootstrapStatus("Loading UI...")
local windUiSource
do
	local urls = {
		"https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/dist/main.lua",
		"https://cdn.jsdelivr.net/gh/Footagesus/WindUI@main/dist/main.lua",
	}
	local lastError
	for _, url in ipairs(urls) do
		local ok, result = pcall(function()
			return game:HttpGet(url)
		end)
		if not ok and type(request) == "function" then
			local requestOk, response = pcall(request, { Url = url, Method = "GET" })
			if requestOk and type(response) == "table" then
				result = response.Body or response.body
				ok = type(result) == "string"
			end
		end
		if ok and type(result) == "string" and #result > 1000 then
			windUiSource = result
			break
		end
		lastError = result
	end
	assert(windUiSource, "WindUI download failed: " .. tostring(lastError))
end
	startupStage = "WindUI compile"
	local compile = assert(loadstring, "Delta loadstring unavailable; update Delta to latest version")
	local windUiChunk, compileError = compile(windUiSource)
	assert(windUiChunk, "WindUI compile failed: " .. tostring(compileError))
	startupStage = "WindUI initialization"
	local WindUI = windUiChunk()
	assert(type(WindUI) == "table", "WindUI returned invalid result")
local running = false
local skipVisuals = true
local targetNames = {} -- labels shown in UI
local selectedTargets = {} -- [name .. mutation] = target
local savedRollSpeed
local autoBuy = false
local autoFarm = false
local autoSell = false
local autoFarmGeneration = 0
local autoSellGeneration = 0
local selectedPetNames = {}
local autoPetBuy = false
local autoPetBuyGeneration = 0
local selectedShopItems = {}
local autoShopBuy = false
local autoShopBuyGeneration = 0
local selectedUseItems = {}
local autoUse = false
local autoUseGeneration = 0
local autoSaveEnabled = true

-- Build dropdown rows from current Studio configs so newly added gnomes and mutations appear automatically.
local MutationList = { { name = "", label = "Normal" } }
for _, mutationName in ipairs(Mutations.getList()) do
	table.insert(MutationList, { name = mutationName, label = mutationName })
end
local GnomeList = {}
do
	local mod = Library.get("Farmers")
	if type(mod) == "table" then
		for name, cfg in pairs(mod) do
			table.insert(GnomeList, {
				name = name,
				rarity = cfg.real_rarity or cfg.rarity or "?",
				price = cfg.price or 0,
				order = cfg.order or 0,
			})
		end
	end
	if #GnomeList == 0 then
		-- Fallback: read from Assets.Farmers instances
		local farmersAssets = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Farmers")
		if farmersAssets then
			for _, gnomeModel in ipairs(farmersAssets:GetChildren()) do
				table.insert(GnomeList, { name = gnomeModel.Name, rarity = "?", price = 0, order = 0 })
			end
		end
	end
end
local PetList = {}
do
	local pets = Library.get("Pets")
	if type(pets) == "table" then
		for key, cfg in pairs(pets) do
			table.insert(PetList, {
				name = cfg.name or key,
				rarity = cfg.rarity or "?",
				price = cfg.price or 0,
				order = cfg.order or 0,
			})
		end
	end
end
local ShopItemList = {}
do
	local itemShop = Library.get("ItemShop")
	for key, cfg in pairs(itemShop and itemShop.Items or {}) do
		if not cfg.ignore then
			table.insert(ShopItemList, {
				key = key,
				name = cfg.name or key,
				price = cfg.price or 0,
				order = cfg.order or 0,
				type = cfg.type,
				alwaysAvailable = cfg.AlwaysAvailable == true,
			})
		end
	end
end

local function formatPrice(v)
	if v >= 1e12 then return ("%.2fT"):format(v / 1e12)
	elseif v >= 1e9 then return ("%.2fB"):format(v / 1e9)
	elseif v >= 1e6 then return ("%.2fM"):format(v / 1e6)
	elseif v >= 1e3 then return ("%.0fK"):format(v / 1e3)
	else return tostring(v) end
end
local function mutationMatches(value, wanted)
	if wanted == "" then
		return value == nil or value == "" or type(value) == "table" and next(value) == nil
	end
	if type(value) == "table" then
		return table.find(value, wanted) ~= nil
	end
	for mutation in string.gmatch(value or "", "[^_]+") do
		if mutation == wanted then
			return true
		end
	end
	return false
end

local function targetKey(name, mutation)
	return name .. "\0" .. mutation
end

local function findSelectedTarget(name, mutations)
	for _, mutation in ipairs(MutationList) do
		local target = selectedTargets[targetKey(name, mutation.name)]
		if target and mutationMatches(mutations, mutation.name) then
			return target
		end
	end
end
local function activatePrompt(prompt, minimumHold)
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
		return false, "Prompt unavailable"
	end

	local holdDuration = math.max(prompt.HoldDuration, minimumHold or 0.1)
	if type(fireproximityprompt) == "function" then
		local ok, err = pcall(fireproximityprompt, prompt, holdDuration)
		if ok then
			return true
		end
		warn("[RollAGnome] Delta fireproximityprompt failed; using native input:", err)
	end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local promptPart = prompt.Parent
	if promptPart and not promptPart:IsA("BasePart") then
		promptPart = promptPart:FindFirstAncestorWhichIsA("BasePart")
	end
	local originalPivot = character and root and character:GetPivot()
	if originalPivot and promptPart then
		local distance = math.max(math.min(prompt.MaxActivationDistance - 1, 2), 0)
		character:PivotTo(promptPart.CFrame * CFrame.new(0, 0, distance))
		task.wait(0.15)
	end

	local ok, err = pcall(function()
		prompt:InputHoldBegin()
		task.wait(holdDuration + 0.05)
		prompt:InputHoldEnd()
	end)
	if originalPivot and character.Parent and root.Parent then
		character:PivotTo(originalPivot)
	end
	return ok, err
end



-- RNG results are purchased through the ProximityPrompt on the preview model, matching the game's original flow.
local function buyGnome(name, mutation)
	if type(name) ~= "string" or name == "" then
		return false, "No name"
	end

	local plotValue = LocalPlayer:FindFirstChild("Plot")
	local plot = plotValue and plotValue.Value
	local rng = plot and plot:FindFirstChild("RNG")
	local preview = rng and rng:FindFirstChild("Preview")
	if not preview then
		return false, "RNG preview unavailable"
	end

	local rolledGnome
	for _, model in ipairs(preview:GetChildren()) do
		if model.Name == name and mutationMatches(model:GetAttribute("Mutations"), mutation) then
			rolledGnome = model
			break
		end
	end
	local prompt = rolledGnome and rolledGnome:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt or prompt.ActionText ~= "Buy" then
		return false, name .. " is not in the current roll"
	end

	local farmersBefore = {}
	for id in pairs(Replication.Data and Replication.Data.farmers or {}) do
		farmersBefore[id] = true
	end
	local ok, err = activatePrompt(prompt, 0.1)
	if not ok then
		return false, err
	end

	local deadline = os.clock() + 2
	repeat
		local farmers = Replication and Replication.Data and Replication.Data.farmers
		for id, info in pairs(farmers or {}) do
			if not farmersBefore[id]
				and type(info) == "table"
				and info.name == name
				and mutationMatches(info.mutations, mutation)
			then
				return true, true
			end
		end
		task.wait(0.05)
	until os.clock() >= deadline

	return false, "Server did not confirm purchase"
end

local function notify(title, content)
	WindUI:Notify({
		Title = title,
		Content = content,
		Duration = 4,
	})
end

local hideUsernameEnabled = false
local nameplateAddedConnection
local function SetLocalNameplateVisible(visible)
	local character = LocalPlayer.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
	local nameplate = humanoidRootPart and humanoidRootPart:FindFirstChild("玩家名称")
	if nameplate and nameplate:IsA("BillboardGui") then
		nameplate.Enabled = visible
	end
end
local function WatchLocalNameplate(character)
	if nameplateAddedConnection then
		nameplateAddedConnection:Disconnect()
		nameplateAddedConnection = nil
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not humanoidRootPart then
		return
	end
	SetLocalNameplateVisible(not hideUsernameEnabled)
	nameplateAddedConnection = humanoidRootPart.ChildAdded:Connect(function(child)
		if hideUsernameEnabled and child.Name == "玩家名称" and child:IsA("BillboardGui") then
			child.Enabled = false
		end
	end)
end
LocalPlayer.CharacterAdded:Connect(WatchLocalNameplate)
if LocalPlayer.Character then
	task.spawn(WatchLocalNameplate, LocalPlayer.Character)
end

local function KeepAlive()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.zero, camera.CFrame)
	end)
	pcall(function()
		local input = game:GetService("VirtualInputManager")
		input:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
		task.wait()
		input:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
	end)
end
local antiAfkConnection
local antiAfkEnabled = false
local antiAfkGeneration = 0

local function setAntiAfk(enabled)
	antiAfkEnabled = enabled
	antiAfkGeneration += 1
	if antiAfkConnection then
		antiAfkConnection:Disconnect()
		antiAfkConnection = nil
	end
	if not enabled then
		return
	end

	antiAfkConnection = LocalPlayer.Idled:Connect(KeepAlive)
	local generation = antiAfkGeneration
	KeepAlive()
	task.spawn(function()
		while antiAfkEnabled and antiAfkGeneration == generation do
			task.wait(60)
			if antiAfkEnabled and antiAfkGeneration == generation then
				KeepAlive()
			end
		end
	end)
end

local function applyVisualSpeed()
	if skipVisuals then
		if savedRollSpeed == nil then
			savedRollSpeed = LocalPlayer:GetAttribute("RollSpeed")
		end
		LocalPlayer:SetAttribute("RollSpeed", 1000000)
	elseif savedRollSpeed ~= nil then
		LocalPlayer:SetAttribute("RollSpeed", savedRollSpeed)
		savedRollSpeed = nil
	end
end

LocalPlayer:GetAttributeChangedSignal("Rolling"):Connect(function()
	if skipVisuals and LocalPlayer:GetAttribute("Rolling") then
		LocalPlayer:SetAttribute("RollSpeed", 1000000)
	end
end)

local function hidePreviewVisual(model)
	local function hide(instance)
		if instance:IsA("BasePart") then
			instance.Transparency = 1
		elseif instance:IsA("Highlight") then
			instance.Enabled = false
		end
	end
	for _, instance in ipairs(model:GetDescendants()) do
		hide(instance)
	end
	model.DescendantAdded:Connect(function(instance)
		if skipVisuals then
			hide(instance)
		end
	end)
end

workspace:WaitForChild("Preview").ChildAdded:Connect(function(instance)
	if skipVisuals and instance:IsA("Model") and instance.Name == "RNG" then
		hidePreviewVisual(instance)
	end
end)

-- Snapshot nama gnome yang ada di inventory
local function getOwnedGnomeNames()
	local owned = {}
	local farmers = Replication and Replication.Data and Replication.Data.farmers
	if farmers then
		for _, info in pairs(farmers) do
			if type(info) == "table" and typeof(info.name) == "string" then
				owned[info.name] = true
			end
		end
	end
	return owned
end
local function getOwnedGnomesById()
	local owned = {}
	local farmers = Replication and Replication.Data and Replication.Data.farmers
	for id, info in pairs(farmers or {}) do
		if type(info) == "table" and typeof(info.name) == "string" then
			owned[id] = { name = info.name, mutations = info.mutations or "" }
		end
	end
	return owned
end
local function getRollPreview()
	local plotValue = LocalPlayer:FindFirstChild("Plot")
	local plot = plotValue and plotValue.Value
	local rng = plot and plot:FindFirstChild("RNG")
	return rng and rng:FindFirstChild("Preview")
end

local function snapshotChildren(parent)
	local snapshot = {}
	for _, child in ipairs(parent and parent:GetChildren() or {}) do
		snapshot[child] = true
	end
	return snapshot
end
local function getReadyPlants()
	local plotValue = LocalPlayer:FindFirstChild("Plot")
	local plot = plotValue and plotValue.Value
	local ready = {}
	local seen = {}
	if not plot then
		return ready
	end

-- Mature plants can be moved client-side from Plants to ReadyToCollect.
	for _, containerName in ipairs({ "Plants", "ReadyToCollect" }) do
		local container = plot:FindFirstChild(containerName)
		if container then
			for _, plant in ipairs(container:GetChildren()) do
				if not seen[plant]
					and plant:IsA("Model")
					and plant:GetAttribute("READY") == true
					and plant:GetAttribute("FruitReady") ~= false
				then
					seen[plant] = true
					table.insert(ready, plant)
				end
			end
		end
	end
	return ready
end

local function setAutoFarm(enabled)
	autoFarm = enabled
	autoFarmGeneration += 1
	if not enabled then
		return
	end

	local generation = autoFarmGeneration
	task.spawn(function()
		while autoFarm and autoFarmGeneration == generation do
			local collected = 0
			for _, plant in ipairs(getReadyPlants()) do
				if not autoFarm or autoFarmGeneration ~= generation then
					return
				end
				if plant.Parent
					and plant:GetAttribute("READY") == true
					and plant:GetAttribute("FruitReady") ~= false
				then
					pcall(Network.InvokeServer, Network, "CollectPlant", plant)
					collected += 1
					if collected >= 3 then
						break
					end
				end
			end
			task.wait(0.25)
		end
	end)
end
local function setAutoShopBuy(enabled)
	autoShopBuy = enabled
	autoShopBuyGeneration += 1
	if not enabled then
		return
	end
	if #selectedShopItems == 0 then
		autoShopBuy = false
		notify("Select item", "Select one or more items from List Item first.")
		return
	end

	local generation = autoShopBuyGeneration
	task.spawn(function()
		while autoShopBuy and autoShopBuyGeneration == generation do
			local ok, stock = pcall(Network.InvokeServer, Network, "GetStock")
			for _, item in ipairs(selectedShopItems) do
				if not autoShopBuy or autoShopBuyGeneration ~= generation then
					return
				end
				local available = item.alwaysAvailable or (ok and type(stock) == "table" and (stock[item.key] or 0) > 0)
				if available then
					local purchaseOk, purchased, purchaseError = pcall(Network.InvokeServer, Network, "Purchase", item.key)
					if purchaseOk and purchased then
						notify("Auto Buy successful", item.name .. " purchased.")
					elseif not purchaseOk then
						notify("Auto Buy failed", tostring(purchased))
					elseif purchaseError then
						notify("Auto Buy failed", tostring(purchaseError))
					end
				end
				task.wait()
			end
			task.wait(0.5)
		end
	end)

end
local function getRandomPlotPlacement()
	local plotValue = LocalPlayer:FindFirstChild("Plot")
	local plot = plotValue and plotValue.Value
	local ground = plot and plot:FindFirstChild("Ground")
	if not ground then
		return
	end

	local groundCFrame, groundSize
	if ground:IsA("Model") then
		groundCFrame, groundSize = ground:GetBoundingBox()
	elseif ground:IsA("BasePart") then
		groundCFrame, groundSize = ground.CFrame, ground.Size
	else
		return
	end

	local x = (math.random() - 0.5) * math.max(groundSize.X - 6, 1)
	local z = (math.random() - 0.5) * math.max(groundSize.Z - 6, 1)
	local origin = groundCFrame:PointToWorldSpace(Vector3.new(x, groundSize.Y / 2 + 20, z))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ground }
	local hit = workspace:Raycast(origin, Vector3.new(0, -(groundSize.Y + 40), 0), params)
	if not hit then
		return
	end

	local floorId = "1"
	local current = hit.Instance
	while current and current ~= ground do
		floorId = current.Name:match("^Floor(%d+)$") or floorId
		current = current.Parent
	end
	return CFrame.new(hit.Position), floorId
end

local function equipItemTool(itemName)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if not character or not humanoid then
		return nil, "Character unavailable"
	end

	local tool = character:FindFirstChild(itemName) or (backpack and backpack:FindFirstChild(itemName))
	if not tool or not tool:IsA("Tool") then
		return nil, itemName .. " is not available in Backpack"
	end
	if tool.Parent ~= character then
		humanoid:EquipTool(tool)
		local deadline = os.clock() + 1
		repeat
			task.wait()
		until tool.Parent == character or os.clock() >= deadline
	end
	if tool.Parent ~= character then
		return nil, "Failed to equip " .. itemName
	end
	return tool
end

local function useNearTarget(tool, targetPart, callback)
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not targetPart or not targetPart:IsA("BasePart") then
		return false, "Target position unavailable"
	end

	local originalPivot = character:GetPivot()
	local ok, result = pcall(function()
		character:PivotTo(targetPart.CFrame * CFrame.new(0, 0, 4))
		task.wait(0.2)
		callback()
		task.wait(1)
	end)
	if character.Parent and root.Parent then
		character:PivotTo(originalPivot)
	end
	if not ok then
		return false, result
	end
	return true
end
local function triggerActivatedPrompt(tool, targetPart)
	-- Tool activation creates the native Give prompt on the client gnome clone.
	tool:Activate()

	local deadline = os.clock() + 2
	repeat
		for _, descendant in ipairs(targetPart:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") and descendant.Enabled and descendant.ActionText == "Give" then
				return activatePrompt(descendant, 0.5)
			end
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return false, "Item prompt did not appear"
end


local function useShopItem(item)
	local tool, equipError = equipItemTool(item.key)
	if not tool then
		return false, equipError
	end

	if item.type == "Sprinkler" or item.type == "Fertilizer" then
		local pivot, floorId = getRandomPlotPlacement()
		if not pivot then
			return false, "No valid placement position found"
		end
		Network:FireServer("Place", item.type, item.key, pivot, floorId)
		return true
	end

	if item.type == "WateringCan" then
		local plotValue = LocalPlayer:FindFirstChild("Plot")
		local plot = plotValue and plotValue.Value
		local plants = plot and plot:FindFirstChild("Plants")
		local candidates = {}
		for _, plant in ipairs(plants and plants:GetChildren() or {}) do
			local center = plant:IsA("Model") and plant:FindFirstChild("CenterPart", true)
			if center and center:IsA("BasePart") then
				table.insert(candidates, { model = plant, part = center })
			end
		end
		if #candidates == 0 then
			return false, "No plants available"
		end
		local target = candidates[math.random(1, #candidates)]
		return useNearTarget(tool, target.part, function()
			tool:Activate()
			task.wait(0.35)
			Network:FireServer("WaterPlant", target.model)
		end)
	end

	if item.type == "GnomeItem" then
		local plotValue = LocalPlayer:FindFirstChild("Plot")
		local plot = plotValue and plotValue.Value
		local workers = plot and plot:FindFirstChild("Workers")
		local clientFarmers = plot and plot:FindFirstChild("ClientFarmers")
		local candidates = {}
		for _, worker in ipairs(workers and workers:GetChildren() or {}) do
			local clientGnome = clientFarmers and clientFarmers:FindFirstChild(worker.Name)
			local rootPart = clientGnome and (clientGnome:FindFirstChild("RootPart") or clientGnome.PrimaryPart)
			if rootPart and rootPart:IsA("BasePart") then
				table.insert(candidates, { model = clientGnome, part = rootPart })
			end
		end
		if #candidates == 0 then
			return false, "No visible gnome targets available"
		end
		local target = candidates[math.random(1, #candidates)]
		local used, useError
		local moved, moveError = useNearTarget(tool, target.part, function()
			used, useError = triggerActivatedPrompt(tool, target.part)
		end)
		if not moved then
			return false, moveError
		end
		return used, useError
	end

	return false, "Unsupported item type: " .. tostring(item.type)
end

local function setAutoUse(enabled)
	autoUse = enabled
	autoUseGeneration += 1
	if not enabled then
		return
	end
	if #selectedUseItems == 0 then
		autoUse = false
		notify("Select item", "Select one or more items before enabling Auto Use.")
		return
	end

	local generation = autoUseGeneration
	task.spawn(function()
		local waitingErrors = {}
		while autoUse and autoUseGeneration == generation do
			for _, item in ipairs(selectedUseItems) do
				if not autoUse or autoUseGeneration ~= generation then
					return
				end
				local ok, used, useError = pcall(useShopItem, item)
				if not ok or not used then
					local message = ok and useError or used
					if message and waitingErrors[item.key] ~= message then
						waitingErrors[item.key] = message
						notify(ok and "Auto Use waiting" or "Auto Use failed", item.name .. ": " .. tostring(message))
					end
					continue
				end
				waitingErrors[item.key] = nil
				task.wait(0.5)
			end
			task.wait(1)
		end
	end)
end

local function setAutoSell(enabled)
	autoSell = enabled
	autoSellGeneration += 1
	if not enabled then
		return
	end

	local generation = autoSellGeneration
	task.spawn(function()
		while autoSell and autoSellGeneration == generation do
			-- Network keeps the mapping stable to the SellAll RemoteFunction; GetChildren order is unstable.
			pcall(Network.InvokeServer, Network, "SellAll")
			task.wait(1)
		end
	end)
end
-- Pet display names carry a size prefix (Huge/Small/Normal/...) e.g. "Huge Bunny".
-- Match the species name behind the prefix instead of requiring an exact ObjectText.
local PET_SIZE_PREFIXES = {
	"Small", "Normal", "Medium", "Large", "Huge",
	"Titan", "Titanic", "Gigantic", "Colossal",
	"TripleTitanic", "UltraTitanic", "Omega", "Mythic", "MEGA",
}
local function matchesPetPrompt(objectText, name)
	local t = (objectText or ""):lower()
	local n = (name or ""):lower()
	if t == n then
		return true
	end
	for _, sz in ipairs(PET_SIZE_PREFIXES) do
		if t == (sz .. " " .. n):lower() then
			return true
		end
	end
	return false
end
local function findPetBuyPrompt(name)
	local petSpawns = workspace:FindFirstChild("PetSpawns")
	local pets = petSpawns and petSpawns:FindFirstChild("Pets")
	if not pets then
		return
	end

	for _, model in ipairs(pets:GetChildren()) do
		local prompt = model:FindFirstChild("BuyPetPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt")
			and prompt.ActionText == "Buy"
			and matchesPetPrompt(prompt.ObjectText, name)
		then
			return prompt
		end
	end
end
local function countOwnedPets(name)
	local count = 0
	local pets = Replication and Replication.Data and Replication.Data.pets
	for _, info in pairs(pets or {}) do
		if type(info) == "table" and (info.name == name or info.PetName == name) then
			count += 1
		end
	end
	return count
end

local function activatePetPrompt(prompt)
	return activatePrompt(prompt, 0.5)
end

local function setAutoPetBuy(enabled)
	autoPetBuy = enabled
	autoPetBuyGeneration += 1
	if not enabled then
		return
	end
	if #selectedPetNames == 0 then
		autoPetBuy = false
		notify("Select pet", "Select one or more pets from the dropdown first.")
		return
	end

	local generation = autoPetBuyGeneration
	task.spawn(function()
		local missingNotified = {}
		while autoPetBuy and autoPetBuyGeneration == generation do
			for _, petName in ipairs(selectedPetNames) do
				if not autoPetBuy or autoPetBuyGeneration ~= generation then
					return
				end
				local prompt = findPetBuyPrompt(petName)
				if not prompt then
					if not missingNotified[petName] then
						missingNotified[petName] = true
						notify("Pet unavailable", petName .. " has not spawned in the world.")
					end
					continue
				end

				missingNotified[petName] = nil
				local ownedBefore = countOwnedPets(petName)
				local activated = activatePetPrompt(prompt)
				if activated then
					local deadline = os.clock() + 2
					repeat
						if countOwnedPets(petName) > ownedBefore then
							notify("Buy Pet successful", petName .. " purchased.")
							break
						end
						task.wait(0.1)
					until os.clock() >= deadline or not autoPetBuy or autoPetBuyGeneration ~= generation
				end
				task.wait()
			end
			task.wait(0.5)
		end
	end)
end

local function stop()
	running = false
	applyVisualSpeed()
end

local function start()
	if running then
		return
	end
	if #targetNames == 0 then
		notify("Select target", "Select a target gnome from the dropdown first.")
		return
	end
	running = true
	applyVisualSpeed()
	task.spawn(function()
		local rolls = 0
		while running do
			local ownedBefore = getOwnedGnomesById()
			local preview = getRollPreview()
			local rolledGnomes = {}
			local previewConnection = preview and preview.ChildAdded:Connect(function(model)
				if model:IsA("Model") then
					table.insert(rolledGnomes, model)
				end
			end)
			while running and LocalPlayer:GetAttribute("Rolling") do
				task.wait()
			end
			if not running then
				break
			end

			local ok, result = pcall(Network.InvokeServer, Network, "Roll")
			if not ok or not result then
				if previewConnection then
					previewConnection:Disconnect()
				end
				running = false
				if not ok then
					notify("Auto roll failed", tostring(result))
				else
					notify("Auto roll rejected", "Server did not accept the roll.")
				end
				break
			end

			rolls += 1
			task.wait() -- give one frame for Rolling and roll result data to arrive
			while running and LocalPlayer:GetAttribute("Rolling") do
				task.wait()
			end
			task.wait() -- synchronize Replication and preview updates without a fixed 0.3-second delay
			if previewConnection then
				previewConnection:Disconnect()
			end

			if running and #targetNames > 0 then
				local ownedAfter = getOwnedGnomesById()
				local rolledTarget
				for _, model in ipairs(rolledGnomes) do
					rolledTarget = findSelectedTarget(model.Name, model:GetAttribute("Mutations") or "")
					if rolledTarget then
						break
					end
				end

				for id, farmer in pairs(ownedAfter) do
					if ownedBefore[id] == nil and not findSelectedTarget(farmer.name, farmer.mutations) then
						for _, model in ipairs(rolledGnomes) do
							if model.Name == farmer.name then
								pcall(Network.FireServer, Network, "SellFarmer", id)
								break
							end
						end
					end
				end

				if rolledTarget then
					notify("Target found", ("%s (%d rolls). Auto Roll continues."):format(rolledTarget.label, rolls))
				end

				if autoBuy and rolledTarget then
					local boughtOk, boughtResult = buyGnome(rolledTarget.name, rolledTarget.mutation)
					if boughtOk and boughtResult then
						notify("Auto buy successful", rolledTarget.label .. " purchased! Auto Roll continues.")
					else
						notify("Auto buy failed", rolledTarget.label .. ": " .. tostring(boughtResult))
					end
				end
			end
		end
		applyVisualSpeed()
	end)
end

	startupStage = "window creation"
	setBootstrapStatus("Creating UI...")
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(760, 520)
local mobileWindowSize = UDim2.fromOffset(math.max(viewport.X - 24, 360), math.max(viewport.Y - 24, 300))
local mobileMenuWidth = math.max(math.min(viewport.X - 64, 520), 320)
local windowOptions = {
	Title = "Roll A Gnome",
	Author = "Auto Roll",
	Icon = "dices",
	Theme = "Dark",
	Folder = "RollAGnome",
	Size = isMobile and mobileWindowSize or UDim2.fromOffset(760, 520),
	SideBarWidth = isMobile and 190 or 320,
	OpenButton = {
		Title = "Roll A Gnome",
		Icon = "dices",
		Enabled = true,
		OnlyIcon = isMobile,
		OnlyMobile = false,
		Draggable = true,
		Position = UDim2.new(1, -74, 1, -74),
		CornerRadius = UDim.new(1, 0),
		Scale = 1,
		Color = ColorSequence.new(Color3.fromRGB(65, 159, 24), Color3.fromRGB(34, 139, 94)),
	},
}
local windowOk, Window = pcall(WindUI.CreateWindow, WindUI, windowOptions)
if not windowOk and tostring(Window):lower():find("lacking capability plugin", 1, true) then
	startupStage = "Plugin capability fallback"
	setBootstrapStatus("Executor needs Plugin capability. Retrying...")
	assert(enablePluginCapability(), "executor exposes no working identity setter")
	windowOk, Window = pcall(WindUI.CreateWindow, WindUI, windowOptions)
end
assert(windowOk and Window, "CreateWindow failed: " .. tostring(Window))

local ConfigManager = Window.ConfigManager
local AutoSaveConfig
if ConfigManager then
	local initOk, initialized = pcall(ConfigManager.Init, ConfigManager, Window)
	if initOk and initialized then
		local createOk, config = pcall(ConfigManager.CreateConfig, ConfigManager, "autosave", true)
		if createOk and config then
			AutoSaveConfig = config
			pcall(AutoSaveConfig.SetAsCurrent, AutoSaveConfig)
		end
	end
end

-- Rarity order used for sorting
local RarityOrder = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Godly = 7,
	IMPOSSIBLE = 8,
}

-- Sort gnome list by rarity order then by price
if #GnomeList > 0 then
	table.sort(GnomeList, function(a, b)
		local rA = RarityOrder[a.rarity] or 0
		local rB = RarityOrder[b.rarity] or 0
		if rA ~= rB then
			return rA < rB
		end
		return a.price < b.price
	end)
end
table.sort(PetList, function(a, b)
	local rA = RarityOrder[a.rarity] or 0
	local rB = RarityOrder[b.rarity] or 0
	if rA ~= rB then
		return rA < rB
	end
	if a.order ~= b.order then
		return a.order < b.order
	end
	return a.name < b.name
end)
table.sort(ShopItemList, function(a, b)
	if a.order ~= b.order then
		return a.order < b.order
	end
	return a.name < b.name
end)

local RollTab = Window:Tab({
	Title = "Auto Roll",
	Icon = "rotate-cw",
})
local FarmTab = Window:Tab({
	Title = "Auto Farm",
	Icon = "sprout",
})
local PetTab = Window:Tab({
	Title = "Pet",
	Icon = "paw-print",
})
local ShopTab = Window:Tab({
	Title = "Shop",
	Icon = "shopping-bag",
})
local ItemTab = Window:Tab({
	Title = "Item",
	Icon = "package",
})
local SettingTab = Window:Tab({
	Title = "Setting",
	Icon = "settings",
})

ItemTab:Section({
	Title = "Item Usage",
	Icon = "package-open",
	Box = true,
})

local useItemOptions = {}
local useItemsByName = {}
for _, item in ipairs(ShopItemList) do
	table.insert(useItemOptions, item.name)
	useItemsByName[item.name] = item
end

ItemTab:Dropdown({
	Flag = "SelectedUseItems",
	Title = "Select Item",
	Values = useItemOptions,
	Multi = true,
	Default = {},
	Callback = function(values)
		selectedUseItems = {}
		for _, name in ipairs(values or {}) do
			local item = useItemsByName[name]
			if item then
				table.insert(selectedUseItems, item)
			end
		end
	end,
})

ItemTab:Toggle({
	Flag = "AutoUse",
	Title = "Auto Use",
	Value = false,
	Callback = setAutoUse,
})

ShopTab:Section({
	Title = "Item Shop",
	Icon = "shopping-cart",
	Box = true,
})

local shopOptions = {}
local shopItemsByLabel = {}
for _, item in ipairs(ShopItemList) do
	local label = ("%s | %s"):format(item.name, formatPrice(item.price))
	table.insert(shopOptions, label)
	shopItemsByLabel[label] = item
end

ShopTab:Dropdown({
	Title = "List Item",
	MenuWidth = 380,
	Values = shopOptions,
	Flag = "SelectedShopItems",
	Multi = true,
	Default = {},
	Callback = function(values)
		selectedShopItems = {}
		for _, label in ipairs(values or {}) do
			local item = shopItemsByLabel[label]
			if item then
				table.insert(selectedShopItems, item)
			end
		end
	end,
})

ShopTab:Toggle({
	Title = "Auto Buy",
	Flag = "AutoShopBuy",
	Value = false,
	Callback = setAutoShopBuy,
})

PetTab:Section({
	Title = "Pet Purchase",
	Icon = "shopping-cart",
	Box = true,
})

local petOptions = {}
for _, pet in ipairs(PetList) do
	table.insert(petOptions, ("%s | %s | %s"):format(pet.name, pet.rarity, formatPrice(pet.price)))
end

PetTab:Dropdown({
	Title = "Select Pet",
	Flag = "SelectedPets",
	Values = petOptions,
	Multi = true,
	Default = {},
	Callback = function(values)
		selectedPetNames = {}
		for _, label in ipairs(values or {}) do
			local name = label:match("^(.-)%s*|")
			if name then
				table.insert(selectedPetNames, name)
			end
		end
	end,
})

PetTab:Toggle({
	Flag = "AutoPetBuy",
	Title = "Buy Pet",
	Value = false,
	Callback = setAutoPetBuy,
})

FarmTab:Section({
	Title = "Plant Automation",
	Icon = "wheat",
	Box = true,
})

FarmTab:Toggle({
	Flag = "AutoFarm",
	Title = "Auto Farm",
	Value = false,
	Callback = setAutoFarm,
})

FarmTab:Toggle({
	Title = "Auto Sell",
	Flag = "AutoSell",
	Value = false,
	Callback = setAutoSell,
})

RollTab:Section({
	Title = "Gnome Target",
	Icon = "target",
	Box = true,
})

local optionTargets = {}
local function buildGnomeOptions()
	local options = table.create(#GnomeList * #MutationList)
	for _, gnome in ipairs(GnomeList) do
		for _, mutation in ipairs(MutationList) do
			local displayName = mutation.name == "" and gnome.name or ("%s [%s]"):format(gnome.name, mutation.label)
			local price = Mutations:buffStat(gnome.price, mutation.name)
			local label = ("%s | %s | %s | %s"):format(gnome.name, mutation.label, gnome.rarity, formatPrice(price))
			table.insert(options, label)
			optionTargets[label] = {
				name = gnome.name,
				mutation = mutation.name,
				label = displayName,
			}
		end
	end
	return options
end

local gnomeOptionsLoaded = false

local GnomeDropdown = RollTab:Dropdown({
	Title = "Select Gnome",
	MenuWidth = isMobile and mobileMenuWidth or 640,
	Values = {},
	Flag = "SelectedGnomes",
	SearchBarEnabled = true,
	Multi = true,
	Default = {},
	Callback = function(value)
		targetNames = {}
		selectedTargets = {}
		for _, label in ipairs(value or {}) do
			local target = optionTargets[label]
			if target then
				table.insert(targetNames, target.label)
				selectedTargets[targetKey(target.name, target.mutation)] = target
			end
		end
	end,
})

local gnomeMenuConstraint = GnomeDropdown.UIElements.MenuCanvas:FindFirstChildWhichIsA("UISizeConstraint")
if gnomeMenuConstraint then
	gnomeMenuConstraint.MaxSize = isMobile and Vector2.new(mobileMenuWidth + 20, math.max(viewport.Y - 80, 240))
		or Vector2.new(680, 400)
end

-- WindUI creates every option row during Refresh. Delay that work until this menu is used.
GnomeDropdown.UIElements.Dropdown.MouseButton1Click:Connect(function()
	if not gnomeOptionsLoaded then
		GnomeDropdown:Refresh(buildGnomeOptions())
		gnomeOptionsLoaded = true
	end
end)

RollTab:Section({
	Title = "Settings",
	Icon = "settings",
	Box = true,
})

RollTab:Toggle({
	Flag = "FastRoll",
	Title = "Fast Roll",
	Value = true,
	Callback = function(enabled)
		skipVisuals = enabled
		applyVisualSpeed()
	end,
})

RollTab:Toggle({
	Flag = "AutoBuyRolledGnome",
	Title = "Auto Buy",
	Value = false,
	Callback = function(enabled)
		autoBuy = enabled
	end,
})

RollTab:Toggle({
	Title = "Auto Roll",
	Flag = "AutoRoll",
	Value = false,
	Callback = function(enabled)
		if enabled then
			start()
		else
			stop()
		end
	end,
})

RollTab:Button({
	Title = "Roll Once",
	Icon = "dice-5",
	Callback = function()
		if LocalPlayer:GetAttribute("Rolling") then
			notify("Still rolling", "Wait for the current roll to finish.")
			return
		end
		applyVisualSpeed()

		local ok, result = pcall(Network.InvokeServer, Network, "Roll")
		if ok and result then
			notify("Roll sent", "Server accepted the roll.")
		else
			notify("Auto roll failed", tostring(result))
		end
	end,
})

RollTab:Paragraph({
	Title = "Target: " .. ( #targetNames > 0 and table.concat(targetNames, ", ") or "-" ),
})

SettingTab:Section({
	Title = "Settings",
	Icon = "settings",
	Box = true,
})

SettingTab:Toggle({
	Title = "Anti AFK",
	Icon = "shield",
	Flag = "AntiAFK",
	Value = false,
	Callback = setAntiAfk,
})

SettingTab:Toggle({
	Title = "Hide Username",
	Icon = "eye-off",
	Flag = "HideUsername",
	Value = false,
	Callback = function(state)
		hideUsernameEnabled = state
		SetLocalNameplateVisible(not state)
	end,
})

SettingTab:Toggle({
	Title = "Auto Save",
	Icon = "save",
	Value = true,
	Flag = "AutoSave",
	Callback = function(state)
		autoSaveEnabled = state
	end,
})

if AutoSaveConfig then
	pcall(AutoSaveConfig.Load, AutoSaveConfig)
	task.spawn(function()
		while Window do
			task.wait(2)
			if autoSaveEnabled then
				pcall(AutoSaveConfig.Save, AutoSaveConfig)
			end
		end
	end)
end

notify("Roll A Gnome ready", isMobile and "Tap the floating button to open the UI." or "Press Insert to show or hide the UI.")
if bootstrapGui then
	bootstrapGui:Destroy()
end
	startupStage = "ready"
end, function(err)
	local message = startupStage .. ": " .. tostring(err)
	if debug and type(debug.traceback) == "function" then
		local ok, trace = pcall(debug.traceback, message, 2)
		if ok then
			return trace
		end
	end
	return message
end)

if not bootstrapOk then
	setBootstrapStatus("Startup failed: " .. tostring(bootstrapError), true)
end

executorEnvironment.cloneref = originalCloneRef
executorEnvironment.clonereference = originalCloneReference
