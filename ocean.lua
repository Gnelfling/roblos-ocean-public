-- Roblox Ocean Generator - CHUNKED INFINITE VERSION
-- Place as a LocalScript in StarterPlayerScripts or StarterGui
-- Reworked to stream water in chunks around the player

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local camera = workspace:FindFirstChild("CurrentCamera") or workspace.CurrentCamera

-- safe tween helper
local function tween(obj, props, time, style, dir)
    if not obj then return nil end
    local info = TweenInfo.new(
        time or 0.3,
        style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out
    )
    local ok, t = pcall(function() return TweenService:Create(obj, info, props) end)
    if ok and t then
        pcall(function() t:Play() end)
        return t
    end
    return nil
end

-- Configs (chunked ocean)
local CHUNK_SIZE = 364              -- chunk width / length in studs
local CHUNK_HEIGHT = 1200              -- vertical thickness of water block (studs)
local RENDER_DISTANCE_CHUNKS = 24    -- how many chunks radius around player to keep
local CHUNK_CULL_PADDING = 8        -- extra padding before removing chunks

-- existing configs
local LOGO_IMAGE = "rbxassetid://4836612768"
local AMBIENCE_SOUND_ID = "rbxassetid://1845341094"
local BUTTON_SOUND_ID = "rbxassetid://6042053626"

local GUI_ZOOM_FOV = 50
local ZOOM_TIME = 0.5
local BLUR_TARGET = 48
local BLUR_TIME = 0.45
local MENU_SCALE_TIME = 0.38

local terrain = workspace:FindFirstChildOfClass("Terrain")
local oceanCenter = Vector3.new(0,0,0)
-- oceanSize not used for chunking now
local oceanSize = Vector3.new(2048,512,2048)

-- State
local menuOpen = false
local currentOceanCFrame = nil
local currentWaterHeight = 0
local locked = false
local defaultFOV = camera and camera.FieldOfView or 70

-- Chunk state
local generatedChunks = {} -- map key -> {cx, cz}
local generationActive = false

-- Safe terrain setter
local function safeSetTerrainProperty(prop, value)
    if not terrain then return false end
    local ok, err = pcall(function() terrain[prop] = value end)
    return ok, err
end

-- Helpers: chunk key / center computation
local function chunkKey(cx, cz) return tostring(cx) .. "_" .. tostring(cz) end

local function chunkWorldCenter(cx, cz, height)
    -- chunk center (x,z) and Y is water surface level
    local x = cx * CHUNK_SIZE + (CHUNK_SIZE/2)
    local z = cz * CHUNK_SIZE + (CHUNK_SIZE/2)
    local y = (height or currentWaterHeight) - (CHUNK_HEIGHT/2)
    return Vector3.new(x, y, z)
end

-- Create one chunk (safe pcall)
local function generateChunk(cx, cz)
    if not terrain then return end
    local k = chunkKey(cx, cz)
    if generatedChunks[k] then return end

    local center = chunkWorldCenter(cx, cz, currentWaterHeight)
    local ok, err = pcall(function()
        terrain:FillBlock(CFrame.new(center), Vector3.new(CHUNK_SIZE, CHUNK_HEIGHT, CHUNK_SIZE), Enum.Material.Water)
    end)
    if ok then
        generatedChunks[k] = {cx = cx, cz = cz}
    end
end

-- Remove one chunk
local function removeChunk(cx, cz)
    if not terrain then return end
    local k = chunkKey(cx, cz)
    if not generatedChunks[k] then return end
    local center = chunkWorldCenter(cx, cz, currentWaterHeight)
    pcall(function()
        terrain:FillBlock(CFrame.new(center), Vector3.new(CHUNK_SIZE, CHUNK_HEIGHT, CHUNK_SIZE), Enum.Material.Air)
    end)
    generatedChunks[k] = nil
end

-- Clear all chunks immediately
local function clearAllChunks()
    if not terrain then
        generatedChunks = {}
        return
    end
    for k, v in pairs(generatedChunks) do
        local cx, cz = v.cx, v.cz
        local center = chunkWorldCenter(cx, cz, currentWaterHeight)
        pcall(function()
            terrain:FillBlock(CFrame.new(center), Vector3.new(CHUNK_SIZE, CHUNK_HEIGHT, CHUNK_SIZE), Enum.Material.Air)
        end)
        generatedChunks[k] = nil
    end
    generatedChunks = {}
