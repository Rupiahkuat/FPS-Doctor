--[[
	FPS DOCTOR  -  Smart Collision & Performance Auditor
	Roblox Studio Plugin (single file)

	Install:
	  1. In Studio, insert a Script into ServerStorage and paste this file's contents.
	  2. Right-click the Script -> "Save as Local Plugin..." -> name it "FPS Doctor".
	  (Or save this file into your Studio Plugins folder as FPSDoctor.lua)

	Features:
	  - Collision & Performance Auditor (scans Workspace or your Selection)
	  - One-Click Fix (CanTouch / CanQuery / CanCollide / CollisionFidelity / CastShadow)
	  - Heatmap Visualizer (green = safe, red = heavy)
	  - Shadow Optimizer (disables CastShadow on small parts)

	Safety:
	  - Every fix is wrapped in ChangeHistory, so Ctrl+Z undoes it in one step.
	  - Parts are treated as "decorative" only if Anchored AND not interactive.
	  - Interactive = Seats, SpawnLocations, parts with ClickDetector / ProximityPrompt /
	    Scripts, anything inside a Humanoid model / Tool, or inside a Model that directly
	    contains a Script.
	  - To protect any object from FPS Doctor, add the tag "FPSDoctor_Ignore" or set the
	    attribute FPSDoctorIgnore = true on it (or on any of its ancestors).
]]

if not plugin then
	return
end

local CoreGui = game:GetService("CoreGui")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local CONFIG = {
	-- Upload your logo (FPSDocotr.jpg) as an Image on create.roblox.com, then paste the
	-- asset id here, e.g. "rbxassetid://1234567890". Leave "" to use the built-in drawn logo.
	LOGO_IMAGE = "",
	TOOLBAR_ICON = "", -- same idea, used for the toolbar button
	IGNORE_TAG = "FPSDoctor_Ignore",
	IGNORE_ATTRIBUTE = "FPSDoctorIgnore",
	MAX_ROWS = 100,
	MAX_HEAT_ADORNMENTS = 3000,
	DEFAULT_KEYWORDS = "leaf, leaves, grass, bush, rock, stone, pebble, tree, flower, plant, foliage, deco, decor, prop, debris, fern, branch, petal, weed, mushroom",
}

local C = {
	bg = Color3.fromRGB(24, 25, 31),
	panel = Color3.fromRGB(33, 35, 43),
	panel2 = Color3.fromRGB(44, 47, 58),
	text = Color3.fromRGB(235, 238, 245),
	sub = Color3.fromRGB(146, 153, 170),
	green = Color3.fromRGB(22, 245, 160),
	greenDark = Color3.fromRGB(14, 150, 100),
	yellow = Color3.fromRGB(255, 210, 60),
	red = Color3.fromRGB(255, 82, 82),
}

local FIDELITY_WEIGHT = {
	[Enum.CollisionFidelity.Box] = 1,
	[Enum.CollisionFidelity.Hull] = 3,
	[Enum.CollisionFidelity.Default] = 6,
	[Enum.CollisionFidelity.PreciseConvexDecomposition] = 10,
}

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local scope = "Workspace" -- or "Selection"
local busy = false
local records = {} -- parts with issues (sorted)
local meshHeat = {} -- {part, score} for MeshParts / Unions
local heatActive = false
local heatFolder = nil

-- leftover from a crashed session
local old = CoreGui:FindFirstChild("FPSDoctor_Heatmap")
if old then
	old:Destroy()
end

------------------------------------------------------------------------
-- UI HELPERS
------------------------------------------------------------------------
local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(inst, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
end

local function padding(inst, p)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, p),
		PaddingRight = UDim.new(0, p),
		PaddingTop = UDim.new(0, p),
		PaddingBottom = UDim.new(0, p),
	}, inst)
end

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function makeLabel(parent, text, size, color, bold)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		TextColor3 = color,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 6),
		LayoutOrder = nextOrder(),
	}, parent)
end

local function makeButton(parent, text, color, textColor, callback)
	local btn = new("TextButton", {
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = textColor,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = nextOrder(),
	}, parent)
	corner(btn, 6)
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.12)
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = color
	end)
	btn.MouseButton1Click:Connect(callback)
	return btn
