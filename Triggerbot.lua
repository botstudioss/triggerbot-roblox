local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local IGNORE_TEAMMATES = true
local fovRadius = 150

local lockedPlayer

local function isVisible(targetPart, camera)
	local direction = targetPart.Position - camera.CFrame.Position
	if direction.Magnitude == 0 then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}
	local hit = workspace:Raycast(camera.CFrame.Position, direction, params)
	return not hit or hit.Instance:IsDescendantOf(targetPart.Parent)
end

local function getTargetPart(targetPlayer)
	if not targetPlayer or targetPlayer == player or targetPlayer.Parent ~= Players then
		return nil
	end
	if IGNORE_TEAMMATES and player.Team and targetPlayer.Team == player.Team then
		return nil
	end

	local character = targetPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if humanoid and humanoid.Health > 0 and head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function getClosestPlayer()
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mousePosition = UserInputService:GetMouseLocation()
	local closestPlayer
	local closestDistance = fovRadius

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local targetPart = getTargetPart(targetPlayer)
		if targetPart then
			local screenPosition, onScreen = camera:WorldToScreenPoint(targetPart.Position)
			if onScreen and screenPosition.Z > 0 then
				local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mousePosition).Magnitude
				if distance <= closestDistance and isVisible(targetPart, camera) then
					closestDistance = distance
					closestPlayer = targetPlayer
				end
			end
		end
	end

	return closestPlayer
end

RunService:BindToRenderStep("Camlock", Enum.RenderPriority.Camera.Value + 1, function()
	if not lockedPlayer then return end

	local targetPart = getTargetPart(lockedPlayer)
	if not targetPart then
		lockedPlayer = nil
		return
	end

	local camera = workspace.CurrentCamera
	if camera then
		local position = camera.CFrame.Position
		if (targetPart.Position - position).Magnitude > 0 then
			camera.CFrame = CFrame.lookAt(position, targetPart.Position)
		end
	end
end)