end

-- Regenerate chunk heights when water level changed
local function rebuildAllChunks()
    -- remove and regenerate around player on next Heartbeat
    clearAllChunks()
    -- next Heartbeat Generation loop will refill around player if generationActive
end

-- Streaming loop: generate around player; cull distant chunks
RunService.Heartbeat:Connect(function()
    if not generationActive then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local px = math.floor(root.Position.X / CHUNK_SIZE)
    local pz = math.floor(root.Position.Z / CHUNK_SIZE)

    -- generate a grid around player
    for x = px - RENDER_DISTANCE_CHUNKS, px + RENDER_DISTANCE_CHUNKS do
        for z = pz - RENDER_DISTANCE_CHUNKS, pz + RENDER_DISTANCE_CHUNKS do
            generateChunk(x, z)
        end
    end

    -- cull chunks outside extended radius
    local maxDist = RENDER_DISTANCE_CHUNKS + CHUNK_CULL_PADDING
    for k, v in pairs(generatedChunks) do
        local dx = math.abs(v.cx - px)
        local dz = math.abs(v.cz - pz)
        if dx > maxDist or dz > maxDist then
            removeChunk(v.cx, v.cz)
        end
    end
end)

-- UI root (keep original GUI creation)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OceanGeneratorUI_FINAL"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Menu (larger)
local menuFrame = Instance.new("Frame")
menuFrame.Name = "Menu"
menuFrame.Size = UDim2.new(0,860,0,780)
menuFrame.AnchorPoint = Vector2.new(0.5,0.5)
menuFrame.Position = UDim2.new(0.5,0.5,0.5,0)
menuFrame.BackgroundColor3 = Color3.fromRGB(10,10,12)
menuFrame.BorderSizePixel = 0
menuFrame.Visible = false
menuFrame.Parent = screenGui
local menuCorner = Instance.new("UICorner", menuFrame) menuCorner.CornerRadius = UDim.new(0,22)

-- Header
local header = Instance.new("Frame", menuFrame)
header.Size = UDim2.new(1,0,0,126)
header.BackgroundTransparency = 1

local logo = Instance.new("ImageLabel", header)
logo.Size = UDim2.new(0,116,0,116)
logo.Position = UDim2.new(0,18,0.5,-58)
logo.BackgroundTransparency = 1
logo.Image = LOGO_IMAGE

local title = Instance.new("TextLabel", header)
title.Position = UDim2.new(0,150,0,18)
title.Size = UDim2.new(0,660,0,36)
title.BackgroundTransparency = 1
title.Text = "Ocean Generator"
title.Font = Enum.Font.GothamBold
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(245,250,255)
title.TextXAlignment = Enum.TextXAlignment.Left

local subtitle = Instance.new("TextLabel", header)
subtitle.Position = UDim2.new(0,150,0,58)
subtitle.Size = UDim2.new(0,660,0,22)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Editable terrain ocean — square HSV picker, presets, and controls"
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 14
subtitle.TextColor3 = Color3.fromRGB(170,195,230)
subtitle.TextXAlignment = Enum.TextXAlignment.Left

-- Panels
local leftPanel = Instance.new("Frame", menuFrame)
leftPanel.Position = UDim2.new(0,18,0,150)
leftPanel.Size = UDim2.new(0,520,0,600)
leftPanel.BackgroundTransparency = 1

local rightPanel = Instance.new("Frame", menuFrame)
rightPanel.Position = UDim2.new(0,560,0,150)
rightPanel.Size = UDim2.new(0,280,0,600)
rightPanel.BackgroundTransparency = 1