end

local function makeToggle(parent, title, sub, default)
	local state = default
	local row = new("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = nextOrder(),
	}, parent)
	local box = new("Frame", {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(0, 10),
		BackgroundColor3 = C.panel2,
	}, row)
	corner(box, 4)
	local tick = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "✓",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextColor3 = C.bg,
	}, box)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(28, 2),
		Size = UDim2.new(1, -28, 0, 16),
		Text = title,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(28, 19),
		Size = UDim2.new(1, -28, 0, 14),
		Text = sub,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local function refresh()
		box.BackgroundColor3 = state and C.green or C.panel2
		tick.Visible = state
	end
	refresh()
	row.MouseButton1Click:Connect(function()
		state = not state
		refresh()
	end)
	return {
		get = function()
			return state
		end,
	}
end

local function makeInput(parent, title, default, width)
	local row = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = nextOrder(),
	}, parent)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(width + 8), 1, 0),
		Text = title,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local box = new("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(width, 24),
		BackgroundColor3 = C.panel2,
		Text = default,
		TextSize = 12,
		Font = Enum.Font.Gotham,
		TextColor3 = C.text,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	corner(box, 5)
	return box
end

local function makePanel(parent, titleText)
	local panel = new("Frame", {
		BackgroundColor3 = C.panel,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = nextOrder(),
	}, parent)
	corner(panel, 8)
	padding(panel, 10)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	if titleText then
		makeLabel(panel, titleText, 13, C.green, true)
	end
	return panel
end

local function drawLine(parent, a, b, thickness, color, z)
	local d = b - a
	local mid = (a + b) / 2
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(mid.X, mid.Y),
		Size = UDim2.fromOffset(d.Magnitude + thickness * 0.5, thickness),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	corner(f, thickness)
	return f
end

local function buildLogo(parent)
	if CONFIG.LOGO_IMAGE ~= "" then
		local img = new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = CONFIG.LOGO_IMAGE,
			Size = UDim2.fromOffset(46, 46),
		}, parent)
		corner(img, 10)
		return img
	end
	local box = new("Frame", {
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Color3.fromRGB(26, 27, 33),
	}, parent)
	corner(box, 11)
	local function rect(x, y, w, h, col, z)
		local f = new("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = col,
			BorderSizePixel = 0,
			ZIndex = z,
		}, box)
		corner(f, 3)
	end
	-- green outlined cross
	rect(16, 5, 14, 36, C.green, 1)
	rect(5, 16, 36, 14, C.green, 1)
	rect(18, 7, 10, 32, Color3.fromRGB(26, 27, 33), 2)
	rect(7, 18, 32, 10, Color3.fromRGB(26, 27, 33), 2)
	-- white heartbeat line
	local pts = {
		Vector2.new(3, 24), Vector2.new(15, 24), Vector2.new(18, 20), Vector2.new(21, 28),
		Vector2.new(24, 12), Vector2.new(28, 34), Vector2.new(31, 22), Vector2.new(33, 27),
		Vector2.new(35, 24), Vector2.new(43, 24),
	}
	for i = 1, #pts - 1 do
		drawLine(box, pts[i], pts[i + 1], 2, Color3.new(1, 1, 1), 3)
	end
	return box
end

------------------------------------------------------------------------
-- WIDGET
------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("FPS Doctor")
local toggleButton = toolbar:CreateButton("FPSDoctorToggle", "Open FPS Doctor", CONFIG.TOOLBAR_ICON, "FPS Doctor")
toggleButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"FPSDoctorWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 380, 700, 330, 420)
)
widget.Title = "FPS Doctor"
widget.Name = "FPSDoctor"

local page = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, widget)
padding(page, 10)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)

-- Header
local header = new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 50),
	LayoutOrder = nextOrder(),
}, page)
buildLogo(header)
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(56, 2),
	Size = UDim2.new(1, -56, 0, 26),
	Text = "FPS Doctor",
	TextSize = 22,
	Font = Enum.Font.GothamBold,
	TextColor3 = C.green,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(56, 28),
	Size = UDim2.new(1, -56, 0, 16),
	Text = "Smart Collision & Performance Auditor",
	TextSize = 12,
	Font = Enum.Font.Gotham,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

