local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local trashLoopModules = ReplicatedStorage:WaitForChild("TrashLoopModules")
local dropTables = trashLoopModules:WaitForChild("DropTables")
local bagDropTables = dropTables:WaitForChild("TrashBagDropTables")

local BagSizeDrops = require(bagDropTables:WaitForChild("BagSizeDrops"))
local BagRarityDrops = require(bagDropTables:WaitForChild("BagRarityDrops"))
local BagTypeDrops = require(bagDropTables:WaitForChild("BagTypeDrops"))

local bagModules = trashLoopModules:WaitForChild("TrashBagModules")
local trashBagsStorage = ServerStorage:WaitForChild("TrashLoop"):WaitForChild("TrashBags")
local trashBagsFolder = workspace:WaitForChild("AllTrashBags")

local mutationModules = trashLoopModules:WaitForChild("MutationModules")
local MutationVisuals = require(mutationModules:WaitForChild("MutationVisuals"))
local rainbowTextScript = mutationModules:WaitForChild("RainbowText")

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 200, 255),
	Uncommon = Color3.fromRGB(80, 255, 80),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 188, 80),
	Mythical = Color3.fromRGB(255, 60, 60),
	Secret = Color3.fromRGB(255, 255, 255)
}

local DESPAWN_TIME = 180

local MUTATION_SPREAD_CHANCE = {
	Gold = 0.25,      -- 25% chance
	Diamond = 0.25,   -- 25% chance
	Rainbow = 0.10    -- 10% chance
}

local activeBags = {} -- ALL SPAWNED BAGS

local TrashBagSpawner = {} -- Spawner

-- Rolls the drop table
local function rollDrop(dropTable)
	local totalWeight = 0
	for _, entry in ipairs(dropTable) do
		totalWeight += entry.weight
	end

	local roll = math.random(1, totalWeight)
	local cumulative = 0

	for _, entry in ipairs(dropTable) do
		cumulative += entry.weight
		if roll <= cumulative then
			return entry.module or entry.count
		end
	end
end

-- Rolls the rarity table
local function rollRarity(rarityTable)
	local totalWeight = 0
	for _, entry in ipairs(rarityTable) do
		totalWeight += entry.weight
	end

	local roll = math.random(1, totalWeight)
	local cumulative = 0

	for _, entry in ipairs(rarityTable) do
		cumulative += entry.weight
		if roll <= cumulative then
			return entry.rarity  -- Return .rarity instead of .module
		end
	end
end

-- Rolls bag count.
function TrashBagSpawner.rollBagCount(size)
	if not BagSizeDrops[size] then
		warn("Invalid size: " .. tostring(size))
		return 1
	end

	return rollDrop(BagSizeDrops[size])
end

-- Rolls bag rarities.
function TrashBagSpawner.rollBagRarities(binRarity, bagCount)
	local rarities = {}

	-- First bag is guaranteed to match bin rarity
	table.insert(rarities, binRarity)

	-- Roll remaining bags from the bin's rarity drop table
	for i = 2, bagCount do
		local rolledRarity = rollRarity(BagRarityDrops[binRarity])
		table.insert(rarities, rolledRarity)
	end

	return rarities
end

-- Roll for specific bag type.
function TrashBagSpawner.rollBagType(rarity)
	if not BagTypeDrops[rarity] then
		warn("Invalid rarity for bag type: " .. tostring(rarity))
		return nil
	end

	return rollDrop(BagTypeDrops[rarity])
end

-- Rolls for possibility of mutation.
function TrashBagSpawner.rollBagMutations(binMutation, bagCount)
	if not binMutation then
		-- No mutation on bin = no mutations on bags
		return table.create(bagCount, nil)
	end

	local mutations = {}
	local guaranteedIndex = math.random(1, bagCount) -- Random bag gets guaranteed mutation
	local spreadChance = MUTATION_SPREAD_CHANCE[binMutation] or 0

	for i = 1, bagCount do
		if i == guaranteedIndex then
			-- Guarantee one mutated bag
			mutations[i] = binMutation
		else
			-- Roll for mutation spread
			if math.random() < spreadChance then
				mutations[i] = binMutation
			else
				mutations[i] = nil
			end
		end
	end

	return mutations
end