-- BUTTON FACTORY
local function makeButton(text, parent, posY, gradientColors, width, height)
    width = width or 460
    height = height or 48
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, width, 0, height)
    btn.Position = UDim2.new(0, 0, 0, posY)
    btn.BackgroundColor3 = Color3.fromRGB(8,8,10)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 18
    btn.TextColor3 = Color3.fromRGB(250,255,255)
    btn.AutoButtonColor = false
    btn.Parent = parent
    local corner = Instance.new("UICorner", btn) corner.CornerRadius = UDim.new(0,10)
    local grad = Instance.new("UIGradient", btn) grad.Rotation = 90
    grad.Color = ColorSequence.new(gradientColors or {
        ColorSequenceKeypoint.new(0, Color3.fromRGB(16,20,30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12,70,130)),
    })
    local stroke = Instance.new("UIStroke", btn) stroke.Color = Color3.fromRGB(16,26,46)
    return btn
end

-- BOING
local function addBoing(btn)
    if not btn then return end
    local baseW = (btn.Size and btn.Size.X and btn.Size.X.Offset) or 360
    local baseH = (btn.Size and btn.Size.Y and btn.Size.Y.Offset) or 44
    local function sizeUD(scale)
        local w = math.max(1, math.floor(baseW * scale))
        local h = math.max(1, math.floor(baseH * scale))
        return UDim2.new(0, w, 0, h)
    end
    btn.MouseEnter:Connect(function() pcall(function() TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = sizeUD(1.04)}):Play() end) end)
    btn.MouseLeave:Connect(function() pcall(function() TweenService:Create(btn, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = sizeUD(1.00)}):Play() end) end)
    btn.Activated:Connect(function()
        pcall(function()
            local t1 = TweenService:Create(btn, TweenInfo.new(0.06, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Size = sizeUD(0.96)})
            local t2 = TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Size = sizeUD(1.00)})
            t1:Play(); t1.Completed:Wait(); t2:Play()
        end)
    end)
end

-- SLIDER FACTORY (with safe Set method)
local function makeSlider(labelText, parent, posY, min, max, default)
    local container = Instance.new("Frame", parent)
    container.Position = UDim2.new(0,0,0,posY)
    container.Size = UDim2.new(1,0,0,64)
    container.BackgroundTransparency = 1

    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(0.6,0,0,20); label.Position = UDim2.new(0,0,0,0)
    label.BackgroundTransparency = 1; label.Text = labelText; label.Font = Enum.Font.Gotham; label.TextSize = 14
    label.TextColor3 = Color3.fromRGB(235,245,255); label.TextXAlignment = Enum.TextXAlignment.Left

    local valueLabel = Instance.new("TextLabel", container)
    valueLabel.Size = UDim2.new(0.4,-6,0,20); valueLabel.Position = UDim2.new(0.6,6,0,0)
    valueLabel.BackgroundTransparency = 1; valueLabel.Text = tostring(default); valueLabel.Font = Enum.Font.Gotham
    valueLabel.TextSize = 14; valueLabel.TextColor3 = Color3.fromRGB(185,210,240); valueLabel.TextXAlignment = Enum.TextXAlignment.Right

    local barBg = Instance.new("Frame", container)
    barBg.Position = UDim2.new(0,0,0,26); barBg.Size = UDim2.new(1,0,0,14); barBg.BackgroundColor3 = Color3.fromRGB(8,8,8)
    local bgCorner = Instance.new("UICorner", barBg) bgCorner.CornerRadius = UDim.new(0,8)

    local fill = Instance.new("Frame", barBg)
    fill.Size = UDim2.new((default-min)/(max-min),0,1,0); fill.BackgroundColor3 = Color3.fromRGB(8,78,150)
    local fillCorner = Instance.new("UICorner", fill) fillCorner.CornerRadius = UDim.new(0,8)

    local hit = Instance.new("TextButton", barBg)
    hit.Size = UDim2.new(1,1,1,1); hit.Text = ""; hit.BackgroundTransparency = 1; hit.AutoButtonColor = false

    local slider = { Container = container, OnChange = nil, OnGet = default }

    local function updateVisual(val)
        local frac = (val - min) / math.max(1, max - min)
        fill.Size = UDim2.new(math.clamp(frac,0,1),0,1,0)
        valueLabel.Text = string.format("%.2f", val)
        slider.OnGet = val
    end

    function slider.Set(val)
        if type(val) ~= "number" then return end
        val = math.clamp(val, min, max)
        updateVisual(val)
        if slider.OnChange then
            pcall(function() slider.OnChange(val) end)
        end
    end

    local dragging = false
    local function updateFromX(x)
        local abs = x - barBg.AbsolutePosition.X
        local width = math.max(1, barBg.AbsoluteSize.X)
        local frac = math.clamp(abs / width, 0, 1)
        local val = min + frac * (max - min)
        slider.Set(val)
        return val
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            if input.Position then updateFromX(input.Position.X) end
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            if input.Position then updateFromX(input.Position.X) end
        end
    end)
    hit.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    pcall(function() slider.Set(default) end)
    return slider