-- Scope selector
local scopeRow = new("Frame", {
	BackgroundColor3 = C.panel,
	Size = UDim2.new(1, 0, 0, 34),
	LayoutOrder = nextOrder(),
}, page)
corner(scopeRow, 8)
padding(scopeRow, 3)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, scopeRow)
local scopeButtons = {}
local function refreshScope()
	for name, b in pairs(scopeButtons) do
		local on = name == scope
		b.BackgroundColor3 = on and C.green or C.panel
		b.TextColor3 = on and C.bg or C.sub
	end
end
for i, name in ipairs({ "Workspace", "Selection" }) do
	local b = new("TextButton", {
		Text = name == "Workspace" and "Entire Workspace" or "Current Selection",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		AutoButtonColor = false,
		Size = UDim2.new(0.5, -2, 1, 0),
		BackgroundColor3 = C.panel,
		TextColor3 = C.sub,
		LayoutOrder = i,
	}, scopeRow)
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		scope = name
		refreshScope()
	end)
	scopeButtons[name] = b
end
refreshScope()

-- Forward declarations
local runScan, applyFixes, toggleHeatmap, optimizeShadows

makeButton(page, "SCAN", C.green, C.bg, function()
	runScan()
end)

-- Summary cards
local summary = new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 62),
	LayoutOrder = nextOrder(),
}, page)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, summary)
local function makeCard(title, idx)
	local card = new("Frame", {
		BackgroundColor3 = C.panel,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		LayoutOrder = idx,
	}, summary)
	corner(card, 8)
	local value = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 28),
		Text = "-",
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		TextColor3 = C.text,
	}, card)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 16),
		Text = title,
		TextSize = 11,
		Font = Enum.Font.Gotham,
		TextColor3 = C.sub,
	}, card)
	return value
end
local healthValue = makeCard("Health Score", 1)
local scannedValue = makeCard("Parts Scanned", 2)
local issuesValue = makeCard("Parts With Issues", 3)

local breakdown = makeLabel(page, "Run a scan to see the breakdown.", 11, C.sub, false)
breakdown.TextWrapped = true
breakdown.Size = UDim2.new(1, 0, 0, 30)
breakdown.TextYAlignment = Enum.TextYAlignment.Top

-- Fix options
local fixPanel = makePanel(page, "ONE-CLICK FIX OPTIONS")
local tgTouch = makeToggle(fixPanel, "Disable CanTouch", "On decorative parts (leaves, grass, rocks...)", true)
local tgQuery = makeToggle(fixPanel, "Disable CanQuery", "On decorative parts - stops raycast / spatial queries", true)
local tgCollide = makeToggle(fixPanel, "Disable CanCollide on tiny decor", "Only decor smaller than the size below", false)
local tgFidelity = makeToggle(fixPanel, "Set CollisionFidelity to Box", "Decorative MeshParts / Unions with heavy collision", true)
local tgShadow = makeToggle(fixPanel, "Disable CastShadow on small parts", "Any part smaller than the shadow threshold", true)
local inSmall = makeInput(fixPanel, "Tiny decor size (max stud dimension)", "2", 60)
local inShadow = makeInput(fixPanel, "Shadow threshold (max stud dimension)", "3", 60)
local inKeywords = makeInput(fixPanel, "Decor keywords (comma separated)", CONFIG.DEFAULT_KEYWORDS, 170)

makeButton(page, "ONE-CLICK FIX", C.yellow, C.bg, function()
	applyFixes()
end)

