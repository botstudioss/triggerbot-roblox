-- Silent Aim hook approach adapted from Averiias/Universal-SilentAim (MIT).
-- Copyright (c) 2022 Averiias
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
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
local autoPrediction = false
local autoPredictionTime = 0
local camlockPart = "Head"
local camlockAirPart = "LowerTorso"
local camlockUseAirPart = false
local camlockKOCheck = false
local camlockJumpOffset = 0
local camlockExtra = {autoLock = false, resolver = false}
local leftHeld = false
local mouseDown = false
local lastTarget

local lockedPlayer
local aim = {enabled = false, active = false, hold = true, radius = 150, limit = true, wall = true, team = true, part = "Head", smoothing = 0.25}
local silent = {enabled = false, radius = 150, limit = true, wall = true, team = true, part = "Head", method = "Mouse", target = nil}

local function aimPosition(targetPart)
	if predictionEnabled or autoPrediction then
		return targetPart.Position + targetPart.AssemblyLinearVelocity * (autoPrediction and autoPredictionTime or predictionTime)
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

local function isKnocked(character, humanoid)
	if humanoid.PlatformStand then return true end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Dead then return true end
	for _, container in ipairs({character, character:FindFirstChild("BodyEffects") or character}) do
		for _, name in ipairs({"K.O", "KO", "Knocked", "Ragdolled", "Ragdoll", "IsRagdolled"}) do
			local flag = container:FindFirstChild(name)
			if flag and flag:IsA("BoolValue") and flag.Value then return true end
		end
	end
	return false
end

local function getTargetPart(targetPlayer, partName, checkTeam)
	if not targetPlayer or targetPlayer == player or targetPlayer.Parent ~= Players then
		return nil
	end

	if checkTeam == nil then checkTeam = IGNORE_TEAMMATES end
	if checkTeam and player.Team and targetPlayer.Team == player.Team then
		return nil
	end

	local character = targetPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild(partName or "Head")

	if humanoid and humanoid.Health > 0 and head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function getCamlockPart(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or (camlockKOCheck and isKnocked(character, humanoid)) then return nil end
	if camlockUseAirPart and humanoid.FloorMaterial == Enum.Material.Air then
		local airPart = getTargetPart(targetPlayer, camlockAirPart)
		if airPart then return airPart end
	end
	return getTargetPart(targetPlayer, camlockPart)
end

local function camlockPosition(targetPart)
	local position = aimPosition(targetPart)
	if camlockExtra.resolver and camlockExtra.samplePart == targetPart and camlockExtra.velocity
		and (predictionEnabled or autoPrediction) then
		position = targetPart.Position + camlockExtra.velocity * (autoPrediction and autoPredictionTime or predictionTime)
	end
	local humanoid = targetPart.Parent and targetPart.Parent:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		position = position + Vector3.new(0, camlockJumpOffset, 0)
	end
	return position
end

local function getClosestPlayer(settings)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mousePosition = UserInputService:GetMouseLocation()
	local closestPlayer
	local closestDistance = settings and (settings.limit and settings.radius or math.huge)
		or (fovLimitEnabled and fovRadius or math.huge)

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local targetPart = settings and getTargetPart(targetPlayer, settings.part, settings.team)
			or (not settings and getCamlockPart(targetPlayer))
		if targetPart then
			local screenPosition, onScreen = camera:WorldToScreenPoint(targetPart.Position)
			if onScreen and screenPosition.Z > 0 then
				local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mousePosition).Magnitude
				local checkWall = settings and settings.wall
				if not settings then checkWall = wallCheck end
				if distance <= closestDistance and (not checkWall or isVisible(targetPart, camera)) then
					closestDistance = distance
					closestPlayer = targetPlayer
				end
			end
		end
	end

	return closestPlayer
end

RunService:BindToRenderStep("Camlock", Enum.RenderPriority.Camera.Value + 1, function()
	if camlockEnabled and camlockExtra.autoLock and not menuOpen and not UserInputService:GetFocusedTextBox() then
		lockedPlayer = getClosestPlayer()
	end
	if not lockedPlayer then
		if not aim.enabled or not aim.active or menuOpen or UserInputService:GetFocusedTextBox() then return end
		local camera = workspace.CurrentCamera
		local target = camera and getClosestPlayer(aim)
		local part = target and getTargetPart(target, aim.part, aim.team)
		if part then
			local position = camera.CFrame.Position
			local destination = aimPosition(part)
			if (destination - position).Magnitude > 0 then
				camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(position, destination), aim.smoothing)
			end
		end
		return
	end

	local targetPart = getCamlockPart(lockedPlayer)
	if not targetPart then
		lockedPlayer = nil
		return
	end

	local camera = workspace.CurrentCamera
	if camera then
		local position = camera.CFrame.Position
		local targetPosition = camlockPosition(targetPart)
		if (targetPosition - position).Magnitude > 0 then
			camera.CFrame = CFrame.lookAt(position, targetPosition)
		end
	end
end)

local mouseHookInstalled, rayHookInstalled = false, false
local function silentTarget()
	if not silent.enabled or menuOpen then return nil end
	local character = player.Character
	if not character or not character:FindFirstChildOfClass("Tool") then return nil end
	local target = silent.target
	return target and getTargetPart(target, silent.part, silent.team) or nil