do
	local enabled = false
	local overlays = {}
	local keys = {
		Camlock = Enum.KeyCode.Q,
		ESP = Enum.KeyCode.T,
		Menu = Enum.KeyCode.RightShift
	}
	local waitingForKey
	local keyButtons = {}
	local palette = {
		{Name = "Gray", Value = Color3.fromRGB(128, 128, 128)},
		{Name = "Red", Value = Color3.fromRGB(255, 75, 75)},
		{Name = "White", Value = Color3.fromRGB(255, 255, 255)},
		{Name = "Blue", Value = Color3.fromRGB(75, 150, 255)},
		{Name = "Green", Value = Color3.fromRGB(75, 220, 100)}
	}
	local colorIndexes = {Visible = 1, Hidden = 2, FOV = 3}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlayerESP"
	screenGui.DisplayOrder = 2147483647
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	if type(gethui) == "function" then
		screenGui.Parent = assert(gethui(), "gethui() did not return a UI container")
	else
		screenGui.Parent = player:WaitForChild("PlayerGui")
	end

	local circle = Instance.new("Frame")
	circle.Name = "FOVCircle"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.BackgroundTransparency = 1
	circle.Parent = screenGui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = circle

	local circleOutline = Instance.new("UIStroke")
	circleOutline.Thickness = 2
	circleOutline.Parent = circle

	local menu = Instance.new("Frame")
	menu.Name = "Settings"
	menu.Size = UDim2.fromOffset(500, 350)
	menu.Position = UDim2.fromOffset(20, 100)
	menu.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	menu.BorderColor3 = Color3.fromRGB(70, 70, 70)
	menu.ZIndex = 10
	menu.Visible = false
	menu.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(6, 0)
	title.Size = UDim2.new(1, -12, 0, 25)
	title.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	title.BorderSizePixel = 0
	title.Text = "Azure | @socialdw | .gg/azuremodded"
	title.Font = Enum.Font.Code
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Parent = menu

	local separator = Instance.new("Frame")
	separator.Position = UDim2.fromOffset(5, 25)
	separator.Size = UDim2.new(1, -10, 0, 1)
	separator.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	separator.BorderSizePixel = 0
	separator.Parent = menu

	local pages = {}
	local tabs = {}
	for index, name in ipairs({"Aimbot", "Player", "Visuals"}) do
		local page = Instance.new("Frame")
		page.Name = name .. "Page"
		page.Position = UDim2.fromOffset(8, 55)
		page.Size = UDim2.new(1, -16, 1, -63)
		page.BackgroundTransparency = 1
		page.Visible = name == "Aimbot"
		page.Parent = menu
		pages[name] = page

		local tab = Instance.new("TextButton")
		tab.Name = name .. "Tab"
		tab.Position = UDim2.fromOffset(8 + (index - 1) * 78, 28)
		tab.Size = UDim2.fromOffset(76, 24)
		tab.BackgroundTransparency = 1
		tab.Text = name
		tab.Font = Enum.Font.Code
		tab.TextSize = 15
		tab.TextColor3 = name == "Aimbot" and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(155, 155, 155)
		tab.Parent = menu
		tabs[name] = tab
		tab.MouseButton1Click:Connect(function()
			for pageName, otherPage in pairs(pages) do
				otherPage.Visible = pageName == name
				tabs[pageName].TextColor3 = pageName == name
					and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(155, 155, 155)
			end
		end)
	end

	local function makeSection(page, name, x)
		local section = Instance.new("Frame")
		section.Position = UDim2.fromOffset(x, 0)
		section.Size = UDim2.new(0, 236, 1, 0)
		section.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		section.BorderColor3 = Color3.fromRGB(60, 60, 60)
		section.Parent = page

		local heading = Instance.new("TextLabel")
		heading.Position = UDim2.fromOffset(8, 5)
		heading.Size = UDim2.new(1, -16, 0, 20)
		heading.BackgroundTransparency = 1
		heading.Text = name
		heading.TextColor3 = Color3.fromRGB(230, 230, 230)
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.Font = Enum.Font.Code
		heading.TextSize = 14
		heading.Parent = section

		local line = Instance.new("Frame")
		line.Position = UDim2.fromOffset(8, 25)
		line.Size = UDim2.new(1, -16, 0, 1)
		line.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
		line.BorderSizePixel = 0
		line.Parent = section
		return section
	end

	local keySection = makeSection(pages.Aimbot, "Keybinds", 0)
	local fovSection = makeSection(pages.Aimbot, "Field of view", 248)
	local teamSection = makeSection(pages.Player, "Team check", 0)
	local visibilitySection = makeSection(pages.Player, "Visibility check", 248)
	local espColors = makeSection(pages.Visuals, "ESP colors", 0)
	local fovColors = makeSection(pages.Visuals, "FOV color", 248)

	local function makeLabel(parent, text, y, height)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromOffset(8, y)
		label.Size = UDim2.new(1, -16, 0, height or 24)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = Color3.fromRGB(180, 180, 180)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.Font = Enum.Font.Code
		label.TextSize = 14
		label.Parent = parent
		return label
	end

	makeLabel(teamSection, "Teammates are skipped when you share a team.", 33, 48)
	makeLabel(visibilitySection, "Camlock selects visible players only.", 33, 48)
	makeLabel(visibilitySection, "Existing locks stay active behind walls.", 85, 48)

	local function makeButton(parent, y, width, x)
		local button = Instance.new("TextButton")
		button.Position = UDim2.fromOffset(x or 8, y)
		button.Size = UDim2.fromOffset(width or 220, 26)
		button.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
		button.BorderColor3 = Color3.fromRGB(10, 10, 10)
		button.TextColor3 = Color3.fromRGB(220, 220, 220)
		button.Font = Enum.Font.Code
		button.TextSize = 14
		button.Parent = parent
		return button
	end

	local function refreshKeyButtons()
		for name, button in pairs(keyButtons) do
			button.Text = name .. " key: " .. (waitingForKey == name and "Press a key..." or keys[name].Name)
		end
	end

	for index, name in ipairs({"Camlock", "ESP", "Menu"}) do
		local button = makeButton(keySection, 35 + (index - 1) * 32)
		keyButtons[name] = button
		button.MouseButton1Click:Connect(function()
			waitingForKey = name
			refreshKeyButtons()
		end)
	end
	refreshKeyButtons()
	makeLabel(keySection, "Click a key to rebind it. Escape cancels.", 145, 50)

	for index, name in ipairs({"Visible", "Hidden", "FOV"}) do
		local section = name == "FOV" and fovColors or espColors
		local y = name == "Hidden" and 67 or 35
		local button = makeButton(section, y)
		local function refreshColorButton()
			button.Text = name .. " color: " .. palette[colorIndexes[name]].Name
		end
		refreshColorButton()
		button.MouseButton1Click:Connect(function()
			colorIndexes[name] = colorIndexes[name] % #palette + 1
			refreshColorButton()
		end)
	end

	local radiusLabel = makeLabel(fovSection, "", 35)
	local function updateRadius()
		radiusLabel.Text = "FOV radius: " .. fovRadius
	end
	updateRadius()
	local decrease = makeButton(fovSection, 66, 104, 8)
	decrease.Text = "-"
	decrease.MouseButton1Click:Connect(function()
		fovRadius = math.max(25, fovRadius - 25)
		updateRadius()
	end)
	local increase = makeButton(fovSection, 66, 104, 124)
	increase.Text = "+"
	increase.MouseButton1Click:Connect(function()
		fovRadius = math.min(1000, fovRadius + 25)
		updateRadius()
	end)

	local function addPlayer(targetPlayer)
		if targetPlayer == player or overlays[targetPlayer] then return end

		local box = Instance.new("Frame")
		box.Name = targetPlayer.Name
		box.BackgroundTransparency = 1
		box.Visible = false
		box.Parent = screenGui

		local outline = Instance.new("UIStroke")
		outline.Thickness = 2
		outline.Parent = box

		local username = Instance.new("TextLabel")
		username.Name = "Username"
		username.BackgroundTransparency = 1
		username.Position = UDim2.new(0, 0, 1, 2)
		username.Size = UDim2.new(1, 0, 0, 18)
		username.Font = Enum.Font.SourceSansBold
		username.Text = targetPlayer.Name
		username.TextColor3 = Color3.fromRGB(255, 255, 255)
		username.TextSize = 14
		username.TextStrokeTransparency = 0
		username.Parent = box

		local distance = Instance.new("TextLabel")
		distance.Name = "Distance"
		distance.BackgroundTransparency = 1
		distance.Position = UDim2.new(0, 0, 1, 20)
		distance.Size = UDim2.new(1, 0, 0, 18)
		distance.Font = Enum.Font.SourceSans
		distance.TextColor3 = Color3.fromRGB(255, 255, 255)
		distance.TextSize = 14
		distance.TextStrokeTransparency = 0
		distance.Parent = box

		overlays[targetPlayer] = {box = box, outline = outline, distance = distance}
	end

	local function removePlayer(targetPlayer)
		local overlay = overlays[targetPlayer]
		if overlay then
			overlay.box:Destroy()
			overlays[targetPlayer] = nil
		end
	end

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		addPlayer(targetPlayer)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	UserInputService.InputBegan:Connect(function(input)
		if UserInputService:GetFocusedTextBox() then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local key = input.KeyCode

		if waitingForKey then
			if key == Enum.KeyCode.Escape then
				waitingForKey = nil
			elseif key ~= Enum.KeyCode.Unknown then
				local duplicate = false
				for name, existing in pairs(keys) do
					if name ~= waitingForKey and existing == key then
						duplicate = true
					end
				end
				if duplicate then
					StarterGui:SetCore("SendNotification", {
						Title = "Settings",
						Text = "That key is already in use.",
						Duration = 3
					})
				else
					keys[waitingForKey] = key
					waitingForKey = nil
				end
			end
			refreshKeyButtons()
			return
		end

		if key == keys.Menu then
			menu.Visible = not menu.Visible
			StarterGui:SetCore("SendNotification", {
				Title = "Settings",
				Text = menu.Visible and "Settings opened" or "Settings closed",
				Duration = 3
			})
		elseif key == keys.Camlock then
			local message
			if lockedPlayer then
				message = "Unlocked from " .. lockedPlayer.Name
				lockedPlayer = nil
			else
				lockedPlayer = getClosestPlayer()
				message = lockedPlayer and ("Locked onto " .. lockedPlayer.Name)
					or "No visible player in FOV"
			end
			StarterGui:SetCore("SendNotification", {
				Title = "Camlock",
				Text = message,
				Duration = 3
			})
		elseif key == keys.ESP then
			enabled = not enabled
			if not enabled then
				for _, overlay in pairs(overlays) do
					overlay.box.Visible = false
				end
			end
			StarterGui:SetCore("SendNotification", {
				Title = "ESP",
				Text = enabled and "ESP enabled" or "ESP disabled",
				Duration = 3
			})
		end
	end)

	RunService.RenderStepped:Connect(function()
		local mousePosition = UserInputService:GetMouseLocation()
		circle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		circle.Size = UDim2.fromOffset(fovRadius * 2, fovRadius * 2)
		circleOutline.Color = palette[colorIndexes.FOV].Value
		if not enabled then return end

		local camera = workspace.CurrentCamera
		for targetPlayer, overlay in pairs(overlays) do
			local box = overlay.box
			local character = targetPlayer.Character
			local targetPart = getTargetPart(targetPlayer)
			if camera and character and character.Parent and targetPart then
				local center, size = character:GetBoundingBox()
				local minX, minY = math.huge, math.huge
				local maxX, maxY = -math.huge, -math.huge
				local inFront = true

				for x = -1, 1, 2 do
					for y = -1, 1, 2 do
						for z = -1, 1, 2 do
							local corner = center:PointToWorldSpace(Vector3.new(
								size.X * x / 2, size.Y * y / 2, size.Z * z / 2
							))
							local point = camera:WorldToViewportPoint(corner)
							if point.Z <= 0 then
								inFront = false
							else
								minX = math.min(minX, point.X)
								minY = math.min(minY, point.Y)
								maxX = math.max(maxX, point.X)
								maxY = math.max(maxY, point.Y)
							end
						end
					end
				end

				local viewport = camera.ViewportSize
				box.Visible = inFront and maxX >= 0 and maxY >= 0
					and minX <= viewport.X and minY <= viewport.Y
				if box.Visible then
					box.Position = UDim2.fromOffset(minX, minY)
					box.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
					local colorName = isVisible(targetPart, camera) and "Visible" or "Hidden"
					overlay.outline.Color = palette[colorIndexes[colorName]].Value
					local localRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local origin = localRoot and localRoot.Position or camera.CFrame.Position
					local targetRoot = character:FindFirstChild("HumanoidRootPart")
					local targetPosition = targetRoot and targetRoot.Position or targetPart.Position
					overlay.distance.Text = string.format("%.0f studs", (targetPosition - origin).Magnitude)
				end
			else
				box.Visible = false
			end
		end
	end)