end

-- LEFT CONTROLS
local waterLevelSlider = makeSlider("Water Level", leftPanel, 0, -128, 256, 0)
local waveSizeSlider   = makeSlider("Wave Size (approx)", leftPanel, 74, 0, 50, 4)
local waveSpeedSlider  = makeSlider("Wave Speed", leftPanel, 148, 0, 10, 1)
local transparencySlider = makeSlider("Water Transparency", leftPanel, 222, 0, 1, 0.2)
local reflectionSlider = makeSlider("Reflection Intensity", leftPanel, 296, 0, 1, 0.5)

-- BUTTONS
local generateBtn = makeButton("Generate Ocean (uses Terrain)", leftPanel, 368, nil, 460, 48)
local removeBtn   = makeButton("Remove Ocean", leftPanel, 428, {
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22,12,12)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(160,16,16)),
}, 460, 48)
local lockBtn     = makeButton("Lock Ocean (Unlock to remove)", leftPanel, 488, nil, 460, 44)
lockBtn.TextColor3 = Color3.fromRGB(255,240,150)

addBoing(generateBtn); addBoing(removeBtn); addBoing(lockBtn)

-- RIGHT PANEL: presets, SV, hue, RGB, preview, ambience (ambience slider moved up)
local colorTitle = Instance.new("TextLabel", rightPanel)
colorTitle.Size = UDim2.new(1,0,0,22); colorTitle.Position = UDim2.new(0,0,0,0)
colorTitle.BackgroundTransparency = 1; colorTitle.Text = "Water Color & Extras"
colorTitle.Font = Enum.Font.GothamBold; colorTitle.TextSize = 16; colorTitle.TextColor3 = Color3.fromRGB(235,245,255)
colorTitle.TextXAlignment = Enum.TextXAlignment.Left

local presetContainer = Instance.new("Frame", rightPanel)
presetContainer.Size = UDim2.new(1,0,0,120); presetContainer.Position = UDim2.new(0,0,0,28); presetContainer.BackgroundTransparency = 1

local presets = {
    Color3.fromRGB(12,80,150),Color3.fromRGB(16,96,160),Color3.fromRGB(24,144,200),
    Color3.fromRGB(10,50,100),Color3.fromRGB(70,130,180),Color3.fromRGB(12,8,50),
    Color3.fromRGB(0,120,200),Color3.fromRGB(0,80,120),Color3.fromRGB(32,178,170),
    Color3.fromRGB(8,24,64),Color3.fromRGB(120,200,240),Color3.fromRGB(4,40,80)
}
local presetSize = 26; local spacing = 6
for i, col in ipairs(presets) do
    local colsPerRow = 4
    local row = math.floor((i-1)/colsPerRow)
    local colIdx = ((i-1) % colsPerRow)
    local btn = Instance.new("TextButton", presetContainer)
    btn.Size = UDim2.new(0,presetSize,0,presetSize)
    btn.Position = UDim2.new(0, colIdx*(presetSize+spacing), 0, row*(presetSize+spacing))
    btn.BackgroundColor3 = col; btn.BorderSizePixel = 0; btn.Text = ""; btn.AutoButtonColor = false
    local corner = Instance.new("UICorner", btn) corner.CornerRadius = UDim.new(0,6)
    addBoing(btn)
    btn.MouseButton1Click:Connect(function()
        if rSlider and rSlider.Set then rSlider.Set(math.floor(col.R * 255)) end
        if gSlider and gSlider.Set then gSlider.Set(math.floor(col.G * 255)) end
        if bSlider and bSlider.Set then bSlider.Set(math.floor(col.B * 255)) end
        pcall(function() if swatch then swatch.BackgroundColor3 = col end end)
        if currentOceanCFrame then pcall(function() safeSetTerrainProperty("WaterColor", col); safeSetTerrainProperty("WaterColor3", col) end) end
    end)