end

local function installSilentHook(method)
	if type(hookmetamethod) ~= "function" then return false, "Missing: hookmetamethod" end
	if type(newcclosure) ~= "function" then return false, "Missing: newcclosure" end
	if type(checkcaller) ~= "function" then return false, "Missing: checkcaller" end
	if method == "Raycast" and type(getnamecallmethod) ~= "function" then
		return false, "Missing: getnamecallmethod"
	end
	if (method == "Mouse" and mouseHookInstalled) or (method == "Raycast" and rayHookInstalled) then
		return true
	end
	local old
	local ok, err = pcall(function()
		if method == "Mouse" then
			old = hookmetamethod(game, "__index", newcclosure(function(object, key)
				if object == mouse and not checkcaller() and silent.method == "Mouse" and (key == "Hit" or key == "Target") then
					local part = silentTarget()
					if part then
						if key == "Target" then return part end
						return part.CFrame + (aimPosition(part) - part.Position)
					end
				end
				return old(object, key)
			end))
			mouseHookInstalled = true
		else
			old = hookmetamethod(game, "__namecall", newcclosure(function(object, ...)
				if object == workspace and not checkcaller() and silent.method == "Raycast" and getnamecallmethod() == "Raycast" then
					local part = silentTarget()
					if part then
						local args = table.pack(...)
						if typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
							local direction = aimPosition(part) - args[1]
							if direction.Magnitude > 0 and args[2].Magnitude > 0 then
								args[2] = direction.Unit * args[2].Magnitude
								return old(object, table.unpack(args, 1, args.n))
							end
						end
					end
				end
				return old(object, ...)
			end))
			rayHookInstalled = true
		end
	end)
	if not ok then return false, "Hook failed: " .. tostring(err) end
	return true
end

