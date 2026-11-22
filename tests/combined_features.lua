local function event()
	local callbacks = {}
	return {
		Connect = function(_, callback) table.insert(callbacks, callback) end,
		fire = function(_, ...) for _, callback in ipairs(callbacks) do callback(...) end end,
	}
end

local vector = {}
vector.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2) end
	if key == "Unit" then return setmetatable({X = self.X / self.Magnitude, Y = self.Y / self.Magnitude, Z = self.Z / self.Magnitude}, vector) end
end
vector.__add = function(a, b) return setmetatable({X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z}, vector) end
vector.__sub = function(a, b) return setmetatable({X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z}, vector) end
vector.__mul = function(a, b) return setmetatable({X = a.X * b, Y = a.Y * b, Z = a.Z * b}, vector) end
local function vec(x, y, z) return setmetatable({X = x, Y = y, Z = z or 0}, vector) end
Vector2, Vector3 = {new = vec}, {new = vec}
CFrame = {lookAt = function(origin, target) return {Position = origin, target = target} end}
UDim = {new = function(...) return {...} end}
UDim2 = {new = function(...) return {...} end, fromOffset = function(...) return {...} end, fromScale = function(...) return {...} end}
Color3 = {fromRGB = function(...) return {...} end, fromHSV = function(...) return {...} end}
math.atan2 = math.atan2 or math.atan
math.clamp = math.clamp or function(value, minimum, maximum)
	return math.max(minimum, math.min(value, maximum))
end
table.find = table.find or function(values, value)
	for index, item in ipairs(values) do if item == value then return index end end
end
local codes = {}
for _, key in ipairs({"Q", "T", "E", "F", "G", "RightShift", "Escape", "Unknown", "LeftControl", "RightControl", "W", "S", "A", "D", "Space"}) do
	codes[key] = {Name = key}
end
Enum = {
	KeyCode = codes, UserInputType = {Keyboard = "Keyboard", MouseButton1 = "MouseButton1", MouseMovement = "MouseMovement"},
	Font = {Code = 1, SourceSans = 2, SourceSansBold = 3, Gotham = 4, GothamBold = 5}, TextXAlignment = {Left = 1},
	RenderPriority = {Camera = {Value = 200}}, RaycastFilterType = {Exclude = 1, Blacklist = 1},
	ScrollingDirection = {Y = 1}, HighlightDepthMode = {AlwaysOnTop = 1}, Material = {Air = "Air"},
	ContextActionResult = {Pass = "Pass", Sink = "Sink"},
	UserInputState = {Begin = "Begin", End = "End"},
	HumanoidStateType = {Physics = "Physics", Dead = "Dead", FallingDown = "FallingDown"},
	ApplyStrokeMode = {Border = 1},
}
RaycastParams = {new = function() return {} end}
local objects = {}
Instance = {new = function(class)
	local object = {class = class, MouseButton1Click = event(), InputBegan = event(), FocusLost = event(), Destroy = function(self) self.destroyed = true end}
	table.insert(objects, object)
	return object
end}
local function find(class, name)
	for _, object in ipairs(objects) do
		if not object.destroyed and object.class == class and (object.Name == name or object.Text == name) then return object end
	end
	error("Missing " .. class .. " " .. name)
end
local function click(name)
	local state, toggleName = name:match("^%[(.)%] (.+)$")
	local button
	if state then
		button = find("TextButton", toggleName .. "Toggle")
		local indicator
		for _, object in ipairs(objects) do
			if object.Parent == button and object.Name == "ToggleIndicator" then indicator = object end
		end
		assert(indicator and (indicator.BackgroundColor3[2] > 200) == (state == "x"), "Unexpected toggle state: " .. name)
	else
		button = find("TextButton", name)
	end
	button.MouseButton1Click:fire()
