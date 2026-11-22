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
local triggerbot = {enabled = true, distanceEnabled = false, maximum = 200, reaction = 0, cooldown = 0}
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
local camlockTargets = {enabled = false, names = {}, priority = "Closest", protectFriends = false, friends = {}}
local aim = {enabled = false, active = false, hold = true, radius = 150, limit = true, wall = true, team = true, part = "Head", smoothing = 0.25}
local silent = {enabled = false, radius = 150, limit = true, wall = true, team = true, part = "Head", method = "Mouse", target = nil}

function camlockTargets.refreshFriend(other)
	if other == player then return end
	local entry = camlockTargets.friends[other]
	if entry and (entry.pending or os.clock() - entry.checkedAt < (entry.error and 10 or 60)) then return end
	entry = {pending = true, checkedAt = os.clock()}
	camlockTargets.friends[other] = entry
	task.spawn(function()
		local ok, result = pcall(function() return player:IsFriendsWith(other.UserId) end)
		if other.Parent ~= Players or camlockTargets.friends[other] ~= entry then return end
		entry.pending, entry.checkedAt = false, os.clock()
		if not ok or type(result) ~= "boolean" then
			entry.error = true
			warn("xwav friend check failed for " .. other.Name .. ": " .. tostring(result))
		else
			entry.isFriend = result
		end
	end)
end
function camlockTargets.protected(other)
	if not camlockTargets.protectFriends then return false end
	camlockTargets.refreshFriend(other)
	local entry = camlockTargets.friends[other]
	return not entry or entry.pending or entry.error or entry.isFriend
end
Players.PlayerRemoving:Connect(function(other) camlockTargets.friends[other] = nil end)

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

