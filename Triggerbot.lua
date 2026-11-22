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
local leftHeld = false
local mouseDown = false
local lastTarget

local lockedPlayer
local camlockTargets = {enabled = false, names = {}}
local aim = {enabled = false, active = false, hold = true, radius = 150, limit = true, wall = true, team = true, part = "Head", smoothing = 0.25}
local silent = {enabled = false, radius = 150, limit = true, wall = true, team = true, part = "Head", method = "Mouse", target = nil}

local function aimPosition(targetPart)
	if predictionEnabled then
		return targetPart.Position + targetPart.AssemblyLinearVelocity * predictionTime
	end
	return targetPart.Position
end

local function isVisible(targetPart, camera, targetCharacter)
	local direction = targetPart.Position - camera.CFrame.Position
	if direction.Magnitude == 0 then return true end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {player.Character}

	local hit = workspace:Raycast(camera.CFrame.Position, direction, params)
	return not hit or hit.Instance:IsDescendantOf(targetCharacter or targetPart.Parent)
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

local function getClosestPlayer(settings)
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local mousePosition = UserInputService:GetMouseLocation()
	local closestPlayer
	local closestDistance = settings and (settings.limit and settings.radius or math.huge)
		or (fovLimitEnabled and fovRadius or math.huge)

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local targetPart = getTargetPart(targetPlayer, settings and settings.part, settings and settings.team)
		if targetPart and (settings or not camlockTargets.enabled or camlockTargets.names[targetPlayer.Name:lower()]) then
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

local mouseHookInstalled, rayHookInstalled = false, false
local rawMouseMetatable, rawRayMetatable
local gameAimAttributes
local function updateGameAim()
	if not gameAimAttributes then return end
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local supported = tool and (tool.Name == "[Revolver]" or tool.Name == "[Double-Barrel SG]"
		or tool.Name == "[TacticalShotgun]")
	local values = {
		AimLock = not menuOpen and supported == true,
		AimLockFov = silent.radius / 5,
		TargetLimb = silent.part,
	}
	for _, entry in ipairs(gameAimAttributes) do
		local value = values[entry.name]
		if player:GetAttribute(entry.name) ~= value then
			player:SetAttribute(entry.name, value)
		end
		entry.applied = value
	end
end
local function stopGameAim()
	if not gameAimAttributes then return end
	for _, entry in ipairs(gameAimAttributes) do
		if player:GetAttribute(entry.name) == entry.applied then
			player:SetAttribute(entry.name, entry.original)
		end
	end
	gameAimAttributes = nil
end
local function startGameAim()
	if game.PlaceId ~= 138014591158268 then return false, "Z ZHD mode is only for Z ZHD." end
	if silent.wall or silent.team then return false, "Z ZHD: turn wall and team checks off." end
	if not silent.limit or silent.radius < 50 then return false, "Z ZHD: use FOV limit of at least 50." end
	gameAimAttributes = {}
	for _, name in ipairs({"AimLock", "AimLockFov", "TargetLimb"}) do
		table.insert(gameAimAttributes, {name = name, original = player:GetAttribute(name)})
	end
	updateGameAim()
	return true
end
local function silentTarget()
	if not silent.enabled or menuOpen then return nil end
	local character = player.Character
	if not character or not character:FindFirstChildOfClass("Tool") then return nil end
	local target = silent.target
	return target and getTargetPart(target, silent.part, silent.team) or nil
end