end

-- SV square and hue slider
local svSize = 180
local svFrame = Instance.new("Frame", rightPanel)
svFrame.Size = UDim2.new(0, svSize, 0, svSize)
svFrame.Position = UDim2.new(0, 8, 0, 158)
svFrame.BorderSizePixel = 0
svFrame.BackgroundColor3 = Color3.fromRGB(255,0,0)
local svCorner = Instance.new("UICorner", svFrame) svCorner.CornerRadius = UDim.new(0,6)
local whiteOverlay = Instance.new("Frame", svFrame)
whiteOverlay.Size = UDim2.new(1,0,1,0); whiteOverlay.Position = UDim2.new(0,0,0,0)
whiteOverlay.BackgroundColor3 = Color3.fromRGB(255,255,255)
local wGrad = Instance.new("UIGradient", whiteOverlay); wGrad.Rotation = 0
wGrad.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1) }
local blackOverlay = Instance.new("Frame", svFrame)
blackOverlay.Size = UDim2.new(1,0,1,0); blackOverlay.Position = UDim2.new(0,0,0,0)
blackOverlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
local bGrad = Instance.new("UIGradient", blackOverlay); bGrad.Rotation = 90
bGrad.Transparency = NumberSequence.new{ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1) }

local hueSlider = Instance.new("Frame", rightPanel)
hueSlider.Position = UDim2.new(0,0,0,358)
hueSlider.Size = UDim2.new(0, svSize, 0, 18)
hueSlider.BackgroundColor3 = Color3.fromRGB(255,0,0)
local hueCorner = Instance.new("UICorner", hueSlider) hueCorner.CornerRadius = UDim.new(0,6)
local hueGrad = Instance.new("UIGradient", hueSlider)
hueGrad.Rotation = 0
hueGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0/6, Color3.fromRGB(255,0,0)),
    ColorSequenceKeypoint.new(1/6, Color3.fromRGB(255,255,0)),
    ColorSequenceKeypoint.new(2/6, Color3.fromRGB(0,255,0)),
    ColorSequenceKeypoint.new(3/6, Color3.fromRGB(0,255,255)),
    ColorSequenceKeypoint.new(4/6, Color3.fromRGB(0,0,255)),
    ColorSequenceKeypoint.new(5/6, Color3.fromRGB(255,0,255)),
    ColorSequenceKeypoint.new(6/6, Color3.fromRGB(255,0,0))
}

-- RGB sliders (under hue)
local rSlider = makeSlider("Red", rightPanel, 386, 0, 255, 16)
local gSlider = makeSlider("Green", rightPanel, 454, 0, 255, 96)
local bSlider = makeSlider("Blue", rightPanel, 522, 0, 255, 160)

-- preview swatch moved up and right (anchored)
local swatch = Instance.new("Frame", rightPanel)
swatch.Size = UDim2.new(0,88,0,88)
swatch.Position = UDim2.new(1, -14, 0, 28)
swatch.AnchorPoint = Vector2.new(1,0)
swatch.BackgroundColor3 = Color3.fromRGB(16,96,160)
local swCorner = Instance.new("UICorner", swatch) swCorner.CornerRadius = UDim.new(0,8)

-- Ambience slider (moved up)
local ambienceSlider = makeSlider("Ambience Volume", rightPanel, 572, 0, 1, 0.12)

-- Sounds & blur
local sfx = Instance.new("Sound", SoundService)
pcall(function() sfx.SoundId = BUTTON_SOUND_ID end)
sfx.Volume = 0.8

local ambience = Instance.new("Sound", SoundService)
pcall(function() ambience.SoundId = AMBIENCE_SOUND_ID end)
ambience.Looped = true
ambience.Volume = ambienceSlider and (ambienceSlider.OnGet or 0.12) or 0.12

local blur = Instance.new("BlurEffect")
blur.Name = "OceanMenuBlur"
blur.Parent = game:GetService("Lighting")
blur.Size = 0 -- ensure no blur initially

