local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local IGNORE_TEAMMATES = true
local fovRadius = 150
local fovLimitEnabled = true
local wallCheck = true
local camlockEnabled = true
local triggerbotEnabled = true
local compatibilityScanEnabled = true
local scanGeneration = 0
local menuOpen = false
local predictionEnabled = false
local predictionTime = 0
local leftHeld = false
local mouseDown = false
local lastTarget

local lockedPlayer

local function aimPosition(targetPart)
	if predictionEnabled then
		return targetPart.Position + targetPart.AssemblyLinearVelocity * predictionTime
	end
	return targetPart.Position
end

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
	local closestDistance = fovLimitEnabled and fovRadius or math.huge

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local targetPart = getTargetPart(targetPlayer)
		if targetPart then
			local screenPosition, onScreen = camera:WorldToScreenPoint(targetPart.Position)
			if onScreen and screenPosition.Z > 0 then
				local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mousePosition).Magnitude
				if distance <= closestDistance and (not wallCheck or isVisible(targetPart, camera)) then
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
		local targetPosition = aimPosition(targetPart)
		if (targetPosition - position).Magnitude > 0 then
			camera.CFrame = CFrame.lookAt(position, targetPosition)
		end
	end
end)

do
	local enabled = false
	local showFovCircle = true
	local showBoxes, showNames, showDistance = true, true, true
	local showTracers, rainbowESP = false, false
	local showTargetDot, showTargetTracer, showTargetHighlight, showTargetStats = false, false, false, false
	local speedEnabled, autoJump, antiVoid, flightEnabled = false, false, false, false
	local savedHumanoid, savedWalkSpeed, safeCFrame, safeCharacter
	local cameraFovEnabled, savedCamera, savedCameraFov = false, nil, nil
	local savedShadows, savedFogStart, savedFogEnd
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
	local theme = {
		background = Color3.fromRGB(13, 14, 13),
		surface = Color3.fromRGB(22, 23, 22),
		control = Color3.fromRGB(18, 19, 18),
		border = Color3.fromRGB(56, 61, 55),
		accent = Color3.fromRGB(151, 240, 139),
		active = Color3.fromRGB(35, 44, 34),
		text = Color3.fromRGB(217, 220, 213),
		muted = Color3.fromRGB(157, 162, 153)
	}

	local function decorate(parent, radius, color)
		if radius > 0 then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, radius)
			corner.Parent = parent
		end
		if color then
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = color
			stroke.Thickness = 1
			stroke.Parent = parent
		end
	end

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
	circle.Visible = true
	circle.Parent = screenGui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = circle

	local circleOutline = Instance.new("UIStroke")
	circleOutline.Thickness = 1.5
	circleOutline.Transparency = 0.2
	circleOutline.Parent = circle

	local menu = Instance.new("Frame")
	menu.Name = "Settings"
	menu.Size = UDim2.fromOffset(500, 400)
	menu.Position = UDim2.fromOffset(20, 100)
	menu.BackgroundColor3 = theme.background
	menu.BorderSizePixel = 0
	menu.ZIndex = 10
	menu.Visible = false
	menu.Parent = screenGui
	decorate(menu, 0, theme.accent)

	local title = Instance.new("TextLabel")
	title.Name = "DragHandle"
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Text = "Azure | discord.gg/azuremodded"
	title.Font = Enum.Font.Code
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = theme.text
	title.Active = true
	title.ZIndex = 11
	title.Parent = menu

	local titlePadding = Instance.new("UIPadding")
	titlePadding.PaddingLeft = UDim.new(0, 8)
	titlePadding.Parent = title

	local dragHint = Instance.new("TextLabel")
	dragHint.Position = UDim2.new(1, -124, 0, 0)
	dragHint.Size = UDim2.fromOffset(108, 24)
	dragHint.BackgroundTransparency = 1
	dragHint.Text = "DRAG TO MOVE"
	dragHint.Font = Enum.Font.Code
	dragHint.TextSize = 10
	dragHint.TextColor3 = theme.muted
	dragHint.ZIndex = 12
	dragHint.Parent = title

	local function makeDraggable(handle, target, canDrag)
		local dragging, startX, startY, targetX, targetY
		handle.Active = true
		handle.InputBegan:Connect(function(input)
			if not target.Visible or not canDrag() or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			dragging = true
			startX, startY = input.Position.X, input.Position.Y
			targetX, targetY = target.AbsolutePosition.X, target.AbsolutePosition.Y
		end)
		UserInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if not target.Visible or not canDrag() then
				dragging = false
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			local x = targetX + input.Position.X - startX
			local y = targetY + input.Position.Y - startY
			local camera = workspace.CurrentCamera
			if camera then
				x = math.max(0, math.min(x, math.max(0, camera.ViewportSize.X - target.AbsoluteSize.X)))
				y = math.max(0, math.min(y, math.max(0, camera.ViewportSize.Y - target.AbsoluteSize.Y)))
			end
			target.Position = UDim2.fromOffset(x, y)
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
		end)
		return function() dragging = false end
	end
	local stopMenuDrag = makeDraggable(title, menu, function() return menu.Visible end)
	local stopStatsDrag

	local separator = Instance.new("Frame")
	separator.Position = UDim2.fromOffset(8, 24)
	separator.Size = UDim2.new(1, -16, 0, 1)
	separator.BackgroundColor3 = theme.border
	separator.BorderSizePixel = 0
	separator.ZIndex = 11
	separator.Parent = menu

	local pages = {}
	local pageContents = {}
	local tabs = {}

	for index, name in ipairs({"Aimbot", "Player", "Visuals"}) do
		local page = Instance.new("Frame")
		page.Name = name .. "Page"
		page.Position = UDim2.fromOffset(8, 53)
		page.Size = UDim2.new(1, -16, 1, -61)
		page.BackgroundTransparency = 1
		page.Visible = name == "Aimbot"
		page.ZIndex = 11
		page.Parent = menu
		pages[name] = page
		local content = Instance.new("ScrollingFrame")
		content.Size = UDim2.new(1, 0, 1, 0)
		content.BackgroundTransparency = 1
		content.BorderSizePixel = 0
		content.CanvasSize = UDim2.fromOffset(0, 358)
		content.ScrollBarThickness = 4
		content.ScrollBarImageColor3 = theme.border
		content.ScrollingDirection = Enum.ScrollingDirection.Y
		content.ZIndex = 12
		content.Parent = page
		pageContents[name] = content

		local tab = Instance.new("TextButton")
		tab.Name = name .. "Tab"
		tab.Position = UDim2.fromOffset(8 + (index - 1) * 80, 27)
		tab.Size = UDim2.fromOffset(76, 22)
		tab.BackgroundColor3 = name == "Aimbot" and theme.active or theme.background
		tab.BorderSizePixel = 0
		tab.Text = name
		tab.Font = Enum.Font.Code
		tab.TextSize = 12
		tab.TextColor3 = name == "Aimbot" and theme.text or theme.muted
		tab.ZIndex = 11
		tab.Parent = menu
		tabs[name] = tab

		tab.MouseButton1Click:Connect(function()
			for pageName, otherPage in pairs(pages) do
				otherPage.Visible = pageName == name
				tabs[pageName].TextColor3 = pageName == name and theme.text or theme.muted
				tabs[pageName].BackgroundColor3 = pageName == name and theme.active or theme.background
			end
		end)
	end

	local function compact(y)
		return math.floor(y * 0.75)
	end

	local function makeSection(page, name, x, height)
		local section = Instance.new("Frame")
		section.Position = UDim2.fromOffset(x, 0)
		section.Size = UDim2.fromOffset(236, compact(height))
		section.BackgroundColor3 = theme.surface
		section.BorderSizePixel = 0
		section.ZIndex = 13
		section.Parent = page
		decorate(section, 0, theme.border)

		local heading = Instance.new("TextLabel")
		heading.Position = UDim2.fromOffset(6, 3)
		heading.Size = UDim2.new(1, -12, 0, 17)
		heading.BackgroundTransparency = 1
		heading.Text = name
		heading.TextColor3 = theme.text
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.Font = Enum.Font.Code
		heading.TextSize = 12
		heading.ZIndex = 14
		heading.Parent = section

		local line = Instance.new("Frame")
		line.Position = UDim2.fromOffset(0, 0)
		line.Size = UDim2.new(1, 0, 0, 2)
		line.BackgroundColor3 = theme.accent
		line.BorderSizePixel = 0
		line.ZIndex = 14
		line.Parent = section

		return section
	end

	local keySection = makeSection(pageContents.Aimbot, "General & Keybinds", 0, 330)
	local fovSection = makeSection(pageContents.Aimbot, "Camera Aimbot", 248, 476)
	local teamSection = makeSection(pageContents.Player, "Player", 0, 185)
	local visibilitySection = makeSection(pageContents.Player, "Movement", 248, 166)
	local espColors = makeSection(pageContents.Visuals, "ESP colors", 0, 300)
	local fovColors = makeSection(pageContents.Visuals, "Visual effects", 248, 262)

	local function makeLabel(parent, text, y, height)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromOffset(8, compact(y))
		label.Size = UDim2.new(1, -16, 0, compact(height or 24))
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = theme.muted
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextWrapped = true
		label.Font = Enum.Font.Code
		label.TextSize = 12
		label.ZIndex = 14
		label.Parent = parent
		return label
	end

	local function makeButton(parent, y, width, x, plain)
		local button = Instance.new("TextButton")
		button.Position = UDim2.fromOffset(x or 8, compact(y))
		button.Size = UDim2.fromOffset(width or 220, 20)
		button.BackgroundColor3 = theme.control
		button.BorderSizePixel = 0
		button.TextColor3 = theme.text
		button.Font = Enum.Font.Code
		button.TextSize = 12
		button.ZIndex = 14
		button.Parent = parent
		if not plain then decorate(button, 0, theme.border) end
		return button
	end

	local function makeToggle(parent, y, name, initial, changed)
		local value = initial
		local button = makeButton(parent, y, nil, nil, true)
		button.Name = name .. "Toggle"
		button.BackgroundTransparency = 1
		button.Text = ""
		local label = Instance.new("TextLabel")
		label.Name = "ToggleLabel"
		label.Position = UDim2.fromOffset(19, 0)
		label.Size = UDim2.new(1, -19, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = name
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Font = Enum.Font.Code
		label.TextSize = 12
		label.ZIndex = 15
		label.Parent = button
		local indicator = Instance.new("Frame")
		indicator.Name = "ToggleIndicator"
		indicator.Position = UDim2.new(0, 3, 0.5, -5)
		indicator.Size = UDim2.fromOffset(10, 10)
		indicator.BorderSizePixel = 0
		indicator.ZIndex = 15
		indicator.Parent = button
		decorate(indicator, 0, theme.border)
		local function refresh()
			label.TextColor3 = theme.text
			indicator.BackgroundColor3 = value and theme.accent or theme.control
		end
		button.MouseButton1Click:Connect(function()
			value = not value
			refresh()
			changed(value)
		end)
		refresh()
		return function(newValue)
			value = newValue
			refresh()
		end
	end

	local function notify(title, text)
		StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = 3})
	end

	local function unlock()
		if lockedPlayer then
			notify("Camlock", "Unlocked from " .. lockedPlayer.Name)
			lockedPlayer = nil
		end
	end

	local function refreshKeyButtons()
		for name, button in pairs(keyButtons) do
			button.Text = name .. " key: " .. (waitingForKey == name and "Press a key..." or keys[name].Name)
		end
	end

	local keyHint = makeLabel(keySection, "Click a key to rebind. Escape cancels.", 145, 24)
	for index, name in ipairs({"Camlock", "ESP", "Menu"}) do
		local button = makeButton(keySection, 35 + (index - 1) * 32)
		keyButtons[name] = button
		button.MouseButton1Click:Connect(function()
			waitingForKey = name
			keyHint.Text = "Click a key to rebind. Escape cancels."
			keyHint.TextColor3 = theme.muted
			refreshKeyButtons()
		end)
	end
	refreshKeyButtons()

	for _, name in ipairs({"Visible", "Hidden", "FOV"}) do
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

	makeToggle(keySection, 177, "FOV", true, function(value)
		fovLimitEnabled = value
		circle.Visible = value and showFovCircle
	end)
	makeToggle(keySection, 210, "Triggerbot", true, function(value)
		triggerbotEnabled = value
		scanGeneration = scanGeneration + 1
		if not value then
			leftHeld, mouseDown, lastTarget = false, false, nil
		end
	end)
	makeToggle(keySection, 242, "Compatibility scan", true, function(value)
		compatibilityScanEnabled = value
		scanGeneration = scanGeneration + 1
	end)
	makeLabel(keySection, "Scan stops immediately; enabling applies on the next spawn.", 274, 48)
	makeToggle(fovSection, 105, "Camlock", true, function(value)
		camlockEnabled = value
		if not value then unlock() end
	end)
	makeToggle(fovSection, 137, "Wall check", true, function(value) wallCheck = value end)
	makeToggle(fovSection, 169, "Prediction", false, function(value) predictionEnabled = value end)
	makeToggle(fovSection, 201, "Target dot", false, function(value) showTargetDot = value end)
	makeToggle(fovSection, 233, "Target tracer", false, function(value) showTargetTracer = value end)
	makeToggle(fovSection, 265, "Target highlight", false, function(value) showTargetHighlight = value end)
	makeToggle(fovSection, 349, "Target stats", false, function(value) showTargetStats = value end)
	makeLabel(fovSection, "Custom prediction (0-1 sec)", 413)
	local predictionInput = Instance.new("TextBox")
	predictionInput.Name = "PredictionInput"
	predictionInput.Position = UDim2.fromOffset(8, compact(440))
	predictionInput.Size = UDim2.fromOffset(220, 20)
	predictionInput.BackgroundColor3 = theme.control
	predictionInput.BorderSizePixel = 0
	predictionInput.TextColor3 = theme.text
	predictionInput.PlaceholderColor3 = theme.muted
	predictionInput.PlaceholderText = "Seconds, e.g. 0.12"
	predictionInput.ClearTextOnFocus = false
	predictionInput.Font = Enum.Font.Code
	predictionInput.TextSize = 12
	predictionInput.ZIndex = 14
	predictionInput.Parent = fovSection
	decorate(predictionInput, 0, theme.border)
	local predictionLabel = makeLabel(fovSection, "", 291)
	local function updatePrediction()
		predictionLabel.Text = "Prediction: " .. tostring(predictionTime) .. " sec"
		predictionLabel.TextColor3 = theme.muted
		predictionInput.Text = tostring(predictionTime)
	end
	updatePrediction()
	predictionInput.FocusLost:Connect(function()
		local value = tonumber(predictionInput.Text)
		if not value or value ~= value or value < 0 or value > 1 then
			updatePrediction()
			predictionLabel.Text = "Enter a number from 0 to 1 sec."
			predictionLabel.TextColor3 = Color3.fromRGB(255, 115, 115)
			return
		end
		predictionTime = value
		updatePrediction()
	end)
	local predictionDecrease = makeButton(fovSection, 317, 104, 8)
	predictionDecrease.Name = "PredictionDecrease"
	predictionDecrease.Text = "-"
	predictionDecrease.MouseButton1Click:Connect(function()
		predictionTime = math.max(0, predictionTime - 0.05)
		updatePrediction()
	end)
	local predictionIncrease = makeButton(fovSection, 317, 104, 124)
	predictionIncrease.Name = "PredictionIncrease"
	predictionIncrease.Text = "+"
	predictionIncrease.MouseButton1Click:Connect(function()
		predictionTime = math.min(1, predictionTime + 0.05)
		updatePrediction()
	end)

	makeToggle(teamSection, 35, "Team check", true, function(value) IGNORE_TEAMMATES = value end)
	makeLabel(teamSection, "Existing locks stay active behind walls.", 70, 50)
	makeLabel(teamSection, "Drag target stats while the menu is open.", 125, 50)
	makeToggle(visibilitySection, 35, "Speed", false, function(value)
		speedEnabled = value
		if not value and savedHumanoid then
			savedHumanoid.WalkSpeed = savedWalkSpeed
			savedHumanoid, savedWalkSpeed = nil, nil
		end
	end)
	makeToggle(visibilitySection, 67, "Auto jump", false, function(value) autoJump = value end)
	makeToggle(visibilitySection, 99, "Anti void", false, function(value)
		antiVoid = value
		safeCFrame, safeCharacter = nil, nil
	end)
	makeToggle(visibilitySection, 131, "Flight (WASD, Space, Ctrl)", false, function(value) flightEnabled = value end)

	local function hideOverlays()
		for _, overlay in pairs(overlays) do
			overlay.box.Visible = false
			overlay.tracer.Visible = false
		end
	end
	local setEspToggle = makeToggle(espColors, 105, "ESP", false, function(value)
		enabled = value
		if not value then hideOverlays() end
	end)
	makeToggle(espColors, 137, "Boxes", true, function(value) showBoxes = value end)
	makeToggle(espColors, 169, "Names", true, function(value) showNames = value end)
	makeToggle(espColors, 201, "Distance", true, function(value) showDistance = value end)
	makeToggle(espColors, 233, "Tracers", false, function(value) showTracers = value end)
	makeToggle(espColors, 265, "Rainbow ESP", false, function(value) rainbowESP = value end)

	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(16, 2)
	crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	crosshair.BorderSizePixel = 0
	crosshair.Visible = false
	crosshair.Parent = screenGui
	local crosshairVertical = Instance.new("Frame")
	crosshairVertical.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshairVertical.Position = UDim2.fromScale(0.5, 0.5)
	crosshairVertical.Size = UDim2.fromOffset(2, 16)
	crosshairVertical.BackgroundColor3 = crosshair.BackgroundColor3
	crosshairVertical.BorderSizePixel = 0
	crosshairVertical.Parent = crosshair
	makeToggle(fovColors, 67, "Crosshair", false, function(value) crosshair.Visible = value end)
	makeToggle(fovColors, 99, "Camera FOV", false, function(value)
		cameraFovEnabled = value
		if not value and savedCamera then
			savedCamera.FieldOfView = savedCameraFov
			savedCamera, savedCameraFov = nil, nil
		end
	end)
	makeToggle(fovColors, 131, "Disable shadows", false, function(value)
		if value then
			savedShadows = Lighting.GlobalShadows
			Lighting.GlobalShadows = false
		else
			Lighting.GlobalShadows = savedShadows
		end
	end)
	makeToggle(fovColors, 163, "Custom fog", false, function(value)
		if value then
			savedFogStart, savedFogEnd = Lighting.FogStart, Lighting.FogEnd
			Lighting.FogStart, Lighting.FogEnd = 0, 100
		else
			Lighting.FogStart, Lighting.FogEnd = savedFogStart, savedFogEnd
		end
	end)
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "AzureColorCorrection"
	colorCorrection.Enabled = false
	colorCorrection.Saturation = 0.2
	colorCorrection.Contrast = 0.1
	colorCorrection.Parent = Lighting
	makeToggle(fovColors, 195, "Color correction", false, function(value) colorCorrection.Enabled = value end)
	makeToggle(fovColors, 227, "FOV circle", true, function(value)
		showFovCircle = value
		circle.Visible = value and fovLimitEnabled
	end)

	local targetDot = Instance.new("Frame")
	targetDot.Name = "TargetDot"
	targetDot.AnchorPoint = Vector2.new(0.5, 0.5)
	targetDot.Size = UDim2.fromOffset(6, 6)
	targetDot.BackgroundColor3 = theme.accent
	targetDot.BorderSizePixel = 0
	targetDot.Visible = false
	targetDot.Parent = screenGui
	decorate(targetDot, 3)
	local targetTracer = Instance.new("Frame")
	targetTracer.Name = "TargetTracer"
	targetTracer.AnchorPoint = Vector2.new(0.5, 0.5)
	targetTracer.BackgroundColor3 = targetDot.BackgroundColor3
	targetTracer.BorderSizePixel = 0
	targetTracer.Visible = false
	targetTracer.Parent = screenGui
	local targetStats = Instance.new("TextLabel")
	targetStats.Name = "TargetStats"
	targetStats.Position = UDim2.fromOffset(20, 50)
	targetStats.Size = UDim2.fromOffset(220, 34)
	targetStats.BackgroundColor3 = theme.background
	targetStats.BackgroundTransparency = 0.1
	targetStats.BorderSizePixel = 0
	targetStats.TextColor3 = theme.text
	targetStats.Font = Enum.Font.Code
	targetStats.TextSize = 12
	targetStats.TextXAlignment = Enum.TextXAlignment.Left
	targetStats.Visible = false
	targetStats.Parent = screenGui
	decorate(targetStats, 0, theme.accent)
	local statsPadding = Instance.new("UIPadding")
	statsPadding.PaddingLeft = UDim.new(0, 12)
	statsPadding.Parent = targetStats
	stopStatsDrag = makeDraggable(targetStats, targetStats, function() return menuOpen end)
	targetStats.Active = false
	local targetHighlight = Instance.new("Highlight")
	targetHighlight.Name = "AzureTargetHighlight"
	targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	targetHighlight.FillColor = theme.accent
	targetHighlight.OutlineColor = theme.text
	targetHighlight.FillTransparency = 0.75
	targetHighlight.Enabled = false
	targetHighlight.Parent = screenGui

	local function positionLine(line, fromX, fromY, toX, toY)
		local dx, dy = toX - fromX, toY - fromY
		line.Position = UDim2.fromOffset((fromX + toX) / 2, (fromY + toY) / 2)
		line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 2)
		line.Rotation = math.deg(math.atan2(dy, dx))
	end

	local function addPlayer(targetPlayer)
		if targetPlayer == player or overlays[targetPlayer] then return end

		local box = Instance.new("Frame")
		box.Name = targetPlayer.Name
		box.BackgroundTransparency = 1
		box.Visible = false
		box.Parent = screenGui

		local outline = Instance.new("UIStroke")
		outline.Thickness = 1.5
		outline.Parent = box

		local username = Instance.new("TextLabel")
		username.Name = "Username"
		username.BackgroundTransparency = 1
		username.Position = UDim2.new(0, 0, 1, 2)
		username.Size = UDim2.new(1, 0, 0, 18)
		username.Font = Enum.Font.GothamBold
		username.Text = targetPlayer.Name
		username.TextColor3 = Color3.fromRGB(255, 255, 255)
		username.TextSize = 12
		username.TextStrokeTransparency = 0
		username.Parent = box

		local distance = Instance.new("TextLabel")
		distance.Name = "Distance"
		distance.BackgroundTransparency = 1
		distance.Position = UDim2.new(0, 0, 1, 20)
		distance.Size = UDim2.new(1, 0, 0, 18)
		distance.Font = Enum.Font.Gotham
		distance.TextColor3 = theme.text
		distance.TextSize = 12
		distance.TextStrokeTransparency = 0
		distance.Parent = box

		local tracer = Instance.new("Frame")
		tracer.Name = "Tracer"
		tracer.AnchorPoint = Vector2.new(0.5, 0.5)
		tracer.BorderSizePixel = 0
		tracer.Visible = false
		tracer.Parent = screenGui

		overlays[targetPlayer] = {
			box = box,
			outline = outline,
			username = username,
			distance = distance,
			tracer = tracer
		}
	end

	local function removePlayer(targetPlayer)
		local overlay = overlays[targetPlayer]
		if overlay then
			overlay.box:Destroy()
			overlay.tracer:Destroy()
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
				keyHint.Text = "Click a key to rebind. Escape cancels."
				keyHint.TextColor3 = theme.muted
			elseif key ~= Enum.KeyCode.Unknown then
				local duplicate = false

				for name, existing in pairs(keys) do
					if name ~= waitingForKey and existing == key then
						duplicate = true
					end
				end

				if duplicate then
					keyHint.Text = "That key is already in use."
					keyHint.TextColor3 = Color3.fromRGB(255, 115, 115)
				else
					keys[waitingForKey] = key
					waitingForKey = nil
					keyHint.Text = "Click a key to rebind. Escape cancels."
					keyHint.TextColor3 = theme.muted
				end
			end
			refreshKeyButtons()
			return
		end

		if key == keys.Menu then
			menu.Visible = not menu.Visible
			menuOpen = menu.Visible
			targetStats.Active = menuOpen
			stopMenuDrag()
			stopStatsDrag()
			if menuOpen then
				leftHeld, mouseDown, lastTarget = false, false, nil
			end
		elseif key == keys.Camlock and camlockEnabled then
			local message

			if lockedPlayer then
				message = "Unlocked from " .. lockedPlayer.Name
				lockedPlayer = nil
			else
				lockedPlayer = getClosestPlayer()
				message = lockedPlayer and ("Locked onto " .. lockedPlayer.Name)
					or "No eligible player in FOV"
			end

			StarterGui:SetCore("SendNotification", {
				Title = "Camlock",
				Text = message,
				Duration = 3
			})
		elseif key == keys.ESP then
			enabled = not enabled
			setEspToggle(enabled)
			if not enabled then
				hideOverlays()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local mousePosition = UserInputService:GetMouseLocation()
		circle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		circle.Size = UDim2.fromOffset(fovRadius * 2, fovRadius * 2)
		circleOutline.Color = palette[colorIndexes.FOV].Value

		local camera = workspace.CurrentCamera
		if cameraFovEnabled and camera then
			if camera ~= savedCamera then
				if savedCamera then savedCamera.FieldOfView = savedCameraFov end
				savedCamera, savedCameraFov = camera, camera.FieldOfView
			end
			camera.FieldOfView = 85
		end

		local targetPart = lockedPlayer and getTargetPart(lockedPlayer)
		targetDot.Visible = false
		targetTracer.Visible = false
		targetStats.Visible = false
		targetHighlight.Enabled = targetPart ~= nil and showTargetHighlight
		targetHighlight.Adornee = targetPart and lockedPlayer.Character or nil
		if targetPart and camera then
			local point, onScreen = camera:WorldToViewportPoint(aimPosition(targetPart))
			if onScreen and point.Z > 0 then
				targetDot.Position = UDim2.fromOffset(point.X, point.Y)
				targetDot.Visible = showTargetDot
				positionLine(targetTracer, camera.ViewportSize.X / 2, camera.ViewportSize.Y, point.X, point.Y)
				targetTracer.Visible = showTargetTracer
			end
			local humanoid = lockedPlayer.Character:FindFirstChildOfClass("Humanoid")
			targetStats.Text = string.format("%s | %.0f HP", lockedPlayer.Name, humanoid.Health)
			targetStats.Visible = showTargetStats
		end

		if not enabled then return end

		for targetPlayer, overlay in pairs(overlays) do
			local box = overlay.box
			overlay.tracer.Visible = false
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
								size.X * x / 2,
								size.Y * y / 2,
								size.Z * z / 2
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
					local color = rainbowESP and Color3.fromHSV((os.clock() % 5) / 5, 1, 1)
						or palette[colorIndexes[colorName]].Value
					overlay.outline.Color = color
					overlay.outline.Enabled = showBoxes
					overlay.username.Visible = showNames
					overlay.distance.Visible = showDistance
					if showTracers then
						positionLine(overlay.tracer, viewport.X / 2, viewport.Y, (minX + maxX) / 2, maxY)
						overlay.tracer.BackgroundColor3 = color
						overlay.tracer.Visible = true
					end

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

	RunService.Heartbeat:Connect(function(deltaTime)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if savedHumanoid and (not speedEnabled or humanoid ~= savedHumanoid) then
			savedHumanoid.WalkSpeed = savedWalkSpeed
			savedHumanoid, savedWalkSpeed = nil, nil
		end
		if speedEnabled and humanoid then
			if not savedHumanoid then
				savedHumanoid, savedWalkSpeed = humanoid, humanoid.WalkSpeed
			end
			humanoid.WalkSpeed = 24
		end
		if autoJump and humanoid and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
			humanoid.Jump = true
		end
		if not root or not humanoid or humanoid.Health <= 0 then
			safeCFrame, safeCharacter = nil, nil
			return
		end
		if antiVoid then
			if character ~= safeCharacter then
				safeCFrame, safeCharacter = nil, character
			end
			if root.Position.Y <= workspace.FallenPartsDestroyHeight + 10 then
				if safeCFrame then
					root.CFrame = safeCFrame
					root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				end
			elseif humanoid.FloorMaterial ~= Enum.Material.Air then
				safeCFrame = root.CFrame
			end
		end
		local camera = workspace.CurrentCamera
		if flightEnabled and camera and not UserInputService:GetFocusedTextBox() then
			local direction = Vector3.new(0, 0, 0)
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction = direction + camera.CFrame.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction = direction - camera.CFrame.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction = direction + camera.CFrame.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction = direction - camera.CFrame.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction = direction + Vector3.new(0, 1, 0) end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
				direction = direction - Vector3.new(0, 1, 0)
			end
			if direction.Magnitude > 0 then direction = direction.Unit end
			root.CFrame = root.CFrame + direction * (100 * deltaTime)
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
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

local holdStartTime = 0
local holdThreshold = 0.25
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

local function scanAllToolsSafely(generation)
	if not triggerbotEnabled or not compatibilityScanEnabled or generation ~= scanGeneration then return end
	local allObjects = {}
	for _, service in ipairs(game:GetChildren()) do
		table.insert(allObjects, service)
	end

	local index = 1
	local batchSize = 20
	local found = false

	local function scanBatch()
		if not triggerbotEnabled or not compatibilityScanEnabled or generation ~= scanGeneration then return end
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

local function scheduleToolScan()
	local generation = scanGeneration
	task.spawn(function() scanAllToolsSafely(generation) end)
end

local function attemptLocalFire()
	if not AUTO_SHOOT_ENABLED or not triggerbotEnabled or menuOpen or isCrouching then return false end

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
	if not triggerbotEnabled or menuOpen or not leftHeld or isCrouching then return end

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
	if not triggerbotEnabled or menuOpen then
		mouseDown = false
		leftHeld = false
		lastTarget = nil
		return Enum.ContextActionResult.Pass
	end
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
	scheduleToolScan()
end)

if player.Character then
	setupCharacter(player.Character)
	scheduleToolScan()
end