-- Heatmap
local heatPanel = makePanel(page, "HEATMAP VISUALIZER")
local heatNote = makeLabel(heatPanel, "Colors MeshParts by estimated collision load.", 11, C.sub, false)
heatNote.TextWrapped = true
heatNote.Size = UDim2.new(1, 0, 0, 28)
local legend = new("Frame", {
	Size = UDim2.new(1, 0, 0, 10),
	BackgroundColor3 = Color3.new(1, 1, 1),
	LayoutOrder = nextOrder(),
}, heatPanel)
corner(legend, 5)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 230, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 210, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 60)),
	}),
}, legend)
local legendLabels = new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 14),
	LayoutOrder = nextOrder(),
}, heatPanel)
new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(0.5, 1),
	Text = "Safe",
	TextSize = 11,
	Font = Enum.Font.Gotham,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Left,
}, legendLabels)
new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.5, 1),
	Text = "Heavy",
	TextSize = 11,
	Font = Enum.Font.Gotham,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Right,
}, legendLabels)
local heatButton = makeButton(heatPanel, "SHOW HEATMAP", C.panel2, C.text, function()
	toggleHeatmap()
end)

-- Shadow optimizer
local shadowPanel = makePanel(page, "SHADOW OPTIMIZER")
local shadowNote = makeLabel(shadowPanel, "Instantly disables CastShadow on every part below the shadow threshold (uses the scope above).", 11, C.sub, false)
shadowNote.TextWrapped = true
shadowNote.Size = UDim2.new(1, 0, 0, 40)
shadowNote.TextYAlignment = Enum.TextYAlignment.Top
makeButton(shadowPanel, "OPTIMIZE SHADOWS", C.greenDark, C.text, function()
	optimizeShadows()
end)

-- Status
local statusLabel = makeLabel(page, "Ready.", 12, C.sub, false)
statusLabel.TextWrapped = true
statusLabel.Size = UDim2.new(1, 0, 0, 34)
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or C.sub
end

-- Results
makeLabel(page, "HEAVIEST OBJECTS", 13, C.green, true)
local resultsFrame = new("Frame", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	Size = UDim2.new(1, 0, 0, 0),
	LayoutOrder = nextOrder(),
}, page)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, resultsFrame)

------------------------------------------------------------------------
-- ANALYSIS
------------------------------------------------------------------------
local function maxDim(p)
	local s = p.Size
	return math.max(s.X, s.Y, s.Z)
end

local function parseKeywords(text)
	local list = {}
	for word in string.gmatch(string.lower(text), "[^,]+") do
		word = word:gsub("^%s+", ""):gsub("%s+$", "")
		if word ~= "" then
			table.insert(list, word)
		end
	end
	return list
end

local function makeCtx()
	return {
		smallSize = tonumber(inSmall.Text) or 2,
		shadowSize = tonumber(inShadow.Text) or 3,
		keywords = parseKeywords(inKeywords.Text),
		cache = {},
	}
end

local function isIgnored(inst)
	return CollectionService:HasTag(inst, CONFIG.IGNORE_TAG) or inst:GetAttribute(CONFIG.IGNORE_ATTRIBUTE) == true
end

local function ancestorInteractive(part, ctx)
	local cache = ctx.cache
	local chain = {}
	local result = false
	local cur = part.Parent
	while cur and cur ~= workspace and cur ~= game do
		local cached = cache[cur]
		if cached ~= nil then
			result = cached
			break
		end
		table.insert(chain, cur)
		if
			isIgnored(cur)
			or cur:IsA("Tool")
			or cur:IsA("Accessory")
			or (cur:IsA("Model") and (cur:FindFirstChildOfClass("Humanoid") or cur:FindFirstChildWhichIsA("BaseScript")))
		then
			result = true
			break
		end
		cur = cur.Parent
	end
	for _, c in ipairs(chain) do
		cache[c] = result
	end
	return result
end

local function isInteractive(part, ctx)
	if part:IsA("Seat") or part:IsA("VehicleSeat") or part:IsA("SpawnLocation") then
		return true
	end
	if isIgnored(part) then
		return true
	end
	for _, child in ipairs(part:GetChildren()) do
		if
			child:IsA("ClickDetector")
			or child:IsA("ProximityPrompt")
			or child:IsA("BaseScript")
			or child:IsA("TouchTransmitter")
			or child:IsA("DragDetector")
		then
			return true
		end
	end
	return ancestorInteractive(part, ctx)
end