-- SV / hue logic
local currentHue = 0.57
local function updateSVBase()
    pcall(function()
        if svFrame then svFrame.BackgroundColor3 = Color3.fromHSV(currentHue, 1, 1) end
        if hueSlider then hueSlider.BackgroundColor3 = Color3.fromHSV(currentHue, 1, 1) end
    end)
end

local function setFromSV(px, py)
    local sat = math.clamp(px,0,1)
    local val = math.clamp(1-py,0,1)
    local c = Color3.fromHSV(currentHue, sat, val)
    local r,g,b = c.R*255, c.G*255, c.B*255
    if rSlider and rSlider.Set then rSlider.Set(r) end
    if gSlider and gSlider.Set then gSlider.Set(g) end
    if bSlider and bSlider.Set then bSlider.Set(b) end
    pcall(function() if swatch then swatch.BackgroundColor3 = c end end)
    if currentOceanCFrame then pcall(function() safeSetTerrainProperty("WaterColor", c); safeSetTerrainProperty("WaterColor3", c) end) end
end

local svDragging = false
svFrame.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        svDragging = true
        local pos = input.Position; local abs = svFrame.AbsolutePosition; local size = svFrame.AbsoluteSize
        setFromSV((pos.X-abs.X)/math.max(1,size.X),(pos.Y-abs.Y)/math.max(1,size.Y))
    end
end)
svFrame.InputChanged:Connect(function(input)
    if svDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local pos = input.Position; local abs = svFrame.AbsolutePosition; local size = svFrame.AbsoluteSize
        setFromSV((pos.X-abs.X)/math.max(1,size.X),(pos.Y-abs.Y)/math.max(1,size.Y))
    end
end)
svFrame.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then svDragging = false end end)

local hueDragging = false
hueSlider.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        hueDragging = true
        local pos = input.Position; local abs = hueSlider.AbsolutePosition; local size = hueSlider.AbsoluteSize
        currentHue = math.clamp((pos.X-abs.X)/math.max(1,size.X),0,1)
        updateSVBase()
    end
end)
hueSlider.InputChanged:Connect(function(input)
    if hueDragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local pos = input.Position; local abs = hueSlider.AbsolutePosition; local size = hueSlider.AbsoluteSize
        currentHue = math.clamp((pos.X-abs.X)/math.max(1,size.X),0,1)
        updateSVBase()
    end
end)
hueSlider.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then hueDragging = false end end)

-- apply color from RGB sliders to swatch & terrain
local function applyColorFromRGB()
    local r = math.clamp((rSlider.OnGet or 0)/255,0,1)
    local g = math.clamp((gSlider.OnGet or 0)/255,0,1)
    local b = math.clamp((bSlider.OnGet or 0)/255,0,1)
    local c = Color3.new(r,g,b)
    pcall(function() if swatch then swatch.BackgroundColor3 = c end end)
    if currentOceanCFrame then pcall(function() safeSetTerrainProperty("WaterColor", c); safeSetTerrainProperty("WaterColor3", c) end) end
end

-- Wire RGB sliders to applyColorFromRGB
if rSlider and rSlider.Set then
    local orig = rSlider.OnChange
    rSlider.OnChange = function(v) rSlider.OnGet = v; applyColorFromRGB(); if orig then pcall(function() orig(v) end) end end
end
if gSlider and gSlider.Set then
    local orig = gSlider.OnChange
    gSlider.OnChange = function(v) gSlider.OnGet = v; applyColorFromRGB(); if orig then pcall(function() orig(v) end) end end
end
if bSlider and bSlider.Set then
    local orig = bSlider.OnChange
    bSlider.OnChange = function(v) bSlider.OnGet = v; applyColorFromRGB(); if orig then pcall(function() orig(v) end) end end
end

-- NOTE: replaced createOrUpdateOcean with chunked generation functions above