end
local input = {
	InputBegan = event(), InputEnded = event(), InputChanged = event(),
	GetFocusedTextBox = function() end, GetMouseLocation = function() return vec(0, 0) end,
	IsKeyDown = function(_, key) return key == codes.W end,
}
local humanoid = {Health = 100, WalkSpeed = 16, FloorMaterial = "Ground"}
local root = {Position = vec(5, 10, 5), CFrame = vec(5, 10, 5), IsA = function(_, name) return name == "BasePart" end}
local equipped
local character = {
	ChildAdded = event(), ChildRemoved = event(),
	GetChildren = function() return equipped and {equipped} or {} end,
	FindFirstChildOfClass = function(_, class)
		if class == "Humanoid" then return humanoid end
		if class == "Tool" then return equipped end
	end,
	FindFirstChild = function(_, name) if name == "HumanoidRootPart" then return root end end,
}
local kicks = 0
local mouseObject = {}
local attributes = {}
local player = {
	Team = "Blue", Character = character, CharacterAdded = event(),
	GetMouse = function() return mouseObject end, WaitForChild = function() return {} end,
	GetAttribute = function(_, name) return attributes[name] end,
	SetAttribute = function(_, name, value) attributes[name] = value end,
	Kick = function() kicks = kicks + 1 end,
}
local players = {LocalPlayer = player, PlayerAdded = event(), PlayerRemoving = event()}
local head = {Position = vec(20, 0, 10), AssemblyLinearVelocity = vec(10, 0, 0), IsA = function(_, name) return name == "BasePart" end}
head.CFrame = vec(20, 0, 10)
local targetHumanoid = {Health = 100}
local targetCharacter = {
	Parent = true,
	FindFirstChildOfClass = function(_, name) if name == "Humanoid" then return targetHumanoid end end,
	FindFirstChild = function(_, name) if name == "Head" or name == "HumanoidRootPart" then return head end end,
	GetBoundingBox = function()
		return {PointToWorldSpace = function(_, p) return vec(20 + p.X, 100 + p.Y, 10 + p.Z) end}, vec(2, 4, 2)
	end,
}
head.Parent = targetCharacter
local target = {Name = "Target", Team = "Red", Parent = players, Character = targetCharacter}
function players:GetPlayers() return {player, target} end
local run = {RenderStepped = event(), Heartbeat = event()}
function run:BindToRenderStep(_, _, callback) self.render = callback end
local messages, titles = {}, {}
local blockClick
local lighting = {GlobalShadows = true, FogStart = 20, FogEnd = 1000, FogColor = {1, 1, 1}}
local services = {
	Players = players, RunService = run, UserInputService = input, Lighting = lighting,
	StarterGui = {SetCore = function(_, _, message)
		table.insert(messages, message.Text)
		table.insert(titles, message.Title)
	end},
	ContextActionService = {BindAction = function(_, _, callback) blockClick = callback end},
}
game = {GetService = function(_, name) return services[name] end, GetChildren = function() return {} end}
local scheduled = {}
task = {
	spawn = function(callback) table.insert(scheduled, callback) end,
	delay = function(_, callback) callback() end,
}
local camera = {
	CFrame = {Position = vec(0, 0, 0), LookVector = vec(0, 0, 1), RightVector = vec(1, 0, 0)},
	ViewportSize = vec(800, 600), FieldOfView = 70,
	WorldToScreenPoint = function(_, p) return p, true end,
	WorldToViewportPoint = function(_, p) return p, true end,
}
local blocked = true
workspace = {
	CurrentCamera = camera, FallenPartsDestroyHeight = -500,
	Raycast = function() if blocked then return {Instance = {IsDescendantOf = function() return false end}} end end,
}
local function press(key) input.InputBegan:fire({UserInputType = "Keyboard", KeyCode = codes[key]}, false) end
local function runScheduled() while #scheduled > 0 do table.remove(scheduled, 1)() end end

local paidScript = TEST_SCRIPT == "Triggerbot_2.lua"
dofile(TEST_SCRIPT or "Triggerbot.lua")
assert(#messages == 1 and titles[1] == "Notification")
local menuFrame = find("Frame", "Settings")
assert(find("TextLabel", "DragHandle").Text == (paidScript
	and "Azure Paid | @socialdw on discord | discord.gg/azuremodded"
	or "Azure | discord.gg/azuremodded"))
local aimingPage, visualsPage = find("Frame", "AimbotPage"), find("Frame", "VisualsPage")
find("TextButton", "VisualsTab").MouseButton1Click:fire()
assert(visualsPage.Visible and not aimingPage.Visible)
find("TextButton", "AimbotTab").MouseButton1Click:fire()
assert(aimingPage.Visible and not visualsPage.Visible)
local fovToggle = find("TextButton", "FOVToggle")
assert(fovToggle.Position[2] + fovToggle.Size[2] < menuFrame.Size[2] - 61)
local inputBox = find("TextBox", "PredictionInput")
assert(inputBox.Position[2] + inputBox.Size[2] <= inputBox.Parent.Size[2])
assert(inputBox.Parent.Size[2] <= inputBox.Parent.Parent.CanvasSize[2])
click("[ ] Silent aim")
assert(find("TextLabel", "Missing: hookmetamethod"))
local hooks, caller, method = {}, false, "Raycast"
hookmetamethod = function(_, name, callback)
	hooks[name] = callback
	if name == "__index" then return function() return "original" end end
	return function(_, origin, direction) return origin, direction end
end
click("[ ] Silent aim")
assert(find("TextLabel", "Missing: newcclosure"))
newcclosure = function(callback) return callback end
click("[ ] Silent aim")
assert(find("TextLabel", "Missing: checkcaller"))
checkcaller = function() return caller end
typeof = function(value) return getmetatable(value) == vector and "Vector3" or type(value) end
click("[ ] Silent aim")
assert(hooks.__index)
click("Method: Mouse")
assert(find("TextLabel", "Missing: getnamecallmethod"))
assert(find("TextButton", "Method: Mouse"))
getnamecallmethod = function() return method end
equipped = {}
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == "original")
click("[x] Silent wall check")
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == head)
click("[ ] Silent wall check")
blocked = false
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == head)
target.Team = "Blue"
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == "original")
click("[x] Silent team check")
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == head)
click("[ ] Silent team check")
target.Team = "Red"
assert(hooks.__index(mouseObject, "Hit").X == 20)
caller = true
assert(hooks.__index(mouseObject, "Target") == "original")
caller = false
equipped = nil
assert(hooks.__index(mouseObject, "Target") == "original")
equipped = {}
head.Position = vec(160, 0, 10)
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == "original")
find("TextButton", "SilentFOVIncrease").MouseButton1Click:fire()
run.RenderStepped:fire()
assert(hooks.__index(mouseObject, "Target") == head)
click("Method: Mouse")
assert(hooks.__namecall)
assert(find("TextLabel", "SilentAimStatus").Text == "")
local origin, direction = hooks.__namecall(workspace, vec(0, 0, 0), vec(0, 0, 100))
assert(origin.Magnitude == 0 and math.abs(direction.Magnitude - 100) < 0.000001 and direction.X > 99)
method = "Other"
_, direction = hooks.__namecall(workspace, vec(0, 0, 0), vec(0, 0, 100))
assert(direction.X == 0)
method = "Raycast"
click("[x] Silent aim")
_, direction = hooks.__namecall(workspace, vec(0, 0, 0), vec(0, 0, 100))
assert(direction.X == 0)
click("Method: Raycast")
click("[ ] Silent aim")
assert(find("TextLabel", "Z ZHD mode is only for Z ZHD."))
game.PlaceId = 138014591158268
click("[ ] Silent aim")
assert(find("TextLabel", "Z ZHD: turn wall and team checks off."))
click("[x] Silent wall check")
click("[x] Silent team check")
attributes.AimLock, attributes.AimLockFov, attributes.TargetLimb = false, 40, "Torso"
equipped = {Name = "[Revolver]"}
click("[ ] Silent aim")
assert(attributes.AimLock == true and attributes.AimLockFov == 35 and attributes.TargetLimb == "Head")
equipped = {Name = "Other"}
run.RenderStepped:fire()
assert(attributes.AimLock == false)
equipped = {Name = "[Double-Barrel SG]"}
run.RenderStepped:fire()
assert(attributes.AimLock == true)
press("RightShift")
assert(attributes.AimLock == false)
press("RightShift")
assert(attributes.AimLock == true)
find("TextButton", "SilentFOVDecrease").MouseButton1Click:fire()
assert(attributes.AimLockFov == 30)
local silentSection = find("TextLabel", "SilentAimStatus").Parent
for _, object in ipairs(objects) do
	if object.class == "TextButton" and object.Parent == silentSection and object.Text == "Target: Head" then
		object.MouseButton1Click:fire()
		break
	end