local function getTargetPart(targetPlayer, partName, checkTeam, allowFriends)
	if not targetPlayer or targetPlayer == player or targetPlayer.Parent ~= Players then
		return nil
	end
	if not allowFriends and camlockTargets.protected(targetPlayer) then return nil end

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
	local closestPlayer, bestScore, bestDistance = nil, math.huge, math.huge
	local fovDistance = settings and (settings.limit and settings.radius or math.huge)
		or (fovLimitEnabled and fovRadius or math.huge)

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local targetPart = settings and getTargetPart(targetPlayer, settings.part, settings.team)
			or (not settings and getCamlockPart(targetPlayer))
		if targetPart and (camlockTargets.priority ~= "Selected" or camlockTargets.names[targetPlayer.Name:lower()])
			and (settings or not camlockTargets.enabled or camlockTargets.names[targetPlayer.Name:lower()]) then
			local screenPosition, onScreen = camera:WorldToScreenPoint(targetPart.Position)
			if onScreen and screenPosition.Z > 0 then
				local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - mousePosition).Magnitude
				local checkWall = settings and settings.wall
				if not settings then checkWall = wallCheck end
				local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
				local score = camlockTargets.priority == "Lowest health" and humanoid.Health or distance
				if distance <= fovDistance and (score < bestScore or (score == bestScore and distance < bestDistance))
					and (not checkWall or isVisible(targetPart, camera)) then
					bestScore, bestDistance = score, distance
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
	if camlockTargets.protectFriends or camlockTargets.priority ~= "Closest" then
		return false, "Z ZHD cannot enforce friend protection or target priority."
	end
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
	local lookAtTarget, viewTarget, rainbowTarget, rainbowFov, filledFov = false, false, false, false, false
	local fovTransparency = 0.75
	local spectateCamera, savedCameraSubject
	local speedEnabled, autoJump, antiVoid, flightEnabled = false, false, false, false
	local movement = {infiniteJump = false, velocitySpeed = false, actions = {}, lastJump = 0, lastAutoJump = 0}
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
		Speed = Enum.KeyCode.Unknown,
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
	title.Text = "xwav Paid | @socialdw on discord | discord.gg/xwav"
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
		content.CanvasSize = UDim2.fromOffset(0, name == "Aimbot" and 1060
			or name == "Player" and 540 or name == "Visuals" and 860 or 358)
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
	local visibilitySection = makeSection(pageContents.Player, "Movement", 248, 325)
	local espColors = makeSection(pageContents.Visuals, "ESP colors", 0, 300)
	local espFilters = makeSection(pageContents.Visuals, "ESP filters", 0, 325, 460)
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

	local config = (function()
		local registry, entries = {}, {}
		local api = {}
		local section = makeSection(pageContents.Config, "Config", 0, 420)
		local savedSection = makeSection(pageContents.Config, "Saved configs", 248, 420)
		local status = makeLabel(section, "Enter a name and save, or select a config.", 310, 95)
		status.Name = "ConfigStatus"
		local filename = "xwav_Attached_Config.json"
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
			entry.default = get()
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
			if data.version == 1 and type(data.values) == "table" then return {["Saved Default"] = data} end
			assert(data.version == 2 and type(data.profiles) == "table", "Invalid config file or version.")
			for name, profile in pairs(data.profiles) do
				assert(validName(name) and type(profile) == "table" and profile.version == 1
					and type(profile.values) == "table", "Invalid saved config: " .. tostring(name))
			end
			if data.profiles.Default then
				local name, index = "Saved Default", 2
				while data.profiles[name] do
					name = "Saved Default " .. index
					index = index + 1
				end
				data.profiles[name], data.profiles.Default = data.profiles.Default, nil
			end
			return data.profiles
		end
		local function defaultProfile()
			local values = {}
			for _, entry in ipairs(entries) do
				if entry.id:sub(1, 7) == "toggle/" then
					values[entry.id] = false
				else
					values[entry.id] = entry.default
				end
			end
			return {version = 1, values = values}
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
			local names = {"Default"}
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
			assert(name:lower() ~= "default", "Default is blank; choose a different name to save.")
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
		local function applyProfile(data)
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
		end
		local function load()
			local name = selectedName()
			local profiles = readProfiles()
			local data = name == "Default" and defaultProfile() or profiles[name]
			assert(data, "No saved config named " .. name .. ".")
			applyProfile(data)
			nameInput.Text = name
			renderProfiles(profiles)
			return name
		end
		local function exportConfig()
			assert(type(writefile) == "function", "writefile is unavailable.")
			local name = selectedName()
			local data = name == "Default" and defaultProfile() or readProfiles()[name]
			assert(data, "Save this config before exporting it.")
			validateProfile(data)
			local base = "xwav_Attached_Export_" .. name
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
			assert(name:lower() ~= "default", "Default is blank; choose a different name to import.")
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
		function api.startAutosave()
			local path = "xwav_Attached_Autosave.json"
			local ok, exists = pcall(function()
				assert(type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function",
					"Autosave needs isfile, readfile and writefile.")
				local result = isfile(path)
				assert(type(result) == "boolean", "isfile returned an invalid result.")
				return result
			end)
			if not ok then
				report(false, "Autosave unavailable: " .. tostring(exists))
				warn("xwav autosave unavailable: " .. tostring(exists))
				return
			end
			if exists then
				local loaded, err = pcall(function()
					local data = game:GetService("HttpService"):JSONDecode(readfile(path))
					applyProfile(data)
				end)
				if not loaded then
					report(false, "Autosave restore error: " .. tostring(err))
					warn("xwav autosave restore failed; file was preserved: " .. tostring(err))
					return
				end
			end
			local function copy(value)
				if type(value) ~= "table" then return value end
				local result = {}
				for key, item in pairs(value) do result[key] = copy(item) end
				return result
			end
			local function equal(a, b)
				if type(a) ~= type(b) then return false end
				if type(a) ~= "table" then return a == b end
				for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
				for key in pairs(b) do if a[key] == nil then return false end end
				return true
			end
			local elapsed, previous, lastError = 0, nil, nil
			RunService.Heartbeat:Connect(function(deltaTime)
				elapsed = elapsed + deltaTime
				if elapsed < 2 then return end
				elapsed = 0
				local saved, result = pcall(function()
					local values = {}
					for _, entry in ipairs(entries) do
						local value = entry.get()
						assert(valid(entry, value), "Invalid current value: " .. entry.id)
						values[entry.id] = value
					end
					if not previous or not equal(values, previous) then
						local json = game:GetService("HttpService"):JSONEncode({version = 1, values = values})
						assert(writefile(path, json) ~= false, "writefile returned false.")
					end
					return copy(values)
				end)
				if saved then
					previous, lastError = result, nil
				elseif tostring(result) ~= lastError then
					lastError = tostring(result)
					report(false, "Autosave error: " .. lastError)
					warn("xwav autosave error: " .. lastError)
				end
			end)
		end
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
		config.register("slider/" .. parent.Name .. "/" .. name, function() return value end, function(newValue)
			if newValue == value then return true end
			changed(newValue)
			value = newValue
			refresh()
			return true
		end, config.number(minimum, maximum))
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

	do
		local section = makeSection(pageContents.Aimbot, "Camlock player selection", 248, 260, 560)
		makeToggle(section, 32, "Selected players only", false, function(value)
			camlockTargets.enabled = value
			if (value or camlockTargets.priority == "Selected") and lockedPlayer
				and not camlockTargets.names[lockedPlayer.Name:lower()] then
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
					if (camlockTargets.enabled or camlockTargets.priority == "Selected")
						and lockedPlayer == other and not camlockTargets.names[name] then
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
			if (camlockTargets.enabled or camlockTargets.priority == "Selected")
				and lockedPlayer and not camlockTargets.names[lockedPlayer.Name:lower()] then
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
		for name, key in pairs(keys) do
			values[name] = key == Enum.KeyCode.Unknown and "Unknown" or key.Name
		end
		return values
	end, function(values)
		for _, name in ipairs({"Speed", "Flight", "AutoJump", "InfiniteJump", "AntiVoid"}) do
			local value = values[name]
			keys[name] = (value == nil or value == "Unknown" or value == "None")
				and Enum.KeyCode.Unknown or Enum.KeyCode[value]
		end
		for name, value in pairs(values) do
			keys[name] = (value == "Unknown" or value == "None") and Enum.KeyCode.Unknown or Enum.KeyCode[value]
		end
		waitingForKey = nil
		aim.active = false
		refreshKeyButtons()
	end, function(values)
		if type(values) ~= "table" then return false end
		local seen = {}
		for name in pairs(keys) do
			local value = values[name]
			local optional = name == "Speed" or name == "Flight" or name == "AutoJump"
				or name == "InfiniteJump" or name == "AntiVoid"
			if value == nil and optional then value = "Unknown" end
			if type(value) ~= "string" or value == "Escape" then return false end
			local unbound = value == "Unknown" or value == "None"
			if unbound then
				if not optional then return false end
			else
				if seen[value] then return false end
				local ok, key = pcall(function() return Enum.KeyCode[value] end)
				if not ok or not key or key == Enum.KeyCode.Unknown then return false end
				seen[value] = true
			end
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

	do
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
	end

	makeToggle(keySection, 177, "FOV", true, function(value)
		fovLimitEnabled = value
		circle.Visible = value and showFovCircle
	end)
	makeToggle(keySection, 210, "Triggerbot", true, function(value)
		triggerbot.enabled = value
		scanGeneration = scanGeneration + 1
		if not value then
			leftHeld, mouseDown, lastTarget = false, false, nil
		end
	end)
	do
		local section = makeSection(pageContents.Aimbot, "Target priority", 248, 175, 780)
		local button = makeButton(section, 35)
		local choices = {"Closest", "Lowest health", "Selected"}
		local function refresh() button.Text = "Priority: " .. camlockTargets.priority end
		local function setPriority(value)
			if silent.enabled and silent.method == "Z ZHD" and value ~= "Closest" then
				notify("Target priority", "Z ZHD mode cannot enforce target priority.")
				return false
			end
			camlockTargets.priority = value
			lockedPlayer = nil
			refresh()
		end
		config.register("aim/priority", function() return camlockTargets.priority end,
			setPriority, config.choice(choices))
		button.MouseButton1Click:Connect(function()
			local index = table.find(choices, camlockTargets.priority)
			setPriority(choices[index % #choices + 1])
		end)
		refresh()
		makeToggle(section, 67, "Friend protection", false, function(value)
			if value and silent.enabled and silent.method == "Z ZHD" then
				notify("Friend protection", "Z ZHD mode cannot protect friends.")
				return false
			end
			camlockTargets.protectFriends = value
			if value then
				for _, other in ipairs(Players:GetPlayers()) do camlockTargets.refreshFriend(other) end
				lockedPlayer = nil
			end
		end)
		makeLabel(section, "Selected uses the Camlock player list. Friends stay visible in ESP.", 100, 65)
	end
	do
		local section = makeSection(pageContents.Aimbot, "Triggerbot timing", 0, 155, 900)
		makeSlider(section, 35, "Reaction seconds", 0, 2, 0, 0.05, function(value) triggerbot.reaction = value end)
		makeSlider(section, 85, "Cooldown seconds", 0, 2, 0, 0.05, function(value) triggerbot.cooldown = value end)
	end
	do
		local section = makeSection(pageContents.Visuals, "Performance", 0, 115, 720)
		makeToggle(section, 35, "Performance mode", false, function(value) camlockTargets.performance = value end)
		makeLabel(section, "ESP at 10 Hz; hides tracers and uses visible color.", 67, 45)
	end
	do
		local section = makeSection(pageContents.Aimbot, "Triggerbot distance", 0, 150, 780)
		makeToggle(section, 35, "Custom distance limit", false, function(value)
			triggerbot.distanceEnabled = value
		end)
		local status = makeLabel(section, "Maximum distance (1-1000 studs)", 67, 24)
		local input = Instance.new("TextBox")
		input.Name = "TriggerbotDistanceInput"
		input.Position = UDim2.fromOffset(8, compact(95))
		input.Size = UDim2.fromOffset(220, 20)
		input.BackgroundColor3 = theme.control
		input.BorderSizePixel = 0
		input.TextColor3 = theme.text
		input.ClearTextOnFocus = false
		input.Font = Enum.Font.Code
		input.TextSize = 12
		input.ZIndex = 14
		input.Parent = section
		decorate(input, 0, theme.border)
		makeLabel(section, "Off: normal weapon limits apply.", 125, 20)
		local function refresh()
			input.Text = tostring(triggerbot.maximum)
			status.Text = "Maximum distance (1-1000 studs)"
			status.TextColor3 = theme.muted
		end
		refresh()
		config.register("triggerbot/distance", function() return triggerbot.maximum end, function(value)
			triggerbot.maximum = value
			refresh()
		end, config.number(1, 1000))
		input.FocusLost:Connect(function()
			local value = tonumber(input.Text)
			if not value or value ~= value or value < 1 or value > 1000 then
				refresh()
				status.Text = "Enter a distance from 1 to 1000."
				status.TextColor3 = Color3.fromRGB(255, 115, 115)
				return
			end
			triggerbot.maximum = value
			refresh()
		end)
	end
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
	end

	do
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
			config.register("camlock/" .. name, function() return hitParts[index] end, function(value)
				index = table.find(hitParts, value)
				changed(value)
				refresh()
			end, config.choice(hitParts))
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
	do
		local function setSpeed(value)
			speedEnabled = value
			if not value and savedHumanoid then
				savedHumanoid.WalkSpeed = savedWalkSpeed
				savedHumanoid, savedWalkSpeed = nil, nil
			end
		end
		local speedToggle = makeToggle(visibilitySection, 35, "Speed", false, setSpeed)
		local autoToggle = makeToggle(visibilitySection, 67, "Auto jump", false, function(value) autoJump = value end)
		local antiToggle = makeToggle(visibilitySection, 99, "Anti void", false, function(value)
			antiVoid = value
			safeCFrame, safeCharacter = nil, nil
		end)
		local flightToggle = makeToggle(visibilitySection, 131, "Flight (WASD, Space, Ctrl)", false, function(value) flightEnabled = value end)
		local jumpToggle = makeToggle(visibilitySection, 297, "Infinite jump", false, function(value) movement.infiniteJump = value end)
		movement.actions.Speed = function() setSpeed(not speedEnabled); speedToggle(speedEnabled) end
		movement.actions.AutoJump = function() autoJump = not autoJump; autoToggle(autoJump) end
		movement.actions.AntiVoid = function()
			antiVoid = not antiVoid
			safeCFrame, safeCharacter = nil, nil
			antiToggle(antiVoid)
		end
		movement.actions.Flight = function() flightEnabled = not flightEnabled; flightToggle(flightEnabled) end
		movement.actions.InfiniteJump = function()
			movement.infiniteJump = not movement.infiniteJump
			jumpToggle(movement.infiniteJump)
		end
		local section = makeSection(pageContents.Player, "Movement keybinds", 0, 205, 365)
		for index, name in ipairs({"Speed", "Flight", "AutoJump", "InfiniteJump", "AntiVoid"}) do
			local button = makeButton(section, 35 + (index - 1) * 32)
			keyButtons[name] = button
			button.MouseButton1Click:Connect(function()
				waitingForKey = name
				keyHint.Text = "Click a key to rebind. Escape cancels."
				keyHint.TextColor3 = theme.muted
				refreshKeyButtons()
			end)
		end
		refreshKeyButtons()
	end
	function movement.applyJump(humanoid, root)
		local jumpVelocity = humanoid.UseJumpPower and humanoid.JumpPower
			or math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
		if jumpVelocity <= 0 then jumpVelocity = 50 end
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, jumpVelocity, velocity.Z)
		humanoid.Jump = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
	local function requestInfiniteJump()
		if not movement.infiniteJump or flightEnabled or menuOpen or UserInputService:GetFocusedTextBox() then return end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return end
		local now = os.clock()
		if movement.lastJump ~= 0 and now - movement.lastJump < 0.1 then return end
		movement.lastJump = now
		if humanoid.FloorMaterial ~= Enum.Material.Air then return end
		movement.applyJump(humanoid, root)
	end
	UserInputService.JumpRequest:Connect(requestInfiniteJump)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == Enum.KeyCode.Space then requestInfiniteJump() end
	end)
	do
		local section = makeSection(pageContents.Player, "Movement compatibility", 248, 110, 440)
		makeToggle(section, 35, "Velocity speed", false, function(value) movement.velocitySpeed = value end)
		makeLabel(section, "Try this if normal speed is overridden. Game checks may still block movement.", 67, 45)
	end
	makeSlider(visibilitySection, 165, "Speed amount", 0, 200, speedAmount, 1, function(value) speedAmount = value end)
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
			config.register("animations/" .. name, function() return selected[name] end, function(value)
				local previous = selected[name]
				selected[name] = value
				if animationEnabled then
					local ok, message = applyAnimations(player.Character)
					if not ok then
						selected[name] = previous
						notify("Animations", message)
						return false
					end
				end
				refresh()
			end, function(value) return type(value) == "boolean" end)
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
	local function nameList(name, label, labelY, inputY, changed)
		makeLabel(espFilters, label, labelY)
		local input = filterInput(name, inputY, "Usernames, separated by commas")
		local previous = ""
		local function parse(value)
			if type(value) ~= "string" then return nil end
			local names = {}
			for entry in (value .. ","):gmatch("(.-),") do
				local username = entry:match("^%s*(.-)%s*$")
				if username ~= "" then
					if #username > 20 or not username:match("^[%w_]+$") then
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
				espFilterStatus.Text = "Use comma-separated usernames."
				return
			end
			previous = input.Text
			changed(names)
			espFilterStatus.Text = ""
		end)
	end
	nameList("ESPTargetsInput", "Target usernames", 158, 183, function(names) espTargets = names end)
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
	local crosshairText = Instance.new("TextLabel")
	crosshairText.Name = "Text"
	crosshairText.AnchorPoint = Vector2.new(0.5, 0)
	crosshairText.Position = UDim2.new(0.5, 0, 0.5, 12)
	crosshairText.Size = UDim2.fromOffset(220, 20)
	crosshairText.BackgroundTransparency = 1
	crosshairText.Text = ".gg/xwav"
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
	config.register("crosshair/text", function() return crosshairText.Text end, function(value)
		crosshairText.Text, crosshairInput.Text = value, value
	end, function(value) return type(value) == "string" end)
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
		config.register("crosshair/color", function() return crosshairColorIndex end, function(value)
			crosshairColorIndex = value
			refreshCrosshairColor()
		end, config.choice({1, 2, 3, 4, 5}))
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
	colorCorrection.Name = "xwavColorCorrection"
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
		config.register("lighting/color", function() return lightingColorIndex end, function(value)
			lightingColorIndex = value
			refreshLightingColor()
		end, config.choice({1, 2, 3, 4, 5}))
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
		config.register("fog/color", function() return fogColorIndex end, function(value)
			fogColorIndex = value
			refreshFogColor()
			if fogEnabled then Lighting.FogColor = value == 0 and savedFogColor or palette[value].Value end
		end, config.choice({0, 1, 2, 3, 4, 5}))
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
	targetHighlight.Name = "xwavTargetHighlight"
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
		silent.target = silent.enabled and silent.method ~= "Z ZHD" and not menuOpen and getClosestPlayer(silent) or nil

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
		espElapsed = espElapsed + (deltaTime or 0)
		if espElapsed < (camlockTargets.performance and 1 / 10 or 1 / 30) then return end
		espElapsed = 0

		for targetPlayer, overlay in pairs(overlays) do
			local box = overlay.box
			overlay.tracer.Visible = false
			local character = targetPlayer.Character
			local targetPart = getTargetPart(targetPlayer, nil, nil, true)
			local name = targetPlayer.Name:lower()
			local localRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local origin = localRoot and localRoot.Position or (camera and camera.CFrame.Position)
			local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
			local targetPosition = targetRoot and targetRoot.Position or (targetPart and targetPart.Position)
			local distance = origin and targetPosition and (targetPosition - origin).Magnitude
			local allowed = not espWhitelist[name] and (not espNamedOnly or espTargets[name])
				and (not espDistanceLimit or (distance and distance <= espMaxDistance))

			if camera and character and character.Parent and targetPart and allowed then
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

					local colorName = (camlockTargets.performance or isVisible(targetPart, camera)) and "Visible" or "Hidden"
					local color = rainbowESP and Color3.fromHSV((os.clock() % 5) / 5, 1, 1)
						or palette[colorIndexes[colorName]].Value
					overlay.outline.Color = color
					overlay.outline.Enabled = showBoxes
					overlay.username.Visible = showNames
					overlay.distance.Visible = showDistance
					if showTracers and not camlockTargets.performance then
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
		if autoJump and not flightEnabled and humanoid and humanoid.Health > 0
			and root and root:IsA("BasePart") and humanoid.FloorMaterial ~= Enum.Material.Air
			and root.AssemblyLinearVelocity.Y <= 1 then
			local now = os.clock()
			if movement.lastAutoJump == 0 or now - movement.lastAutoJump >= 0.25 then
				movement.lastAutoJump = now
				movement.applyJump(humanoid, root)
			end
		end
		if disableSeats and humanoid and humanoid.Sit then humanoid.Sit = false end
		if not root or not humanoid or humanoid.Health <= 0 then
			safeCFrame, safeCharacter = nil, nil
			return
		end
		if speedEnabled and movement.velocitySpeed and not flightEnabled
			and not (strafeEnabled and lockedPlayer and not menuOpen) then
			local direction = humanoid.MoveDirection
			local horizontal = Vector3.new(direction.X, 0, direction.Z)
			if horizontal.Magnitude > 0 then
				local velocity = root.AssemblyLinearVelocity
				horizontal = horizontal.Unit * (speedAmount * math.min(horizontal.Magnitude, 1))
				root.AssemblyLinearVelocity = Vector3.new(horizontal.X, velocity.Y, horizontal.Z)
			end
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
	config.startAutosave()
end

StarterGui:SetCore("SendNotification", {
	Title = "Notification",
	Text = "made by /xwav",
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
	if camlockTargets.protected(targetPlayer) then return true end
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
	if not triggerbot.enabled or not compatibilityScanEnabled or generation ~= scanGeneration then return end
	local allObjects = {}
	for _, service in ipairs(game:GetChildren()) do
		table.insert(allObjects, service)
	end

	local index = 1
	local batchSize = 20
	local found = false

	local function scanBatch()
		if not triggerbot.enabled or not compatibilityScanEnabled or generation ~= scanGeneration then return end
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
	if not AUTO_SHOOT_ENABLED or not triggerbot.enabled or menuOpen or isCrouching then return false end

	local tool = getEquippedTool()
	if tool and isGun(tool) and canShoot and os.clock() >= (triggerbot.readyAt or 0) then
		canShoot = false
		local activated, activationError = pcall(function() tool:Activate() end)
		if not activated then
			triggerbot.readyAt = os.clock() + 0.25
			canShoot = true
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

		triggerbot.readyAt = os.clock() + triggerbot.cooldown
		canShoot = true
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
			if not isFriendly(targetPlayer) and not isRagdolled(model) then return targetPlayer end
			return nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function handleMouseMovement()
	if not triggerbot.enabled or menuOpen or not leftHeld or isCrouching then return end

	local tool = getEquippedTool()
	if not tool or not isGun(tool) then
		leftHeld = false
		lastTarget = nil
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then lastTarget = nil; return end
	local origin = camera.CFrame.Position
	local offset = mouse.Hit.Position - origin
	if offset.Magnitude == 0 then lastTarget = nil; return end
	local direction = offset.Unit * 1000
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { player.Character }

	local result = workspace:Raycast(origin, direction, params)
	local targetPlayer = result and isValidTarget(result.Instance)
	if targetPlayer then
		local distance = (result.Position - origin).Magnitude

		local toolName = tool.Name:lower()
		if triggerbot.distanceEnabled and distance > triggerbot.maximum then
			lastTarget = nil
			return
		elseif not triggerbot.distanceEnabled and toolName:find("revolver", 1, true) and distance > 200 then
			lastTarget = nil
			return
		elseif not triggerbot.distanceEnabled and (toolName:find("double-barrel", 1, true)
			or toolName:find("shotgun", 1, true)) and distance > 75 then
			lastTarget = nil
			return
		end

		if targetPlayer ~= lastTarget or tool ~= triggerbot.lastTool then
			lastTarget = targetPlayer
			triggerbot.lastTool = tool
			triggerbot.acquiredAt = os.clock()
		end
		if os.clock() - triggerbot.acquiredAt >= triggerbot.reaction then
			attemptLocalFire()
		end
	else
		lastTarget = nil
	end
end

local function blockLeftClick(actionName, inputState)
	if not triggerbot.enabled or menuOpen then
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
		local safeTarget = lastTarget
		mouseDown = false
		leftHeld = false
		lastTarget = nil

		local heldTime = tick() - holdStartTime
		if gunEquipped and heldTime < holdThreshold and not isCrouching and not autoFired
			and (not camlockTargets.protectFriends or (safeTarget and not camlockTargets.protected(safeTarget))) then
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
		lastTarget = nil
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