do
	local enabled = false
	local showFovCircle = true
	local showBoxes, showNames, showDistance = true, true, true
	local showTracers, rainbowESP = false, false
	local showTargetDot, showTargetTracer, showTargetHighlight, showTargetStats = false, false, false, false
	local lookAtTarget, viewTarget, rainbowTarget, rainbowFov, filledFov = false, false, false, false, false
	local fovTransparency = 0.75
	local spectateCamera, savedCameraSubject
	local speedEnabled, autoJump, antiVoid, flightEnabled = false, false, false, false
	local disableSeats = false
	local speedAmount, flightAmount = 24, 100
	local strafeEnabled, strafeRandom, strafeSpeed, strafeDistance, strafeHeight = false, false, 1, 10, 0
	local strafeAngle = 0
	local strafeRandomRate, strafeRandomElapsed = 1, 0
	local savedHumanoid, savedWalkSpeed, safeCFrame, safeCharacter
	local cameraFovEnabled, savedCamera, savedCameraFov = false, nil, nil
	local cameraFovAmount = 85
	local savedShadows, savedFogStart, savedFogEnd, savedFogColor
	local fogEnabled, fogStart, fogEnd = false, 0, 100
	local crosshairRainbow, crosshairUseText = false, false
	local rainbowLighting, rainbowFog = false, false
	local crosshairColorIndex, lightingColorIndex, fogColorIndex = 3, 3, 0
	local crosshairSize, crosshairThickness = 16, 2
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
		background = Color3.fromRGB(17, 17, 17),
		surface = Color3.fromRGB(27, 27, 27),
		control = Color3.fromRGB(35, 35, 35),
		border = Color3.fromRGB(65, 65, 65),
		accent = Color3.fromRGB(210, 210, 210),
		active = Color3.fromRGB(40, 40, 40),
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
	menu.Size = UDim2.fromOffset(500, 600)
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
	title.Text = "Azure Paid | @socialdw on discord | discord.gg/azuremodded"
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
	dragHint.Text = ""
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

	for index, name in ipairs({"Aimbot", "Player", "Visuals", "Aim modes"}) do
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
		content.CanvasSize = UDim2.fromOffset(0, name == "Aimbot" and 800
			or name == "Player" and 500 or name == "Visuals" and 760 or 358)
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

	local function makeSection(page, name, x, height, y)
		local section = Instance.new("Frame")
		section.Position = UDim2.fromOffset(x, y or 0)
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
	local visibilitySection = makeSection(pageContents.Player, "Movement", 248, 325)
	local espColors = makeSection(pageContents.Visuals, "ESP colors", 0, 300)
	local fovColors = makeSection(pageContents.Visuals, "Visual effects", 248, 262)
	local aimSection = makeSection(pageContents["Aim modes"], "Camera aimbot", 0, 476)
	local silentSection = makeSection(pageContents["Aim modes"], "Silent aim", 248, 476)
	local strafeSection = makeSection(pageContents.Aimbot, "Target Strafe", 0, 275, 256)
	local targetVisualSection = makeSection(pageContents.Aimbot, "Target visuals", 248, 255, 365)
	local crosshairSection = makeSection(pageContents.Visuals, "Crosshair", 0, 290, 233)
	local lightingSection = makeSection(pageContents.Visuals, "Lighting", 248, 255, 205)
	local fogSection = makeSection(pageContents.Visuals, "Fog", 248, 220, 404)
	local cameraSection = makeSection(pageContents.Visuals, "Field Of View", 248, 75, 577)
	local camlockSettings = makeSection(pageContents.Aimbot, "Camlock settings", 0, 390, 470)
	local animationSection = makeSection(pageContents.Player, "Animations (R15)", 0, 265, 150)
	local toolSection = makeSection(pageContents.Player, "Tool Position", 248, 230, 255)

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
			if changed(value) == false then value = not value end
			refresh()
		end)
		refresh()
		return function(newValue)
			value = newValue
			refresh()
		end
	end

	local function makeSlider(parent, y, name, minimum, maximum, initial, step, changed)
		local label = makeLabel(parent, "", y, 20)
		local track = makeButton(parent, y + 20, nil, nil, true)
		track.Name = name .. "Slider"
		track.Size = UDim2.fromOffset(220, 12)
		track.Text = ""
		decorate(track, 0, theme.border)
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = theme.accent
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.ZIndex = 15
		fill.Parent = track
		local value = initial
		local dragging = false
		local function refresh()
			label.Text = name .. ": " .. string.format("%g", value)
			fill.Size = UDim2.fromScale((value - minimum) / (maximum - minimum), 1)
		end
		local function update(x)
			if track.AbsoluteSize.X <= 0 then return end
			local fraction = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			value = math.clamp(minimum + math.floor(((maximum - minimum) * fraction) / step + 0.5) * step, minimum, maximum)
			refresh()
			changed(value)
		end
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				update(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then update(input.Position.X) end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
		end)
		refresh()
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
	keys.Aim = Enum.KeyCode.E
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

	do
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
	end

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
	do
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
	end

	local aimCircle = Instance.new("Frame")
	aimCircle.Name = "AimbotFOV"
	aimCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	aimCircle.BackgroundTransparency = 1
	aimCircle.Visible = false
	aimCircle.Parent = screenGui
	local aimRound = Instance.new("UICorner")
	aimRound.CornerRadius = UDim.new(1, 0)
	aimRound.Parent = aimCircle
	local aimStroke = Instance.new("UIStroke")
	aimStroke.Color = Color3.fromRGB(100, 200, 255)
	aimStroke.Thickness = 1
	aimStroke.Parent = aimCircle
	local silentCircle = Instance.new("Frame")
	silentCircle.Name = "SilentFOV"
	silentCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	silentCircle.BackgroundTransparency = 1
	silentCircle.Visible = false
	silentCircle.Parent = screenGui
	local silentRound = Instance.new("UICorner")
	silentRound.CornerRadius = UDim.new(1, 0)
	silentRound.Parent = silentCircle
	local silentStroke = Instance.new("UIStroke")
	silentStroke.Color = Color3.fromRGB(210, 125, 255)
	silentStroke.Thickness = 1
	silentStroke.Parent = silentCircle
	local showAimCircle, showSilentCircle = false, false

	do
		local aimKeyButton = makeButton(aimSection, 35)
		keyButtons.Aim = aimKeyButton
		aimKeyButton.MouseButton1Click:Connect(function()
			waitingForKey = "Aim"
			keyHint.Text = "Click a key to rebind. Escape cancels."
			keyHint.TextColor3 = theme.muted
			refreshKeyButtons()
		end)
		refreshKeyButtons()
		makeToggle(aimSection, 67, "Aimbot", false, function(value)
			aim.enabled, aim.active = value, false
		end)
		local aimMode = makeButton(aimSection, 99)
		local function refreshAimMode() aimMode.Text = "Mode: " .. (aim.hold and "Hold" or "Toggle") end
		refreshAimMode()
		aimMode.MouseButton1Click:Connect(function()
			aim.hold = not aim.hold
			aim.active = false
			refreshAimMode()
		end)
		makeToggle(aimSection, 131, "Aimbot FOV limit", true, function(value) aim.limit = value end)
		makeToggle(aimSection, 163, "Aimbot FOV circle", false, function(value) showAimCircle = value end)
		makeToggle(aimSection, 195, "Aimbot wall check", true, function(value) aim.wall = value end)
		makeToggle(aimSection, 227, "Aimbot team check", true, function(value) aim.team = value end)
		local aimPartButton = makeButton(aimSection, 259)
		local function refreshAimPart() aimPartButton.Text = "Target: " .. aim.part end
		refreshAimPart()
		aimPartButton.MouseButton1Click:Connect(function()
			aim.part = aim.part == "Head" and "HumanoidRootPart" or "Head"
			refreshAimPart()
		end)
		local aimRadius = makeLabel(aimSection, "", 291)
		local function refreshAimRadius() aimRadius.Text = "Aimbot FOV: " .. aim.radius end
		refreshAimRadius()
		local aimMinus = makeButton(aimSection, 323, 104, 8)
		aimMinus.Name, aimMinus.Text = "AimbotFOVDecrease", "-"
		aimMinus.MouseButton1Click:Connect(function() aim.radius = math.max(25, aim.radius - 25); refreshAimRadius() end)
		local aimPlus = makeButton(aimSection, 323, 104, 124)
		aimPlus.Name, aimPlus.Text = "AimbotFOVIncrease", "+"
		aimPlus.MouseButton1Click:Connect(function() aim.radius = math.min(1000, aim.radius + 25); refreshAimRadius() end)
		local smoothButton = makeButton(aimSection, 355)
		local function refreshSmooth() smoothButton.Text = string.format("Smoothing: %.2f", aim.smoothing) end
		refreshSmooth()
		smoothButton.MouseButton1Click:Connect(function()
			aim.smoothing = aim.smoothing >= 1 and 0.1 or math.min(1, aim.smoothing + 0.15)
			refreshSmooth()
		end)
		makeLabel(aimSection, "Uses the Aimbot tab prediction setting.", 390, 48)
	end

	do
		local silentStatus = makeLabel(silentSection, "", 323, 65)
		silentStatus.Name = "SilentAimStatus"
		local function silentError(message)
			silentStatus.Text = message
			silentStatus.TextColor3 = Color3.fromRGB(255, 115, 115)
		end
		makeToggle(silentSection, 35, "Silent aim", false, function(value)
			if value then
				local ok, err = installSilentHook(silent.method)
				if not ok then silentError(err); return false end
			end
			silent.enabled = value
			silent.target = nil
			silentStatus.Text = ""
			silentStatus.TextColor3 = theme.muted
		end)
		local methodButton = makeButton(silentSection, 67)
		local function refreshMethod() methodButton.Text = "Method: " .. silent.method end
		refreshMethod()
		methodButton.MouseButton1Click:Connect(function()
			local method = silent.method == "Mouse" and "Raycast" or "Mouse"
			if silent.enabled then
				local ok, err = installSilentHook(method)
				if not ok then silentError(err); return end
			end
			silent.method = method
			silentStatus.Text = ""
			silentStatus.TextColor3 = theme.muted
			refreshMethod()
		end)
		makeToggle(silentSection, 99, "Silent FOV limit", true, function(value) silent.limit = value end)
		makeToggle(silentSection, 131, "Silent FOV circle", false, function(value) showSilentCircle = value end)
		makeToggle(silentSection, 163, "Silent wall check", true, function(value) silent.wall = value end)
		makeToggle(silentSection, 195, "Silent team check", true, function(value) silent.team = value end)
		local silentPartButton = makeButton(silentSection, 227)
		local function refreshSilentPart() silentPartButton.Text = "Target: " .. silent.part end
		refreshSilentPart()
		silentPartButton.MouseButton1Click:Connect(function()
			silent.part = silent.part == "Head" and "HumanoidRootPart" or "Head"
			silent.target = nil
			refreshSilentPart()
		end)
		local silentRadius = makeLabel(silentSection, "", 259)
		local function refreshSilentRadius() silentRadius.Text = "Silent FOV: " .. silent.radius end
		refreshSilentRadius()
		local silentMinus = makeButton(silentSection, 291, 104, 8)
		silentMinus.Name, silentMinus.Text = "SilentFOVDecrease", "-"
		silentMinus.MouseButton1Click:Connect(function() silent.radius = math.max(25, silent.radius - 25); refreshSilentRadius() end)
		local silentPlus = makeButton(silentSection, 291, 104, 124)
		silentPlus.Name, silentPlus.Text = "SilentFOVIncrease", "+"
		silentPlus.MouseButton1Click:Connect(function() silent.radius = math.min(1000, silent.radius + 25); refreshSilentRadius() end)
	end

	makeToggle(strafeSection, 35, "Enabled", false, function(value)
		strafeEnabled = value
		strafeAngle = 0
	end)
	makeSlider(strafeSection, 70, "Speed", 0, 10, strafeSpeed, 0.1, function(value) strafeSpeed = value end)
	makeSlider(strafeSection, 120, "Distance", 1, 50, strafeDistance, 1, function(value) strafeDistance = value end)
	makeSlider(strafeSection, 170, "Height", -25, 25, strafeHeight, 1, function(value) strafeHeight = value end)
	makeToggle(strafeSection, 220, "Random", false, function(value)
		strafeRandom = value
		strafeRandomElapsed = 0
	end)
	makeToggle(targetVisualSection, 35, "Look At", false, function(value) lookAtTarget = value end)
	makeToggle(targetVisualSection, 67, "View At", false, function(value) viewTarget = value end)
	makeToggle(targetVisualSection, 99, "Rainbow target", false, function(value) rainbowTarget = value end)
	makeToggle(targetVisualSection, 131, "Rainbow FOV", false, function(value) rainbowFov = value end)
	makeToggle(targetVisualSection, 163, "FOV Filled", false, function(value) filledFov = value end)
	makeSlider(targetVisualSection, 195, "FOV Transparency", 0, 1, fovTransparency, 0.05, function(value) fovTransparency = value end)

	do
		local hitParts = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Torso"}
		local function partSelector(y, name, initial, changed)
			local index = table.find(hitParts, initial)
			local button = makeButton(camlockSettings, y)
			local function refresh() button.Text = name .. ": " .. hitParts[index] end
			button.MouseButton1Click:Connect(function()
				index = index % #hitParts + 1
				changed(hitParts[index])
				refresh()
			end)
			refresh()
		end
		partSelector(35, "Hit part", camlockPart, function(value) camlockPart = value end)
		partSelector(99, "Air part", camlockAirPart, function(value) camlockAirPart = value end)
	end
	makeToggle(camlockSettings, 67, "Use air part", false, function(value) camlockUseAirPart = value end)
	makeToggle(camlockSettings, 131, "KO check", false, function(value) camlockKOCheck = value end)
	local function updateAutoPrediction()
		local ok, ping = pcall(function() return player:GetNetworkPing() end)
		if not ok or type(ping) ~= "number" or ping ~= ping or ping < 0 or ping == math.huge then
			return false
		end
		autoPredictionTime = math.clamp(ping, 0, 1)
		return true
	end
	local setAutoPrediction = makeToggle(camlockSettings, 163, "Auto prediction", false, function(value)
		if value and not updateAutoPrediction() then
			notify("Auto prediction", "Network ping is unavailable.")
			return false
		end
		autoPrediction = value
	end)
	makeSlider(camlockSettings, 195, "Jump offset", -10, 10, camlockJumpOffset, 0.5, function(value)
		camlockJumpOffset = value
	end)
	makeToggle(camlockSettings, 245, "Auto lock", false, function(value)
		camlockExtra.autoLock = value
		lockedPlayer = nil
	end)
	makeToggle(camlockSettings, 277, "Recalculate velocity", false, function(value)
		camlockExtra.resolver = value
		camlockExtra.samplePart, camlockExtra.velocity = nil, nil
	end)
	makeLabel(camlockSettings, "Auto prediction uses network ping; applies to all aim modes.", 310, 60)

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
	makeSlider(visibilitySection, 165, "Speed amount", 0, 100, speedAmount, 1, function(value) speedAmount = value end)
	makeSlider(visibilitySection, 215, "Flight amount", 0, 200, flightAmount, 1, function(value) flightAmount = value end)
	makeToggle(visibilitySection, 265, "Disable seats", false, function(value) disableSeats = value end)

	do
		local zombie = {
			Idle = {Animation1 = "rbxassetid://616158929", Animation2 = "rbxassetid://616160636"},
			Walk = {WalkAnim = "rbxassetid://616168032"},
			Run = {RunAnim = "rbxassetid://616163682"},
			Jump = {JumpAnim = "rbxassetid://616161997"},
			Fall = {FallAnim = "rbxassetid://616157476"}
		}
		local selected = {Idle = true, Walk = true, Run = true, Jump = true, Fall = true}
		local original = {}
		local animationEnabled = false
		local generation = 0
		local setAnimationEnabled
		local function restoreAnimations()
			for animation, id in pairs(original) do
				if animation.Parent then animation.AnimationId = id end
			end
			original = {}
		end
		local function applyAnimations(character)
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
				return false, "Zombie animations require an R15 character."
			end
			local animate = character:FindFirstChild("Animate")
			if not animate then return false, "The standard Animate script was not found." end
			local replacements = {}
			for name, ids in pairs(zombie) do
				if selected[name] then
					local group = animate:FindFirstChild(name:lower())
					for childName, id in pairs(ids) do
						local animation = group and group:FindFirstChild(childName)
						if not animation or not animation:IsA("Animation") then
							return false, "Missing standard " .. name .. " animation " .. childName .. "."
						end
						replacements[animation] = id
					end
				end
			end
			for animation, id in pairs(original) do
				if not replacements[animation] then
					if animation.Parent then animation.AnimationId = id end
					original[animation] = nil
				end
			end
			for animation, id in pairs(replacements) do
				if not original[animation] then original[animation] = animation.AnimationId end
				animation.AnimationId = id
			end
			return true
		end
		setAnimationEnabled = makeToggle(animationSection, 35, "Enabled", false, function(value)
			generation = generation + 1
			if value then
				local ok, message = applyAnimations(player.Character)
				if not ok then notify("Animations", message); return false end
			else
				restoreAnimations()
			end
			animationEnabled = value
		end)
		for index, name in ipairs({"Idle", "Walk", "Run", "Jump", "Fall"}) do
			local button = makeButton(animationSection, 35 + index * 36)
			local function refresh() button.Text = name .. ": " .. (selected[name] and "Zombie" or "Default") end
			button.MouseButton1Click:Connect(function()
				selected[name] = not selected[name]
				if animationEnabled then
					local ok, message = applyAnimations(player.Character)
					if not ok then
						selected[name] = not selected[name]
						notify("Animations", message)
						return
					end
				end
				refresh()
			end)
			refresh()
		end
		player.CharacterAdded:Connect(function(character)
			if not animationEnabled then return end
			generation = generation + 1
			local currentGeneration = generation
			restoreAnimations()
			task.spawn(function()
				character:WaitForChild("Humanoid", 10)
				character:WaitForChild("Animate", 10)
				if not animationEnabled or generation ~= currentGeneration or player.Character ~= character then return end
				local ok, message = applyAnimations(character)
				if not ok then
					animationEnabled = false
					setAnimationEnabled(false)
					restoreAnimations()
					notify("Animations", message)
				end
			end)
		end)
	end

	do
		local toolPosition = {enabled = false, x = 0, y = 0, z = 0}
		local currentTool, originalGrip
		local function restoreTool()
			if currentTool and currentTool.Parent then currentTool.Grip = originalGrip end
			currentTool, originalGrip = nil, nil
		end
		makeToggle(toolSection, 35, "Enabled", false, function(value)
			toolPosition.enabled = value
			if not value then
				restoreTool()
			elseif not player.Character or not player.Character:FindFirstChildOfClass("Tool") then
				notify("Tool Position", "Equip a tool to apply the offset.")
			end
		end)
		makeSlider(toolSection, 70, "Custom X", -5, 5, 0, 0.1, function(value) toolPosition.x = value end)
		makeSlider(toolSection, 120, "Custom Y", -5, 5, 0, 0.1, function(value) toolPosition.y = value end)
		makeSlider(toolSection, 170, "Custom Z", -5, 5, 0, 0.1, function(value) toolPosition.z = value end)
		RunService.Heartbeat:Connect(function()
			if not toolPosition.enabled then return end
			local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
			if tool ~= currentTool then
				restoreTool()
				if tool then currentTool, originalGrip = tool, tool.Grip end
			end
			if currentTool then
				currentTool.Grip = originalGrip * CFrame.new(toolPosition.x, toolPosition.y, toolPosition.z)
			end
		end)
	end

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
	local crosshairText = Instance.new("TextLabel")
	crosshairText.Name = "Text"
	crosshairText.AnchorPoint = Vector2.new(0.5, 0)
	crosshairText.Position = UDim2.new(0.5, 0, 0.5, 12)
	crosshairText.Size = UDim2.fromOffset(220, 20)
	crosshairText.BackgroundTransparency = 1
	crosshairText.Text = ".gg/azuremodded"
	crosshairText.Font = Enum.Font.Code
	crosshairText.TextSize = 12
	crosshairText.TextColor3 = crosshair.BackgroundColor3
	crosshairText.Visible = false
	crosshairText.Parent = crosshair
	local function updateCrosshair()
		crosshair.Size = UDim2.fromOffset(crosshairSize, crosshairThickness)
		crosshairVertical.Size = UDim2.fromOffset(crosshairThickness, crosshairSize)
		crosshairText.Position = UDim2.new(0.5, 0, 0.5, crosshairSize / 2 + 4)
		crosshairText.Visible = crosshairUseText
	end
	makeToggle(fovColors, 67, "Crosshair", false, function(value) crosshair.Visible = value end)
	makeToggle(crosshairSection, 35, "Rainbow", false, function(value) crosshairRainbow = value end)
	makeToggle(crosshairSection, 67, "Use text", false, function(value)
		crosshairUseText = value
		updateCrosshair()
	end)
	makeLabel(crosshairSection, "Text", 99)
	local crosshairInput = Instance.new("TextBox")
	crosshairInput.Name = "CrosshairTextInput"
	crosshairInput.Position = UDim2.fromOffset(8, compact(123))
	crosshairInput.Size = UDim2.fromOffset(220, 20)
	crosshairInput.BackgroundColor3 = theme.control
	crosshairInput.BorderSizePixel = 0
	crosshairInput.TextColor3 = theme.text
	crosshairInput.ClearTextOnFocus = false
	crosshairInput.Text = crosshairText.Text
	crosshairInput.Font = Enum.Font.Code
	crosshairInput.TextSize = 12
	crosshairInput.ZIndex = 14
	crosshairInput.Parent = crosshairSection
	decorate(crosshairInput, 0, theme.border)
	crosshairInput.FocusLost:Connect(function() crosshairText.Text = crosshairInput.Text end)
	makeSlider(crosshairSection, 155, "Size", 2, 100, crosshairSize, 1, function(value)
		crosshairSize = value
		updateCrosshair()
	end)
	makeSlider(crosshairSection, 205, "Thickness", 1, 20, crosshairThickness, 1, function(value)
		crosshairThickness = value
		updateCrosshair()
	end)
	do
		local crosshairColorButton = makeButton(crosshairSection, 255)
		local function refreshCrosshairColor() crosshairColorButton.Text = "Color: " .. palette[crosshairColorIndex].Name end
		crosshairColorButton.MouseButton1Click:Connect(function()
			crosshairColorIndex = crosshairColorIndex % #palette + 1
			refreshCrosshairColor()
		end)
		refreshCrosshairColor()
	end
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
		fogEnabled = value
		if value then
			savedFogStart, savedFogEnd, savedFogColor = Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor
			Lighting.FogStart, Lighting.FogEnd = math.min(fogStart, fogEnd), fogEnd
			Lighting.FogColor = fogColorIndex == 0 and savedFogColor or palette[fogColorIndex].Value
		else
			Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor = savedFogStart, savedFogEnd, savedFogColor
		end
	end)
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "AzureColorCorrection"
	colorCorrection.Enabled = false
	colorCorrection.Saturation = 0.2
	colorCorrection.Contrast = 0.1
	colorCorrection.Parent = Lighting
	makeToggle(fovColors, 195, "Color correction", false, function(value) colorCorrection.Enabled = value end)
	makeSlider(lightingSection, 35, "Brightness", -1, 1, 0, 0.05, function(value) colorCorrection.Brightness = value end)
	makeSlider(lightingSection, 80, "Saturation", -1, 1, 0.2, 0.05, function(value) colorCorrection.Saturation = value end)
	makeSlider(lightingSection, 125, "Contrast", -1, 1, 0.1, 0.05, function(value) colorCorrection.Contrast = value end)
	makeToggle(lightingSection, 175, "Rainbow", false, function(value) rainbowLighting = value end)
	do
		local lightingColorButton = makeButton(lightingSection, 210)
		local function refreshLightingColor() lightingColorButton.Text = "Color: " .. palette[lightingColorIndex].Name end
		lightingColorButton.MouseButton1Click:Connect(function()
			lightingColorIndex = lightingColorIndex % #palette + 1
			refreshLightingColor()
		end)
		refreshLightingColor()
	end
	makeSlider(fogSection, 35, "Start", 0, 1000, fogStart, 10, function(value)
		fogStart = value
		if fogEnabled then Lighting.FogStart = math.min(fogStart, fogEnd) end
	end)
	makeSlider(fogSection, 85, "End", 0, 1000, fogEnd, 10, function(value)
		fogEnd = value
		if fogEnabled then
			Lighting.FogStart = math.min(fogStart, fogEnd)
			Lighting.FogEnd = fogEnd
		end
	end)
	makeToggle(fogSection, 135, "Rainbow", false, function(value) rainbowFog = value end)
	do
		local fogColorButton = makeButton(fogSection, 170)
		local function refreshFogColor()
			fogColorButton.Text = "Color: " .. (fogColorIndex == 0 and "Game default" or palette[fogColorIndex].Name)
		end
		fogColorButton.MouseButton1Click:Connect(function()
			fogColorIndex = fogColorIndex % #palette + 1
			refreshFogColor()
		end)
		refreshFogColor()
	end
	makeSlider(cameraSection, 35, "Amount", 1, 120, cameraFovAmount, 1, function(value) cameraFovAmount = value end)
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

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
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
					if waitingForKey == "Aim" then aim.active = false end
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
				aim.active = false
			end
		elseif key == keys.Aim and aim.enabled and not menuOpen and not gameProcessed then
			aim.active = aim.hold or not aim.active
		elseif key == keys.Camlock and camlockEnabled and not camlockExtra.autoLock then
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

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == keys.Aim and aim.hold then
			aim.active = false
		end
	end)

	RunService.RenderStepped:Connect(function()
		local mousePosition = UserInputService:GetMouseLocation()
		local rainbowColor = Color3.fromHSV((os.clock() % 5) / 5, 1, 1)
		local crosshairColor = crosshairRainbow and rainbowColor or palette[crosshairColorIndex].Value
		crosshair.BackgroundColor3 = crosshairColor
		crosshairVertical.BackgroundColor3 = crosshairColor
		crosshairText.TextColor3 = crosshairColor
		colorCorrection.TintColor = rainbowLighting and rainbowColor or palette[lightingColorIndex].Value
		if fogEnabled then
			Lighting.FogColor = rainbowFog and rainbowColor
				or (fogColorIndex == 0 and savedFogColor or palette[fogColorIndex].Value)
		end
		circle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		circle.Size = UDim2.fromOffset(fovRadius * 2, fovRadius * 2)
		circleOutline.Color = rainbowFov and rainbowColor or palette[colorIndexes.FOV].Value
		circle.BackgroundColor3 = circleOutline.Color
		circle.BackgroundTransparency = filledFov and fovTransparency or 1
		aimCircle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		aimCircle.Size = UDim2.fromOffset(aim.radius * 2, aim.radius * 2)
		aimCircle.Visible = showAimCircle and aim.limit
		silentCircle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		silentCircle.Size = UDim2.fromOffset(silent.radius * 2, silent.radius * 2)
		silentCircle.Visible = showSilentCircle and silent.limit
		silent.target = silent.enabled and not menuOpen and getClosestPlayer(silent) or nil

		local camera = workspace.CurrentCamera
		local targetCharacter = lockedPlayer and lockedPlayer.Character
		local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
		if spectateCamera and (not viewTarget or not targetHumanoid or targetHumanoid.Health <= 0 or camera ~= spectateCamera) then
			spectateCamera.CameraSubject = savedCameraSubject
			spectateCamera, savedCameraSubject = nil, nil
		end
		if viewTarget and camera and targetHumanoid and targetHumanoid.Health > 0 then
			if camera ~= spectateCamera then
				spectateCamera, savedCameraSubject = camera, camera.CameraSubject
			end
			camera.CameraSubject = targetHumanoid
		end
		if cameraFovEnabled and camera then
			if camera ~= savedCamera then
				if savedCamera then savedCamera.FieldOfView = savedCameraFov end
				savedCamera, savedCameraFov = camera, camera.FieldOfView
			end
			camera.FieldOfView = cameraFovAmount
		end

		local targetPart = lockedPlayer and getCamlockPart(lockedPlayer)
		local targetColor = rainbowTarget and rainbowColor or theme.accent
		targetDot.BackgroundColor3 = targetColor
		targetTracer.BackgroundColor3 = targetColor
		targetHighlight.FillColor = targetColor
		targetDot.Visible = false
		targetTracer.Visible = false
		targetStats.Visible = false
		targetHighlight.Enabled = targetPart ~= nil and showTargetHighlight
		targetHighlight.Adornee = targetPart and lockedPlayer.Character or nil
		if targetPart and camera then
			local point, onScreen = camera:WorldToViewportPoint(camlockPosition(targetPart))
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

	local pingElapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		if camlockExtra.resolver then
			local part = lockedPlayer and getCamlockPart(lockedPlayer)
			if part ~= camlockExtra.samplePart then
				camlockExtra.samplePart = part
				camlockExtra.samplePosition = part and part.Position
				camlockExtra.sampleElapsed, camlockExtra.velocity = 0, nil
			elseif part then
				camlockExtra.sampleElapsed = camlockExtra.sampleElapsed + deltaTime
				if camlockExtra.sampleElapsed >= 0.1 then
					camlockExtra.velocity = (part.Position - camlockExtra.samplePosition) / camlockExtra.sampleElapsed
					camlockExtra.samplePosition, camlockExtra.sampleElapsed = part.Position, 0
				end
			end
		end
		if autoPrediction then
			pingElapsed = pingElapsed + deltaTime
			if pingElapsed >= 1 then
				pingElapsed = 0
				if not updateAutoPrediction() then
					autoPrediction = false
					setAutoPrediction(false)
					notify("Auto prediction", "Network ping is unavailable; disabled.")
				end
			end
		end
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
			humanoid.WalkSpeed = speedAmount
		end
		if autoJump and humanoid and humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
			humanoid.Jump = true
		end
		if disableSeats and humanoid and humanoid.Sit then humanoid.Sit = false end
		if not root or not humanoid or humanoid.Health <= 0 then
			safeCFrame, safeCharacter = nil, nil
			return
		end
		if lookAtTarget and lockedPlayer then
			local targetPart = getTargetPart(lockedPlayer, "HumanoidRootPart")
			if targetPart then
				local destination = Vector3.new(targetPart.Position.X, root.Position.Y, targetPart.Position.Z)
				if (destination - root.Position).Magnitude > 0 then root.CFrame = CFrame.lookAt(root.Position, destination) end
			end
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
			root.CFrame = root.CFrame + direction * (flightAmount * deltaTime)
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		elseif strafeEnabled and lockedPlayer and not menuOpen then
			local targetPart = getTargetPart(lockedPlayer, "HumanoidRootPart")
			if targetPart then
				if strafeRandom then
					strafeRandomElapsed = strafeRandomElapsed - deltaTime
					if strafeRandomElapsed <= 0 then
						strafeRandomRate = math.random(-100, 100) / 100
						strafeRandomElapsed = 1
					end
				end
				strafeAngle = strafeAngle + strafeSpeed * (strafeRandom and strafeRandomRate or 1) * deltaTime
				local offset = Vector3.new(math.cos(strafeAngle) * strafeDistance, strafeHeight, math.sin(strafeAngle) * strafeDistance)
				root.CFrame = root.CFrame + (targetPart.Position + offset - root.Position)
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end
		end
	end)
