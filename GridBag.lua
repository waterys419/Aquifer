-- GridBag: one combined bag as a plain grid, with explicit controller neighbors.
local addonName = ...
local GB = {}
_G.GridBag = GB

local DEFAULTS = { enabled = true, columns = 8, scale = 1, padNav = true }
local SLOT, GAP, PAD, TOP = 37, 4, 8, 28
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

-- ---------- state ----------
local frame, nav, hl, title
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
        return t.iconFileID, t.stackCount, t.quality, t.isLocked
    end
    if GetContainerItemInfo then
        local icon, count, locked, quality = GetContainerItemInfo(bag, slot)
        return icon, count, quality, locked
    end
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
    local b = CreateFrame("Button", "GridBagSlot" .. i, frame, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(SLOT, SLOT)
    b:RegisterForClicks("AnyUp")
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    b:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
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

local function refreshSlot(b)
    if not b.bag then return end
    local icon, count, quality, locked = itemInfo(b.bag, b.slot)
    if icon then
        b.icon:SetTexture(icon); b.icon:SetDesaturated(locked and true or false)
        b.count:SetText((count and count > 1) and count or "")
        if quality and quality >= 1 then
            local r, g, bl = qualityColor(quality)
            b:SetBackdropBorderColor(r, g, bl, 1)
        else b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end
    else
        b.icon:SetTexture(nil); b.count:SetText("")
        b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
end

function GB.Refresh()
    if not frame then return end
    local free = 0
    for i = 1, shownCount do
        refreshSlot(slots[i])
        if not itemInfo(slots[i].bag, slots[i].slot) then free = free + 1 end
    end
    title:SetText("Bag  " .. free .. "/" .. shownCount .. " free")
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
    frame:SetSize(PAD * 2 + cols * SLOT + (cols - 1) * GAP, TOP + PAD + rows * SLOT + (rows - 1) * GAP)
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
    frame = CreateFrame("Frame", "GridBagFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    frame:SetScale(DB.scale)
    local p = DB.point
    if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120) end
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -8)
    frame:SetScript("OnDragStart", function(self)
        if not inCombat() and IsAltKeyDown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
    frame:Hide()
    tinsert(UISpecialFrames, "GridBagFrame")

    nav = CreateFrame("Frame", "GridBagNav", frame, "SecureHandlerBaseTemplate")
    hl = CreateFrame("Frame", "GridBagFocus", frame, "BackdropTemplate")
    hl:SetSize(SLOT + 4, SLOT + 4)
    hl:SetFrameLevel(frame:GetFrameLevel() + 20)
    hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
    hl:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    hl:Hide()
    nav:SetFrameRef("hl", hl)
    for _, d in ipairs({ "up", "down", "left", "right" }) do
        local btn = CreateFrame("Button", "GridBagPad" .. d, frame, "SecureHandlerClickTemplate")
        btn:SetAttribute("dir", d)
        btn:SetFrameRef("nav", nav)
        btn:SetAttribute("_onclick", NAV_MOVE)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        nav:SetFrameRef(d, btn)
    end
    frame:SetScript("OnShow", function() GB.Refresh() end)
    frame:SetScript("OnHide", function()
        if not inCombat() then SecureHandlerExecute(nav, "self:ClearBindings(); self:GetFrameRef('hl'):Hide()") end
    end)
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
local function say(m) print("|cff66ccffGridBag|r " .. m) end
local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "help" then
        say("/gridbag toggle - open or close the bag")
        say("/gridbag cols 8 - slots per row (4 to 20)")
        say("/gridbag default on|off - on = use the normal bag again")
        say("/gridbag pad on|off - controller d-pad moves in the grid")
        say("/gridbag scale 1 - window size (0.5 to 2)")
        say("/gridbag reset - put the window back")
        say("/gridbag config - show settings")
        say("Alt + drag moves the window.")
    elseif cmd == "toggle" then GB.Toggle()
    elseif cmd == "cols" or cmd == "columns" then
        local v = tonumber(arg)
        if not v then return say("Use a number, like /gridbag cols 8") end
        DB.columns = math.max(4, math.min(20, math.floor(v)))
        GB.Layout(); say("Columns: " .. DB.columns)
        if pending then say("In combat. Will apply after.") end
    elseif cmd == "default" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /gridbag default on  or  off") end
        DB.enabled = (on == "off")
        if not DB.enabled and GB.IsOpen() then GB.Close() end
        say(DB.enabled and "GridBag bag is ON." or "Normal bag is back. GridBag is OFF.")
    elseif cmd == "pad" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /gridbag pad on  or  off") end
        DB.padNav = (on == "on")
        if frame and not inCombat() then nav:SetAttribute("padnav", DB.padNav and 1 or 0); if GB.IsOpen() then SecureHandlerExecute(nav, NAV_SETUP) end end
        say("Controller d-pad grid: " .. (DB.padNav and "ON" or "OFF"))
    elseif cmd == "scale" then
        local v = tonumber(arg)
        if not v then return say("Use a number, like /gridbag scale 1") end
        DB.scale = math.max(0.5, math.min(2, v))
        if frame then frame:SetScale(DB.scale) end
        say("Scale: " .. DB.scale)
    elseif cmd == "reset" then
        if inCombat() then return say("Not in combat.") end
        DB.point = nil; frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120)
        say("Window put back.")
    elseif cmd == "config" then
        say("GridBag: " .. (DB.enabled and "ON" or "OFF (normal bag)"))
        say("Columns: " .. DB.columns .. "   Scale: " .. DB.scale)
        say("Controller d-pad grid: " .. (DB.padNav and "ON" or "OFF"))
    else say("Unknown. Type /gridbag help") end
end
GB.Slash = slash
SLASH_GRIDBAG1 = "/gridbag"
SLASH_GRIDBAG2 = "/gb"
SlashCmdList.GRIDBAG = slash

-- ---------- events ----------
local ev = CreateFrame("Frame", "GridBagEvents")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, e, a1)
    if e == "ADDON_LOADED" and a1 == addonName then
        GridBagDB = GridBagDB or {}
        DB = GridBagDB
        for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
        GB.DB = DB
    elseif e == "PLAYER_LOGIN" then
        DB = GridBagDB or DB
        build(); hookAll()
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