local function nameMatches(part, ctx)
	local n = string.lower(part.Name)
	local pn = part.Parent and string.lower(part.Parent.Name) or ""
	for _, kw in ipairs(ctx.keywords) do
		if string.find(n, kw, 1, true) or string.find(pn, kw, 1, true) then
			return true
		end
	end
	return false
end

local function isDecor(part, ctx)
	if not part.Anchored then
		return false
	end
	if isInteractive(part, ctx) then
		return false
	end
	if nameMatches(part, ctx) then
		return true
	end
	-- invisible + non-colliding parts are probably trigger zones / hitboxes: leave them alone
	if part.Transparency >= 1 and not part.CanCollide then
		return false
	end
	if not part.CanCollide then
		return true
	end
	return maxDim(part) <= ctx.smallSize
end

local function analyze(part, ctx)
	local isMesh = part:IsA("MeshPart") or part:IsA("UnionOperation")
	local fidelity = isMesh and part.CollisionFidelity or nil
	local md = maxDim(part)
	local decor = isDecor(part, ctx)

	local issues = {}
	local tags = {}
	local count = 0
	local function flag(key, tag)
		issues[key] = true
		table.insert(tags, tag)
		count += 1
	end

	if decor then
		if part.CanTouch then
			flag("touch", "CanTouch")
		end
		if part.CanQuery then
			flag("query", "CanQuery")
		end
		if part.CanCollide and md <= ctx.smallSize then
			flag("collide", "CanCollide")
		end
		if isMesh and fidelity ~= Enum.CollisionFidelity.Box then
			flag("fidelity", "Fidelity:" .. fidelity.Name)
		end
	end
	if part.CastShadow and md < ctx.shadowSize then
		flag("shadow", "CastShadow")
	end

	local heavy = false
	if isMesh and not decor and fidelity == Enum.CollisionFidelity.PreciseConvexDecomposition then
		heavy = true
		table.insert(tags, "Precise collision")
	end

	-- Estimated collision load (heuristic): fidelity weight x active collision flags
	local fw = fidelity and FIDELITY_WEIGHT[fidelity] or 1
	local active = (part.CanCollide and 1 or 0) + (part.CanTouch and 0.5 or 0) + (part.CanQuery and 0.5 or 0)
	local raw = fw * (0.5 + active) + count * 0.75
	local score = math.clamp(math.floor(raw / 20 * 100 + 0.5), 0, 100)

	return {
		part = part,
		issues = issues,
		count = count,
		score = score,
		isMesh = isMesh,
		heavy = heavy,
		tags = tags,
		decor = decor,
	}
end

------------------------------------------------------------------------
-- SCAN
------------------------------------------------------------------------
local function gatherRoots()
	if scope == "Selection" then
		return Selection:Get()
	end
	return { workspace }
end

local function forEachPart(roots, fn)
	local seen = {}
	local n = 0
	for _, root in ipairs(roots) do
		local list = root:GetDescendants()
		table.insert(list, root)
		for _, inst in ipairs(list) do
			if not seen[inst] then
				seen[inst] = true
				if inst:IsA("BasePart") and not inst:IsA("Terrain") then
					fn(inst)
				end
			end
			n += 1
			if n % 1500 == 0 then
				task.wait()
			end
		end
	end
end

local function healthColor(h)
	if h >= 85 then
		return C.green
	elseif h >= 60 then
		return C.yellow
	end
	return C.red
end

local function heatColor(t)
	local g, y, r = Color3.fromRGB(46, 230, 120), Color3.fromRGB(255, 210, 60), Color3.fromRGB(255, 60, 60)
	if t < 0.5 then
		return g:Lerp(y, t * 2)
	end
	return y:Lerp(r, (t - 0.5) * 2)
end