end

StarterGui:SetCore("SendNotification", {
	Title = "Notification",
	Text = "made by /azuremodded",
	Duration = 5
})

local mouse = player:GetMouse()
local ContextActionService = game:GetService("ContextActionService")
local AUTO_SHOOT_ENABLED = true

local WHITELISTED_TOOLS = {
	["[Revolver]"] = true,
	["[Double-Barrel SG]"] = true,
	["[TacticalShotgun]"] = true
}

local KICK_MESSAGE = [[No supported tools were found in this experience.
This script requires at least one compatible weapon tool to function correctly.

Please contact the creator on Discord (@socialdw) for assistance.

The creator will resolve this by adding your tool to the supported whitelist.

Make sure to include the game link and a screenshot of this kick message.

No reply = Jerking off (DO NOT DISTURB!)]]

local leftHeld = false
local mouseDown = false
local holdStartTime = 0
local holdThreshold = 0.25
local lastTarget
local canShoot = true
local isCrouching = false
local autoFired = false

local shotDelays = {0}

local function getEquippedTool()
	local char = player.Character
	if char then
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then
				return tool
			end
		end
	end
	return nil
end

local function isFriendly(targetPlayer)
	if not targetPlayer then return false end
	if targetPlayer == player then return true end
	if IGNORE_TEAMMATES and player.Team and targetPlayer.Team and player.Team == targetPlayer.Team then
		return true
	end
	return false