end
assert(attributes.TargetLimb == "HumanoidRootPart")
click("[ ] Silent team check")
assert(find("TextLabel", "Z ZHD does not support team checks."))
click("[x] Silent FOV limit")
assert(find("TextLabel", "Z ZHD requires an FOV limit."))
attributes.TargetLimb = "External"
click("[x] Silent aim")
assert(attributes.AimLock == false and attributes.AimLockFov == 40 and attributes.TargetLimb == "External")
click("Method: Z ZHD")
click("[ ] Silent wall check")
click("[ ] Silent team check")
find("TextButton", "SilentFOVIncrease").MouseButton1Click:fire()
equipped = nil
head.Position = vec(20, 0, 10)

camera.CFrame.Lerp = function(self, target) self.target = target.target; return self end
click("[ ] Aimbot")
click("[ ] Aimbot FOV circle")
click("[ ] Silent FOV circle")
run.RenderStepped:fire()
assert(find("Frame", "AimbotFOV").Size[1] == 300)
assert(find("Frame", "SilentFOV").Size[1] == 350)
head.Position = vec(160, 0, 10)
input.InputBegan:fire({UserInputType = "Keyboard", KeyCode = codes.E}, true)
run.render()
assert(camera.CFrame.target == nil)
press("E")
run.render()
assert(camera.CFrame.target == nil)
find("TextButton", "AimbotFOVIncrease").MouseButton1Click:fire()
run.render()
assert(camera.CFrame.target == head.Position)
head.Position = vec(20, 0, 10)
run.render()
assert(camera.CFrame.target == head.Position)
camera.CFrame.target = nil
input.InputEnded:fire({UserInputType = "Keyboard", KeyCode = codes.E}, false)
run.render()
assert(camera.CFrame.target == nil)
click("Mode: Hold")
press("E")
run.render()
assert(camera.CFrame.target == head.Position)
camera.CFrame.target = nil
press("E")
run.render()
assert(camera.CFrame.target == nil)
click("[x] Aimbot")
blocked = true
press("RightShift")
press("RightShift")
press("T")
press("T")
assert(#messages == 1)
click("Camlock key: Q")
press("T")
assert(find("TextLabel", "That key is already in use.") and #messages == 1)
press("Escape")
assert(find("TextLabel", "Click a key to rebind. Escape cancels."))
if not paidScript then
	local selectedSection = find("TextLabel", "Camlock player selection").Parent
	assert(selectedSection.Position[2] + selectedSection.Size[2] <= selectedSection.Parent.CanvasSize[2])
	local rivalHead = {Position = vec(5, 0, 10), AssemblyLinearVelocity = vec(0, 0, 0),
		IsA = function(_, name) return name == "BasePart" end}
	local rivalCharacter = {
		FindFirstChildOfClass = function(_, name) if name == "Humanoid" then return targetHumanoid end end,
		FindFirstChild = function(_, name) if name == "Head" then return rivalHead end end,
	}
	rivalHead.Parent = rivalCharacter
	local rival = {Name = "Rival", Team = "Red", Parent = players, Character = rivalCharacter}
	local newcomer = {Name = "Newcomer", Team = "Red", Parent = players, Character = rivalCharacter}
	local current = {player, target, rival}
	function players:GetPlayers() return current end
	players.PlayerAdded:fire(rival)
	blocked = false
	click("[ ] Selected players only")
	press("Q")
	assert(messages[#messages] == "No eligible player in FOV", "Empty player selection must not lock randomly")
	click("[ ] Aimbot")
	camera.CFrame.target = nil
	press("E")
	run.render()
	assert(camera.CFrame.target == rivalHead.Position, "Camlock selection must not filter the camera aimbot")
	press("E")
	click("[x] Aimbot")
	find("TextButton", "CamlockPlayer:Target").MouseButton1Click:fire()
	press("Q")
	assert(messages[#messages] == "Locked onto Target", "Selected target must take priority over a closer unselected player")
	find("TextButton", "CamlockPlayer:Target").MouseButton1Click:fire()
	press("Q")
	assert(messages[#messages] == "No eligible player in FOV", "Deselecting the locked player must unlock")
	find("TextButton", "CamlockPlayer:Target").MouseButton1Click:fire()
	find("TextButton", "CamlockPlayer:Rival").MouseButton1Click:fire()
	press("Q")
	assert(messages[#messages] == "Locked onto Rival", "Closest selected player should be chosen")
	press("Q")
	rival.Team = "Blue"
	press("Q")
	assert(messages[#messages] == "Locked onto Target", "Team check must still apply")
	press("Q")
	rival.Team = "Red"
	table.insert(current, newcomer)
	players.PlayerAdded:fire(newcomer)
	assert(find("TextButton", "CamlockPlayer:Newcomer"))
	players.PlayerRemoving:fire(newcomer)
	table.remove(current, #current)
	assert(not pcall(find, "TextButton", "CamlockPlayer:Newcomer"))
	click("[x] Selected players only")
	press("Q")
	assert(messages[#messages] == "Locked onto Rival", "Disabling selection should restore normal targeting")
	press("Q")
	function players:GetPlayers() return {player, target} end
	players.PlayerRemoving:fire(rival)
	blocked = true
end
press("Q")
assert(messages[#messages] == "No eligible player in FOV" and titles[#titles] == "Camlock")
click("[x] Wall check")
head.Position = vec(160, 0, 10)
press("Q")
assert(messages[#messages] == "No eligible player in FOV")
local circle = find("Frame", "FOVCircle")
click("[x] FOV")
assert(not circle.Visible)
press("Q")
assert(messages[#messages] == "Locked onto Target")
press("Q")
click("[x] FOV circle")
click("[ ] FOV")
assert(not circle.Visible)
click("[ ] FOV circle")
assert(circle.Visible)
head.Position = vec(20, 0, 10)
press("Q")
assert(messages[#messages] == "Locked onto Target")
click("[ ] Prediction")
local section = find("TextLabel", "Camera Aimbot").Parent
local predictionIncrease = find("TextButton", "PredictionIncrease")
assert(predictionIncrease.Parent == section)
predictionIncrease.MouseButton1Click:fire()
run.render()
assert(camera.CFrame.target.X == 20.5)
local prediction = find("TextBox", "PredictionInput")
prediction.Text = "0.1234"
prediction.FocusLost:fire()
run.render()
assert(math.abs(camera.CFrame.target.X - 21.234) < 0.000001)
for _, invalid in ipairs({"abc", "-0.1", "1.1", "1e309", ""}) do
	local count = #messages
	prediction.Text = invalid
	prediction.FocusLost:fire()
	assert(prediction.Text == "0.1234" and #messages == count)
	assert(find("TextLabel", "Enter a number from 0 to 1 sec."))
end
prediction.Text = "1"
prediction.FocusLost:fire()
assert(find("TextLabel", "Prediction: 1 sec"))
run.render()
assert(camera.CFrame.target.X == 30)
click("[x] Prediction")
run.render()
assert(camera.CFrame.target.X == 20)
click("[ ] Prediction")
prediction.Text = "0"
prediction.FocusLost:fire()
run.render()
assert(camera.CFrame.target.X == 20)
click("[ ] Target dot")
click("[ ] Target tracer")
click("[ ] Target highlight")
click("[ ] Target stats")
run.RenderStepped:fire()
assert(find("Frame", "TargetDot").Visible and find("Frame", "TargetTracer").Visible)
assert(find("Highlight", "AzureTargetHighlight").Adornee == targetCharacter)
local stats = find("TextLabel", "TargetStats")
assert(stats.Text:find("Target"))
stats.AbsolutePosition, stats.AbsoluteSize = vec(20, 50), vec(220, 34)
stats.InputBegan:fire({UserInputType = "MouseButton1", Position = vec(30, 60)})
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(100, 100)}, false)
assert(stats.Position[1] == 20 and stats.Position[2] == 50)
press("RightShift")
assert(stats.Active)
stats.InputBegan:fire({UserInputType = "MouseButton1", Position = vec(30, 60)})
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(100, 100)}, false)
assert(stats.Position[1] == 90 and stats.Position[2] == 90)
press("RightShift")
assert(not stats.Active)
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(150, 150)}, false)
assert(stats.Position[1] == 90 and stats.Position[2] == 90)
click("[x] Camlock")
run.RenderStepped:fire()
assert(not find("Frame", "TargetDot").Visible and not find("Highlight", "AzureTargetHighlight").Enabled)
click("[ ] Camlock")
target.Team = "Blue"
press("Q")
assert(messages[#messages] == "No eligible player in FOV")
click("[x] Team check")
press("Q")
assert(messages[#messages] == "Locked onto Target")
press("Q")
click("[ ] Team check")
target.Team = "Red"

press("RightShift")
assert(blockClick("BlockMouseClick", "Begin") == "Pass")
local menu, handle = find("Frame", "Settings"), find("TextLabel", "DragHandle")
menu.AbsolutePosition, menu.AbsoluteSize = vec(20, 100), vec(500, 400)
handle.InputBegan:fire({UserInputType = "MouseButton1", Position = vec(40, 120)})
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(90, 150)}, false)
assert(menu.Position[1] == 70 and menu.Position[2] == 130)
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(2000, -100)}, false)
assert(menu.Position[1] == 300 and menu.Position[2] == 0)
input.InputEnded:fire({UserInputType = "MouseButton1"}, false)
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(100, 100)}, false)
assert(menu.Position[1] == 300 and menu.Position[2] == 0)
handle.InputBegan:fire({UserInputType = "MouseButton1", Position = vec(40, 120)})
press("RightShift")
press("RightShift")
input.InputChanged:fire({UserInputType = "MouseMovement", Position = vec(100, 100)}, false)
assert(menu.Position[1] == 300 and menu.Position[2] == 0)
click("[x] Compatibility scan")
click("[ ] Compatibility scan")
runScheduled()
assert(kicks == 0)
click("[x] Triggerbot")
runScheduled()
assert(kicks == 0)
click("[ ] Triggerbot")
player.CharacterAdded:fire(character)
runScheduled()
assert(kicks == 1)

click("[ ] Speed")
click("[ ] Auto jump")
click("[ ] Anti void")
run.Heartbeat:fire(0.1)
assert(humanoid.WalkSpeed == 24 and humanoid.Jump)
root.Position, root.CFrame, humanoid.FloorMaterial = vec(0, -495, 0), vec(0, -495, 0), "Air"
run.Heartbeat:fire(0.1)
assert(root.CFrame.X == 5 and root.CFrame.Y == 10)
assert(root.AssemblyLinearVelocity.Magnitude == 0)
local replacementRoot = {Position = vec(0, -495, 0), CFrame = vec(0, -495, 0), IsA = function(_, name) return name == "BasePart" end}
local replacementCharacter = {
	FindFirstChildOfClass = character.FindFirstChildOfClass,
	FindFirstChild = function(_, name) if name == "HumanoidRootPart" then return replacementRoot end end,
}
player.Character = replacementCharacter
run.Heartbeat:fire(0.1)
assert(replacementRoot.CFrame.Y == -495)
player.Character = character
click("[x] Speed")
assert(humanoid.WalkSpeed == 16)
click("Speed key: G")
press("T")
assert(find("TextLabel", "That key is already in use."))
press("F")
assert(find("TextButton", "Speed key: F"))
if paidScript then
	local slider = find("TextButton", "Speed amountSlider")
	slider.AbsolutePosition, slider.AbsoluteSize = vec(0, 0), vec(220, 12)
	slider.InputBegan:fire({UserInputType = "MouseButton1", Position = vec(220, 0)})
	input.InputEnded:fire({UserInputType = "MouseButton1"})
else
	local speedInput = find("TextBox", "SpeedAmountInput")
	speedInput.Text = "200"
	speedInput.FocusLost:fire()
	speedInput.Text = "201"
	speedInput.FocusLost:fire()
	assert(speedInput.Text == "200" and find("TextLabel", "Enter speed from 0 to 200"))
end
press("F")
run.Heartbeat:fire(0.1)
assert(humanoid.WalkSpeed == 16, "Speed key must not activate with the menu open")
press("RightShift")
input.InputBegan:fire({UserInputType = "Keyboard", KeyCode = codes.F}, true)
run.Heartbeat:fire(0.1)
assert(humanoid.WalkSpeed == 16, "Processed key must not activate speed")
press("F")
run.Heartbeat:fire(0.1)
assert(humanoid.WalkSpeed == 200)
press("F")
assert(humanoid.WalkSpeed == 16)
press("RightShift")
click("[x] Anti void")
camera.CFrame = {Position = vec(0, 0, 0), LookVector = vec(0, 0, 1), RightVector = vec(1, 0, 0)}
click("[ ] Flight (WASD, Space, Ctrl)")
run.Heartbeat:fire(0.1)
assert(root.CFrame.Z == 15)
click("[x] Flight (WASD, Space, Ctrl)")

press("T")
click("[x] FOV circle")
assert(not circle.Visible)
click("[ ] FOV circle")
assert(circle.Visible)
click("[x] Boxes")
click("[x] Names")
click("[x] Distance")
click("[ ] Tracers")
click("[ ] Rainbow ESP")
run.RenderStepped:fire()
local box = find("Frame", "Target")
local outline, username, distance
for _, object in ipairs(objects) do
	if object.Parent == box then
		if object.class == "UIStroke" then outline = object end
		if object.Name == "Username" then username = object end
		if object.Name == "Distance" then distance = object end
	end
end
assert(box.Visible and not outline.Enabled and not username.Visible and not distance.Visible)
assert(find("Frame", "Tracer").Visible)

local filterSection = find("TextLabel", "ESP filters").Parent
assert(filterSection.Position[2] + filterSection.Size[2] <= filterSection.Parent.CanvasSize[2])
local distanceInput = find("TextBox", "ESPDistanceInput")
local targetsInput = find("TextBox", "ESPTargetsInput")
local whitelistInput = find("TextBox", "ESPWhitelistInput")
local filterStatus = find("TextLabel", "ESPFilterStatus")
for _, field in ipairs({distanceInput, targetsInput, whitelistInput}) do
	assert(field.Position[2] + field.Size[2] <= filterSection.Size[2])
end
distanceInput.Text = "50"
distanceInput.FocusLost:fire()
click("[ ] ESP distance limit")
root.Position = vec(head.Position.X - 50, head.Position.Y, head.Position.Z)
run.RenderStepped:fire()
assert(box.Visible and find("Frame", "Tracer").Visible)
root.Position = vec(head.Position.X - 50.01, head.Position.Y, head.Position.Z)
run.RenderStepped:fire()
assert(not box.Visible and not find("Frame", "Tracer").Visible)
distanceInput.Text = "1e309"
distanceInput.FocusLost:fire()
assert(distanceInput.Text == "50" and filterStatus.Text ~= "")
click("[x] ESP distance limit")
click("[ ] ESP named only")
run.RenderStepped:fire()
assert(not box.Visible)
local otherTarget = {Name = "OtherPlayer", Team = "Red", Parent = players, Character = targetCharacter}
players.PlayerAdded:fire(otherTarget)
local otherBox = find("Frame", "OtherPlayer")
targetsInput.Text = " somebody, TARGET "
targetsInput.FocusLost:fire()
run.RenderStepped:fire()
assert(box.Visible and not otherBox.Visible)
whitelistInput.Text = "target"
whitelistInput.FocusLost:fire()
run.RenderStepped:fire()
assert(not box.Visible and not find("Frame", "Tracer").Visible)
whitelistInput.Text = ""
whitelistInput.FocusLost:fire()
run.RenderStepped:fire()
assert(box.Visible)
targetsInput.Text = "invalid\1name"
targetsInput.FocusLost:fire()
assert(targetsInput.Text == " somebody, TARGET " and filterStatus.Text ~= "")
run.RenderStepped:fire()
assert(box.Visible)
target.DisplayName = "Scarlet Star"
targetsInput.Text = " scarlet star "
targetsInput.FocusLost:fire()
run.RenderStepped:fire()
assert(box.Visible and not otherBox.Visible, "Display names should match independently of case")
target.Team = "Blue"
run.RenderStepped:fire()
assert(not box.Visible, "ESP team check must still apply to targeted display names")
target.Team = "Red"
targetHumanoid.Health = 0
run.RenderStepped:fire()
assert(not box.Visible, "ESP should hide characters whose humanoid is dead")
targetHumanoid.Health = 100
whitelistInput.Text = "target"
whitelistInput.FocusLost:fire()
run.RenderStepped:fire()
assert(not box.Visible, "Hidden usernames must override display-name targets")
whitelistInput.Text = ""
whitelistInput.FocusLost:fire()
local oldFind, oldHumanoid, oldBounds = targetCharacter.FindFirstChild, targetCharacter.FindFirstChildOfClass, targetCharacter.GetBoundingBox
targetCharacter.FindFirstChild = function() end
targetCharacter.FindFirstChildOfClass = function() end
targetCharacter.FindFirstChildWhichIsA = function(_, class) if class == "BasePart" then return head end end
run.RenderStepped:fire()
assert(box.Visible, "ESP should support a character without Head or Humanoid")
targetCharacter.GetBoundingBox = function()
	return {PointToWorldSpace = function(_, p) return vec(20 + p.X, 100 + p.Y, p.Z) end}, vec(2, 4, 2)
end
run.RenderStepped:fire()
assert(box.Visible, "ESP should remain visible when part of the box is behind the camera")
targetCharacter.GetBoundingBox = function()
	return {PointToWorldSpace = function(_, p) return vec(20 + p.X, 100 + p.Y, -20 + p.Z) end}, vec(2, 4, 2)
end
run.RenderStepped:fire()
assert(not box.Visible, "ESP should hide a box entirely behind the camera")
targetCharacter.FindFirstChild, targetCharacter.FindFirstChildOfClass, targetCharacter.GetBoundingBox = oldFind, oldHumanoid, oldBounds
target.DisplayName = nil
targetsInput.Text = ""
targetsInput.FocusLost:fire()
run.RenderStepped:fire()
assert(not box.Visible)
click("[x] ESP named only")
run.RenderStepped:fire()
assert(box.Visible and otherBox.Visible)
whitelistInput.Text = "OTHERPLAYER"
whitelistInput.FocusLost:fire()
run.RenderStepped:fire()
assert(box.Visible and not otherBox.Visible)
whitelistInput.Text = ""
whitelistInput.FocusLost:fire()
players.PlayerRemoving:fire(otherTarget)

click("[ ] Crosshair")
assert(find("Frame", "Crosshair").Visible)
click("[ ] Camera FOV")
run.RenderStepped:fire()
assert(camera.FieldOfView == 85)
local replacementCamera = {
	FieldOfView = 60, ViewportSize = camera.ViewportSize,
	CFrame = camera.CFrame, WorldToViewportPoint = camera.WorldToViewportPoint,
}
workspace.CurrentCamera = replacementCamera
run.RenderStepped:fire()
assert(camera.FieldOfView == 70 and replacementCamera.FieldOfView == 85)
click("[x] Camera FOV")
assert(replacementCamera.FieldOfView == 60)
workspace.CurrentCamera = camera
click("[ ] Disable shadows")
assert(not lighting.GlobalShadows)
click("[x] Disable shadows")
assert(lighting.GlobalShadows)
click("[ ] Custom fog")
assert(lighting.FogEnd == 100)
click("[x] Custom fog")
assert(lighting.FogStart == 20 and lighting.FogEnd == 1000)
click("[ ] Color correction")
assert(find("ColorCorrectionEffect", "AzureColorCorrection").Enabled)
click("[x] Color correction")
assert(not find("ColorCorrectionEffect", "AzureColorCorrection").Enabled)
click("[x] ESP")
assert(not box.Visible and not find("Frame", "Tracer").Visible)

press("RightShift")
local now, shots = 0, 0
tick = function() return now end
targetHumanoid.GetState = function() return "Running" end
targetCharacter.IsA = function(_, name) return name == "Model" end
targetCharacter.GetDescendants = function()
	return {{IsA = function(_, name) return name == "Motor6D" end}}
end
players.GetPlayerFromCharacter = function(_, model) if model == targetCharacter then return target end end
head.FindFirstAncestorOfClass = function() return targetCharacter end
mouseObject.Hit = {Position = vec(0, 0, 50)}
local hitPart, hitPosition = head, vec(0, 0, 50)
workspace.Raycast = function() return {Instance = hitPart, Position = hitPosition} end
local function weapon(name)
	return {
		Name = name,
		IsA = function(_, kind) return kind == "Tool" end,
		FindFirstChild = function() end,
		FindFirstChildOfClass = function() end,
		Activate = function() shots = shots + 1 end,
		Deactivate = function() end,
	}
end
local function heldShot()
	assert(blockClick("BlockMouseClick", "Begin") == "Sink")
	run.RenderStepped:fire()
	now = now + 1
	blockClick("BlockMouseClick", "End")
end
equipped = weapon("[Double-Barrel SG]")
heldShot()
assert(shots == 1)
hitPosition = vec(0, 0, 76)
heldShot()
assert(shots == 1, "Expected no additional DB shot; got " .. shots)
equipped = weapon("[Revolver]")
hitPosition = vec(0, 0, 199)
heldShot()
assert(shots == 2)
hitPosition = vec(0, 0, 201)
heldShot()
assert(shots == 2)
local nestedModel = {FindFirstAncestorOfClass = function() return targetCharacter end}
hitPart = {FindFirstAncestorOfClass = function() return nestedModel end}
hitPosition = vec(0, 0, 50)
heldShot()
assert(shots == 3)
target.Team = "Blue"
heldShot()
assert(shots == 3)
target.Team = "Red"
workspace.CurrentCamera = nil
heldShot()
assert(shots == 3)
workspace.CurrentCamera = camera
mouseObject.Hit = {Position = camera.CFrame.Position}
heldShot()
assert(shots == 3)
mouseObject.Hit = {Position = vec(0, 0, 50)}
local warning
warn = function(message) warning = message end
equipped.Activate = function() error("activation failed") end
heldShot()
assert(shots == 3 and warning:find("Triggerbot failed to activate", 1, true))
equipped = weapon("[Revolver]")
heldShot()
assert(shots == 4)

local targetTracer = find("Frame", "Tracer")
players.PlayerRemoving:fire(target)
assert(box.destroyed and targetTracer.destroyed)
for index = 2, #titles do assert(titles[index] == "Camlock") end

local configStatus = find("TextLabel", "ConfigStatus")
local configSection = configStatus.Parent
assert(find("TextLabel", "Config name (click to edit)").Parent == configSection)
for _, controlName in ipairs({"ConfigSave", "ConfigLoad", "ConfigExport", "ConfigImport", "ConfigRefresh"}) do
	local control = find("TextButton", controlName)
	assert(control.Position[2] + control.Size[2] <= configSection.Size[2])
end
assert(configSection.Position[2] + configSection.Size[2] <= configSection.Parent.CanvasSize[2])
click("Save config")
assert(configStatus.Text:lower():find("file", 1, true))
click("Load config")
assert(configStatus.Text:lower():find("file", 1, true))
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end
local saved, files, documents, serial
files, documents, serial = {}, {}, 0
services.HttpService = {
	JSONEncode = function(_, value)
		serial = serial + 1
		saved = copy(value)
		local encoded = "json-" .. serial
		documents[encoded] = saved
		return encoded
	end,
	JSONDecode = function(_, value)
		assert(documents[value], "bad json")
		return copy(documents[value])
	end,
}
writefile = function(path, value) files[path] = value end
readfile = function(path) assert(files[path], "file missing"); return files[path] end
isfile = function(path) return files[path] ~= nil end
local filename = paidScript and "Azure_Paid_Config.json" or "Azure_Public_Config.json"
local configName = find("TextBox", "ConfigName")
configName.Text = "Unsaved"
click("Export JSON")
assert(configStatus.Text:lower():find("save", 1, true) and not files[filename])
configName.Text = "Default"
prediction.Text = "0.37"
prediction.FocusLost:fire()
local targetsInput = find("TextBox", "ESPTargetsInput")
targetsInput.Text = "Target,Scarlet Star"
targetsInput.FocusLost:fire()
click("[ ] Speed")
if not paidScript then click("[ ] Selected players only") end
click("Save config")
assert(files[filename] and saved.profiles.Default, "Config should be saved to the version-specific file")
if not paidScript then
	assert(saved.profiles.Default.values["camlock/selectedPlayers"].target
		and saved.profiles.Default.values["camlock/selectedPlayers"].rival)
	click("[x] Selected players only")
	players.PlayerAdded:fire(target)
	find("TextButton", "CamlockPlayer:Target").MouseButton1Click:fire()
end
documents.legacy = copy(saved.profiles.Default)
files[filename] = "legacy"
click("Refresh list")
click("Default")
click("Load config")
if not paidScript then
	assert(find("TextButton", "CamlockPlayer:Target").Text == "[x] Target", "Loading must restore selected players")
end
click("Save config")
assert(saved.version == 2 and saved.profiles.Default, "Legacy config should migrate without losing its settings")
prediction.Text = "0.8"
prediction.FocusLost:fire()
targetsInput.Text = "Other"
targetsInput.FocusLost:fire()
click("[x] Speed")
if paidScript then
	find("TextButton", "Speed amountSlider").InputBegan:fire({UserInputType = "MouseButton1", Position = vec(55, 0)})
	input.InputEnded:fire({UserInputType = "MouseButton1"})
else
	local speedInput = find("TextBox", "SpeedAmountInput")
	speedInput.Text = "50"
	speedInput.FocusLost:fire()
end
click("Speed key: F")
press("G")
configName.Text = "Second"
click("Save config")
assert(saved.profiles.Default and saved.profiles.Second)
click("Export JSON")
local fileInput = find("TextBox", "ConfigFile")
local exportPath = (paidScript and "Azure_Paid_Export_" or "Azure_Public_Export_") .. "Second.json"
assert(fileInput.Text == exportPath and files[exportPath])
local firstExport = files[exportPath]
click("Export JSON")
assert(files[exportPath] == firstExport and fileInput.Text:match("Second%-2%.json$"))
assert(files[fileInput.Text], "Repeated exports should not overwrite earlier files")
configName.Text = "Imported"
fileInput.Text = "../invalid.json"
local previousCollection = files[filename]
click("Import JSON")
assert(files[filename] == previousCollection and configStatus.Text:lower():find("error", 1, true))
documents.invalidProfile = {version = 1, values = {["camlock/prediction"] = 2}}
files["Invalid.json"] = "invalidProfile"
fileInput.Text = "Invalid.json"
click("Import JSON")
assert(files[filename] == previousCollection and configStatus.Text:lower():find("invalid", 1, true))
fileInput.Text = "Missing.json"
click("Import JSON")
assert(files[filename] == previousCollection and configStatus.Text:lower():find("error", 1, true))
fileInput.Text = exportPath
click("Import JSON")
assert(saved.profiles.Default and saved.profiles.Second and saved.profiles.Imported)
click("Imported")
click("Load config")
assert(prediction.Text == "0.8" and targetsInput.Text == "Other")
click("Refresh list")
click("Default")
click("Load config")
assert(prediction.Text == "0.37" and targetsInput.Text == "Target,Scarlet Star")
assert(find("TextButton", "Speed key: F"))
if not paidScript then
	click("[x] Selected players only")
	click("[ ] Selected players only")
end
run.Heartbeat:fire(0.1)
assert(humanoid.WalkSpeed == 200)
press("F")
assert(humanoid.WalkSpeed == 16)
click("Second")
assert(prediction.Text == "0.37", "Selecting a config must not load it automatically")
click("Load config")
assert(prediction.Text == "0.8" and targetsInput.Text == "Other")
click("Default")
click("Load config")
press("F")
click("[x] Silent wall check")
click("[x] Silent team check")
click("Method: Mouse")
click("Method: Raycast")
click("[ ] Silent aim")
click("Save config")
assert(saved.profiles.Second, "Overwriting one config must preserve the others")
click("Method: Z ZHD")
click("[ ] Silent wall check")
click("[ ] Silent team check")
click("Load config")
assert(find("TextButton", "Method: Z ZHD"))
assert(attributes.AimLock == true, "Loading Z ZHD should restore its prerequisites before enabling it")
click("[x] Silent aim")
files[filename] = "invalid json"
prediction.Text = "0.9"
prediction.FocusLost:fire()
click("Load config")
assert(prediction.Text == "0.9" and configStatus.Text:lower():find("error", 1, true))
click("Save config")
assert(files[filename] == "invalid json" and configStatus.Text:lower():find("error", 1, true))
files[filename] = "json-" .. serial
saved.profiles.Default.values["camlock/prediction"] = 2
click("Load config")
assert(prediction.Text == "0.9" and configStatus.Text:lower():find("invalid", 1, true))
saved.profiles.Default.values["camlock/prediction"] = 0.37
saved.profiles.Default.values.keybinds.Speed = saved.profiles.Default.values.keybinds.ESP
click("Load config")
assert(prediction.Text == "0.9" and find("TextButton", "Speed key: F"))
configName.Text = "../invalid"
local previousFile = files[filename]
click("Save config")
assert(files[filename] == previousFile and configStatus.Text:lower():find("name", 1, true))
configName.Text = "Default"
writefile = function() error("disk full") end
click("Save config")
assert(configStatus.Text:lower():find("error", 1, true))
print("Combined feature checks passed")
