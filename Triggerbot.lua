game:GetService("StarterGui"):SetCore("SendNotification", {
	Title = "Notification",
	Text = "made by /azuremodded",
	Duration = 5
})

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local AUTO_SHOOT_ENABLED = true
local IGNORE_TEAMMATES = false

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

Replace the previous ESP block with this version. It draws the username directly on the screen above the gray box:

```lua
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("AzureESP")
if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "AzureESP"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local enabled = false
local entries = {}

local function removeESP(target)
	local entry = entries[target]
	if entry then
		entry.box:Destroy()
		entry.label:Destroy()
		entries[target] = nil
	end
end

local function createESP(target)
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Visible = false
	box.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(128, 128, 128)
	stroke.Thickness = 2
	stroke.Parent = box

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(200, 54)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.Visible = false
	label.Parent = gui

	entries[target] = {box = box, label = label}
	return entries[target]
end

ContextActionService:BindActionAtPriority(
	"AzureESP_Toggle",
	function(_, inputState)
		if inputState == Enum.UserInputState.Begin
			and not UserInputService:GetFocusedTextBox() then
			enabled = not enabled
			if not enabled then
				for target in pairs(entries) do
					removeESP(target)
				end
			end
		end
		return Enum.ContextActionResult.Pass
	end,
	false,
	Enum.ContextActionPriority.High.Value + 1,
	Enum.KeyCode.T
)

RunService:UnbindFromRenderStep("AzureESP_Update")
RunService:BindToRenderStep("AzureESP_Update", Enum.RenderPriority.Last.Value, function()
	if not enabled then return end

	for target in pairs(entries) do
		if target.Parent ~= Players then
			removeESP(target)
		end
	end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local localRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

	for _, target in ipairs(Players:GetPlayers()) do
		if target ~= player then
			local character = target.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if not root or not humanoid or humanoid.Health <= 0 then
				removeESP(target)
			else
				local entry = entries[target] or createESP(target)
				local center, onScreen = camera:WorldToViewportPoint(root.Position)
				local top = camera:WorldToViewportPoint(root.Position + camera.CFrame.UpVector * 3)
				local bottom = camera:WorldToViewportPoint(root.Position - camera.CFrame.UpVector * 3)
				local left = camera:WorldToViewportPoint(root.Position - camera.CFrame.RightVector * 2)
				local right = camera:WorldToViewportPoint(root.Position + camera.CFrame.RightVector * 2)

				local visible = onScreen and center.Z > 0
				entry.box.Visible = visible
				entry.label.Visible = visible

				if visible then
					local width = math.abs(right.X - left.X)
					local height = math.abs(bottom.Y - top.Y)
					local x = center.X - width / 2
					local y = center.Y - height / 2

					entry.box.Position = UDim2.fromOffset(x, y)
					entry.box.Size = UDim2.fromOffset(width, height)
					entry.label.Position = UDim2.fromOffset(center.X - 100, math.max(0, y - 54))

					local distance = localRoot
						and string.format("%d studs", math.floor((localRoot.Position - root.Position).Magnitude))
						or "Distance: --"

					entry.label.Text = string.format(
						"%s\nHealth: %d / %d\n%s",
						target.Name,
						math.ceil(humanoid.Health),
						math.ceil(humanoid.MaxHealth),
						distance
					)
				end
			end
		end
	end
end)
