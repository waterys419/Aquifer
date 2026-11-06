-- Waterys Satchel: one combined bag as a plain grid, with explicit controller neighbors. (was GridBag)
local addonName = ...
local GB = {}
_G.WaterysSatchel = GB

local DEFAULTS = { enabled = true, columns = 8, scale = 1, padNav = true }
local MM_DEFAULT = { angle = 215, hide = false }
local ICON = "Interface\\Icons\\INV_Drink_06"
local SLOT, GAP, PAD, TOP, BOTTOM = 37, 4, 8, 50, 24
local MAXSLOT = 200

-- ---------- pure layout helpers (tested offline) ----------

-- Bag 0 slot 1 first, then bag 1, ... Only one flat list, no per-bag sections.
function GB.BuildOrder(sizes)
    local order = {}
    for bag = 0, (sizes.n or #sizes) do
        for slot = 1, (sizes[bag] or 0) do order[#order + 1] = { bag, slot } end
    end
    return order
end

-- Explicit neighbors for slot index i in a grid of n slots and cols columns.
-- Left/right wrap to the previous/next row. Up/down wrap top <-> bottom.
function GB.Neighbors(n, cols)
    local nb = { left = {}, right = {}, up = {}, down = {} }
    if n < 1 then return nb end
    cols = math.max(1, cols)
    local lastRow = math.floor((n - 1) / cols)
    for i = 1, n do
        local r, c = math.floor((i - 1) / cols), (i - 1) % cols
        nb.right[i] = (i < n) and (i + 1) or 1
        nb.left[i] = (i > 1) and (i - 1) or n
        local d = i + cols
        if d <= n then nb.down[i] = d
        elseif r < lastRow then nb.down[i] = n
        else nb.down[i] = c + 1 end
        local u = i - cols
        if u >= 1 then nb.up[i] = u
        elseif lastRow == 0 then nb.up[i] = i
        else
            u = lastRow * cols + c + 1
            if u > n then u = u - cols end
            nb.up[i] = u
        end
    end
    return nb
end

function GB.Position(i, cols)
    local r, c = math.floor((i - 1) / cols), (i - 1) % cols
    return PAD + c * (SLOT + GAP), -(TOP + r * (SLOT + GAP))
end

-- Minimap button offset from the minimap centre for an angle in degrees.
function GB.MinimapOffset(angle, radius)
    local a = math.rad(angle)
    radius = radius or 80
    return math.cos(a) * radius, math.sin(a) * radius
end
function GB.AngleFromCursor(dx, dy) return math.deg(math.atan2(dy, dx)) % 360 end

function GB.MoneyText(c)
    c = c or 0
    local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r", g, sv, cp)
end

-- Search: empty query matches everything.
function GB.Matches(name, query)
    if not query or query == "" then return true end
    return name ~= nil and name:lower():find(query:lower(), 1, true) ~= nil
end

-- ---------- state ----------
local frame, nav, hl, title, moneyText, search, mmButton, settings
local query = ""
local freeText
local slots = {}
local order, shownCount = {}, 0
local pending = false
local DB

local function bagSize(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function itemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local t = C_Container.GetContainerItemInfo(bag, slot)
        if not t then return end
        return t.iconFileID, t.stackCount, t.quality, t.isLocked, t.hyperlink
    end
    if GetContainerItemInfo then
        local icon, count, locked, quality, _, _, link = GetContainerItemInfo(bag, slot)
        return icon, count, quality, locked, link
    end
end
local function cooldown(bag, slot)
    if C_Container and C_Container.GetContainerItemCooldown then return C_Container.GetContainerItemCooldown(bag, slot) end
    if GetContainerItemCooldown then return GetContainerItemCooldown(bag, slot) end
end
local function pickup(bag, slot)
    if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(bag, slot)
    else PickupContainerItem(bag, slot) end
end
local function qualityColor(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function inCombat() return InCombatLockdown() end

-- ---------- slots ----------
local function makeSlot(i)
    local b = CreateFrame("Button", "WaterysSatchelSlot" .. i, frame, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(SLOT, SLOT)
    b:RegisterForClicks("AnyUp")
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    b:SetBackdropColor(0.04, 0.12, 0.2, 0.85)
    b:SetBackdropBorderColor(0.16, 0.34, 0.48, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.cd = CreateFrame("Cooldown", "WaterysSatchelCD" .. i, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.index = i
    -- Right click uses the item (secure, works in combat). Left click picks up / drops.
    b:SetAttribute("type2", "item")
    b:SetScript("PostClick", function(self, button)
        if button == "LeftButton" and self.bag then pickup(self.bag, self.slot) end
    end)
    b:SetScript("OnEnter", function(self)
        if self.bag then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.bag, self.slot) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    slots[i] = b
    nav:SetFrameRef("s" .. i, b)
    return b
end

local EMPTY_BORDER = { 0.16, 0.34, 0.48 }
local function refreshSlot(b)
    if not b.bag then return end
    local icon, count, quality, locked, link = itemInfo(b.bag, b.slot)
    local dim = false
    if icon then
        b.icon:SetTexture(icon)
        b.count:SetText((count and count > 1) and count or "")
        if quality and quality >= 1 then
            local r, g, bl = qualityColor(quality)
            b:SetBackdropBorderColor(r, g, bl, 1)
        else b:SetBackdropBorderColor(EMPTY_BORDER[1], EMPTY_BORDER[2], EMPTY_BORDER[3], 1) end
        if query ~= "" then
            local name = link and GetItemInfo and GetItemInfo(link)
            dim = not GB.Matches(name, query)
        end
        local start, dur, en = cooldown(b.bag, b.slot)
        if start and dur and dur > 0 and (en == nil or en == 1 or en == true) then b.cd:SetCooldown(start, dur)
        else b.cd:SetCooldown(0, 0) end
    else
        b.icon:SetTexture(nil); b.count:SetText("")
        b:SetBackdropBorderColor(EMPTY_BORDER[1], EMPTY_BORDER[2], EMPTY_BORDER[3], 1)
        b.cd:SetCooldown(0, 0)
    end
    b.icon:SetDesaturated((locked or dim) and true or false)
    b:SetAlpha(dim and 0.35 or 1)
end

function GB.SetQuery(q) query = (q or ""):match("^%s*(.-)%s*$"); GB.Refresh() end

function GB.Refresh()
    if not frame then return end
    local free = 0
    for i = 1, shownCount do
        refreshSlot(slots[i])
        if not itemInfo(slots[i].bag, slots[i].slot) then free = free + 1 end
    end
    GB.free = free
    freeText:SetText(free .. "/" .. shownCount .. " free")
    moneyText:SetText(GB.MoneyText(GetMoney and GetMoney() or 0))
end

local function currentSizes()
    local sizes = {}
    local top = tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, top do sizes[bag] = bagSize(bag) end
    sizes.n = top
    return sizes
end

local NAV_SETUP = [[
local nav = self
nav:SetAttribute("focus", 1)
local b = nav:GetFrameRef("s1")
local hl = nav:GetFrameRef("hl")
if b and hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER"); hl:Show() end
nav:ClearBindings()
if nav:GetAttribute("padnav") == 1 then
  nav:SetBindingClick(true, "PADDUP", nav:GetFrameRef("up"), "LeftButton")
  nav:SetBindingClick(true, "PADDDOWN", nav:GetFrameRef("down"), "LeftButton")
  nav:SetBindingClick(true, "PADDLEFT", nav:GetFrameRef("left"), "LeftButton")
  nav:SetBindingClick(true, "PADDRIGHT", nav:GetFrameRef("right"), "LeftButton")
  if b then
    nav:SetBindingClick(true, "PAD1", b, "RightButton")
    nav:SetBindingClick(true, "PAD3", b, "LeftButton")
  end
end
]]
-- Run when a d-pad button is pressed. Moves focus using the stored neighbor table.
local NAV_MOVE = [[
if down then return end -- belt and braces: never move on the key-down click
local nav = self:GetFrameRef("nav")
local dir = self:GetAttribute("dir")
local f = nav:GetAttribute("focus") or 1
local t = nav:GetAttribute(dir .. f) or f
nav:SetAttribute("focus", t)
local b = nav:GetFrameRef("s" .. t)
local hl = nav:GetFrameRef("hl")
if b and hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER"); hl:Show() end
if b then
  nav:SetBindingClick(true, "PAD1", b, "RightButton")
  nav:SetBindingClick(true, "PAD3", b, "LeftButton")
end
]]
GB.NAV_SETUP, GB.NAV_MOVE = NAV_SETUP, NAV_MOVE

function GB.Layout()
    if inCombat() then pending = true; return end
    pending = false
    order = GB.BuildOrder(currentSizes())
    local n = math.min(#order, MAXSLOT)
    local cols = math.max(1, math.min(DB.columns, 20))
    for i = 1, n do
        local b = slots[i] or makeSlot(i)
        local x, y = GB.Position(i, cols)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        b.bag, b.slot = order[i][1], order[i][2]
        b:SetAttribute("item2", b.bag .. " " .. b.slot)
        b:Show()
    end
    for i = n + 1, #slots do slots[i]:Hide(); slots[i].bag = nil; slots[i]:SetAttribute("item2", nil) end
    shownCount = n
    local rows = math.max(1, math.ceil(n / cols))
    frame:SetSize(PAD * 2 + cols * SLOT + (cols - 1) * GAP, TOP + BOTTOM + rows * SLOT + (rows - 1) * GAP)
    local nb = GB.Neighbors(n, cols)
    for _, d in ipairs({ "left", "right", "up", "down" }) do
        for i = 1, n do nav:SetAttribute(d .. i, nb[d][i]) end
    end
    nav:SetAttribute("count", n)
    nav:SetAttribute("padnav", DB.padNav and 1 or 0)
    GB.Refresh()
end

-- ---------- window ----------
function GB.IsOpen() return frame and frame:IsShown() end

local function savePos()
    local p, _, rp, x, y = frame:GetPoint()
    DB.point = { p, rp, x, y }
end

function GB.Open()
    if not frame or not DB.enabled then return end
    if inCombat() then return end
    GB.Layout()
    frame:Show()
    SecureHandlerExecute(nav, NAV_SETUP)
end
function GB.Close()
    if not frame or inCombat() then return end
    frame:Hide()
end
function GB.Toggle() if GB.IsOpen() then GB.Close() else GB.Open() end end

local function build()
    frame = CreateFrame("Frame", "WaterysSatchelFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    frame:SetBackdropColor(0.02, 0.09, 0.15, 0.94)
    frame:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    frame:SetScale(DB.scale)
    local p = DB.point
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120) end
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetText("|cff55ccffWaterys Satchel|r")
    freeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("TOPRIGHT", -PAD, -10)
    moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyText:SetPoint("BOTTOMRIGHT", -PAD, 8)
    -- Search box. Only reachable by mouse/cursor click: the d-pad grid never lands on it.
    search = CreateFrame("EditBox", "WaterysSatchelSearch", frame, "InputBoxTemplate")
    search:SetSize(110, 18)
    search:SetPoint("TOPLEFT", PAD + 62, -6)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(self) GB.SetQuery(self:GetText()) end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame:SetScript("OnDragStart", function(self)
        if not inCombat() and IsAltKeyDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    frame:Hide()
    tinsert(UISpecialFrames, "WaterysSatchelFrame")

    nav = CreateFrame("Frame", "WaterysSatchelNav", frame, "SecureHandlerBaseTemplate")
    hl = CreateFrame("Frame", "WaterysSatchelFocus", frame, "BackdropTemplate")
    hl:SetSize(SLOT + 4, SLOT + 4)
    hl:SetFrameLevel(frame:GetFrameLevel() + 20)
    hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
    hl:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    hl:Hide()
    nav:SetFrameRef("hl", hl)
    for _, d in ipairs({ "up", "down", "left", "right" }) do
        local btn = CreateFrame("Button", "WaterysSatchelPad" .. d, frame, "SecureHandlerClickTemplate")
        btn:SetAttribute("dir", d)
        btn:SetFrameRef("nav", nav)
        btn:SetAttribute("_onclick", NAV_MOVE)
        -- ONE click event per press: a key bound with SetBindingClick sends a down click AND an
-- up click. Registering for both ran the move twice (two slots per press). Up only.
        btn:RegisterForClicks("AnyUp")
        nav:SetFrameRef(d, btn)
    end
    frame:SetScript("OnShow", function() GB.Refresh() end)
    frame:SetScript("OnHide", function()
        if search then search:ClearFocus() end
        if not inCombat() then SecureHandlerExecute(nav, "self:ClearBindings(); self:GetFrameRef('hl'):Hide()") end
    end)
end

-- ---------- minimap button ----------
function GB.PlaceMinimap()
    if not mmButton then return end
    local mm = DB.minimap
    if mm.hide then mmButton:Hide(); return end
    local x, y = GB.MinimapOffset(mm.angle)
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    mmButton:Show()
end

local function buildMinimap()
    if not Minimap then return end
    local b = CreateFrame("Button", "WaterysSatchelMinimapButton", Minimap)
    mmButton = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20); bg:SetPoint("CENTER", 0, 1)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetVertexColor(0.1, 0.45, 0.8, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then GB.ToggleSettings() else GB.Toggle() end
    end)
    b:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            DB.minimap.angle = GB.AngleFromCursor(cx / sc - mx, cy / sc - my)
            GB.PlaceMinimap()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Waterys Satchel")
        GameTooltip:AddLine("Left click: open / close bag", 1, 1, 1)
        GameTooltip:AddLine("Right click: settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    GB.PlaceMinimap()
end

function GB.SetMinimapHidden(h) DB.minimap.hide = h and true or false; GB.PlaceMinimap() end

-- ---------- settings window ----------
local function buildSettings()
    local f = CreateFrame("Frame", "WaterysSatchelSettings", UIParent, "BackdropTemplate")
    settings = f
    f:SetSize(220, 190); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.02, 0.09, 0.15, 0.96); f:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10); t:SetText("|cff55ccffWaterys Satchel|r settings")
    local close = CreateFrame("Button", "WaterysSatchelSettingsClose", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local function check(name, y, label, get, set)
        local c = CreateFrame("CheckButton", name, f, "UICheckButtonTemplate")
        c:SetPoint("TOPLEFT", 10, y)
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        l:SetPoint("LEFT", c, "RIGHT", 2, 0); l:SetText(label)
        c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        c.refresh = function() c:SetChecked(get()) end
        return c
    end
    f.checks = {
        check("WaterysSatchelCheckMinimap", -34, "Hide minimap icon", function() return DB.minimap.hide end, GB.SetMinimapHidden),
        check("WaterysSatchelCheckPad", -60, "Controller d-pad in bag", function() return DB.padNav end, function(v) GB.SetPad(v) end),
        check("WaterysSatchelCheckBag", -86, "Use Waterys Satchel instead of normal bag", function() return DB.enabled end, function(v) GB.SetEnabled(v) end),
    }
    local cl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cl:SetPoint("TOPLEFT", 14, -126)
    f.colText = cl
    local function colBtn(name, x, txt, d)
        local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
        b:SetSize(26, 22); b:SetPoint("TOPLEFT", x, -148); b:SetText(txt)
        b:SetScript("OnClick", function() GB.SetCols(DB.columns + d); f.refresh() end)
    end
    colBtn("WaterysSatchelColMinus", 14, "-", -1); colBtn("WaterysSatchelColPlus", 44, "+", 1)
    f.refresh = function()
        cl:SetText("Columns: " .. DB.columns)
        for _, c in ipairs(f.checks) do c.refresh() end
    end
    f:SetScript("OnShow", f.refresh)
    f:Hide()
    tinsert(UISpecialFrames, "WaterysSatchelSettings")
end
function GB.ToggleSettings()
    if not settings then return end
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

-- ---------- default bag replacement ----------
local DEFAULT_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 13 do DEFAULT_FRAMES[#DEFAULT_FRAMES + 1] = "ContainerFrame" .. i end

local function hideDefault()
    if not DB or not DB.enabled or inCombat() then return end
    for _, name in ipairs(DEFAULT_FRAMES) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
end

local function hookAll()
    local toggles = { "ToggleAllBags", "ToggleBackpack", "ToggleBag" }
    local opens = { "OpenAllBags", "OpenBackpack", "OpenBag" }
    local closes = { "CloseAllBags", "CloseBackpack", "CloseBag" }
    local function ours(fn)
        return function()
            if not DB.enabled or inCombat() then return end -- in combat the normal bag opens
            fn(); hideDefault()
        end
    end
    for _, n in ipairs(toggles) do if _G[n] then hooksecurefunc(n, ours(GB.Toggle)) end end
    for _, n in ipairs(opens) do if _G[n] then hooksecurefunc(n, ours(GB.Open)) end end
    for _, n in ipairs(closes) do if _G[n] then hooksecurefunc(n, ours(GB.Close)) end end
    for _, name in ipairs(DEFAULT_FRAMES) do
        local f = _G[name]
        if f and f.HookScript then f:HookScript("OnShow", function(self)
            if DB.enabled and not inCombat() then self:Hide() end
        end) end
    end
end

-- ---------- slash ----------
function GB.SetCols(v)
    DB.columns = math.max(4, math.min(20, math.floor(v)))
    GB.Layout()
    return DB.columns
end
function GB.SetPad(on)
    DB.padNav = on and true or false
    if frame and not inCombat() then
        nav:SetAttribute("padnav", DB.padNav and 1 or 0)
        if GB.IsOpen() then SecureHandlerExecute(nav, NAV_SETUP) end
    end
end
function GB.SetEnabled(on)
    DB.enabled = on and true or false
    if not DB.enabled and GB.IsOpen() then GB.Close() end
end

local function say(m) print("|cff66ccffWaterys Satchel|r " .. m) end
local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "help" then
        say("/satchel toggle - open or close the bag (also /ws)")
        say("/satchel settings - settings window")
        say("/satchel minimap on|off - minimap icon")
        say("/satchel search word - grey out other items")
        say("/satchel cols 8 - slots per row (4 to 20)")
        say("/satchel default on|off - on = use the normal bag again")
        say("/satchel pad on|off - controller d-pad moves in the grid")
        say("/satchel scale 1 - window size (0.5 to 2)")
        say("/satchel reset - put the window back")
        say("/satchel config - show settings")
        say("Alt + drag moves the window.")
    elseif cmd == "toggle" then GB.Toggle()
    elseif cmd == "settings" or cmd == "options" then GB.ToggleSettings()
    elseif cmd == "minimap" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /satchel minimap on  or  off") end
        GB.SetMinimapHidden(on == "off")
        say("Minimap icon: " .. (DB.minimap.hide and "hidden" or "shown"))
    elseif cmd == "search" then GB.SetQuery(arg); if search then search:SetText(arg) end
    elseif cmd == "cols" or cmd == "columns" then
        local v = tonumber(arg)
        if not v then return say("Use a number, like /satchel cols 8") end
        GB.SetCols(v); say("Columns: " .. DB.columns)
        if pending then say("In combat. Will apply after.") end
    elseif cmd == "default" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /satchel default on  or  off") end
        GB.SetEnabled(on == "off")
        say(DB.enabled and "Waterys Satchel bag is ON." or "Normal bag is back. Waterys Satchel is OFF.")
    elseif cmd == "pad" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /satchel pad on  or  off") end
        GB.SetPad(on == "on")
        say("Controller d-pad grid: " .. (DB.padNav and "ON" or "OFF"))
    elseif cmd == "scale" then
        local v = tonumber(arg)
        if not v then return say("Use a number, like /satchel scale 1") end
        DB.scale = math.max(0.5, math.min(2, v))
        if frame then frame:SetScale(DB.scale) end
        say("Scale: " .. DB.scale)
    elseif cmd == "reset" then
        if inCombat() then return say("Not in combat.") end
        DB.point = nil; frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120)
        say("Window put back.")
    elseif cmd == "config" then
        say("Waterys Satchel: " .. (DB.enabled and "ON" or "OFF (normal bag)"))
        say("Columns: " .. DB.columns .. "   Scale: " .. DB.scale)
        say("Controller d-pad grid: " .. (DB.padNav and "ON" or "OFF"))
    else say("Unknown. Type /satchel help") end
end
GB.Slash = slash
SLASH_WATERYSSATCHEL1 = "/satchel"
SLASH_WATERYSSATCHEL2 = "/ws"
SlashCmdList.WATERYSSATCHEL = slash

-- ---------- events ----------
local ev = CreateFrame("Frame", "WaterysSatchelEvents")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_MONEY", "BAG_UPDATE_COOLDOWN" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "ADDON_LOADED" and a1 == addonName then
        -- Migrate settings from the old Tidepool or GridBag addon (once, only if it has none yet).
        if not WaterysSatchelDB then
            WaterysSatchelDB = {}
            if type(TidepoolDB) == "table" then
                for k, v in pairs(TidepoolDB) do WaterysSatchelDB[k] = v end
            end
            if next(WaterysSatchelDB) == nil and type(GridBagDB) == "table" then
                for k, v in pairs(GridBagDB) do WaterysSatchelDB[k] = v end
            end
        end
        DB = WaterysSatchelDB
        if type(DB.minimap) ~= "table" then DB.minimap = {} end
        for k, v in pairs(MM_DEFAULT) do if DB.minimap[k] == nil then DB.minimap[k] = v end end
        for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
        GB.DB = DB
    elseif e == "PLAYER_LOGIN" then
        DB = WaterysSatchelDB or DB
        build(); buildMinimap(); buildSettings(); hookAll()
        GB.Layout()
    elseif e == "PLAYER_REGEN_ENABLED" then
        if frame and pending then GB.Layout() end
    elseif frame and frame:IsShown() then
        if e == "BAG_UPDATE" and not inCombat() then
            -- bag sizes can change when a bag is swapped
            local n = 0
            for _, s in ipairs(GB.BuildOrder(currentSizes())) do n = n + 1 end
            if n ~= shownCount then GB.Layout() else GB.Refresh() end
        else GB.Refresh() end
    end
end)