-- Applies name tag
function TrashBagSpawner.applyBagNameTag(model, bagData, mutation)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 150, 0, 100)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true

	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	billboard.Adornee = adornee

	-- Mutation label (if applicable)
	if mutation then
		local mutationLabel = Instance.new("TextLabel")
		mutationLabel.Name = "MutationLabel"
		mutationLabel.BackgroundTransparency = 1
		mutationLabel.Size = UDim2.new(1, 0, 0, 24)
		mutationLabel.Position = UDim2.new(0, 0, 0, 0)
		mutationLabel.Text = mutation
		mutationLabel.TextScaled = false
		mutationLabel.TextSize = 16
		mutationLabel.Font = Enum.Font.FredokaOne
		mutationLabel.Parent = billboard

		local mutationStroke = Instance.new("UIStroke")
		mutationStroke.Thickness = 2
		mutationStroke.Color = Color3.fromRGB(0, 0, 0)
		mutationStroke.Parent = mutationLabel

		-- Rainbow text effect
		if mutation == "Rainbow" then
			local rainbowClone = rainbowTextScript:Clone()
			rainbowClone.Enabled = true
			rainbowClone.Parent = mutationLabel
		elseif mutation == "Gold" then
			mutationLabel.TextColor3 = Color3.fromRGB(239, 184, 56)
		elseif mutation == "Diamond" then
			mutationLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
		end
	end

	-- Name label
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 28)
	label.Position = UDim2.new(0, 0, 0, mutation and 24 or 0)
	label.Text = bagData.name
	label.TextScaled = false
	label.TextSize = 18
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(239, 239, 239)
	label.Parent = billboard

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Thickness = 2
	uiStroke.Color = Color3.fromRGB(0, 0, 0)
	uiStroke.Parent = label

	-- Rarity label
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Size = UDim2.new(1, 0, 0, 22)
	rarityLabel.Position = UDim2.new(0, 0, 0, mutation and 52 or 28)
	rarityLabel.Text = bagData.rarity
	rarityLabel.TextScaled = false
	rarityLabel.TextSize = 16
	rarityLabel.Font = Enum.Font.FredokaOne
	rarityLabel.TextColor3 = RARITY_COLORS[bagData.rarity]
	rarityLabel.Parent = billboard

	local uiStrokeRar = Instance.new("UIStroke")
	uiStrokeRar.Thickness = 2
	uiStrokeRar.Color = Color3.fromRGB(0, 0, 0)
	uiStrokeRar.Parent = rarityLabel

	-- Timer label
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, 0, 0, 20)
	timerLabel.Position = UDim2.new(0, 0, 0, mutation and 74 or 50)
	timerLabel.Text = "3:00"
	timerLabel.TextScaled = false
	timerLabel.TextSize = 14
	timerLabel.Font = Enum.Font.FredokaOne
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerLabel.Parent = billboard

	local timerStroke = Instance.new("UIStroke")
	timerStroke.Thickness = 2
	timerStroke.Color = Color3.fromRGB(0, 0, 0)
	timerStroke.Parent = timerLabel

	billboard.Parent = model
end