-- Lock notification animation (moved up and polished)
local function animateLockNotification(text)
    local ok, notif = pcall(function()
        local lbl = Instance.new("TextLabel", menuFrame)
        lbl.Size = UDim2.new(0,360,0,28)
        lbl.Position = UDim2.new(0.5,-180,0,12) -- higher up
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.Font = Enum.Font.GothamSemibold
        lbl.TextSize = 16
        lbl.TextColor3 = Color3.fromRGB(255,140,120)
        lbl.TextStrokeTransparency = 0.8
        lbl.TextTransparency = 1
        lbl.AnchorPoint = Vector2.new(0.5,0)
        return lbl
    end)
    if not ok or not notif then return end

    local startPos = notif.Position
    local upPos = UDim2.new(startPos.X.Scale, startPos.X.Offset, startPos.Y.Scale, startPos.Y.Offset - 10)
    pcall(function()
        tween(notif, {TextTransparency = 0, Position = upPos}, 0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    end)
    delay(0.85, function()
        pcall(function()
            tween(notif, {TextTransparency = 1, Position = startPos}, 0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
            delay(0.28, function() pcall(function() notif:Destroy() end) end)
        end)
    end)
end

-- Confirm remove modal (keeps original semantics)
local function confirmRemove()
    local modal = Instance.new("Frame", screenGui)
    modal.Size = UDim2.new(1,0,1,0)
    modal.BackgroundTransparency = 1

    local panel = Instance.new("Frame", modal)
    panel.Size = UDim2.new(0,460,0,160)
    panel.Position = UDim2.new(0.5,0,0.5,-20)
    panel.AnchorPoint = Vector2.new(0.5,0.5)
    panel.BackgroundColor3 = Color3.fromRGB(18,18,20)
    local pc = Instance.new("UICorner", panel) pc.CornerRadius = UDim.new(0,12)

    local txt = Instance.new("TextLabel", panel)
    txt.Size = UDim2.new(1,-20,0,80); txt.Position = UDim2.new(0,10,0,10)
    txt.BackgroundTransparency = 1
    txt.Text = "Are you sure you want to remove the ocean? This cannot be undone."
    txt.TextWrapped = true; txt.Font = Enum.Font.Gotham; txt.TextColor3 = Color3.fromRGB(230,230,230); txt.TextSize = 14

    local ok = makeButton("Yes, Remove", panel, 100, {
        ColorSequenceKeypoint.new(0, Color3.fromRGB(140,10,10)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200,20,20)),
    }, 200, 40)
    ok.Position = UDim2.new(0,20,0,100)
    local cancel = makeButton("Cancel", panel, 100, nil, 200, 40)
    cancel.Position = UDim2.new(0,240,0,100)

    addBoing(ok); addBoing(cancel)
    ok.MouseButton1Click:Connect(function()
        pcall(function()
            if generationActive and not locked and terrain then
                generationActive = false
                clearAllChunks()
            end
        end)
        pcall(function() sfx:Play() end)
        modal:Destroy()
    end)
    cancel.MouseButton1Click:Connect(function()
        pcall(function() sfx:Play() end)
        modal:Destroy()
    end)
end

-- Button behaviors & hooks
local function playButtonSound() pcall(function() sfx:Play() end) end

generateBtn.MouseButton1Click:Connect(function()
    playButtonSound()
    if locked then
        animateLockNotification("Ocean is locked! Unlock to generate.")
        return
    end
    generationActive = true
    -- ensure current water height set from slider
    currentWaterHeight = waterLevelSlider.OnGet or 0
    -- apply global terrain props
    pcall(function() safeSetTerrainProperty("WaterTransparency", transparencySlider.OnGet) end)
    pcall(function() safeSetTerrainProperty("WaterWaveSize", waveSizeSlider.OnGet) end)
    pcall(function() safeSetTerrainProperty("WaveSize", waveSizeSlider.OnGet) end)
    pcall(function() safeSetTerrainProperty("WaterWaveSpeed", tonumber(waveSpeedSlider.OnGet) or 1) end)
    pcall(function() safeSetTerrainProperty("WaterReflectance", reflectionSlider.OnGet) end)
end)

removeBtn.MouseButton1Click:Connect(function()
    playButtonSound()
    if locked then
        animateLockNotification("Ocean is locked! Unlock to remove.")
        return
    end
    generationActive = false
    clearAllChunks()
end)

lockBtn.MouseButton1Click:Connect(function()
    locked = not locked
    lockBtn.Text = locked and "Ocean Locked (can't remove)" or "Lock Ocean (Unlock to remove)"
    playButtonSound()
    animateLockNotification( locked and "Ocean locked — removal disabled" or "Ocean unlocked — you may remove" )
end)

-- Update initial SV/hue and swatch
updateSVBase()
pcall(function() if swatch then swatch.BackgroundColor3 = Color3.fromHSV(currentHue, 0.6, 0.6) end end)
ambience.Volume = ambienceSlider and (ambienceSlider.OnGet or 0.12) or 0.12
blur.Size = 0
defaultFOV = camera and camera.FieldOfView or 70

-- OPEN / CLOSE MENU functions
local function OpenMenu()
    if menuOpen then return end
    menuOpen = true
    menuFrame.Visible = true
    pcall(function() ambience:Play() end)
    tween(ambience, {Volume = ambienceSlider.OnGet or 0.12}, 0.5)
    tween(blur, {Size = BLUR_TARGET}, BLUR_TIME)
    tween(camera, {FieldOfView = GUI_ZOOM_FOV}, ZOOM_TIME)
    menuFrame:TweenSizeAndPosition(UDim2.new(0,860,0,780), UDim2.new(0.5,0,0.5,0), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, MENU_SCALE_TIME, true)
end

local function CloseMenu()
    if not menuOpen then return end
    menuOpen = false
    tween(ambience, {Volume = 0}, 0.45)
    delay(0.5, function() pcall(function() ambience:Stop() end) end)
    tween(blur, {Size = 0}, BLUR_TIME)
    tween(camera, {FieldOfView = defaultFOV}, ZOOM_TIME)
    menuFrame:TweenSizeAndPosition(UDim2.new(0,820,0,740), UDim2.new(0.5,0,0.5,10), Enum.EasingDirection.In, Enum.EasingStyle.Quart, MENU_SCALE_TIME, true)
    delay(MENU_SCALE_TIME + 0.06, function() if menuFrame then menuFrame.Visible = false end end)
end

-- Toggle menu via M
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.M then
        playButtonSound()
        if not menuOpen then OpenMenu() else CloseMenu() end
    end
end)