end

local function isGun(tool)
	if not tool or not tool:IsA("Tool") then return false end
	if WHITELISTED_TOOLS[tool.Name] then return true end
	for _, child in ipairs(tool:GetChildren()) do
		if child:IsA("Script") or child:IsA("LocalScript") then
			if string.match(child.Name:lower(), "gun") then
				return true
			end
		end
		if child:IsA("RemoteEvent") then
			return true
		end
		if child:IsA("Folder") then
			for _, sub in ipairs(child:GetDescendants()) do
				if sub:IsA("RemoteEvent") then
					return true
				end
			end
		end
	end
	local handle = tool:FindFirstChild("Handle")
	if handle then
		for _, sound in ipairs(handle:GetDescendants()) do
			if sound:IsA("Sound") and string.match(sound.Name:lower(), "shoot") then
				return true
			end
		end
	end
	return false
end

local function scanAllToolsSafely()
	local allObjects = {}
	for _, service in ipairs(game:GetChildren()) do
		table.insert(allObjects, service)
	end
	local index = 1
	local batchSize = 20
	local found = false

	local function scanBatch()
		local processed = 0
		while index <= #allObjects and processed < batchSize do
			local obj = allObjects[index]
			index = index + 1
			processed = processed + 1
			if obj:IsA("Tool") and isGun(obj) then
				found = true
				return
			end
			for _, child in ipairs(obj:GetChildren()) do
				table.insert(allObjects, child)
			end
		end
		if not found and index <= #allObjects then
			RunService.Heartbeat:Wait()
			task.spawn(scanBatch)
		elseif not found then
			player:Kick(KICK_MESSAGE)
		end
	end

	task.spawn(scanBatch)