local function renderResults()
	for _, c in ipairs(resultsFrame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if #records == 0 then
		local l = makeLabel(resultsFrame, "No issues found. Your game looks healthy.", 12, C.sub, false)
		l.LayoutOrder = 1
		return
	end
	local shown = math.min(#records, CONFIG.MAX_ROWS)
	for i = 1, shown do
		local rec = records[i]
		local row = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.panel,
			Size = UDim2.new(1, 0, 0, 46),
			LayoutOrder = i,
		}, resultsFrame)
		corner(row, 6)
		local parentName = rec.part.Parent and rec.part.Parent.Name or "?"
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -56, 0, 18),
			Text = parentName .. "  >  " .. rec.part.Name,
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 24),
			Size = UDim2.new(1, -56, 0, 16),
			Text = rec.part.ClassName .. "  |  " .. table.concat(rec.tags, ", "),
			TextSize = 10,
			Font = Enum.Font.Gotham,
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
		new("TextLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(40, 24),
			Text = tostring(rec.score),
			TextSize = 18,
			Font = Enum.Font.GothamBold,
			TextColor3 = heatColor(rec.score / 100),
		}, row)
		row.MouseEnter:Connect(function()
			row.BackgroundColor3 = C.panel2
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundColor3 = C.panel
		end)
		row.MouseButton1Click:Connect(function()
			if rec.part and rec.part.Parent then
				Selection:Set({ rec.part })
			end
		end)
	end
	if #records > shown then
		local l = makeLabel(resultsFrame, ("Showing top %d of %d. Fix or re-scan to see more."):format(shown, #records), 11, C.sub, false)
		l.LayoutOrder = shown + 1
	end
end

local function clearHeatmap()
	if heatFolder then
		heatFolder:Destroy()
		heatFolder = nil
	end
	heatActive = false
	heatButton.Text = "SHOW HEATMAP"
	heatButton.BackgroundColor3 = C.panel2
end

local function drawHeatmap()
	if heatFolder then
		heatFolder:Destroy()
	end
	heatFolder = new("Folder", { Name = "FPSDoctor_Heatmap" }, CoreGui)
	table.sort(meshHeat, function(a, b)
		return a.score > b.score
	end)
	local limit = math.min(#meshHeat, CONFIG.MAX_HEAT_ADORNMENTS)
	for i = 1, limit do
		local e = meshHeat[i]
		if e.part and e.part.Parent then
			new("BoxHandleAdornment", {
				Adornee = e.part,
				Size = e.part.Size + Vector3.new(0.05, 0.05, 0.05),
				Color3 = heatColor(e.score / 100),
				Transparency = 0.35,
				AlwaysOnTop = false,
				ZIndex = 1,
			}, heatFolder)
		end
		if i % 300 == 0 then
			task.wait()
		end
	end
	heatActive = true
	heatButton.Text = "HIDE HEATMAP"
	heatButton.BackgroundColor3 = C.red
	if #meshHeat > limit then
		setStatus(("Heatmap: showing the heaviest %d of %d MeshParts."):format(limit, #meshHeat), C.yellow)
	elseif #meshHeat == 0 then
		setStatus("Heatmap: no MeshParts / Unions found in this scope.", C.yellow)
	else
		setStatus(("Heatmap: %d MeshParts colored. Scores are estimates based on collision settings."):format(#meshHeat), C.green)
	end
end

function runScan()
	if busy then
		return
	end
	local roots = gatherRoots()
	if #roots == 0 then
		setStatus("Nothing selected. Select objects in Studio or switch to Entire Workspace.", C.yellow)
		return
	end
	busy = true
	setStatus("Scanning...", C.yellow)
	task.wait()

	local ctx = makeCtx()
	local newRecords, newHeat = {}, {}
	local total, flagged = 0, 0
	local counts = { touch = 0, query = 0, collide = 0, fidelity = 0, shadow = 0, precise = 0 }

	forEachPart(roots, function(p)
		total += 1
		local rec = analyze(p, ctx)
		if rec.count > 0 or rec.heavy then
			flagged += 1
			table.insert(newRecords, rec)
			for k in pairs(rec.issues) do
				counts[k] += 1
			end
			if rec.heavy then
				counts.precise += 1
			end
		end
		if rec.isMesh then
			table.insert(newHeat, { part = p, score = rec.score })
		end
	end)

	table.sort(newRecords, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.count > b.count
	end)
	records, meshHeat = newRecords, newHeat

	local health = total > 0 and math.floor(100 * (1 - flagged / total) + 0.5) or 100
	healthValue.Text = health .. "%"
	healthValue.TextColor3 = healthColor(health)
	scannedValue.Text = tostring(total)
	issuesValue.Text = tostring(flagged)
	breakdown.Text = ("CanTouch: %d  |  CanQuery: %d  |  CanCollide: %d\nFidelity: %d  |  CastShadow: %d  |  Precise (info): %d"):format(
		counts.touch, counts.query, counts.collide, counts.fidelity, counts.shadow, counts.precise
	)
	renderResults()
	busy = false
	setStatus(("Scan complete: %d parts scanned, %d with issues."):format(total, flagged), flagged == 0 and C.green or C.text)

	if heatActive then
		drawHeatmap()
	end
end

------------------------------------------------------------------------
-- FIXES (undoable)
------------------------------------------------------------------------
local function beginRec(name)
	local ok, id = pcall(function()
		return ChangeHistoryService:TryBeginRecording(name)
	end)
	if ok and id then
		return id
	end
	return nil
end

local function endRec(id, name)
	if id then
		pcall(function()
			ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
		end)
	else
		ChangeHistoryService:SetWaypoint(name)
	end
end

local function setProp(part, prop, value)
	local ok = pcall(function()
		part[prop] = value
	end)
	return ok
end

function applyFixes()
	if busy then
		return
	end
	if #records == 0 then
		setStatus("Nothing to fix. Run a scan first.", C.yellow)
		return
	end
	busy = true
	setStatus("Applying fixes...", C.yellow)
	local recId = beginRec("FPS Doctor - One-Click Fix")

	local opts = {
		touch = tgTouch.get(),
		query = tgQuery.get(),
		collide = tgCollide.get(),
		fidelity = tgFidelity.get(),
		shadow = tgShadow.get(),
	}
	local changes, partsChanged = 0, 0

	for i, rec in ipairs(records) do
		local p = rec.part
		if p and p.Parent then
			local did = false
			local function apply(key, prop, value)
				if opts[key] and rec.issues[key] and setProp(p, prop, value) then
					changes += 1
					did = true
				end
			end
			apply("touch", "CanTouch", false)
			apply("query", "CanQuery", false)
			apply("collide", "CanCollide", false)
			apply("fidelity", "CollisionFidelity", Enum.CollisionFidelity.Box)
			apply("shadow", "CastShadow", false)
			if did then
				partsChanged += 1
			end
		end
		if i % 500 == 0 then
			task.wait()
		end
	end

	endRec(recId, "FPS Doctor - One-Click Fix")
	busy = false
	setStatus(("Fixed %d properties on %d parts. Press Ctrl+Z to undo."):format(changes, partsChanged), C.green)
	runScan()
end

function optimizeShadows()
	if busy then
		return
	end
	local roots = gatherRoots()
	if #roots == 0 then
		setStatus("Nothing selected. Select objects in Studio or switch to Entire Workspace.", C.yellow)
		return
	end
	busy = true
	setStatus("Optimizing shadows...", C.yellow)
	local recId = beginRec("FPS Doctor - Shadow Optimizer")
	local threshold = tonumber(inShadow.Text) or 3
	local n = 0
	forEachPart(roots, function(p)
		if p.CastShadow and maxDim(p) < threshold and setProp(p, "CastShadow", false) then
			n += 1
		end
	end)
	endRec(recId, "FPS Doctor - Shadow Optimizer")
	busy = false
	setStatus(("Shadow Optimizer: disabled CastShadow on %d parts. Press Ctrl+Z to undo."):format(n), C.green)
	if #records > 0 then
		runScan()
	end
end

function toggleHeatmap()
	if busy then
		return
	end
	if heatActive then
		clearHeatmap()
		setStatus("Heatmap hidden.", C.sub)
		return
	end
	if #meshHeat == 0 then
		heatActive = true -- runScan will draw it when finished
		runScan()
		if #meshHeat == 0 and heatActive and not heatFolder then
			heatActive = false
		end
	else
		drawHeatmap()
	end
end

------------------------------------------------------------------------
-- WIRING
------------------------------------------------------------------------
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
	if not widget.Enabled then
		clearHeatmap()
	end
end)
plugin.Unloading:Connect(function()
	clearHeatmap()
end)

renderResults()