-- Main spawner function.
function TrashBagSpawner.spawnBag(bagModuleName, spawnPosition, mutation, index, totalBags)
	-- Load bag module data
	local moduleScript = bagModules:FindFirstChild(bagModuleName)
	if not moduleScript then
		warn("Bag module not found: " .. tostring(bagModuleName))
		return
	end

	local bagData = require(moduleScript)

	-- Get bag model from storage
	local model = trashBagsStorage:FindFirstChild(bagData.storeName)
	if not model then
		warn("Bag model missing for: " .. tostring(bagData.storeName))
		return
	end

	-- Clone bag
	local clone = model:Clone()

	-- Store mutation if present
	if mutation then
		local mutationValue = Instance.new("StringValue")
		mutationValue.Name = "Mutation"
		mutationValue.Value = mutation
		mutationValue.Parent = clone
	end

	-- Calculate launch angle (spread bags in circle)
	local angleStep = (math.pi * 2) / totalBags
	local angle = angleStep * (index - 1)

	-- Random distance (between 8-15 studs from center)
	local distance = math.random(80, 150) / 10

	-- Calculate target position
	local targetX = spawnPosition.X + math.cos(angle) * distance
	local targetZ = spawnPosition.Z + math.sin(angle) * distance
	local targetY = spawnPosition.Y -- Ground level

	local targetPosition = Vector3.new(targetX, targetY, targetZ)
	

	-- Set initial position (slightly above spawn point)
	clone:SetPrimaryPartCFrame(CFrame.new(spawnPosition + Vector3.new(0, 2, 0)))
	clone.Parent = trashBagsFolder

	-- Apply mutation visuals
	if mutation then
		if mutation == "Gold" then
			MutationVisuals.applyGold(clone)
		elseif mutation == "Diamond" then
			MutationVisuals.applyDiamond(clone)
		elseif mutation == "Rainbow" then
			MutationVisuals.applyRainbow(clone)
		end
	end

	-- Apply nametag
	TrashBagSpawner.applyBagNameTag(clone, bagData, mutation)

	-- Create trail
	local primaryPart = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if primaryPart then
		local attachment0 = Instance.new("Attachment", primaryPart)
		local attachment1 = Instance.new("Attachment", primaryPart)
		attachment1.Position = Vector3.new(0, 1, 0)

		local trail = Instance.new("Trail")
		trail.Attachment0 = attachment0
		trail.Attachment1 = attachment1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.5
		trail.MinLength = 0
		trail.Parent = primaryPart
	end
	
	-- Add ProximityPrompt
	local primaryPart = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
	if primaryPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick up"
		prompt.ObjectText = bagData.name
		prompt.HoldDuration = 3 -- 3 second hold
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = primaryPart
	end

	-- Animate parabolic arc
	task.spawn(function()
		local startPos = clone:GetPrimaryPartCFrame().Position
		local duration = 0.8
		local height = 12 -- Arc height

		local elapsed = 0
		while elapsed < duration do
			elapsed += task.wait()
			local t = math.min(elapsed / duration, 1)

			-- Parabolic interpolation
			local currentX = startPos.X + (targetPosition.X - startPos.X) * t
			local currentZ = startPos.Z + (targetPosition.Z - startPos.Z) * t
			local currentY = startPos.Y + (targetPosition.Y - startPos.Y) * t + height * math.sin(t * math.pi)

			clone:SetPrimaryPartCFrame(CFrame.new(currentX, currentY, currentZ))
		end

		local rayOrigin = targetPosition + Vector3.new(0, 50, 0)
		local rayDirection = Vector3.new(0, -500, 0) -- 500 studs down

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {clone, trashBagsFolder}

		local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

		if rayResult then
			-- Position bag on ground
			local groundY = rayResult.Position.Y

			-- Find lowest point of bag (similar to your bin spawning logic)
			local lowestY = math.huge
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					local size = part.Size
					local cf = part.CFrame

					local corners = {
						cf * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
						cf * CFrame.new(-size.X/2, -size.Y/2, size.Z/2),
						cf * CFrame.new(-size.X/2, size.Y/2, -size.Z/2),
						cf * CFrame.new(-size.X/2, size.Y/2, size.Z/2),
						cf * CFrame.new(size.X/2, -size.Y/2, -size.Z/2),
						cf * CFrame.new(size.X/2, -size.Y/2, size.Z/2),
						cf * CFrame.new(size.X/2, size.Y/2, -size.Z/2),
						cf * CFrame.new(size.X/2, size.Y/2, size.Z/2),
					}

					for _, corner in ipairs(corners) do
						if corner.Y < lowestY then
							lowestY = corner.Y
						end
					end
				end
			end

			-- Calculate lift amount
			local liftAmount = groundY - lowestY
			local currentCF = clone:GetPrimaryPartCFrame()
			clone:SetPrimaryPartCFrame(currentCF + Vector3.new(0, liftAmount, 0))
		else
			-- Fallback if raycast fails
			clone:SetPrimaryPartCFrame(CFrame.new(targetPosition))
		end
	end)


	-- Track for despawn
	activeBags[clone] = {
		spawnTime = tick(),
		duration = DESPAWN_TIME
	}

	-- TODO: Add proximity prompt here later

	return clone
end


-- Main function: spawns all bags from a destroyed bin
function TrashBagSpawner.spawnBagsFromBin(binModel, binData)
	local binRarity = binData.rarity
	local binSize = binData.size or "Normal" -- Default to Normal if not specified
	local binMutation = binModel:FindFirstChild("Mutation") and binModel.Mutation.Value or nil

	-- Step 1: Roll bag count
	local bagCount = TrashBagSpawner.rollBagCount(binSize)

	-- Step 2: Roll bag rarities
	local bagRarities = TrashBagSpawner.rollBagRarities(binRarity, bagCount)

	-- Step 3: Roll mutations
	local bagMutations = TrashBagSpawner.rollBagMutations(binMutation, bagCount)

	-- Step 4: Spawn each bag
	local spawnPosition = binModel.PrimaryPart.Position

	for i = 1, bagCount do
		local rarity = bagRarities[i]
		local bagModuleName = TrashBagSpawner.rollBagType(rarity)
		local mutation = bagMutations[i]

		TrashBagSpawner.spawnBag(bagModuleName, spawnPosition, mutation, i, bagCount)

		-- Small delay between spawns for visual effect
		task.wait(0.05)
	end
end


-- Despawn timer (runs on Heartbeat)
RunService.Heartbeat:Connect(function()
	local currentTime = tick()

	for bag, data in pairs(activeBags) do
		-- Clean up destroyed bags
		if not bag.Parent then
			activeBags[bag] = nil
			continue
		end

		-- Calculate remaining time
		local elapsed = currentTime - data.spawnTime
		local remaining = math.max(0, data.duration - elapsed)

		-- Update timer display
		local billboard = bag:FindFirstChild("NameTag")
		if billboard then
			local timerLabel = billboard:FindFirstChild("TimerLabel")
			if timerLabel then
				local minutes = math.floor(remaining / 60)
				local seconds = math.floor(remaining % 60)
				timerLabel.Text = string.format("%d:%02d", minutes, seconds)
			end
		end

		-- Despawn when time is up
		if remaining <= 0 then
			activeBags[bag] = nil
			bag:Destroy()
		end
	end
end)


return TrashBagSpawner