-- Ambience slider hook
if ambienceSlider and ambienceSlider.Set then
    local orig = ambienceSlider.OnChange
    ambienceSlider.OnChange = function(v)
        ambienceSlider.OnGet = v
        pcall(function() ambience.Volume = v end)
        if orig then pcall(function() orig(v) end) end
    end
end

-- Left sliders hooks (ensure dynamic updates)
waterLevelSlider.OnChange = function(v)
    waterLevelSlider.OnGet = v
    currentWaterHeight = v
    if generationActive then
        -- rebuild so chunks use new Y
        rebuildAllChunks()
    end
end
waveSizeSlider.OnChange = function(v) waveSizeSlider.OnGet = v if generationActive then pcall(function() safeSetTerrainProperty("WaterWaveSize", v); safeSetTerrainProperty("WaveSize", v) end) end end
waveSpeedSlider.OnChange = function(v) waveSpeedSlider.OnGet = v if generationActive then pcall(function() safeSetTerrainProperty("WaterWaveSpeed", tonumber(v) or 1) end) end end
transparencySlider.OnChange = function(v) transparencySlider.OnGet = v if generationActive then pcall(function() safeSetTerrainProperty("WaterTransparency", v) end) end end
reflectionSlider.OnChange = function(v) reflectionSlider.OnGet = v if generationActive then pcall(function() safeSetTerrainProperty("WaterReflectance", v) end) end end

-- Defaults
if waterLevelSlider and waterLevelSlider.Set then waterLevelSlider.Set(0) else waterLevelSlider.OnGet = 0 end
if waveSizeSlider and waveSizeSlider.Set then waveSizeSlider.Set(4) else waveSizeSlider.OnGet = 4 end
if waveSpeedSlider and waveSpeedSlider.Set then waveSpeedSlider.Set(1) else waveSpeedSlider.OnGet = 1 end
if transparencySlider and transparencySlider.Set then transparencySlider.Set(0.2) else transparencySlider.OnGet = 0.2 end
if reflectionSlider and reflectionSlider.Set then reflectionSlider.Set(0.5) else reflectionSlider.OnGet = 0.5 end

print("Ocean Chunked Generator loaded. Press M to toggle the menu. Press Generate to start streaming the ocean.")