local function installSilentHook(method)
	if type(hookmetamethod) ~= "function" and type(getrawmetatable) ~= "function" then
		return false, "Missing: hookmetamethod"
	end
	if method == "Raycast" and type(getnamecallmethod) ~= "function" then
		return false, "Missing: getnamecallmethod"
	end
	if type(hookmetamethod) == "function" and type(newcclosure) ~= "function"
		and (type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function") then
		return false, "Missing: newcclosure"
	end
	if type(hookmetamethod) == "function" and type(checkcaller) ~= "function"
		and (type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function") then
		return false, "Missing: checkcaller"
	end
	if type(hookmetamethod) ~= "function" and type(getrawmetatable) == "function"
		and type(setreadonly) ~= "function" then
		return false, "Missing: setreadonly"
	end
	if (method == "Mouse" and mouseHookInstalled) or (method == "Raycast" and rayHookInstalled) then
		return true
	end
	local old
	local ok, err = pcall(function()
		if method == "Mouse" then
			local function indexHook(object, key)
				local external = type(checkcaller) ~= "function" or not checkcaller()
				if object == mouse and external and silent.method == "Mouse" and (key == "Hit" or key == "Target") then
					local part = silentTarget()
					if part then
						if key == "Target" then return part end
						return part.CFrame + (aimPosition(part) - part.Position)
					end
				end
				return old(object, key)
			end
			if type(hookmetamethod) == "function" and type(newcclosure) == "function" then
				old = hookmetamethod(game, "__index", newcclosure(indexHook))
			elseif type(getrawmetatable) == "function" and type(setreadonly) == "function" then
				if type(setreadonly) ~= "function" then error("Missing: setreadonly") end
				rawMouseMetatable = getrawmetatable(game)
				setreadonly(rawMouseMetatable, false)
				old = rawMouseMetatable.__index
				rawMouseMetatable.__index = newcclosure and newcclosure(indexHook) or indexHook
				setreadonly(rawMouseMetatable, true)
			elseif type(hookmetamethod) == "function" then
				error("Missing: newcclosure")
			else
				error("Missing: setreadonly")
			end
			mouseHookInstalled = true
		else
			local function namecallHook(object, ...)
				local external = type(checkcaller) ~= "function" or not checkcaller()
				if object == workspace and external and silent.method == "Raycast" and getnamecallmethod() == "Raycast" then
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
			end
			if type(hookmetamethod) == "function" and type(newcclosure) == "function" then
				old = hookmetamethod(game, "__namecall", newcclosure(namecallHook))
			elseif type(getrawmetatable) == "function" and type(setreadonly) == "function" then
				rawRayMetatable = getrawmetatable(game)
				setreadonly(rawRayMetatable, false)
				old = rawRayMetatable.__namecall
				rawRayMetatable.__namecall = newcclosure and newcclosure(namecallHook) or namecallHook
				setreadonly(rawRayMetatable, true)
			elseif type(hookmetamethod) == "function" then
				error("Missing: newcclosure")
			else
				error("Missing: setreadonly")
			end
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
	local speedEnabled, autoJump, antiVoid, flightEnabled = false, false, false, false
	local movement = {infiniteJump = false, actions = {}}
	local speedAmount = 24
	local savedHumanoid, savedWalkSpeed, safeCFrame, safeCharacter
	local cameraFovEnabled, savedCamera, savedCameraFov = false, nil, nil
	local savedShadows, savedFogStart, savedFogEnd
	local overlays = {}
	local keys = {
		Camlock = Enum.KeyCode.Q,
		ESP = Enum.KeyCode.T,
		Speed = Enum.KeyCode.G,
		Flight = Enum.KeyCode.Unknown,
		AutoJump = Enum.KeyCode.Unknown,
		InfiniteJump = Enum.KeyCode.Unknown,
		AntiVoid = Enum.KeyCode.Unknown,
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

	local pageContents = {tabs = {}}

	for index, name in ipairs({"Aimbot", "Player", "Visuals", "Aim modes", "Config"}) do
		local page = Instance.new("Frame")
		page.Name = name .. "Page"
		page.Position = UDim2.fromOffset(8, 53)
		page.Size = UDim2.new(1, -16, 1, -61)
		page.BackgroundTransparency = 1
		page.Visible = name == "Aimbot"
		page.ZIndex = 11
		page.Parent = menu
		local content = Instance.new("ScrollingFrame")
		content.Size = UDim2.new(1, 0, 1, 0)
		content.BackgroundTransparency = 1
		content.BorderSizePixel = 0
		content.CanvasSize = UDim2.fromOffset(0, name == "Visuals" and 485 or name == "Aimbot" and 455 or 358)
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
		pageContents.tabs[name] = tab

		tab.MouseButton1Click:Connect(function()
			for pageName, otherTab in pairs(pageContents.tabs) do
				pageContents[pageName].Parent.Visible = pageName == name
				otherTab.TextColor3 = pageName == name and theme.text or theme.muted
				otherTab.BackgroundColor3 = pageName == name and theme.active or theme.background
			end
		end)
	end

	local function compact(y)
		return math.floor(y * 0.75)
	end

	local function makeSection(page, name, x, height, y)
		local section = Instance.new("Frame")
		section.Name = "Section:" .. name
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
	local visibilitySection = makeSection(pageContents.Player, "Movement", 248, 255)
	local movementKeys = makeSection(pageContents.Player, "Movement keybinds", 0, 205, 150)
	local espColors = makeSection(pageContents.Visuals, "ESP colors", 0, 300)
	local espFilters = makeSection(pageContents.Visuals, "ESP filters", 0, 325, 233)
	local fovColors = makeSection(pageContents.Visuals, "Visual effects", 248, 262)
	local aimSection = makeSection(pageContents["Aim modes"], "Camera aimbot", 0, 476)
	local silentSection = makeSection(pageContents["Aim modes"], "Silent aim", 248, 476)

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

	local config = (function()
		local registry, entries = {}, {}
		local api = {}
		local section = makeSection(pageContents.Config, "Config", 0, 420)
		local savedSection = makeSection(pageContents.Config, "Saved configs", 248, 420)
		local status = makeLabel(section, "Enter a name and save, or select a config.", 310, 95)
		status.Name = "ConfigStatus"
		local filename = "Azure_Public_Config.json"
		makeLabel(section, "Config name (click to edit)", 30, 20)
		local nameInput = Instance.new("TextBox")
		nameInput.Name = "ConfigName"
		nameInput.Position = UDim2.fromOffset(8, compact(52))
		nameInput.Size = UDim2.fromOffset(220, 20)
		nameInput.BackgroundColor3 = theme.control
		nameInput.BorderSizePixel = 0
		nameInput.TextColor3 = theme.text
		nameInput.PlaceholderColor3 = theme.muted
		nameInput.PlaceholderText = "Config name"
		nameInput.ClearTextOnFocus = false
		nameInput.Text = "Default"
		nameInput.Font = Enum.Font.Code
		nameInput.TextSize = 12
		nameInput.ZIndex = 14
		nameInput.Parent = section
		decorate(nameInput, 0, theme.border)
		makeLabel(section, "JSON file in executor workspace", 85, 20)
		local fileInput = Instance.new("TextBox")
		fileInput.Name = "ConfigFile"
		fileInput.Position = UDim2.fromOffset(8, compact(107))
		fileInput.Size = UDim2.fromOffset(220, 20)
		fileInput.BackgroundColor3 = theme.control
		fileInput.BorderSizePixel = 0
		fileInput.TextColor3 = theme.text
		fileInput.PlaceholderColor3 = theme.muted
		fileInput.PlaceholderText = "File name to import"
		fileInput.ClearTextOnFocus = false
		fileInput.Text = ""
		fileInput.Font = Enum.Font.Code
		fileInput.TextSize = 12
		fileInput.ZIndex = 14
		fileInput.Parent = section
		decorate(fileInput, 0, theme.border)
		local list = Instance.new("ScrollingFrame")
		list.Name = "ConfigList"
		list.Position = UDim2.fromOffset(8, 25)
		list.Size = UDim2.new(1, -16, 1, -33)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 4
		list.ScrollBarImageColor3 = theme.border
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ZIndex = 14
		list.Parent = savedSection
		local listButtons = {}

		local function finite(value, seen)
			if type(value) == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
			if type(value) ~= "table" then return true end
			seen = seen or {}
			if seen[value] then return false end
			seen[value] = true
			for key, item in pairs(value) do
				if not finite(key, seen) or not finite(item, seen) then return false end
			end
			seen[value] = nil
			return true
		end
		local function valid(entry, value)
			return finite(value) and entry.validate(value) == true
		end
		function api.number(minimum, maximum)
			return function(value)
				return type(value) == "number" and finite(value) and value >= minimum and value <= maximum
			end
		end
		function api.choice(list)
			return function(value)
				if not finite(value) then return false end
				for _, item in ipairs(list) do
					if value == item then return true end
				end
				return false
			end
		end
		function api.register(id, get, set, validate, phase)
			assert(type(id) == "string" and id ~= "" and not registry[id], "Invalid or duplicate config id: " .. tostring(id))
			assert(type(get) == "function" and type(set) == "function" and type(validate) == "function", "Invalid config callbacks: " .. id)
			if phase == nil then phase = 1 end
			assert(type(phase) == "number" and finite(phase), "Invalid config phase: " .. id)
			local entry = {id = id, get = get, set = set, validate = validate, phase = phase, order = #entries + 1}
			registry[id] = entry
			table.insert(entries, entry)
		end
		local function report(ok, message)
			status.Text = message
			status.TextColor3 = ok and theme.muted or Color3.fromRGB(255, 115, 115)
		end
		local function validName(name)
			return type(name) == "string" and #name > 0 and #name <= 32
				and name:match("^[%w_ %-]+$") ~= nil and name:match("^%s") == nil and name:match("%s$") == nil
		end
		local function selectedName()
			local name = nameInput.Text:match("^%s*(.-)%s*$")
			assert(validName(name), "Name must be 1-32 letters, numbers, spaces, underscores or hyphens.")
			return name
		end
		local function readProfiles()
			assert(type(isfile) == "function", "isfile is unavailable.")
			local exists = isfile(filename)
			assert(type(exists) == "boolean", "isfile returned an invalid result.")
			if not exists then return {} end
			assert(type(readfile) == "function", "readfile is unavailable.")
			local data = game:GetService("HttpService"):JSONDecode(readfile(filename))
			assert(type(data) == "table", "Invalid config file.")
			if data.version == 1 and type(data.values) == "table" then return {Default = data} end
			assert(data.version == 2 and type(data.profiles) == "table", "Invalid config file or version.")
			for name, profile in pairs(data.profiles) do
				assert(validName(name) and type(profile) == "table" and profile.version == 1
					and type(profile.values) == "table", "Invalid saved config: " .. tostring(name))
			end
			return data.profiles
		end
		local function validateProfile(data)
			assert(type(data) == "table" and data.version == 1 and type(data.values) == "table", "Invalid config format or version.")
			for id, value in pairs(data.values) do
				local entry = registry[id]
				assert(entry and valid(entry, value), "Invalid or unknown setting: " .. tostring(id))
			end
		end
		local function writeProfiles(profiles)
			assert(type(writefile) == "function", "writefile is unavailable.")
			local json = game:GetService("HttpService"):JSONEncode({version = 2, profiles = profiles})
			assert(writefile(filename, json) ~= false, "writefile returned false.")
		end
		local function renderProfiles(profiles)
			for _, button in ipairs(listButtons) do button:Destroy() end
			listButtons = {}
			local names = {}
			for name in pairs(profiles) do table.insert(names, name) end
			table.sort(names)
			for index, name in ipairs(names) do
				local button = makeButton(list, (index - 1) * 32, 205, 0)
				button.Name = "ConfigItem:" .. name
				button.Text = name
				button.BackgroundColor3 = nameInput.Text == name and theme.active or theme.control
				button.MouseButton1Click:Connect(function()
					nameInput.Text = name
					renderProfiles(profiles)
					report(true, "Selected " .. name .. ". Click Load config.")
				end)
				table.insert(listButtons, button)
			end
			list.CanvasSize = UDim2.fromOffset(0, #names * 24)
		end
		local function save()
			assert(type(writefile) == "function", "writefile is unavailable.")
			local name = selectedName()
			local profiles = readProfiles()
			local values = {}
			for _, entry in ipairs(entries) do
				local value = entry.get()
				assert(valid(entry, value), "Invalid current value: " .. entry.id)
				values[entry.id] = value
			end
			profiles[name] = {version = 1, values = values}
			writeProfiles(profiles)
			nameInput.Text = name
			renderProfiles(profiles)
			return name
		end
		local function load()
			local name = selectedName()
			local profiles = readProfiles()
			local data = profiles[name]
			assert(data, "No saved config named " .. name .. ".")
			validateProfile(data)
			local silent = registry["toggle/Section:Silent aim/Silent aim"]
			local silentValue = silent.get()
			local desiredSilent = data.values[silent.id]
			if desiredSilent == nil then desiredSilent = silentValue end
			local ordered = {}
			for _, entry in ipairs(entries) do
				if entry ~= silent and data.values[entry.id] ~= nil then table.insert(ordered, entry) end
			end
			table.sort(ordered, function(a, b)
				if a.phase ~= b.phase then return a.phase < b.phase end
				return a.order < b.order
			end)
			local function apply(entry, value)
				local ok, result, detail = pcall(entry.set, value)
				if not ok or result == false then
					return false, entry.id .. ": " .. tostring(ok and (detail or "rejected") or result)
				end
				return true
			end
			if silentValue then
				local ok, err = apply(silent, false)
				assert(ok, "Could not disable " .. tostring(err) .. " (settings may have partially applied).")
			end
			for _, entry in ipairs(ordered) do
				local ok, err = apply(entry, data.values[entry.id])
				if not ok then
					local restored, restoreErr = apply(silent, desiredSilent)
					error("Could not apply " .. err .. "; load partially applied."
						.. (restored and "" or (" Silent aim restore failed: " .. restoreErr)))
				end
			end
			local ok, err = apply(silent, desiredSilent)
			assert(ok, "Could not apply " .. tostring(err) .. "; load partially applied.")
			nameInput.Text = name
			renderProfiles(profiles)
			return name
		end
		local function exportConfig()
			assert(type(writefile) == "function", "writefile is unavailable.")
			local name = selectedName()
			local data = readProfiles()[name]
			assert(data, "Save this config before exporting it.")
			validateProfile(data)
			local base = "Azure_Public_Export_" .. name
			local path
			for index = 1, 10000 do
				local candidate = base .. (index == 1 and "" or ("-" .. index)) .. ".json"
				local exists = isfile(candidate)
				assert(type(exists) == "boolean", "isfile returned an invalid result.")
				if not exists then path = candidate; break end
			end
			assert(path, "Too many exports with this name.")
			local json = game:GetService("HttpService"):JSONEncode(data)
			assert(writefile(path, json) ~= false, "writefile returned false.")
			fileInput.Text = path
			return path
		end
		local function importConfig()
			assert(type(readfile) == "function", "readfile is unavailable.")
			local name = selectedName()
			local path = fileInput.Text:match("^%s*(.-)%s*$")
			assert(#path <= 128 and path:match("^[%w_ %-]+%.json$"), "Enter a JSON filename from the workspace.")
			local data = game:GetService("HttpService"):JSONDecode(readfile(path))
			validateProfile(data)
			local profiles = readProfiles()
			profiles[name] = data
			writeProfiles(profiles)
			nameInput.Text, fileInput.Text = name, path
			renderProfiles(profiles)
			return name
		end
		local saveButton = makeButton(section, 145)
		saveButton.Name, saveButton.Text = "ConfigSave", "Save config"
		saveButton.MouseButton1Click:Connect(function()
			local ok, err = pcall(save)
			report(ok, ok and ("Saved " .. err) or ("Save error: " .. tostring(err)))
		end)
		local loadButton = makeButton(section, 178)
		loadButton.Name, loadButton.Text = "ConfigLoad", "Load config"
		loadButton.MouseButton1Click:Connect(function()
			local ok, err = pcall(load)
			report(ok, ok and ("Loaded " .. err) or ("Load error: " .. tostring(err)))
		end)
		local exportButton = makeButton(section, 211)
		exportButton.Name, exportButton.Text = "ConfigExport", "Export JSON"
		exportButton.MouseButton1Click:Connect(function()
			local ok, result = pcall(exportConfig)
			report(ok, ok and ("Exported " .. result) or ("Export error: " .. tostring(result)))
		end)
		local importButton = makeButton(section, 244)
		importButton.Name, importButton.Text = "ConfigImport", "Import JSON"
		importButton.MouseButton1Click:Connect(function()
			local ok, result = pcall(importConfig)
			report(ok, ok and ("Imported " .. result) or ("Import error: " .. tostring(result)))
		end)
		local refreshButton = makeButton(section, 277)
		refreshButton.Name, refreshButton.Text = "ConfigRefresh", "Refresh list"
		refreshButton.MouseButton1Click:Connect(function()
			local ok, result = pcall(readProfiles)
			if ok then renderProfiles(result) end
			report(ok, ok and "Saved configs refreshed." or ("Refresh error: " .. tostring(result)))
		end)
		do
			local ok, result = pcall(readProfiles)
			if ok then renderProfiles(result) else report(false, "Config list error: " .. tostring(result)) end
		end
		return api
	end)()

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
		config.register("toggle/" .. parent.Name .. "/" .. name, function() return value end, function(newValue)
			if newValue == value then return true end
			if changed(newValue) == false then return false end
			value = newValue
			refresh()
			return true
		end, function(newValue) return type(newValue) == "boolean" end,
			name == "Silent aim" and parent.Name == "Section:Silent aim" and 3 or 2)
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

	local function notify(title, text)
		StarterGui:SetCore("SendNotification", {Title = title, Text = text, Duration = 3})
	end

	local function unlock()
		if lockedPlayer then
			notify("Camlock", "Unlocked from " .. lockedPlayer.Name)
			lockedPlayer = nil
		end
	end

	do
		local section = makeSection(pageContents.Aimbot, "Camlock player selection", 0, 260, 256)
		makeToggle(section, 32, "Selected players only", false, function(value)
			camlockTargets.enabled = value
			if value and lockedPlayer and not camlockTargets.names[lockedPlayer.Name:lower()] then
				unlock()
			end
		end)
		makeLabel(section, "Select players below. Empty list locks nobody.", 63, 42)
		local list = Instance.new("ScrollingFrame")
		list.Name = "CamlockPlayerList"
		list.Position = UDim2.fromOffset(8, compact(105))
		list.Size = UDim2.new(1, -16, 1, -compact(112))
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 4
		list.ScrollBarImageColor3 = theme.border
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ZIndex = 14
		list.Parent = section
		local buttons = {}
		local function refresh(excluded, added)
			for _, button in ipairs(buttons) do button:Destroy() end
			buttons = {}
			local current, included = {}, {}
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and other ~= excluded then
					table.insert(current, other)
					included[other] = true
				end
			end
			if added and added ~= player and not included[added] then table.insert(current, added) end
			table.sort(current, function(a, b) return a.Name:lower() < b.Name:lower() end)
			for index, other in ipairs(current) do
				local name = other.Name:lower()
				local button = makeButton(list, (index - 1) * 32, 205, 0)
				button.Name = "CamlockPlayer:" .. other.Name
				button.Text = (camlockTargets.names[name] and "[x] " or "[ ] ") .. other.Name
				button.BackgroundColor3 = camlockTargets.names[name] and theme.active or theme.control
				button.MouseButton1Click:Connect(function()
					camlockTargets.names[name] = not camlockTargets.names[name] or nil
					if camlockTargets.enabled and lockedPlayer == other and not camlockTargets.names[name] then
						unlock()
					end
					refresh()
				end)
				table.insert(buttons, button)
			end
			list.CanvasSize = UDim2.fromOffset(0, #current * 24)
		end
		config.register("camlock/selectedPlayers", function()
			local names = {}
			for name in pairs(camlockTargets.names) do names[name] = true end
			return names
		end, function(names)
			camlockTargets.names = {}
			for name in pairs(names) do camlockTargets.names[name] = true end
			if camlockTargets.enabled and lockedPlayer and not camlockTargets.names[lockedPlayer.Name:lower()] then
				unlock()
			end
			refresh()
		end, function(names)
			if type(names) ~= "table" then return false end
			for name, selected in pairs(names) do
				if type(name) ~= "string" or #name > 20 or #name < 1
					or not name:match("^[%w_]+$") or name ~= name:lower() or selected ~= true then return false end
			end
			return true
		end)
		Players.PlayerAdded:Connect(function(other) refresh(nil, other) end)
		Players.PlayerRemoving:Connect(function(other) refresh(other) end)
		refresh()
	end

	local function refreshKeyButtons()
		for name, button in pairs(keyButtons) do
			button.Text = name .. " key: " .. (waitingForKey == name and "Press a key..."
				or keys[name] == Enum.KeyCode.Unknown and "Unbound" or keys[name].Name)
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
	config.register("keybinds", function()
		local values = {}
		for name, key in pairs(keys) do values[name] = key.Name end
		return values
	end, function(values)
		for _, name in ipairs({"Flight", "AutoJump", "InfiniteJump", "AntiVoid"}) do
			keys[name] = Enum.KeyCode[values[name] or "Unknown"]
		end
		for name, value in pairs(values) do keys[name] = Enum.KeyCode[value] end
		waitingForKey = nil
		aim.active = false
		refreshKeyButtons()
	end, function(values)
		if type(values) ~= "table" then return false end
		local seen = {}
		for name in pairs(keys) do
			local value = values[name]
			local optional = name == "Flight" or name == "AutoJump" or name == "InfiniteJump" or name == "AntiVoid"
			if value == nil and optional then value = "Unknown" end
			if type(value) ~= "string" or (value == "Unknown" and not optional)
				or value == "Escape" or (value ~= "Unknown" and seen[value]) then return false end
			local ok, key = pcall(function() return Enum.KeyCode[value] end)
			if not ok or not key then return false end
			if value ~= "Unknown" then seen[value] = true end
		end
		for name in pairs(values) do if not keys[name] then return false end end
		return true
	end)

	for _, name in ipairs({"Visible", "Hidden", "FOV"}) do
		local section = name == "FOV" and fovColors or espColors
		local y = name == "Hidden" and 67 or 35
		local button = makeButton(section, y)

		local function refreshColorButton()
			button.Text = name .. " color: " .. palette[colorIndexes[name]].Name
		end

		refreshColorButton()
		config.register("color/" .. name, function() return colorIndexes[name] end, function(value)
			colorIndexes[name] = value
			refreshColorButton()
		end, config.choice({1, 2, 3, 4, 5}))
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
	config.register("camlock/radius", function() return fovRadius end, function(value)
		fovRadius = value
		updateRadius()
	end, config.number(25, 1000))

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
	config.register("camlock/prediction", function() return predictionTime end, function(value)
		predictionTime = value
		updatePrediction()
	end, config.number(0, 1))
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
	config.register("aim/hold", function() return aim.hold end, function(value)
		aim.hold, aim.active = value, false
		refreshAimMode()
	end, function(value) return type(value) == "boolean" end)
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
	config.register("aim/part", function() return aim.part end, function(value)
		aim.part = value
		refreshAimPart()
	end, config.choice({"Head", "HumanoidRootPart"}))
	aimPartButton.MouseButton1Click:Connect(function()
		aim.part = aim.part == "Head" and "HumanoidRootPart" or "Head"
		refreshAimPart()
	end)
	local aimRadius = makeLabel(aimSection, "", 291)
	local function refreshAimRadius() aimRadius.Text = "Aimbot FOV: " .. aim.radius end
	refreshAimRadius()
	config.register("aim/radius", function() return aim.radius end, function(value)
		aim.radius = value
		refreshAimRadius()
	end, config.number(25, 1000))
	local aimMinus = makeButton(aimSection, 323, 104, 8)
	aimMinus.Name, aimMinus.Text = "AimbotFOVDecrease", "-"
	aimMinus.MouseButton1Click:Connect(function() aim.radius = math.max(25, aim.radius - 25); refreshAimRadius() end)
	local aimPlus = makeButton(aimSection, 323, 104, 124)
	aimPlus.Name, aimPlus.Text = "AimbotFOVIncrease", "+"
	aimPlus.MouseButton1Click:Connect(function() aim.radius = math.min(1000, aim.radius + 25); refreshAimRadius() end)
	local smoothButton = makeButton(aimSection, 355)
	local function refreshSmooth() smoothButton.Text = string.format("Smoothing: %.2f", aim.smoothing) end
	refreshSmooth()
	config.register("aim/smoothing", function() return aim.smoothing end, function(value)
		aim.smoothing = value
		refreshSmooth()
	end, config.number(0.1, 1))
	smoothButton.MouseButton1Click:Connect(function()
		aim.smoothing = aim.smoothing >= 1 and 0.1 or math.min(1, aim.smoothing + 0.15)
		refreshSmooth()
	end)
	makeLabel(aimSection, "Uses the Aimbot tab prediction setting.", 390, 48)

	local silentStatus = makeLabel(silentSection, "", 323, 65)
	silentStatus.Name = "SilentAimStatus"
	local function silentError(message)
		silentStatus.Text = message
		silentStatus.TextColor3 = Color3.fromRGB(255, 115, 115)
	end
	local function refreshSilentStatus()
		silentStatus.Text = silent.method == "Z ZHD" and "Z ZHD: no prediction; server may reject." or ""
		silentStatus.TextColor3 = theme.muted
	end
	local function startSilent(method)
		if method == "Z ZHD" then return startGameAim() end
		return installSilentHook(method)
	end
	makeToggle(silentSection, 35, "Silent aim", false, function(value)
		if value then
			local ok, err = startSilent(silent.method)
			if not ok then silentError(err); return false end
		else
			stopGameAim()
		end
		silent.enabled = value
		silent.target = nil
		refreshSilentStatus()
	end)
	local methodButton = makeButton(silentSection, 67)
	local function refreshMethod() methodButton.Text = "Method: " .. silent.method end
	refreshMethod()
	config.register("silent/method", function() return silent.method end, function(value)
		if silent.enabled then
			local ok, err = startSilent(value)
			if not ok then silentError(err); return false end
			if silent.method == "Z ZHD" then stopGameAim() end
		end
		silent.method = value
		refreshSilentStatus()
		refreshMethod()
	end, config.choice({"Mouse", "Raycast", "Z ZHD"}))
	methodButton.MouseButton1Click:Connect(function()
		local method = silent.method == "Mouse" and "Raycast"
			or silent.method == "Raycast" and "Z ZHD" or "Mouse"
		if silent.enabled then
			local ok, err = startSilent(method)
			if not ok then silentError(err); return end
			if silent.method == "Z ZHD" then stopGameAim() end
		end
		silent.method = method
		refreshSilentStatus()
		refreshMethod()
	end)
	makeToggle(silentSection, 99, "Silent FOV limit", true, function(value)
		if not value and silent.enabled and silent.method == "Z ZHD" then
			silentError("Z ZHD requires an FOV limit.")
			return false
		end
		silent.limit = value
	end)
	makeToggle(silentSection, 131, "Silent FOV circle", false, function(value) showSilentCircle = value end)
	makeToggle(silentSection, 163, "Silent wall check", true, function(value)
		if value and silent.enabled and silent.method == "Z ZHD" then
			silentError("Z ZHD does not support wall checks.")
			return false
		end
		silent.wall = value
	end)
	makeToggle(silentSection, 195, "Silent team check", true, function(value)
		if value and silent.enabled and silent.method == "Z ZHD" then
			silentError("Z ZHD does not support team checks.")
			return false
		end
		silent.team = value
	end)
	local silentPartButton = makeButton(silentSection, 227)
	local function refreshSilentPart() silentPartButton.Text = "Target: " .. silent.part end
	refreshSilentPart()
	config.register("silent/part", function() return silent.part end, function(value)
		silent.part, silent.target = value, nil
		updateGameAim()
		refreshSilentPart()
	end, config.choice({"Head", "HumanoidRootPart"}))
	silentPartButton.MouseButton1Click:Connect(function()
		silent.part = silent.part == "Head" and "HumanoidRootPart" or "Head"
		silent.target = nil
		updateGameAim()
		refreshSilentPart()
	end)
	local silentRadius = makeLabel(silentSection, "", 259)
	local function refreshSilentRadius() silentRadius.Text = "Silent FOV: " .. silent.radius end
	refreshSilentRadius()
	config.register("silent/radius", function() return silent.radius end, function(value)
		silent.radius = value
		updateGameAim()
		refreshSilentRadius()
	end, config.number(25, 1000))
	local silentMinus = makeButton(silentSection, 291, 104, 8)
	silentMinus.Name, silentMinus.Text = "SilentFOVDecrease", "-"
	silentMinus.MouseButton1Click:Connect(function()
		local minimum = silent.enabled and silent.method == "Z ZHD" and 50 or 25
		silent.radius = math.max(minimum, silent.radius - 25)
		updateGameAim()
		refreshSilentRadius()
	end)
	local silentPlus = makeButton(silentSection, 291, 104, 124)
	silentPlus.Name, silentPlus.Text = "SilentFOVIncrease", "+"
	silentPlus.MouseButton1Click:Connect(function()
		silent.radius = math.min(1000, silent.radius + 25)
		updateGameAim()
		refreshSilentRadius()
	end)

	makeToggle(teamSection, 35, "Team check", true, function(value) IGNORE_TEAMMATES = value end)
	makeLabel(teamSection, "Existing locks stay active behind walls.", 70, 50)
	makeLabel(teamSection, "Drag target stats while the menu is open.", 125, 50)
	local function setSpeed(value)
		speedEnabled = value
		if not value and savedHumanoid then
			savedHumanoid.WalkSpeed = savedWalkSpeed
			savedHumanoid, savedWalkSpeed = nil, nil
		end
	end
	local setSpeedToggle = makeToggle(visibilitySection, 35, "Speed", false, setSpeed)
	local setAutoJumpToggle = makeToggle(visibilitySection, 67, "Auto jump", false, function(value) autoJump = value end)
	local setAntiVoidToggle = makeToggle(visibilitySection, 99, "Anti void", false, function(value)
		antiVoid = value
		safeCFrame, safeCharacter = nil, nil
	end)
	local setFlightToggle = makeToggle(visibilitySection, 131, "Flight (WASD, Space, Ctrl)", false, function(value) flightEnabled = value end)
	local setInfiniteJumpToggle = makeToggle(movementKeys, 35, "Infinite jump", false, function(value) movement.infiniteJump = value end)
	movement.actions.AutoJump = function() autoJump = not autoJump; setAutoJumpToggle(autoJump) end
	movement.actions.AntiVoid = function()
		antiVoid = not antiVoid
		safeCFrame, safeCharacter = nil, nil
		setAntiVoidToggle(antiVoid)
	end
	movement.actions.Flight = function() flightEnabled = not flightEnabled; setFlightToggle(flightEnabled) end
	movement.actions.InfiniteJump = function()
		movement.infiniteJump = not movement.infiniteJump
		setInfiniteJumpToggle(movement.infiniteJump)
	end
	for index, name in ipairs({"Flight", "AutoJump", "InfiniteJump", "AntiVoid"}) do
		local button = makeButton(movementKeys, 35 + index * 32)
		keyButtons[name] = button
		button.MouseButton1Click:Connect(function()
			waitingForKey = name
			keyHint.Text = "Click a key to rebind. Escape cancels."
			keyHint.TextColor3 = theme.muted
			refreshKeyButtons()
		end)
	end
	UserInputService.JumpRequest:Connect(function()
		if not movement.infiniteJump or flightEnabled or menuOpen or UserInputService:GetFocusedTextBox() then return end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
	end)
	local speedLabel = makeLabel(visibilitySection, "Speed amount (0-200)", 158)
	local speedInput = Instance.new("TextBox")
	speedInput.Name = "SpeedAmountInput"
	speedInput.Position = UDim2.fromOffset(8, compact(184))
	speedInput.Size = UDim2.fromOffset(220, 20)
	speedInput.BackgroundColor3 = theme.control
	speedInput.BorderSizePixel = 0
	speedInput.TextColor3 = theme.text
	speedInput.ClearTextOnFocus = false
	speedInput.Text = tostring(speedAmount)
	speedInput.Font = Enum.Font.Code
	speedInput.TextSize = 12
	speedInput.ZIndex = 14
	speedInput.Parent = visibilitySection
	decorate(speedInput, 0, theme.border)
	config.register("movement/speed", function() return speedAmount end, function(value)
		speedAmount = value
		speedInput.Text = tostring(value)
		speedLabel.Text = "Speed amount (0-200)"
		speedLabel.TextColor3 = theme.muted
	end, config.number(0, 200))
	speedInput.FocusLost:Connect(function()
		local value = tonumber(speedInput.Text)
		if not value or value ~= value or value < 0 or value > 200 then
			speedInput.Text = tostring(speedAmount)
			speedLabel.Text = "Enter speed from 0 to 200"
			speedLabel.TextColor3 = Color3.fromRGB(255, 115, 115)
			return
		end
		speedAmount = value
		speedInput.Text = tostring(value)
		speedLabel.Text = "Speed amount (0-200)"
		speedLabel.TextColor3 = theme.muted
	end)
	local speedKeyButton = makeButton(visibilitySection, 217)
	keyButtons.Speed = speedKeyButton
	speedKeyButton.MouseButton1Click:Connect(function()
		waitingForKey = "Speed"
		keyHint.Text = "Click a key to rebind. Escape cancels."
		keyHint.TextColor3 = theme.muted
		refreshKeyButtons()
	end)
	refreshKeyButtons()

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

	local espDistanceLimit, espMaxDistance = false, 500
	local espNamedOnly, espTargets, espWhitelist = false, {}, {}
	local espFilterStatus = makeLabel(espFilters, "", 276, 45)
	espFilterStatus.Name = "ESPFilterStatus"
	local function filterInput(name, y, placeholder)
		local input = Instance.new("TextBox")
		input.Name = name
		input.Position = UDim2.fromOffset(8, compact(y))
		input.Size = UDim2.fromOffset(220, 20)
		input.BackgroundColor3 = theme.control
		input.BorderSizePixel = 0
		input.TextColor3 = theme.text
		input.PlaceholderColor3 = theme.muted
		input.PlaceholderText = placeholder
		input.ClearTextOnFocus = false
		input.Text = ""
		input.Font = Enum.Font.Code
		input.TextSize = 12
		input.ZIndex = 14
		input.Parent = espFilters
		decorate(input, 0, theme.border)
		return input
	end
	makeToggle(espFilters, 35, "ESP distance limit", false, function(value) espDistanceLimit = value end)
	makeLabel(espFilters, "Max distance (studs)", 67)
	local espDistanceInput = filterInput("ESPDistanceInput", 92, "1-100000")
	espDistanceInput.Text = tostring(espMaxDistance)
	config.register("esp/distance", function() return espMaxDistance end, function(value)
		espMaxDistance = value
		espDistanceInput.Text = tostring(value)
		espFilterStatus.Text = ""
	end, config.number(1, 100000))
	espDistanceInput.FocusLost:Connect(function()
		local value = tonumber(espDistanceInput.Text)
		if not value or value ~= value or value < 1 or value > 100000 then
			espDistanceInput.Text = tostring(espMaxDistance)
			espFilterStatus.Text = "Distance must be 1-100000 studs."
			return
		end
		espMaxDistance = value
		espDistanceInput.Text = tostring(value)
		espFilterStatus.Text = ""
	end)
	makeToggle(espFilters, 126, "ESP named only", false, function(value) espNamedOnly = value end)
	local function nameList(name, label, labelY, inputY, changed, allowDisplayNames)
		makeLabel(espFilters, label, labelY)
		local input = filterInput(name, inputY, allowDisplayNames and "Usernames or display names, comma-separated"
			or "Usernames, separated by commas")
		local previous = ""
		local function parse(value)
			if type(value) ~= "string" then return nil end
			local names = {}
			for entry in (value .. ","):gmatch("(.-),") do
				local username = entry:match("^%s*(.-)%s*$")
				if username ~= "" then
					if (allowDisplayNames and (#username > 80 or username:find("[%c]")))
						or (not allowDisplayNames and (#username > 20 or not username:match("^[%w_]+$"))) then
						return nil
					end
					names[username:lower()] = true
				end
			end
			return names
		end
		config.register("esp/" .. name, function() return previous end, function(value)
			previous, input.Text = value, value
			changed(parse(value))
			espFilterStatus.Text = ""
		end, function(value) return parse(value) ~= nil end)
		input.FocusLost:Connect(function()
			local names = parse(input.Text)
			if not names then
				input.Text = previous
				espFilterStatus.Text = allowDisplayNames and "Use comma-separated player names." or "Use comma-separated usernames."
				return
			end
			previous = input.Text
			changed(names)
			espFilterStatus.Text = ""
		end)
	end
	nameList("ESPTargetsInput", "Target player names", 158, 183, function(names) espTargets = names end, true)
	nameList("ESPWhitelistInput", "Hidden usernames", 217, 242, function(names) espWhitelist = names end)

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
					keyButtons[waitingForKey].Text = "That key is already in use."
					return
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
			updateGameAim()
			targetStats.Active = menuOpen
			stopMenuDrag()
			stopStatsDrag()
			if menuOpen then
				leftHeld, mouseDown, lastTarget = false, false, nil
				aim.active = false
			end
		elseif key == keys.Aim and aim.enabled and not menuOpen and not gameProcessed then
			aim.active = aim.hold or not aim.active
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
		elseif key == keys.Speed and not menuOpen and not gameProcessed then
			setSpeed(not speedEnabled)
			setSpeedToggle(speedEnabled)
		elseif key == keys.ESP then
			enabled = not enabled
			setEspToggle(enabled)
			if not enabled then
				hideOverlays()
			end
		elseif not menuOpen and not gameProcessed and key ~= Enum.KeyCode.Unknown then
			for name, toggle in pairs(movement.actions) do
				if key == keys[name] then toggle(); break end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == keys.Aim and aim.hold then
			aim.active = false
		end
	end)

	local espElapsed = 1 / 30
	RunService.RenderStepped:Connect(function(deltaTime)
		updateGameAim()
		local mousePosition = UserInputService:GetMouseLocation()
		circle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		circle.Size = UDim2.fromOffset(fovRadius * 2, fovRadius * 2)
		circleOutline.Color = palette[colorIndexes.FOV].Value
		aimCircle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		aimCircle.Size = UDim2.fromOffset(aim.radius * 2, aim.radius * 2)
		aimCircle.Visible = showAimCircle and aim.limit
		silentCircle.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
		silentCircle.Size = UDim2.fromOffset(silent.radius * 2, silent.radius * 2)
		silentCircle.Visible = showSilentCircle and silent.limit
		silent.target = silent.enabled and silent.method ~= "Z ZHD" and not menuOpen and getClosestPlayer(silent) or nil

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
		espElapsed = espElapsed + (deltaTime or 0)
		if espElapsed < 1 / 30 then return end
		espElapsed = 0

		for targetPlayer, overlay in pairs(overlays) do
			local box = overlay.box
			overlay.tracer.Visible = false
			local character = targetPlayer.Character
			local targetPart
			if character and (not IGNORE_TEAMMATES or not player.Team or targetPlayer.Team ~= player.Team) then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health > 0 then
					targetPart = character:FindFirstChild("Head")
					if not targetPart or not targetPart:IsA("BasePart") then
						targetPart = character:FindFirstChild("HumanoidRootPart")
					end
					if not targetPart or not targetPart:IsA("BasePart") then
						targetPart = character.PrimaryPart or character:FindFirstChildWhichIsA("BasePart", true)
					end
				end
			end
			local name = targetPlayer.Name:lower()
			local displayName = (targetPlayer.DisplayName or targetPlayer.Name):lower()
			local localRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local origin = localRoot and localRoot:IsA("BasePart") and localRoot.Position or (camera and camera.CFrame.Position)
			local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
			local targetPosition = targetRoot and targetRoot:IsA("BasePart") and targetRoot.Position or (targetPart and targetPart.Position)
			local distance = origin and targetPosition and (targetPosition - origin).Magnitude
			local allowed = not espWhitelist[name] and (not espNamedOnly or espTargets[name] or espTargets[displayName])
				and (not espDistanceLimit or (distance and distance <= espMaxDistance))

			if camera and character and character.Parent and targetPart and allowed then
				local center, size = character:GetBoundingBox()
				local minX, minY = math.huge, math.huge
				local maxX, maxY = -math.huge, -math.huge
				local inFront = false

				for x = -1, 1, 2 do
					for y = -1, 1, 2 do
						for z = -1, 1, 2 do
							local corner = center:PointToWorldSpace(Vector3.new(
								size.X * x / 2,
								size.Y * y / 2,
								size.Z * z / 2
							))
							local point = camera:WorldToViewportPoint(corner)

							if point.Z > 0 then
								inFront = true
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

					local colorName = isVisible(targetPart, camera, character) and "Visible" or "Hidden"
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

					overlay.distance.Text = string.format("%.0f studs", distance)
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
			humanoid.WalkSpeed = speedAmount
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