end

local function attemptLocalFire()
	if not AUTO_SHOOT_ENABLED or isCrouching then return false end
	local tool = getEquippedTool()
	if tool and isGun(tool) and canShoot then
		canShoot = false
		autoFired = true
		pcall(function()
			tool:Activate()
			if tool:IsA("Tool") and tool:FindFirstChildOfClass("RemoteEvent") == nil then
				if tool:FindFirstChild("Handle") then
					task.wait(0.01)
					tool:Deactivate()
				else
					tool:Deactivate()
				end
			else
				tool:Deactivate()
			end
		end)
		local delayTime = shotDelays[math.random(1, #shotDelays)]
		task.delay(delayTime, function()
			canShoot = true
		end)
		return true
	end
	return false
end

local function isRagdolled(model)
	if not model or not model:IsA("Model") then return true end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return true end
	if humanoid.Health <= 0 then return true end
	local ok, state = pcall(function() return humanoid:GetState() end)
	if ok and (state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Dead or state == Enum.HumanoidStateType.FallingDown) then
		return true
	end
	if humanoid.PlatformStand == true then return true end
	local possibleFlagNames = {"Ragdolled","Ragdoll","IsRagdolled","RagdollFlag","RagdollState"}
	for _, name in ipairs(possibleFlagNames) do
		local v = model:FindFirstChild(name)
		if v then
			if v:IsA("BoolValue") and v.Value == true then
				return true
			elseif v:IsA("StringValue") and (v.Value == "true" or v.Value == "ragdolled") then
				return true
			end
		end
	end
	local foundMotor6D = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			foundMotor6D = true
			break
		end
	end
	if not foundMotor6D then
		return true
	end
	return false
end

local function isValidTarget(instance)
	if not instance then return false end
	local model = instance:FindFirstAncestorOfClass("Model")
	if not model then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	local targetPlayer = Players:GetPlayerFromCharacter(model)
	if not targetPlayer or isFriendly(targetPlayer) then return false end
	if isRagdolled(model) then return false end
	return true
end

local function handleMouseMovement()
	if not leftHeld or isCrouching then return end
	local tool = getEquippedTool()
	if not tool or not isGun(tool) then
		leftHeld = false
		lastTarget = nil
		return
	end
	local origin = workspace.CurrentCamera.CFrame.Position
	local direction = (mouse.Hit.Position - origin).Unit * 1000
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(origin, direction, params)
	if result and isValidTarget(result.Instance) then
		local distance = (result.Position - origin).Magnitude
		if tool.Name:lower():find("revolver") and distance > 200 then
			lastTarget = nil
			return
		elseif tool.Name:lower():find("double-barrel") or tool.Name:lower():find("shotgun") and distance > 75 then
			lastTarget = nil
			return
		end
		if result.Instance ~= lastTarget then
			lastTarget = result.Instance
			attemptLocalFire()
		elseif canShoot then
			attemptLocalFire()
		end
	else
		lastTarget = nil
	end
end

local function blockLeftClick(actionName, inputState)
	local tool = getEquippedTool()
	local gunEquipped = tool and isGun(tool)

	if inputState == Enum.UserInputState.Begin then
		mouseDown = true
		holdStartTime = tick()
		autoFired = false
		if gunEquipped and not isCrouching then
			leftHeld = true
			return Enum.ContextActionResult.Sink
		end
	elseif inputState == Enum.UserInputState.End then
		mouseDown = false
		leftHeld = false
		lastTarget = nil
		local heldTime = tick() - holdStartTime
		if gunEquipped and heldTime < holdThreshold and not isCrouching and not autoFired then
			attemptLocalFire()
			return Enum.ContextActionResult.Sink
		end
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("BlockMouseClick", blockLeftClick, false, Enum.UserInputType.MouseButton1)

UserInputService.InputChanged:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		handleMouseMovement()
	end
end)

RunService.RenderStepped:Connect(function()
	if leftHeld and not isCrouching then
		handleMouseMovement()
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		isCrouching = true
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		isCrouching = false
		if mouseDown then
			leftHeld = true
		end
	end
end)

local function setupCharacter(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and isGun(child) then
			if mouseDown and not isCrouching then
				leftHeld = true
			end
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			lastTarget = nil
			canShoot = true
		end
	end)
end

player.CharacterAdded:Connect(function(char)
	setupCharacter(char)
	task.spawn(scanAllToolsSafely)
end)

if player.Character then
	setupCharacter(player.Character)
	task.spawn(scanAllToolsSafely)
end
