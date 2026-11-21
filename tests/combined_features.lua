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
local codes = {}
for _, key in ipairs({"Q", "T", "E", "RightShift", "Escape", "Unknown", "LeftControl", "RightControl", "W", "S", "A", "D", "Space"}) do
	codes[key] = {Name = key}
end
Enum = {
	KeyCode = codes, UserInputType = {Keyboard = "Keyboard", MouseButton1 = "MouseButton1", MouseMovement = "MouseMovement"},
	Font = {Code = 1, SourceSans = 2, SourceSansBold = 3, Gotham = 4, GothamBold = 5}, TextXAlignment = {Left = 1},
	RenderPriority = {Camera = {Value = 200}}, RaycastFilterType = {Exclude = 1, Blacklist = 1},
	ScrollingDirection = {Y = 1}, HighlightDepthMode = {AlwaysOnTop = 1}, Material = {Air = "Air"},
	ContextActionResult = {Pass = "Pass", Sink = "Sink"},
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
		if object.class == class and (object.Name == name or object.Text == name) then return object end
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
local root = {Position = vec(5, 10, 5), CFrame = vec(5, 10, 5)}
local equipped
local character = {
	ChildAdded = event(), ChildRemoved = event(),
	FindFirstChildOfClass = function(_, class)
		if class == "Humanoid" then return humanoid end
		if class == "Tool" then return equipped end
	end,
	FindFirstChild = function(_, name) if name == "HumanoidRootPart" then return root end end,
}
local kicks = 0
local mouseObject = {}
local player = {
	Team = "Blue", Character = character, CharacterAdded = event(),
	GetMouse = function() return mouseObject end, WaitForChild = function() return {} end,
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
local lighting = {GlobalShadows = true, FogStart = 20, FogEnd = 1000}
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
task = {spawn = function(callback) table.insert(scheduled, callback) end}
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

dofile("Triggerbot.lua")
assert(#messages == 1 and titles[1] == "Notification")
local menuFrame = find("Frame", "Settings")
assert(find("TextLabel", "DragHandle").Text == "Azure | discord.gg/azuremodded")
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
assert(find("TextLabel", "Executor hook APIs unavailable."))
click("[ ] Silent aim")
assert(find("TextLabel", "Executor hook APIs unavailable."))
local hooks, caller, method = {}, false, "Raycast"
hookmetamethod = function(_, name, callback)
	hooks[name] = callback
	if name == "__index" then return function() return "original" end end
	return function(_, origin, direction) return origin, direction end
end
newcclosure = function(callback) return callback end
checkcaller = function() return caller end
getnamecallmethod = function() return method end
typeof = function(value) return getmetatable(value) == vector and "Vector3" or type(value) end
click("[ ] Silent aim")
assert(hooks.__index)
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
local origin, direction = hooks.__namecall(workspace, vec(0, 0, 0), vec(0, 0, 100))
assert(origin.Magnitude == 0 and math.abs(direction.Magnitude - 100) < 0.000001 and direction.X > 99)
method = "Other"
_, direction = hooks.__namecall(workspace, vec(0, 0, 0), vec(0, 0, 100))
assert(direction.X == 0)
method = "Raycast"
click("[x] Silent aim")
_, direction = hooks.__namecall(workspace, vec(0, 0, 0), vec(0, 0, 100))
assert(direction.X == 0)
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
local replacementRoot = {Position = vec(0, -495, 0), CFrame = vec(0, -495, 0)}
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
players.PlayerRemoving:fire(target)
assert(box.destroyed and find("Frame", "Tracer").destroyed)
for index = 2, #titles do assert(titles[index] == "Camlock") end
print("Combined feature checks passed")