end

StarterGui:SetCore("SendNotification", {
	Title = "Notification",
	Text = "made by /azuremodded",
	Duration = 5
})

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
		local activated, activationError = pcall(function() tool:Activate() end)
		if not activated then
			task.delay(0.25, function() canShoot = true end)
			warn("Triggerbot failed to activate " .. tool.Name .. ": " .. tostring(activationError))
			return false
		end
		autoFired = true
		if tool:FindFirstChildOfClass("RemoteEvent") == nil and tool:FindFirstChild("Handle") then
			task.wait(0.01)
		end
		local deactivated, deactivationError = pcall(function() tool:Deactivate() end)
		if not deactivated then
			warn("Triggerbot failed to deactivate " .. tool.Name .. ": " .. tostring(deactivationError))
		end

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
	while model do
		local targetPlayer = Players:GetPlayerFromCharacter(model)
		if targetPlayer then
			return not isFriendly(targetPlayer) and not isRagdolled(model)
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function handleMouseMovement()
	if not triggerbotEnabled or menuOpen or not leftHeld or isCrouching then return end

	local tool = getEquippedTool()
	if not tool or not isGun(tool) then
		leftHeld = false
		lastTarget = nil
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then return end
	local origin = camera.CFrame.Position
	local offset = mouse.Hit.Position - origin
	if offset.Magnitude == 0 then return end
	local direction = offset.Unit * 1000
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(origin, direction, params)
	if result and isValidTarget(result.Instance) then
		local distance = (result.Position - origin).Magnitude

		local toolName = tool.Name:lower()
		if toolName:find("revolver", 1, true) and distance > 200 then
			lastTarget = nil
			return
		elseif (toolName:find("double-barrel", 1, true) or toolName:find("shotgun", 1, true)) and distance > 75 then
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
