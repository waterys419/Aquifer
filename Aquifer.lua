-- Aquifer: one combined bag as a plain grid, with explicit controller neighbors. (was GridBag)
local addonName = ...
local GB = {}
_G.Aquifer = GB

local DEFAULTS = { enabled = true, columns = 8, scale = 1, padNav = true, collapsed = false, notice = false, debugEnabled = false }
local MM_DEFAULT = { angle = 215, hide = false }
-- Frame refs: the global SecureHandlerSetFrameRef works even when BackdropTemplate wipes the secure template's methods (WoW Forever crash at :SetFrameRef, Nov 6).
local function SetRef(f, k, v) SecureHandlerSetFrameRef(f, k, v) end
local ICON = "Interface\\Icons\\INV_Misc_Bag_21"
local SLOT, GAP, PAD, TOP, BOTTOM = 37, 4, 8, 32, 46   -- BOTTOM = money row + controller hint row
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
    radius = radius or 80   -- caller passes Minimap:GetWidth()/2 + 10 so the button sits on the outer ring
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
local frame, nav, hl, moneyText, search, mmButton, settings
local query = ""
local freeText, footer
local slots = {}
local order, shownCount = {}, 0
local pending = false
local focusManager, pendingFocusRemoval
local focusMark, focusNotice, focusRecoveryPending
local function rememberSelection()
    local b = nav and slots[nav:GetAttribute("focus") or 1]
    if b and b.bag then
        local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(b.bag,b.slot)
        return {bag=b.bag, slot=b.slot, id=info and info.itemID, index=nav:GetAttribute("focus")}
    end
end
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

-- Tooltip work stays outside secure navigation; the existing 0.1s UI tick follows it.
local tooltipSlot, tooltipKey, hoverSlot, tooltipFocus
local function ownsSlotTooltip()
    return tooltipSlot and GameTooltip and (not GameTooltip.GetOwner or GameTooltip:GetOwner()==tooltipSlot)
end
function GB.HideSlotTooltip()
    if ownsSlotTooltip() then GameTooltip:Hide() end
    tooltipSlot,tooltipKey=nil,nil
end
function GB.UpdateSlotTooltip()
    if not GameTooltip or not GameTooltip.SetOwner or not GameTooltip.SetBagItem then return end
    if not frame or not frame:IsShown() or inCombat() or not hoverSlot and (nav:GetAttribute("focusowned")==0
        or nav:GetAttribute("padnav")~=1 or GB.itemMenu:IsShown() or GB.bagMenu:IsShown()) then
        GB.HideSlotTooltip(); return
    end
    local selected=nav:GetAttribute("focus") or 1
    local moved=tooltipFocus~=selected
    if moved then hoverSlot=nil; tooltipFocus=selected end
    local b=hoverSlot or slots[selected]
    local icon,count,_,_,link
    if b and b.bag and b:IsShown() then icon,count,_,_,link=itemInfo(b.bag,b.slot) end
    if not icon then GB.HideSlotTooltip(); return end
    local key=tostring(b.bag)..":"..tostring(b.slot)..":"..tostring(link)..":"..tostring(count)
    -- Another window's mouse tooltip wins until the next selection/hover change.
    if not moved and not hoverSlot and GameTooltip:IsShown() and GameTooltip.GetOwner
        and GameTooltip:GetOwner()~=tooltipSlot then return end
    if tooltipSlot~=b or tooltipKey~=key or not ownsSlotTooltip() or not GameTooltip:IsShown() then
        GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
        GameTooltip:SetBagItem(b.bag,b.slot)
        GameTooltip:Show()
        tooltipSlot,tooltipKey=b,key
    end
end

-- Which entries the item menu offers for one item. Pure: takes the link and stack count.
-- Use only if the item is usable, Equip only if it is equippable, Split only for stacks.
-- This client has no global IsEquippableItem / GetItemSpell / IsUsableItem / GetItemInfoInstant /
-- GetItemInfo (the stock UI only calls C_Item.*). Resolve at call time, C_Item first.
local function itemAPI(name)
    if C_Item and type(C_Item[name]) == "function" then return C_Item[name] end
    local g = _G[name]
    if type(g) == "function" then return g end
end
GB.itemAPI = itemAPI
function GB.ItemMenuKeys(link, count)
    local k = { bind = true, link = true, destroy = true }
    if count and count > 1 then k.split = true end
    if link then
        local eq, sp, inst, us = itemAPI("IsEquippableItem"), itemAPI("GetItemSpell"), itemAPI("GetItemInfoInstant"), itemAPI("IsUsableItem")
        if eq and eq(link) then k.equip = true end
        local usable = false
        if sp and sp(link) then usable = true end
        if not usable and inst then
            local _, _, _, _, _, classID = inst(link)
            if classID == 0 then usable = true end   -- consumable
        end
        if not usable and not k.equip and us and us(link) then usable = true end
        k.use = usable
    end
    return k
end

-- ---------- slots ----------
local function makeSlot(i)
    local b = CreateFrame("Button", "AquiferSlot" .. i, frame, "SecureActionButtonTemplate,BackdropTemplate")
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
    b.cd = CreateFrame("Cooldown", "AquiferCD" .. i, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.index = i
    -- The stock StackSplitFrame calls owner:SplitStack(amount) on confirm (it crashed without this).
    b.hasStackSplit = 0
    b.SplitStack = function(self, n)
        self.hasStackSplit = 0
        if not (self.bag and n and n > 0) then return end
        if C_Container and C_Container.SplitContainerItem then C_Container.SplitContainerItem(self.bag, self.slot, n)
        elseif SplitContainerItem then SplitContainerItem(self.bag, self.slot, n) end
    end
    -- Right click uses the item (secure, works in combat). Left click picks up / drops.
    b:SetAttribute("type2", "item")
    b:SetScript("PostClick", function(self, button)
        if button == "LeftButton" and self.bag then pickup(self.bag, self.slot) end
    end)
    b:SetScript("OnEnter", function(self)
        if self.bag then
            -- A hovered context item must also be the item the confirm key acts on.
            if not inCombat() and GB.InteractionAction and GB.InteractionAction()
                and nav and nav:GetAttribute("focusowned") ~= 0
                and not GB.itemMenu:IsShown() and not GB.bagMenu:IsShown() then
                nav:SetAttribute("focus",self.index)
                SecureHandlerExecute(nav,GB.NAV_CLAMP)
                GB.UpdateFooter()
            end
            hoverSlot=self
            tooltipFocus=nav and (nav:GetAttribute("focus") or 1)
            -- Mouse inspection still works without controller navigation or in another window.
            if not inCombat() then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.bag, self.slot) end
                GameTooltip:Show()
                tooltipSlot,tooltipKey=self,nil
            end
        end
    end)
    b:SetScript("OnLeave", function(self)
        if hoverSlot==self then hoverSlot=nil end
        if tooltipSlot==self then GB.HideSlotTooltip() end
    end)
    slots[i] = b
    SetRef(nav, "s" .. i, b)
    return b
end

-- The restricted menu snippet reads these slot attributes (m_<key>, hasitem). Only outside combat.
local MENU_KEYS = { "use", "equip", "bind", "split", "link", "destroy", "pickup" }
local function updateSlotMenu(b)
    if inCombat() or not b.bag then return end
    local icon, count, _, _, link = itemInfo(b.bag, b.slot)
    local k = icon and GB.ItemMenuKeys(link, count) or {}
    k.pickup = icon and GB.InteractionAction and GB.InteractionAction() ~= nil
    for _, key in ipairs(MENU_KEYS) do b:SetAttribute("m_" .. key, k[key] and 1 or nil) end
    b:SetAttribute("hasitem", icon and 1 or nil)
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
            local gi = itemAPI("GetItemInfo")
            local name = link and gi and gi(link)
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
    updateSlotMenu(b)
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

-- Rebinds the pad for the current focus. Run by RunAttribute("rebind") on nav.
-- PlayStation names: PAD1 = X (cross), PAD2 = Circle, PAD3 = Square, PAD4 = Triangle.
local NAV_REBIND = [[
local nav = self
nav:ClearBindings()
if nav:GetAttribute("combatpaused") ~= 1 and nav:GetAttribute("padnav") == 1 and nav:GetAttribute("bindinghandoff") ~= 1 and nav:GetAttribute("focusowned") ~= 0 then
  nav:SetBindingClick(true, "PADDUP", nav:GetFrameRef("up"), "LeftButton")
  nav:SetBindingClick(true, "PADDDOWN", nav:GetFrameRef("down"), "LeftButton")
  nav:SetBindingClick(true, "PADDLEFT", nav:GetFrameRef("left"), "LeftButton")
  nav:SetBindingClick(true, "PADDRIGHT", nav:GetFrameRef("right"), "LeftButton")
  nav:SetBindingClick(true, "PAD1", nav:GetFrameRef(nav:GetAttribute("interaction") and "contextaction" or "itemopen"), "LeftButton")
  nav:SetBindingClick(true, "PAD2", nav:GetFrameRef("closebag"), "LeftButton")
  nav:SetBindingClick(true, "PAD3", nav:GetFrameRef("quick"), "LeftButton")
  nav:SetBindingClick(true, "PAD4", nav:GetFrameRef("triopen"), "LeftButton")
end
]]
local NAV_SETUP = [[
local nav = self
if nav:GetAttribute("focusowned") == 0 then nav:ClearBindings(); return end
nav:SetAttribute("focus", 1)
local b = nav:GetFrameRef("s1")
local hl = nav:GetFrameRef("hl")
if b and hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER"); hl:Show() end
nav:RunAttribute("rebind")
]]
-- After a re-layout: keep focus inside the new slot count and put the yellow box back.
local NAV_CLAMP = [[
local nav = self
if nav:GetAttribute("focusowned") == 0 then nav:ClearBindings(); return end
local n = nav:GetAttribute("count") or 0
local f = nav:GetAttribute("focus") or 1
if f > n then f = n end
if f < 1 then f = 1 end
nav:SetAttribute("focus", f)
local b = nav:GetFrameRef("s" .. f)
local hl = nav:GetFrameRef("hl")
if b and b:IsShown() and hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER"); hl:Show()
elseif hl then hl:Hide() end
nav:RunAttribute("rebind")
]]
-- Run when a d-pad button is pressed. Moves focus using the stored neighbor table.
local NAV_MOVE = [[
if down then return end -- belt and braces: never move on the key-down click
local nav = self:GetFrameRef("nav")
if nav:GetAttribute("focusowned") == 0 then return end
local dir = self:GetAttribute("dir")
local f = nav:GetAttribute("focus") or 1
local t = nav:GetAttribute(dir .. f) or f
nav:SetAttribute("focus", t)
local b = nav:GetFrameRef("s" .. t)
local hl = nav:GetFrameRef("hl")
if b and hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER"); hl:Show() end
]]
-- Circle with no menu open: close the whole window.
-- The window is a secure-template frame (protected), so a restricted snippet may Hide it,
-- also in combat. (An unprotected frame would be rejected.)
local CLOSE_BAG = [[
if down then return end
self:GetFrameRef("frame"):Hide()
]]
local QUICK_PRE = [[
local f = owner:GetAttribute("focus") or 1
local s = owner:GetFrameRef("s" .. f)
local item = s and s:GetAttribute("item2")
if item and s:GetAttribute("hasitem") and (s:GetAttribute("m_equip") or s:GetAttribute("m_use")) then
  self:SetAttribute("type", "macro")
  self:SetAttribute("macrotext", "/use " .. item)
else
  self:SetAttribute("type", "macro")
  self:SetAttribute("macrotext", "")
end
]]
-- ---------- controller menus (stock style) ----------
-- X or Triangle on an ITEM opens the item menu (only the entries that fit that item).
-- Triangle on an EMPTY slot opens the bag menu. D-pad up/down chooses, X confirms, Circle closes.
-- Use and Equip are secure macro buttons ("/use <bag> <slot>"), so they work in combat.
local ITEM_MENU = {
  { key = "use",     label = "Use" },
  { key = "equip",   label = "Equip" },
  { key = "bind",    label = "Bind" },
  { key = "split",   label = "Split" },
  { key = "link",    label = "Share in Chat" },
  { key = "destroy", label = "Destroy" },
  { key = "pickup", label = "Pick up" },
}
local BAG_MENU = {
  { key = "cleanup", label = "Cleanup" },
  { key = "junk",    label = "Sell Junk" },
  { key = "hide",    label = "Hide empty slots" },
  { key = "bank", label = "View bank" },
}
GB.ITEM_MENU, GB.BAG_MENU = ITEM_MENU, BAG_MENU
-- Run by X (mode "x") and Triangle (mode "tri"). Item under focus -> item menu, built from the
-- m_<key> attributes on the slot. Empty slot -> bag menu for Triangle, nothing for X.
-- Anchors only to protected frames (secure slot buttons / the menu itself).
local MENU_OPEN = [[
if down then return end
local nav = self:GetFrameRef("nav")
if nav:GetAttribute("bindinghandoff") == 1 or nav:GetAttribute("focusowned") == 0 then return end
local f = nav:GetAttribute("focus") or 1
local s = nav:GetFrameRef("s" .. f)
if not s then return end
local item = s:GetAttribute("item2")
local m
if item and s:GetAttribute("hasitem") then m = self:GetFrameRef("imenu")
elseif self:GetAttribute("mode") == "tri" then m = self:GetFrameRef("bmenu")
else return end
if m:GetAttribute("kind") == "item" then
  m:SetAttribute("slotindex", f)
  local n = 0
  for i = 1, m:GetAttribute("pool") do
    local e = m:GetFrameRef("e" .. i)
    local key = e:GetAttribute("key")
    if s:GetAttribute("m_" .. key) then
      n = n + 1
      m:SetAttribute("v" .. n, i)
      e:ClearAllPoints(); e:SetPoint("TOPLEFT", m, "TOPLEFT", 5, -5 - (n - 1) * 22); e:Show()
      if key == "use" or key == "equip" then e:SetAttribute("type", "macro"); e:SetAttribute("macrotext", "/use " .. item) end
    else e:Hide() end
  end
  if n == 0 then return end
  m:SetAttribute("count", n)
  m:SetHeight(n * 22 + 10)
  m:ClearAllPoints(); m:SetPoint("TOPLEFT", s, "TOPRIGHT", 4, 0)
else
  -- anchor to a secure slot button: the main window is not protected, so the restricted
  -- environment rejects it as a relative frame ("Invalid relative frame handle", Nov 6)
  m:ClearAllPoints(); m:SetPoint("TOPLEFT", nav:GetFrameRef("s1"), "TOPLEFT", 4, -4)
end
m:SetAttribute("sel", 1)
m:Show()
nav:ClearBindings()
m:ClearBindings()
m:SetBindingClick(true, "PADDUP", m:GetFrameRef("up"), "LeftButton")
m:SetBindingClick(true, "PADDDOWN", m:GetFrameRef("down"), "LeftButton")
local e = m:GetFrameRef("e" .. m:GetAttribute("v1"))
m:SetBindingClick(true, "PAD1", e, "LeftButton")
m:SetBindingClick(true, "PAD2", m:GetFrameRef("closebtn"), "LeftButton")
local h = m:GetFrameRef("mhl")
h:ClearAllPoints(); h:SetPoint("TOPLEFT", e, "TOPLEFT", 0, 0); h:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0); h:Show()
]]
local MENU_MOVE = [[
if down then return end
local m = self:GetFrameRef("menu")
if m:GetFrameRef("nav"):GetAttribute("bindinghandoff") == 1 or m:GetFrameRef("nav"):GetAttribute("focusowned") == 0 then return end
local n = m:GetAttribute("count")
local sel = m:GetAttribute("sel") or 1
if self:GetAttribute("dir") == "up" then sel = sel - 1; if sel < 1 then sel = n end
else sel = sel + 1; if sel > n then sel = 1 end end
m:SetAttribute("sel", sel)
local e = m:GetFrameRef("e" .. m:GetAttribute("v" .. sel))
local h = m:GetFrameRef("mhl")
h:ClearAllPoints(); h:SetPoint("TOPLEFT", e, "TOPLEFT", 0, 0); h:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
m:SetBindingClick(true, "PAD1", e, "LeftButton")
]]
-- Every plain entry (and the Circle close button) runs this first: close the menu, give the pad back to the grid.
local MENU_CLOSE = [[
if down then return end
local m = self:GetFrameRef("menu")
m:ClearBindings()
m:Hide()
m:GetFrameRef("nav"):RunAttribute("rebind")
]]
-- Use / Equip entries: secure action buttons, so the menu closes from a wrapped OnClick (post body,
-- after the macro ran). `owner` is the wrap header = the menu. Also run directly out of combat.
local MENU_SHUT = [[
local m = owner or self
m:ClearBindings()
m:Hide()
m:GetFrameRef("nav"):RunAttribute("rebind")
]]
local MENU_HIDE_ALL = "self:ClearBindings(); self:Hide()"
GB.NAV_SETUP, GB.NAV_MOVE, GB.NAV_REBIND = NAV_SETUP, NAV_MOVE, NAV_REBIND

function GB.Layout()
    if inCombat() then pending = true; return end
    pending = false
    local selected = focusMark or rememberSelection()
    order = GB.BuildOrder(currentSizes())
    if DB.collapsed then   -- collapsed: only slots that hold an item
        local keep = {}
        for _, o in ipairs(order) do if itemInfo(o[1], o[2]) then keep[#keep + 1] = o end end
        order = keep
    end
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
    for i = n + 1, #slots do slots[i]:Hide(); slots[i].bag = nil; slots[i]:SetAttribute("item2", nil); slots[i]:SetAttribute("hasitem", nil) end
    shownCount = n
    local rows = math.max(1, math.ceil(n / cols))
    frame:SetSize(PAD * 2 + cols * SLOT + (cols - 1) * GAP, TOP + BOTTOM + rows * SLOT + (rows - 1) * GAP)
    local nb = GB.Neighbors(n, cols)
    for _, d in ipairs({ "left", "right", "up", "down" }) do
        for i = 1, n do nav:SetAttribute(d .. i, nb[d][i]) end
    end
    if selected then
        local same, matching
        for i=1,n do
            local b=slots[i]
            local info=C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(b.bag,b.slot)
            if b.bag==selected.bag and b.slot==selected.slot then same=i end
            if selected.id and info and info.itemID==selected.id then
                if not matching or (b.bag==selected.bag and b.slot==selected.slot) then matching=i end
            end
        end
        nav:SetAttribute("focus", matching or same or math.max(1,math.min(selected.index or 1,n)))
    end
    nav:SetAttribute("count", n)
    nav:SetAttribute("padnav", DB.padNav and 1 or 0)
    GB.Refresh()
    if frame:IsShown() and not (GB.itemMenu:IsShown() or GB.bagMenu:IsShown()) then SecureHandlerExecute(nav, NAV_CLAMP) end
end


-- ---------- controller button hints (footer) ----------
-- The stock UI draws PlayStation art from the client's atlas. This client ships no readable UI
-- code, so the exact atlas names could not be read from disk. We probe likely names at run time
-- (and /aquifer glyph <button> <atlas> can set one by hand). Fallback: plain yellow text.
local GLYPH_WORD = { cross = { "Cross", "X" }, circle = { "Circle", "B" }, square = { "Square", "X" }, triangle = { "Triangle", "Y" } }
local GLYPH_PATTERNS = { "Gamepad_Ltr_%s_%d", "Gamepad_Rev_%s_%d", "Gamepad_Gen_%s_%d", "Gamepad_%s_%d",
    "Gamepad_PS_%s_%d", "Gamepad_Playstation_%s_%d" }
local GLYPH_SIZES = { 64, 32, 128, 24, 48 }
local GLYPH_TEXT = { cross = "X", circle = "O", square = "Sq", triangle = "Tri" }
local glyphCache = {}
local function atlasExists(a)
    local ga = C_Texture and C_Texture.GetAtlasInfo
    return ga and ga(a) and true or false
end
local function findGlyph(name)
    local forced = DB and DB.glyph and DB.glyph[name]
    if forced and atlasExists(forced) then return forced end
    for _, pat in ipairs(GLYPH_PATTERNS) do
        for _, size in ipairs(GLYPH_SIZES) do
            local a = pat:format(GLYPH_WORD[name][1], size)
            if atlasExists(a) then return a end
        end
    end
end
function GB.Glyph(name)
    if glyphCache[name] == nil then glyphCache[name] = findGlyph(name) or false end
    local atlas = glyphCache[name]
    if atlas then return "|A:" .. atlas .. ":18:18|a" end
    return "|cffffd100[" .. GLYPH_TEXT[name] .. "]|r"
end
function GB.ResetGlyphs() glyphCache = {} end
function GB.GlyphReport()
    local out = {}
    for _, n in ipairs({ "cross", "circle", "square", "triangle" }) do
        glyphCache[n] = nil
        local a = findGlyph(n)
        out[#out + 1] = n .. ": " .. (a or "not found (text fallback)")
    end
    return out
end
-- list entries: { glyphName or {glyphName, ...}, label }
function GB.HintText(list)
    local t = {}
    for _, h in ipairs(list) do
        local g = {}
        for _, n in ipairs(type(h[1]) == "table" and h[1] or { h[1] }) do g[#g + 1] = GB.Glyph(n) end
        t[#t + 1] = table.concat(g, "") .. " |cffffd100" .. h[2] .. "|r"
    end
    return table.concat(t, "   ")
end
-- Footer depends on what the yellow box is on.
function GB.QuickLabel(link, count)
    local k = GB.ItemMenuKeys(link, count)
    if k.equip then return "Equip" elseif k.use then return "Use" end
end
function GB.GridHints(onItem, quick)
    if onItem then
        local l = { { { "cross", "triangle" }, "Item Menu" } }
        if quick then l[#l + 1] = { "square", quick } end
        l[#l + 1] = { "circle", "Close" }
        return GB.HintText(l)
    end
    return GB.HintText({ { "cross", "Place" }, { "triangle", "Bag Menu" }, { "circle", "Close" } })
end
function GB.MenuHints() return GB.HintText({ { "cross", "Select" }, { "circle", "Close" } }) end
-- Called often (cheap): re-draws the footer when the focus moves to an item / empty slot.
function GB.UpdateFooter()
    GB.UpdateSlotTooltip()
    if not (footer and frame and frame:IsShown() and nav) then return end
    if GB.UpdateFocusNotice then GB.UpdateFocusNotice() end
    if nav:GetAttribute("combatpaused") == 1 then footer:SetText("Controller paused during combat"); return end
    if nav:GetAttribute("focusowned") == 0 then
        footer.shownKey=nil
        footer:SetText("L2 / R2: return to Bags"); return
    end
    local action = GB.InteractionAction and GB.InteractionAction()
    if not inCombat() and nav:GetAttribute("interaction") ~= action then GB.RefreshInteraction() end
    local b = slots[nav:GetAttribute("focus") or 1]
    local icon, count, _, _, link
    if b and b.bag then icon, count, _, _, link = itemInfo(b.bag, b.slot) end
    local onItem = icon and true or false
    local quick = onItem and GB.QuickLabel(link, count) or nil
    local hintAction = action and ((CursorHasItem and CursorHasItem()) and "Place" or (onItem and GB.ContextHint(b,action)))
    local key = (onItem and "i" or "e") .. tostring(quick) .. tostring(hintAction)
    if footer.shownKey ~= key then
        footer.shownKey = key
        if action then
            local hints={}
            if hintAction then hints[#hints+1]={"cross",hintAction} end
            hints[#hints+1]={"triangle",onItem and "Item Menu" or "Bag Menu"}
            hints[#hints+1]={"circle","Close"}
            footer:SetText(GB.HintText(hints) .. " | L2/R2: windows")
        else footer:SetText(GB.GridHints(onItem, quick)) end
    end
end

local function menuSlot()
    local m = GB.itemMenu
    local i = m and m:GetAttribute("slotindex")
    local b = i and slots[i]
    if b and b.bag then return b end
end
local function say2(m) print("|cff66ccffAquifer|r " .. m) end
local function itemLink(b)
    local _, _, _, _, link = itemInfo(b.bag, b.slot)
    return link
end
local function itemCount(b)
    local _, count = itemInfo(b.bag, b.slot)
    return count or 0
end
-- Opens the chat edit box with the link in it (works with no chat box open, on a controller).
function GB.OpenChatWith(link)
    if ChatFrame_OpenChat then
        local ok = pcall(ChatFrame_OpenChat, link, _G.DEFAULT_CHAT_FRAME)
        if ok then return true end
    end
    local cf = _G.DEFAULT_CHAT_FRAME
    local eb = (cf and cf.editBox) or _G.ChatFrame1EditBox
    if eb and ChatEdit_ActivateChat then
        pcall(ChatEdit_ActivateChat, eb)
        if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
        if eb.Insert then eb:Insert(link); return true end
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
    say2(link)
end
local DEFAULT_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 13 do DEFAULT_FRAMES[#DEFAULT_FRAMES + 1] = "ContainerFrame" .. i end
-- Controller-only action-slot picker for Bind (2.2.7). Out of combat this client allows the
-- same two calls the stock UI makes on a hardware drop: PickupContainerItem, then PlaceAction.
-- Never drive the stock Bind editor, its focus methods or SetPreferredGamepadInteractTarget.
-- The gamepad cross bars store their actions in gamepad storage slots. The page-unit slot IDs are
-- fixed positions (Top 1-8, Left 9-16, Right 17-24, Bottom 25-32); IDs 5-8 are reserved UI actions.
-- Buttons 1-4 of each bar are the d-pad diamond, 5-8 the face-button diamond; a bar is reached by
-- holding its cross-bar modifier (left, right or both). This mirrors the stock layout code.
local GP_TILE, GP_GAP = 40, 3
local GP_COLS, GP_ROWS = 12, 9
local GP_RESERVED_FIRST, GP_RESERVED_COUNT = 5, 4
local bindHandoff = false
local pickerPage, pickerSel = 1, 1
local pickerBag, pickerSlot
local picker, pickerHl, pickerPageText, pickerHint
local pickerTiles, pickerPool, pickerPad = {}, {}, {}
local pickerPageKeys
local pickerAttrStuck = false
local hideDefault
local function bindCursorBusy()
    if GetCursorInfo then return GetCursorInfo() ~= nil end
    return CursorHasItem and CursorHasItem()
end
function GB.IsBindingHandoff() return bindHandoff end
local function actionInfo(slot)
    local f = (C_ActionBar and C_ActionBar.GetActionInfo) or GetActionInfo
    if not f then return end
    return f(slot)
end
local function actionTexture(slot)
    local f = (C_ActionBar and C_ActionBar.GetActionTexture) or GetActionTexture
    if not f then return end
    return f(slot)
end
local function gpConstants()
    local c = Constants and Constants.GamepadActionBarConstants
    if type(c) == "table" then return c end
end
local function gpPageCount()
    local c = gpConstants()
    return math.max(1, (c and c.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT) or 3)
end
local function gpPageUnitSlots()
    local c = gpConstants()
    return math.max(1, (c and c.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE) or 32)
end
local function gpReserved()
    local c = gpConstants()
    return math.max(0, (c and c.NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT) or 4)
end
local function gpFirstStorage()
    local f = C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex
    if not f then return end
    return tonumber(f())
end
-- Same formula as the stock GamepadActionBarBindingUtil, so PlaceAction hits the slot the
-- gamepad button really fires.
local function gpStorageSlot(page, pageUnitSlotID)
    local first = gpFirstStorage()
    if not first then return end
    local perPage = gpPageUnitSlots()
    local reserved = gpReserved()
    local slot = perPage * (page - 1) + first + (pageUnitSlotID - 1) - reserved * (page - 1)
    if pageUnitSlotID >= GP_RESERVED_FIRST then slot = slot - reserved end
    return slot
end
local function validStorage(slot)
    local f = C_GamepadUI and C_GamepadUI.IsValidGamepadActionStorageSlotIndex
    if not f then return true end
    return f(slot) and true or false
end
local function bindingKey(command)
    if not GetBindingKey then return end
    local key = GetBindingKey(command, 1) or GetBindingKey(command)
    if type(key) == "string" and key ~= "" then return key end
end
local function modifierKeys()
    return bindingKey("GAMEPADLEFTMOD"), bindingKey("GAMEPADRIGHTMOD")
end
-- Quiet bounded diagnostics; /aq debug only enables chat output.
local debugManager, debugState, debugElapsed
local function debugValue(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    if v==nil then return "-" end
    return tostring(v)
end
local function debugFrame(f)
    local name=f and f.GetName and f:GetName()
    if type(name)~="string" then return "-" end
    -- Never log arbitrary unit/character-named frames.
    if name:match("^Aquifer[%w_]*$") or name:match("^ContainerFrame[%w_]*$") or name:match("^ChatFrame%d+$")
        or name=="GamepadActionBarEditFrame" or name=="BankFrame" or name=="MerchantFrame"
        or name=="MailFrame" or name=="TradeFrame" or name=="CharacterFrame" then return name end
    return "<other frame>"
end
local function debugSnapshot()
    local m=SmartNavigationSecureHelper and GamepadMode and GamepadMode.FrameControlsManager
    local edit=_G.GamepadActionBarEditFrame
    local cursor=GetCursorInfo and GetCursorInfo() or (CursorHasItem and CursorHasItem() and "item")
    return "picker="..debugValue(bindHandoff).." page="..debugValue(pickerPage).." sel="..debugValue(pickerSel)
        .." slot="..debugValue(pickerTiles and pickerTiles[pickerSel] and pickerTiles[pickerSel].slot or nil)
        .." item="..debugValue(pickerBag and (pickerBag..":"..pickerSlot) or nil)
        .." bag="..debugValue(frame and frame:IsShown()).." owned="..debugValue(nav and nav:GetAttribute("focusowned"))
        .." owner="..debugFrame(m and m.focusedFrame).." cursor="..debugValue(cursor)
        .." editor="..debugValue(edit and edit:IsShown()).." mode="..debugValue(edit and edit.activeMode)
        .." combat="..debugValue(inCombat())
end
function GB.DebugTrace(event,detail)
    if not DB then return end
    if type(DB.debugLog)~="table" then DB.debugLog={} end
    DB.debugSequence=(DB.debugSequence or 0)+1
    local line=DB.debugSequence.." "..string.format("%.2f",GetTime and GetTime() or 0).." "..event
        .." "..debugValue(detail).." | "..debugSnapshot()
    table.insert(DB.debugLog,line)
    while #DB.debugLog>200 do table.remove(DB.debugLog,1) end
    if DB.debugEnabled then print("|cff66ccffAquifer debug|r "..line) end
end
function GB.DebugPoll(elapsed)
    if not DB then return end
    debugElapsed=(debugElapsed or 0)+(elapsed or 0)
    if debugElapsed<(DB.debugEnabled and 0.1 or 0.25) then return end
    debugElapsed=0
    local m=SmartNavigationSecureHelper and GamepadMode and GamepadMode.FrameControlsManager
    if m and m~=debugManager and type(m.FrameShown)=="function" and type(m.FrameHidden)=="function" then
        -- Secure post-hooks leave Blizzard's wrapped methods and return values intact.
        hooksecurefunc(m,"FrameShown",function(_,f) GB.DebugTrace("manager.FrameShown",debugFrame(f)) end)
        hooksecurefunc(m,"FrameHidden",function(_,f) GB.DebugTrace("manager.FrameHidden",debugFrame(f)) end)
        debugManager=m
        GB.DebugTrace("manager hooked")
    end
    local state=debugSnapshot()
    if state~=debugState then debugState=state; GB.DebugTrace("state") end
end
local PICKER_BIND_BASE = [[
self:ClearBindings()
self:SetBindingClick(true, "PADDUP", self:GetFrameRef("up"), "LeftButton")
self:SetBindingClick(true, "PADDDOWN", self:GetFrameRef("down"), "LeftButton")
self:SetBindingClick(true, "PADDLEFT", self:GetFrameRef("left"), "LeftButton")
self:SetBindingClick(true, "PADDRIGHT", self:GetFrameRef("right"), "LeftButton")
self:SetBindingClick(true, "PAD1", self:GetFrameRef("place"), "LeftButton")
self:SetBindingClick(true, "PAD2", self:GetFrameRef("cancel"), "LeftButton")
]]
-- Page keys are whatever is not one of the cross-bar modifiers (the on-screen bars use those).
local PAGE_KEY_PAIRS = { { "PADLSHOULDER", "PADRSHOULDER" }, { "PADLTRIGGER", "PADRTRIGGER" } }
local function pickerPageKeyPair()
    local leftMod, rightMod = modifierKeys()
    for _, pair in ipairs(PAGE_KEY_PAIRS) do
        if pair[1] ~= leftMod and pair[1] ~= rightMod and pair[2] ~= leftMod and pair[2] ~= rightMod then
            return pair[1], pair[2]
        end
    end
    return PAGE_KEY_PAIRS[1][1], PAGE_KEY_PAIRS[1][2]
end
local function pickerKeys()
    if pickerPageKeys then return pickerPageKeys[1], pickerPageKeys[2] end
    return pickerPageKeyPair()
end
local function pickerBindSnippet()
    local prevKey, nextKey = pickerKeys()
    return PICKER_BIND_BASE
        .. 'self:SetBindingClick(true, "' .. prevKey .. '", self:GetFrameRef("prevpage"), "LeftButton")\n'
        .. 'self:SetBindingClick(true, "' .. nextKey .. '", self:GetFrameRef("nextpage"), "LeftButton")\n'
end
-- The client ships the gamepad labels itself (SharedConstants SetGamepadBindingStrings). Prefer
-- GetBindingText/the KEY_* markup so the tile shows the player's own button art; text is the fallback.
local GP_KEY_TEXT = { PAD1 = "X", PAD2 = "O", PAD3 = "Sq", PAD4 = "Tri",
    PADDUP = "\e", PADDDOWN = "\g", PADDLEFT = "\d", PADDRIGHT = "\f",
    PADLSHOULDER = "L1", PADRSHOULDER = "R1", PADLTRIGGER = "L2", PADRTRIGGER = "R2",
    PADLSTICK = "L3", PADRSTICK = "R3" }
local function keyPart(key, glyphSize)
    local text
    if GetBindingText then
        local ok, t = pcall(GetBindingText, key, 1)
        if ok and type(t) == "string" and t ~= "" and t ~= key then text = t end
    end
    if not text then
        local g = _G["KEY_" .. key] or _G["KEY_ABBR_" .. key]
        if type(g) == "string" then text = g end
    end
    if not text then text = GP_KEY_TEXT[key] or ("[" .. key .. "]") end
    return (text:gsub("(%|A:[^:]+):%d+:%d+|a", "%1:" .. glyphSize .. ":" .. glyphSize .. "|a"))
end
local function comboLabel(key, mods)
    local parts = {}
    for _, m in ipairs(mods or {}) do if m then parts[#parts + 1] = keyPart(m, 10) end end
    parts[#parts + 1] = keyPart(key, (#parts >= 2) and 10 or 11)
    return table.concat(parts, "|cffbbbbbb+|r")
end
-- On-screen layout: top bar above, left/right cross bars beside each other, bottom bar below.
-- Left diamond = d-pad buttons, right diamond = face buttons.
local GP_BARS = {
    { col = 4, row = 0 },  -- top bar: only the d-pad diamond is bindable
    { col = 0, row = 3 },  -- left cross bar (left modifier)
    { col = 6, row = 3 },  -- right cross bar (right modifier)
    { col = 3, row = 6 },  -- bottom cross bar (both modifiers)
}
local GP_DIAMOND = { { 0, 1 }, { 1, 0 }, { 2, 1 }, { 1, 2 }, { 0, 1 }, { 1, 0 }, { 2, 1 }, { 1, 2 } }
-- Only if the client cannot report the cross-bar bindings at all, fall back to the standard pad
-- positions (d-pad left/up/right/down, then square/triangle/circle/cross).
local GP_DEFAULT_KEYS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" }
local function anyGamepadActionBinding()
    for i = 1, 8 do
        if bindingKey("GAMEPADACTIONBUTTON" .. i) then return true end
    end
    return false
end
local function pickerLayout()
    local leftMod, rightMod = modifierKeys()
    local useDefaultKeys = not anyGamepadActionBinding()
    if useDefaultKeys then
        leftMod = leftMod or "PADLTRIGGER"
        rightMod = rightMod or "PADRTRIGGER"
    end
    local out = {}
    for id = 1, gpPageUnitSlots() do
        if not (id >= GP_RESERVED_FIRST and id < GP_RESERVED_FIRST + GP_RESERVED_COUNT) then
            local bar = math.floor((id - 1) / 8) + 1
            local idx = ((id - 1) % 8) + 1
            local mods, reachable
            if bar == 1 then mods, reachable = {}, true
            elseif bar == 2 then mods, reachable = { leftMod }, leftMod ~= nil
            elseif bar == 3 then mods, reachable = { rightMod }, rightMod ~= nil
            else mods, reachable = { leftMod, rightMod }, (leftMod ~= nil and rightMod ~= nil) end
            local key = bindingKey("GAMEPADACTIONBUTTON" .. idx)
            if not key and useDefaultKeys then key = GP_DEFAULT_KEYS[idx] end
            local slot = gpStorageSlot(pickerPage, id)
            if reachable and key and slot and validStorage(slot) then
                local geo = GP_BARS[bar] or GP_BARS[1]
                local d = GP_DIAMOND[idx]
                out[#out + 1] = {
                    id = id, slot = slot, key = key, mods = mods,
                    col = geo.col + d[1] + (idx <= 4 and 0 or 3),
                    row = geo.row + d[2],
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.row ~= b.row then return a.row < b.row end
        return a.col < b.col
    end)
    return out
end
local function PickerUpdateHighlight()
    local t = pickerTiles[pickerSel]
    if t and t.btn and pickerHl then
        pickerHl:ClearAllPoints()
        pickerHl:SetPoint("TOPLEFT", t.btn, "TOPLEFT", -2, 2)
        pickerHl:SetPoint("BOTTOMRIGHT", t.btn, "BOTTOMRIGHT", 2, -2)
        pickerHl:Show()
    elseif pickerHl then
        pickerHl:Hide()
    end
end
local function PickerRefreshIcons()
    for _, t in ipairs(pickerTiles) do
        local tex = actionTexture(t.slot)
        if tex then
            t.btn.icon:SetTexture(tex); t.btn.icon:SetVertexColor(1, 1, 1, 1)
        else
            t.btn.icon:SetTexture("Interface\\Buttons\\WHITE8X8"); t.btn.icon:SetVertexColor(0.05, 0.09, 0.13, 1)
        end
    end
end
local function pickerTileButton(i)
    local b = pickerPool[i]
    if b then return b end
    b = CreateFrame("Button", "AquiferPickerSlot" .. i, picker)
    b:SetSize(GP_TILE, GP_TILE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("BOTTOMLEFT", 1, 1)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function()
        if not bindHandoff then return end
        for idx, t in ipairs(pickerTiles) do
            if t.btn == b then pickerSel = idx; break end
        end
        PickerUpdateHighlight()
    end)
    pickerPool[i] = b
    return b
end
local function PickerRebuild(keepSlot)
    local old = pickerTiles[pickerSel]
    keepSlot = keepSlot or (old and old.slot)
    pickerTiles = {}
    local layout = pickerLayout()
    for i, item in ipairs(layout) do
        local btn = pickerTileButton(i)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", picker, "TOPLEFT",
            PAD + item.col * (GP_TILE + GP_GAP), -(28 + item.row * (GP_TILE + GP_GAP)))
        btn.label:SetText(comboLabel(item.key, item.mods))
        btn.slot = item.slot
        btn:Show()
        item.btn = btn
        pickerTiles[i] = item
    end
    for i = #layout + 1, #pickerPool do pickerPool[i]:Hide() end
    pickerSel = 1
    for i, item in ipairs(pickerTiles) do
        if item.slot == keepSlot then pickerSel = i; break end
    end
    if pickerPageText then pickerPageText:SetText("Page " .. pickerPage .. "/" .. gpPageCount()) end
    if pickerHint then
        if #pickerTiles == 0 then
            pickerHint:SetText("|cffff6666No gamepad action buttons found on this page.|r")
        else
            local prevKey, nextKey = pickerKeys()
            pickerHint:SetText(GB.HintText({ { "cross", "Place" }, { "circle", "Cancel" } })
                .. "   |cffffd100D-pad choose | " .. keyPart(prevKey, 11) .. " " .. keyPart(nextKey, 11) .. " page|r")
        end
    end
    PickerRefreshIcons()
    PickerUpdateHighlight()
end
local function pickerMoveDir(dir)
    local cur = pickerTiles[pickerSel]
    if not cur then return end
    local best, bestScore
    for i, t in ipairs(pickerTiles) do
        local dx, dy = t.col - cur.col, t.row - cur.row
        local ok = (dir == "right" and dx > 0) or (dir == "left" and dx < 0)
            or (dir == "up" and dy < 0) or (dir == "down" and dy > 0)
        if ok then
            local score
            if dir == "up" or dir == "down" then score = math.abs(dx) * 2 + math.abs(dy)
            else score = math.abs(dx) + math.abs(dy) * 2 end
            if not bestScore or score < bestScore then best, bestScore = i, score end
        end
    end
    if best then pickerSel = best; PickerUpdateHighlight() end
end
function GB.PickerMove(dir)
    if bindHandoff then pickerMoveDir(dir) end
end
function GB.PickerPage(delta)
    if not bindHandoff then return end
    local page = pickerPage + (delta or 0)
    local count = gpPageCount()
    if page < 1 then page = count elseif page > count then page = 1 end
    pickerPage = page
    PickerRebuild()
end
function GB.PickerState()
    local t = pickerTiles[pickerSel]
    return pickerPage, pickerSel, t and t.slot, bindHandoff, #pickerTiles
end
-- forced: closing because the bag itself was closed; must also work in combat (restricted Hide).
function GB.CloseActionPicker(cancelled, forced)
    if not bindHandoff then return false end
    if inCombat() and not forced then say2("[O] Cancel after combat."); return false end
    bindHandoff = false
    if picker then SecureHandlerExecute(picker, "self:ClearBindings(); self:Hide()") end
    if inCombat() then
        pickerAttrStuck = true   -- clear the nav attribute after combat; it is protected now
    else
        SecureHandlerExecute(nav, "self:SetAttribute('bindinghandoff', nil); self:RunAttribute('rebind')")
    end
    local t = pickerTiles[pickerSel]
    GB.DebugTrace(cancelled and "action picker cancel" or "action picker close", t and t.slot or nil)
    if footer then footer.shownKey = nil end
    if focusNotice then focusNotice:Hide() end
    return true
end
function GB.PlacePickedAction()
    if not bindHandoff then return false end
    if inCombat() then say2("Binds wait until combat ends."); return false end
    local tile = pickerTiles[pickerSel]
    if not tile then say2("No gamepad action slot selected. Nothing changed."); return false end
    local slot = tile.slot
    local before = actionInfo(slot)
    pickup(pickerBag, pickerSlot)
    if not bindCursorBusy() then
        GB.DebugTrace("action picker pickup failed", pickerBag .. ":" .. pickerSlot)
        say2("This item cannot be picked up. Nothing changed.")
        GB.CloseActionPicker(true)
        return false
    end
    local ok, err = pcall(PlaceAction, slot)
    if not ok then
        if ClearCursor then ClearCursor() end
        DB.bindBlocked = { event = "PlaceAction", action = tostring(err) }
        GB.DebugTrace("action picker refused", tostring(err))
        say2("The client refused action placement. Nothing changed.")
        GB.CloseActionPicker(true)
        return false
    end
    -- A protected call that did nothing is indistinguishable from success unless we look:
    -- an empty slot that stays empty means the client refused. Put the item back.
    if not before and not actionInfo(slot) then
        if bindCursorBusy() and ClearCursor then ClearCursor() end
        DB.bindBlocked = { event = "PlaceAction", action = "slot " .. slot .. " unchanged" }
        GB.DebugTrace("action picker refused", "slot " .. slot .. " unchanged")
        say2("The client refused action placement. Nothing changed.")
        GB.CloseActionPicker(true)
        return false
    end
    if bindCursorBusy() and ClearCursor then ClearCursor() end   -- displaced action/item; default is to clear it
    GB.DebugTrace("action slot place", slot)
    GB.CloseActionPicker(false)
    say2("Bound to action slot " .. slot .. ".")
    return true
end
function GB.OpenActionPicker(b)
    if bindHandoff then return false end
    if inCombat() then say2("Binds wait until combat ends."); return false end
    if not (frame and nav and b and b.bag and b.slot) then return false end
    if bindCursorBusy() then say2("Place the held item first, or cancel it with [O]."); return false end
    local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(b.bag, b.slot)
    if not (info and info.itemID) then return false end
    local edit = _G.GamepadActionBarEditFrame
    if edit and edit:IsShown() then return false end
    pickerBag, pickerSlot = b.bag, b.slot
    bindHandoff = true
    pickerPage = math.max(1, math.min(gpPageCount(), pickerPage or 1))
    pickerPageKeys = { pickerPageKeyPair() }
    focusMark = rememberSelection()
    SecureHandlerExecute(nav, "self:SetAttribute('bindinghandoff', 1); self:ClearBindings(); self:GetFrameRef('hl'):Hide()")
    SecureHandlerExecute(GB.itemMenu, MENU_HIDE_ALL)
    SecureHandlerExecute(GB.bagMenu, MENU_HIDE_ALL)
    PickerRebuild()
    picker:Show()
    SecureHandlerExecute(picker, pickerBindSnippet())
    local t = pickerTiles[pickerSel]
    say2("Choose an action slot. D-pad moves, [X] places, [O] cancels.")
    GB.DebugTrace("action picker open", pickerBag .. ":" .. pickerSlot .. " page " .. pickerPage .. " slot " .. (t and t.slot or "none"))
    return true
end
local function buildActionPicker()
    picker = CreateFrame("Frame", "AquiferActionPicker", UIParent, "SecureHandlerBaseTemplate,BackdropTemplate")
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:SetSize(PAD * 2 + GP_COLS * GP_TILE + (GP_COLS - 1) * GP_GAP,
        GP_ROWS * GP_TILE + (GP_ROWS - 1) * GP_GAP + 52)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    picker:SetBackdropColor(0.02, 0.09, 0.15, 0.98)
    picker:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetText("Bind to action bar")
    pickerPageText = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickerPageText:SetPoint("TOPRIGHT", -PAD, -9)
    pickerHint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickerHint:SetPoint("BOTTOMLEFT", PAD, 8)
    pickerHint:SetText(GB.HintText({ { "cross", "Place" }, { "circle", "Cancel" } }))
    pickerHl = CreateFrame("Frame", "AquiferActionPickerFocus", picker, "BackdropTemplate")
    pickerHl:SetFrameLevel(picker:GetFrameLevel() + 20)
    pickerHl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    pickerHl:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    pickerHl:Hide()
    local function padButton(key, label, handler)
        -- Same proven shape as the item-menu entries: secure frame, up-only click, snippet keeps
        -- the restricted click path, PostClick runs the addon callback.
        local b = CreateFrame("Button", "AquiferPicker" .. label, picker, "SecureActionButtonTemplate,SecureHandlerClickTemplate")
        b:SetSize(1, 1)
        b:SetPoint("TOPLEFT", picker, "TOPLEFT", -10, -10)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
        b:SetAttribute("_onclick", "if down then return end")
        b:SetScript("PostClick", function(self, button, down)
            if down then return end
            handler()
        end)
        SetRef(picker, key, b)
        pickerPad[key] = b
    end
    padButton("up", "Up", function() GB.PickerMove("up") end)
    padButton("down", "Down", function() GB.PickerMove("down") end)
    padButton("left", "Left", function() GB.PickerMove("left") end)
    padButton("right", "Right", function() GB.PickerMove("right") end)
    padButton("place", "Place", function() GB.PlacePickedAction() end)
    padButton("cancel", "Cancel", function() GB.CloseActionPicker(true) end)
    padButton("prevpage", "PrevPage", function() GB.PickerPage(-1) end)
    padButton("nextpage", "NextPage", function() GB.PickerPage(1) end)
    picker:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    picker:RegisterEvent("UPDATE_BINDINGS")
    picker:SetScript("OnEvent", function(_, event)
        if not bindHandoff then return end
        if event == "UPDATE_BINDINGS" then PickerRebuild() else PickerRefreshIcons() end
    end)
    picker:Hide()
end
local PROBE_PAT = { "Bind", "ActionBar", "Prompt", "GamePad", "Gamepad", "Controller", "QuickBind" }
local function probeMatch(k)
    for _, p in ipairs(PROBE_PAT) do if k:find(p) then return true end end
    return k:find("Spellbook") and k:find("Bind")
end
local function methodsOf(t, pat)
    local ms = {}
    for mk, mv in pairs(t) do
        if type(mk) == "string" and type(mv) == "function" and (not pat or mk:find("Bind") or mk:find("Use")) then ms[#ms + 1] = mk end
    end
    table.sort(ms)
    return ms
end
function GB.Probe()
    local out = {}
    local function add(l) out[#out + 1] = l; say2(l) end
    local names = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and probeMatch(k) then
            local t = type(v)
            if t == "table" and v.GetObjectType then t = "frame" end
            names[#names + 1] = k .. "(" .. t .. ")"
        end
    end
    table.sort(names)
    add("probe: " .. #names .. " global names (full list saved in AquiferDB.probe)")
    local line = ""
    for _, n in ipairs(names) do
        if #line + #n > 200 then say2(line); line = "" end
        line = line .. n .. " "
    end
    if line ~= "" then say2(line) end
    local cv = (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("GamePadEnable")) or (GetCVar and GetCVar("GamePadEnable"))
    add("GamePadEnable=" .. tostring(cv))
    if DB and DB.bindBlocked then
        add("Last bind block: " .. DB.bindBlocked.event .. " / " .. DB.bindBlocked.action)
    end
    if type(C_GamePad) == "table" then add("C_GamePad: " .. table.concat(methodsOf(C_GamePad), ", ")) else add("C_GamePad: absent") end
    local cb = _G.ContainerFrameCombinedBags
    if cb then
        local kids = {}
        if cb.GetChildren then
            for _, c in ipairs({ cb:GetChildren() }) do kids[#kids + 1] = (c.GetName and c:GetName()) or "?" end
        end
        add("CombinedBags children: " .. table.concat(kids, ", "))
        local items = cb.Items or cb.itemButtons
        local ib = type(items) == "table" and items[1] or nil
        if ib then
            add("item button methods (Bind/Use): " .. table.concat(methodsOf(ib, true), ", "))
            local mt = getmetatable(ib)
            if mt and type(mt.__index) == "table" then add("item button mixin (Bind/Use): " .. table.concat(methodsOf(mt.__index, true), ", ")) end
        else add("CombinedBags: no item button found (open the bag once, then retry)") end
    else add("ContainerFrameCombinedBags: absent") end
    for _, n in ipairs(names) do
        local k = n:match("^(.-)%(")
        if type(_G[k]) == "table" and not _G[k].GetObjectType then
            local ms = methodsOf(_G[k])
            if #ms > 0 then add(k .. ": " .. table.concat(ms, ", ")) end
        end
    end
    if DB then DB.probe = out; DB.probe[#DB.probe + 1] = table.concat(names, " ") end
end
-- Non-secure menu actions. They never touch protected frames.
GB.MenuActions = {
    pickup = function(b) if not inCombat() then pickup(b.bag, b.slot) end end,
    bank = function() if GB.OpenBank then GB.OpenBank() end end,
    -- Programmatic callers open the picker; stock binding code is never invoked.
    bind = function(b)
        GB.OpenActionPicker(b)
    end,
    -- Destroy: pick up, then the game's own delete confirmation (type DELETE for good items).
    destroy = function(b)
        local link = itemLink(b)
        if not link then return end
        pickup(b.bag, b.slot)
        local _, _, quality = itemInfo(b.bag, b.slot)
        local which = "DELETE_ITEM"
        if quality and quality >= 3 and StaticPopupDialogs and StaticPopupDialogs.DELETE_GOOD_ITEM then which = "DELETE_GOOD_ITEM" end
        if StaticPopup_Show then StaticPopup_Show(which, link)
        else say2("Item is on your cursor. Drag it out of the window to delete it.") end
    end,
    link = function(b)
        local link = itemLink(b)
        if not link then return end
        GB.OpenChatWith(link)
    end,
    split = function(b)
        local count = itemCount(b)
        if count < 2 then return say2("This item is not a stack.") end
        -- same call the stock bag makes: StackSplitFrame:OpenStackSplitFrame(maxStack, owner, anchor, anchorTo)
        local ss = _G.StackSplitFrame
        b.hasStackSplit = 1
        if ss and ss.OpenStackSplitFrame then
            pcall(ss.OpenStackSplitFrame, ss, count, b, "BOTTOMRIGHT", "TOPRIGHT")
            if ss.IsShown and ss:IsShown() then return end
        elseif _G.OpenStackSplitFrame then
            pcall(_G.OpenStackSplitFrame, count, b, "BOTTOMRIGHT", "TOPRIGHT")
            if ss and ss.IsShown and ss:IsShown() then return end
        end
        b.hasStackSplit = 0
        local half = math.floor(count / 2)
        if C_Container and C_Container.SplitContainerItem then C_Container.SplitContainerItem(b.bag, b.slot, half)
        elseif SplitContainerItem then SplitContainerItem(b.bag, b.slot, half) end
        say2("Split " .. half .. " onto your cursor. Press X on an empty slot to drop it.")
    end,
    hide = function() GB.ToggleCollapse() end,
    cleanup = function()
        if C_Container and C_Container.SortBags then C_Container.SortBags()
        elseif SortBags then SortBags() end
    end,
    junk = function()
        if not (MerchantFrame and MerchantFrame:IsShown()) then return say2("Open a vendor first.") end
        if C_Container and C_Container.SellAllJunkItems then C_Container.SellAllJunkItems() end
    end,
}
-- "Hide empty slots" (settings tick box + bag menu entry). DB.collapsed.
function GB.SetCollapsed(on)
    if inCombat() then return say2("Not in combat.") end
    DB.collapsed = on and true or false
    GB.UpdateMenuLabels()
    GB.Layout()
    if frame and frame:IsShown() then SecureHandlerExecute(nav, NAV_SETUP) end
    if footer then footer.shownKey = nil end
    GB.UpdateFooter()
end
function GB.ToggleCollapse() GB.SetCollapsed(not DB.collapsed) end

-- Runs after X: with an item on the cursor, drop it on the focused slot (and close any menu that
-- just opened). X on an empty slot does nothing else.
local function menuOpened()
    local b = slots[nav:GetAttribute("focus") or 1]
    if not (b and b.bag) then return end
    if CursorHasItem and CursorHasItem() then
        if not inCombat() then
            SecureHandlerExecute(GB.itemMenu, MENU_SHUT)
        end
        pickup(b.bag, b.slot)
    end
end
GB.MenuOpened = menuOpened

local function newMenu(kind, defs, parent)
    local m = CreateFrame("Frame", "AquiferMenu_" .. kind, parent, "SecureHandlerBaseTemplate,BackdropTemplate")
    m:SetFrameStrata("DIALOG")
    m:SetClampedToScreen(true)
    m:SetSize(150, #defs * 22 + 10)
    m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    m:SetBackdropColor(0.02, 0.09, 0.15, 0.98)
    m:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    m:SetAttribute("count", #defs)
    m:SetAttribute("pool", #defs)
    m:SetAttribute("sel", 1)
    m:SetAttribute("kind", kind)
    for i = 1, #defs do m:SetAttribute("v" .. i, i) end
    SetRef(m, "nav", nav)
    m:Hide()
    local mhl = CreateFrame("Frame", "AquiferMenuFocus_" .. kind, m, "BackdropTemplate")
    mhl:SetFrameLevel(m:GetFrameLevel() + 20)
    mhl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    mhl:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    mhl:Hide()
    SetRef(m, "mhl", mhl)
    m.hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.hint:SetPoint("TOPLEFT", m, "BOTTOMLEFT", 2, -4)
    m.entries = {}
    for i, def in ipairs(defs) do
        local secureAction = (def.key == "use" or def.key == "equip")
        local stockBind = def.key == "bind"
        local e = CreateFrame("Button", "AquiferMenu_" .. kind .. "_" .. def.key, m,
            (secureAction or stockBind) and "SecureActionButtonTemplate" or "SecureActionButtonTemplate,SecureHandlerClickTemplate")
        e:SetSize(140, 20)
        e:SetPoint("TOPLEFT", m, "TOPLEFT", 5, -5 - (i - 1) * 22)
        e:RegisterForClicks("AnyUp") -- up only: a bound key sends down + up
        e:SetAttribute("key", def.key)
        e:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        e.label = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        e.label:SetPoint("LEFT", 6, 0)
        e.label:SetText(def.label)
        e.def = def
        if stockBind then
            -- A single up-only PostClick prepares handoff. No PreClick, secure
            -- clickbutton delegation, or second MenuActions.bind invocation.
            e:SetAttribute("useOnKeyDown", false)
        elseif secureAction then
            e:SetAttribute("type", "macro")
            e:SetAttribute("useOnKeyDown", false)
            e:SetAttribute("macrotext", "")   -- snippet fills "/use <bag> <slot>" when the menu opens
            SecureHandlerWrapScript(e, "OnClick", m, "return nil, true", MENU_SHUT)  -- WoW Forever rejects a nil pre-body; returning a message makes the post-body run
        else
            SetRef(e, "menu", m)
            e:SetAttribute("_onclick", MENU_CLOSE)
        end
        e:SetScript("PostClick", function(self, button, down)
            if stockBind then
                if button == "LeftButton" and not down then
                    GB.OpenActionPicker(menuSlot())
                end
                return
            end
            if secureAction then
                if not inCombat() then SecureHandlerExecute(m, MENU_SHUT) end   -- backup if the wrap did not run
                return
            end
            local fn = GB.MenuActions[def.key]
            if not fn then return end
            if kind == "item" then
                local b = menuSlot()
                if b and (not inCombat() or def.key == "link") then fn(b) end
            elseif not inCombat() then fn() end
        end)
        SetRef(m, "e" .. i, e)
        m.entries[i] = e
    end
    for _, d in ipairs({ "up", "down" }) do
        local btn = CreateFrame("Button", "AquiferMenuPad_" .. kind .. d, m, "SecureHandlerClickTemplate")
        btn:SetAttribute("dir", d)
        SetRef(btn, "menu", m)
        btn:SetAttribute("_onclick", MENU_MOVE)
        btn:RegisterForClicks("AnyUp")
        SetRef(m, d, btn)
    end
    local cb = CreateFrame("Button", "AquiferMenuClose_" .. kind, m, "SecureHandlerClickTemplate")
    SetRef(cb, "menu", m)
    cb:SetAttribute("_onclick", MENU_CLOSE)
    cb:RegisterForClicks("AnyUp")
    SetRef(m, "closebtn", cb)
    return m
end

function GB.UpdateMenuLabels()
    local m = GB.bagMenu
    if not (m and m.entries and DB) then return end
    for _, e in ipairs(m.entries) do
        if e.def.key == "hide" then e.label:SetText("Hide empty slots: " .. (DB.collapsed and "On" or "Off")) end
    end
end

local function newOpener(name, mode, im, bm, parent)
    local o = CreateFrame("Button", name, parent, "SecureHandlerClickTemplate")
    o:SetAttribute("mode", mode)
    SetRef(o, "nav", nav)
    SetRef(o, "imenu", im)
    SetRef(o, "bmenu", bm)
    o:SetAttribute("_onclick", MENU_OPEN)
    o:RegisterForClicks("AnyUp")
    return o
end

local function buildMenu(parent)
    SetRef(nav, "frame", parent)
    local im = newMenu("item", ITEM_MENU, parent)
    local bm = newMenu("bag", BAG_MENU, parent)
    GB.itemMenu, GB.bagMenu = im, bm
    -- X: item menu on an item (cursor drop handled in PostClick). Triangle: item menu on an item, bag menu on an empty slot.
    local xo = newOpener("AquiferMenuOpen_x", "x", im, bm, parent)
    xo:SetScript("PostClick", menuOpened)
    local to = newOpener("AquiferMenuOpen_tri", "tri", im, bm, parent)
    GB.openX, GB.openTri = xo, to
    SetRef(nav, "itemopen", xo)
    SetRef(nav, "triopen", to)
    for _, m in ipairs({ im, bm }) do m.hint:SetText(GB.MenuHints()) end
    GB.UpdateMenuLabels()
    local cl = CreateFrame("Button", "AquiferCloseBag", parent, "SecureHandlerClickTemplate")
    SetRef(cl, "frame", parent)
    cl:SetAttribute("_onclick", CLOSE_BAG)
    cl:RegisterForClicks("AnyUp")
    SetRef(nav, "closebag", cl)
    -- Square: quick action on the focused item (Equip if equippable, else Use if usable). A secure
    -- macro button; the pre-body of the wrap fills "/use <bag> <slot>" from the focused slot.
    local qa = CreateFrame("Button", "AquiferQuick", parent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    qa:RegisterForClicks("AnyUp")
    qa:SetAttribute("type", "macro")
    qa:SetAttribute("useOnKeyDown", false)   -- we register up-clicks only; with ActionButtonUseKeyDown=1 the secure handler would otherwise ignore them
    qa:SetAttribute("macrotext", "")
    SecureHandlerWrapScript(qa, "OnClick", nav, QUICK_PRE)
    GB.quickBtn = qa
    SetRef(nav, "quick", qa)
    nav:SetAttribute("rebind", NAV_REBIND)
end
GB.MENU_OPEN, GB.MENU_MOVE, GB.MENU_CLOSE, GB.MENU_SHUT, GB.NAV_CLAMP, GB.CLOSE_BAG = MENU_OPEN, MENU_MOVE, MENU_CLOSE, MENU_SHUT, NAV_CLAMP, CLOSE_BAG

-- ---------- stock window focus and live interaction ----------
local function shown(name) local f = _G[name]; return f and f:IsShown() end
function GB.InteractionAction()
    if shown("MerchantFrame") then
        if MerchantFrame.selectedTab == 2 or (CanSellItems and not CanSellItems()) or (InRepairMode and InRepairMode()) then return "Unavailable" end
        return "Sell item"
    end
    if shown("BankFrame") then return "Deposit" end
    if shown("TradeFrame") then return "Trade" end
    if shown("MailFrame") and shown("SendMailFrame") then return "Attach" end
    -- These windows still use stock L2/R2 focus; X holds/drops for manual placement.
    if shown("MailFrame") or shown("AuctionFrame") or shown("AuctionHouseFrame") or shown("GuildBankFrame") then return "Pick up" end
end
-- Use the same per-item price as the stock tooltip; an uncached price is unknown.
function GB.ContextHint(slot,action)
    if action=="Unavailable" then return nil end
    if action~="Sell item" then return action end
    if not slot or not slot.bag then return nil end
    local info=C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(slot.bag,slot.slot)
    if info and info.hasNoValue then return "Can't sell" end
    local _,_,_,_,link=itemInfo(slot.bag,slot.slot)
    local gi=itemAPI("GetItemInfo")
    if not link or not gi then return nil end
    local price=select(11,gi(link))
    if issecretvalue and issecretvalue(price) then return nil end
    if type(price)~="number" then return nil end
    return price>0 and "Sell item" or "Can't sell"
end
function GB.RefreshInteraction()
    if not nav or inCombat() then return end
    nav:SetAttribute("interaction", GB.InteractionAction())
    if frame:IsShown() and not GB.itemMenu:IsShown() and not GB.bagMenu:IsShown() then
        SecureHandlerExecute(nav, "self:RunAttribute('rebind')")
    end
end
local function nativeFocusManager()
    -- These two methods are explicitly wrapped by Blizzard's SecureHelper, unlike
    -- BindItem. Never call the unwrapped FocusFrame/FocusNextFrame methods or set
    -- useCustomNavigation / any other stock-read flag from insecure Lua.
    if not SmartNavigationSecureHelper then return end
    local m = GamepadMode and GamepadMode.FrameControlsManager
    if m and type(m.FrameShown) == "function" and type(m.FrameHidden) == "function" then return m end
end
function GB.RegisterControllerFocus()
    if inCombat() or not frame or not frame:IsShown() or GB.IsBindingHandoff() then return end
    local m = nativeFocusManager()
    if not m then return end
    if pendingFocusRemoval and focusManager then focusManager:FrameHidden(frame) end
    pendingFocusRemoval = false
    focusManager = m
    m:FrameShown(frame) -- stock allowlisted wrapper; no addon-created taint wrapper
end
function GB.UnregisterControllerFocus()
    if not focusManager then return end
    if inCombat() then pendingFocusRemoval = true; return end
    local m = focusManager
    focusManager, pendingFocusRemoval = nil, false
    m:FrameHidden(frame)
end
function GB.ControllerFocusGained()
    GB.DebugTrace("focus gained")
    if inCombat() or not frame:IsShown() or GB.IsBindingHandoff() then return end
    nav:SetAttribute("focusowned", 1)
    GB.Layout()
    focusMark=nil
    GB.RefreshInteraction()
    SecureHandlerExecute(nav, NAV_CLAMP)
    if footer then footer.shownKey = nil end
end
function GB.ControllerFocusLost()
    GB.DebugTrace("focus lost")
    hoverSlot=nil; GB.HideSlotTooltip()
    if inCombat() then return end
    focusMark = focusMark or rememberSelection()
    nav:SetAttribute("focusowned", 0)
    SecureHandlerExecute(nav, "self:ClearBindings(); self:GetFrameRef('hl'):Hide()")
    SecureHandlerExecute(GB.itemMenu, MENU_HIDE_ALL)
    SecureHandlerExecute(GB.bagMenu, MENU_HIDE_ALL)
    -- Keep the window, selected slot and cursor item exactly as they are.
    if footer then footer.shownKey = nil end
end
local function buildContextAction()
    local b = CreateFrame("Button", "AquiferContextAction", frame, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp"); b:SetAttribute("useOnKeyDown", false)
    SetRef(nav, "contextaction", b)
    b:SetScript("PreClick", function(self, button, down)
        if inCombat() then return end
        self:SetAttribute("type", nil); self:SetAttribute("macrotext", nil)
        self.pickupSlot = nil
        if button ~= "LeftButton" or down or nav:GetAttribute("focusowned") == 0 or GB.IsBindingHandoff() then return end
        local slot = slots[nav:GetAttribute("focus") or 1]
        if not (slot and slot.bag) then return end
        local action = GB.InteractionAction()
        if not action then return end -- window closed since the key was bound; never accidentally use/equip
        if CursorHasItem and CursorHasItem() then self.pickupSlot = slot; return end
        if action == "Unavailable" or GB.ContextHint(slot,action)=="Can't sell" then return end
        if action == "Pick up" then self.pickupSlot = slot; return end
        local icon = itemInfo(slot.bag, slot.slot)
        if not icon then return end
        -- Native container use supplies the vendor/bank/trade context. Hardware
        -- secure macro, no direct stock item-button methods or binding/focus calls.
        self:SetAttribute("type", "macro")
        self:SetAttribute("macrotext", "/use " .. slot.bag .. " " .. slot.slot)
    end)
    b:SetScript("PostClick", function(self, button, down)
        if inCombat() then return end
        self:SetAttribute("type", nil); self:SetAttribute("macrotext", nil)
        local slot = self.pickupSlot; self.pickupSlot = nil
        if button == "LeftButton" and not down and slot then pickup(slot.bag, slot.slot) end
    end)
end

-- ---------- window ----------
-- Escape closes the window only out of combat: Hide() on a protected frame is blocked in combat.
function GB.SetEsc(on)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "AquiferFrame" then table.remove(UISpecialFrames, i) end
    end
    if on then table.insert(UISpecialFrames, "AquiferFrame") end
end
function GB.IsOpen() return frame and frame:IsShown() end

local function savePos()
    local p, _, rp, x, y = frame:GetPoint()
    DB.point = { p, rp, x, y }
end

function GB.Open()
    if not frame or not DB.enabled or bindHandoff then return end
    if inCombat() then return end
    if GB.CloseBank then GB.CloseBank() end
    GB.Layout()
    frame:Show()
    SecureHandlerExecute(nav, NAV_CLAMP)
end
function GB.Close()
    if not frame or inCombat() then return end
    frame:Hide()
end
function GB.Toggle() if GB.IsOpen() then GB.Close() else GB.Open() end end

-- Read the manager's public state; never change stock frame fields or focus methods.
function GB.FocusLabel()
    if bindHandoff then return "Action slots: [X] Place | [O] Cancel | L2/R2: page" end
    if inCombat() then return "Combat: controller paused" end
    local m=focusManager
    if m and m.isUIFocused == false then return "World controls: L2/R2 to Bags" end
    local active=m and m.focusedFrame
    if active and active~=frame then
        for _,pair in ipairs({{"BankFrame","Bank"},{"MerchantFrame","Vendor"},{"MailFrame","Mail"},
            {"TradeFrame","Trade"},{"CharacterFrame","Character"},{"AuctionFrame","Auction"},{"GuildBankFrame","Guild bank"}}) do
            if active==_G[pair[1]] then return "Controls: "..pair[2].." | L2/R2: windows" end
        end
        return "Controls: other window | L2/R2: windows"
    end
    if GB.itemMenu and GB.itemMenu:IsShown() then return "Controls: Item menu | Circle: back to Bags" end
    if GB.bagMenu and GB.bagMenu:IsShown() then return "Controls: Bag menu | Circle: back to Bags" end
    if nav and nav:GetAttribute("focusowned")==0 then return "Controls: stock window | L2/R2: Bags" end
    if DB and not DB.padNav then return "Bags: controller navigation off" end
    return "Controls: Bags | Yellow box = selected slot"
end
function GB.UpdateFocusNotice()
    if focusNotice then
        focusNotice.label:SetText(GB.FocusLabel())
        if DB and DB.notice and (bindHandoff or (frame and frame:IsShown())) then focusNotice:Show() else focusNotice:Hide() end
    end
end
function GB.SyncControllerFocus()
    if inCombat() or not nav or not frame:IsShown() or bindHandoff then return end
    local m=focusManager
    if m and m.isUIFocused~=nil then
        local owned=m.isUIFocused and m.focusedFrame==frame
        if owned and nav:GetAttribute("focusowned")==0 then GB.ControllerFocusGained()
        elseif not owned and nav:GetAttribute("focusowned")~=0 then GB.ControllerFocusLost() end
    elseif nav:GetAttribute("focusowned")==0 then GB.ControllerFocusGained() end
end
function GB.RecoverControllerFocus()
    if bindHandoff then GB.CloseActionPicker(true); return end
    if inCombat() then focusRecoveryPending=true; return end
    if not frame or not DB.enabled then return end
    focusMark=focusMark or rememberSelection()
    SecureHandlerExecute(GB.itemMenu,MENU_HIDE_ALL)
    SecureHandlerExecute(GB.bagMenu,MENU_HIDE_ALL)
    GB.UnregisterControllerFocus()
    GB.Open()
    GB.RegisterControllerFocus()
    GB.SyncControllerFocus()
    GB.UpdateFooter()
end
function GB.BuildFocusNotice()
    focusNotice=CreateFrame("Frame","AquiferFocusNotice",UIParent,"BackdropTemplate")
    focusNotice:SetSize(410,30)
    focusNotice:SetPoint("BOTTOMLEFT",frame,"TOPLEFT",0,4)
    focusNotice:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
    focusNotice:SetBackdropColor(.03,.05,.08,.95)
    focusNotice.label=focusNotice:CreateFontString(nil,"OVERLAY","GameFontNormal")
    focusNotice.label:SetPoint("TOPLEFT",8,-7)
    focusNotice:Hide()
end

local function build()
    -- Secure template on purpose: restricted snippets (Circle = CLOSE_BAG) may only Hide a protected frame.
    -- Consequence: show / hide / move / resize only outside combat (all of those are guarded below).
    frame = CreateFrame("Frame", "AquiferFrame", UIParent, "SecureHandlerBaseTemplate,BackdropTemplate")
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
    freeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("TOPRIGHT", -PAD, -10)
    moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyText:SetPoint("BOTTOMRIGHT", -PAD, 26)
    footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", PAD, 8)
    -- Search box. Only reachable by mouse/cursor click: the d-pad grid never lands on it.
    search = CreateFrame("EditBox", "AquiferSearch", frame, "InputBoxTemplate")
    search:SetSize(110, 18)
    search:SetPoint("TOPLEFT", PAD + 6, -6)
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
    GB.SetEsc(true)

    nav = CreateFrame("Frame", "AquiferNav", frame, "SecureHandlerBaseTemplate")
    hl = CreateFrame("Frame", "AquiferFocus", frame, "BackdropTemplate")
    hl:SetSize(SLOT + 4, SLOT + 4)
    hl:SetFrameLevel(frame:GetFrameLevel() + 20)
    hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
    hl:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    hl:Hide()
    SetRef(nav, "hl", hl)
    buildMenu(frame)
    SetRef(nav,"itemmenu",GB.itemMenu)
    SetRef(nav,"bagmenu",GB.bagMenu)
    buildActionPicker()
    buildContextAction()
    for _, d in ipairs({ "up", "down", "left", "right" }) do
        local btn = CreateFrame("Button", "AquiferPad" .. d, frame, "SecureHandlerClickTemplate")
        btn:SetAttribute("dir", d)
        SetRef(btn, "nav", nav)
        btn:SetAttribute("_onclick", NAV_MOVE)
        -- ONE click event per press: a key bound with SetBindingClick sends a down click AND an
-- up click. Registering for both ran the move twice (two slots per press). Up only.
        btn:RegisterForClicks("AnyUp")
        SetRef(nav, d, btn)
    end
    GB.BuildFocusNotice()
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc > 0.1 then acc = 0; GB.SyncControllerFocus(); GB.UpdateFooter() end
    end)
    nav:SetAttribute("_onstate-combat", [[
        if newstate == "1" then
            self:SetAttribute("combatpaused",1)
            self:SetAttribute("focusowned",0)
            self:ClearBindings()
            self:GetFrameRef("hl"):Hide()
            local im=self:GetFrameRef("itemmenu")
            local bm=self:GetFrameRef("bagmenu")
            if im then im:ClearBindings(); im:Hide() end
            if bm then bm:ClearBindings(); bm:Hide() end
        else self:SetAttribute("combatpaused",nil) end
    ]])
    RegisterStateDriver(nav,"combat","[combat] 1; 0")
    frame.FocusGamepad = GB.ControllerFocusGained
    frame.UnfocusGamepad = GB.ControllerFocusLost
    frame:SetScript("OnShow", function()
        GB.DebugTrace("Aquifer shown")
        GB.UpdateFocusNotice(); footer.shownKey = nil; GB.Refresh(); GB.RefreshInteraction(); GB.RegisterControllerFocus(); GB.UpdateFooter()
    end)
    frame:SetScript("OnHide", function()
        GB.DebugTrace("Aquifer hidden")
        if bindHandoff then GB.CloseActionPicker(true, true) end
        hoverSlot=nil; tooltipFocus=nil; GB.HideSlotTooltip()
        GB.UnregisterControllerFocus()
        if focusNotice and not bindHandoff then focusNotice:Hide() end
        if search then search:ClearFocus() end
        if not inCombat() then
            SecureHandlerExecute(nav, "self:ClearBindings(); self:GetFrameRef('hl'):Hide()")
            SecureHandlerExecute(GB.itemMenu, MENU_HIDE_ALL)
            SecureHandlerExecute(GB.bagMenu, MENU_HIDE_ALL)
        end
    end)
end

-- ---------- minimap button ----------
function GB.PlaceMinimap()
    if not mmButton then return end
    local mm = DB.minimap
    if mm.hide then mmButton:Hide(); return end
    local w = Minimap.GetWidth and Minimap:GetWidth() or 140
    if not w or w < 10 then w = 140 end
    local x, y = GB.MinimapOffset(mm.angle, w / 2 + 10)
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    mmButton:Show()
end

local function buildMinimap()
    if not Minimap then return end
    local b = CreateFrame("Button", "AquiferMinimapButton", Minimap)
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
        GameTooltip:SetText("Aquifer")
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
    local f = CreateFrame("Frame", "AquiferSettings", UIParent, "BackdropTemplate")
    settings = f
    f:SetSize(240, 216); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.02, 0.09, 0.15, 0.96); f:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10); t:SetText("|cff55ccffSettings|r")
    local close = CreateFrame("Button", "AquiferSettingsClose", f, "UIPanelCloseButton")
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
        check("AquiferCheckMinimap", -34, "Hide minimap icon", function() return DB.minimap.hide end, GB.SetMinimapHidden),
        check("AquiferCheckPad", -60, "Controller d-pad in bag", function() return DB.padNav end, function(v) GB.SetPad(v) end),
        check("AquiferCheckBag", -86, "Use Aquifer instead of normal bag", function() return DB.enabled end, function(v) GB.SetEnabled(v) end),
        check("AquiferCheckHide", -112, "Hide empty slots", function() return DB.collapsed end, function(v) GB.SetCollapsed(v) end),
    }
    local cl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cl:SetPoint("TOPLEFT", 14, -152)
    f.colText = cl
    local function colBtn(name, x, txt, d)
        local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
        b:SetSize(26, 22); b:SetPoint("TOPLEFT", x, -174); b:SetText(txt)
        b:SetScript("OnClick", function() GB.SetCols(DB.columns + d); f.refresh() end)
    end
    colBtn("AquiferColMinus", 14, "-", -1); colBtn("AquiferColPlus", 44, "+", 1)
    f.refresh = function()
        cl:SetText("Columns: " .. DB.columns)
        for _, c in ipairs(f.checks) do c.refresh() end
    end
    f:SetScript("OnShow", f.refresh)
    f:Hide()
    tinsert(UISpecialFrames, "AquiferSettings")
end
function GB.ToggleSettings()
    if not settings then return end
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

-- ---------- default bag replacement ----------

local HIDE_DEFAULT_BAGS = [[
for i = 1, self:GetAttribute("defaultbagcount") or 0 do
    local bag = self:GetFrameRef("defaultbag" .. i)
    if bag and bag:IsShown() then bag:Hide(true) end
end
]]
hideDefault = function()
    if not DB or not DB.enabled or inCombat() or bindHandoff or not nav then return end
    local count = 0
    for _, name in ipairs(DEFAULT_FRAMES) do
        local bag = _G[name]
        local id = bag and bag.GetID and bag:GetID()
        if bag and (name == "ContainerFrameCombinedBags" or id == nil or (id >= 0 and id <= (NUM_BAG_SLOTS or 4))) then
            count = count + 1; SetRef(nav, "defaultbag" .. count, bag)
        end
    end
    nav:SetAttribute("defaultbagcount", count)
    -- RestrictedFrames.HANDLE:Hide uses Blizzard's native frame method. Do not
    -- run stock bag OnHide/focus callbacks from an ordinary addon frame:Hide().
    SecureHandlerExecute(nav, HIDE_DEFAULT_BAGS)
end

local function hookAll()
    local toggles = { "ToggleAllBags", "ToggleBackpack", "ToggleBag" }
    local opens = { "OpenAllBags", "OpenBackpack", "OpenBag" }
    local closes = { "CloseAllBags", "CloseBackpack", "CloseBag" }
    local function ours(fn, name)
        return function(bagID)
            GB.DebugTrace(name or "bag API",bagID)
            if type(bagID) == "number" and (bagID < 0 or bagID > (NUM_BAG_SLOTS or 4)) then return end
            if not DB.enabled or inCombat() or bindHandoff then return end -- Leave stock input/focus alone during binding.
            fn(); hideDefault()
        end
    end
    for _, n in ipairs(toggles) do if _G[n] then hooksecurefunc(n, ours(GB.Toggle,n)) end end
    for _, n in ipairs(opens) do if _G[n] then hooksecurefunc(n, ours(GB.Open,n)) end end
    for _, n in ipairs(closes) do if _G[n] then hooksecurefunc(n, ours(GB.Close,n)) end end
    for _, name in ipairs(DEFAULT_FRAMES) do
        local f = _G[name]
        if f and f.HookScript then
            f:HookScript("OnShow", function(self)
                GB.DebugTrace("stock shown",debugFrame(self)); hideDefault()
            end)
            f:HookScript("OnHide", function(self) GB.DebugTrace("stock hidden",debugFrame(self)) end)
        end
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

local function say(m) print("|cff66ccffAquifer|r " .. m) end
local function slash(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "bug" then GB.ShowBugReport()
    elseif cmd == "debug" then
        DB.debugEnabled=not DB.debugEnabled
        if DB.debugEnabled then
            debugState=nil; GB.DebugTrace("debug on","2.2.7"); GB.DebugPoll(0.1)
        else say("Debug chat off; quiet recording continues.") end
    elseif cmd == "bank" then GB.OpenBank()
    elseif cmd == "recover" then GB.RecoverControllerFocus()
    elseif cmd == "notice" then
        DB.notice=not DB.notice;GB.UpdateFocusNotice()
        say("Focus notice "..(DB.notice and "on." or "off."))
    elseif cmd == "bindcancel" then GB.CloseActionPicker(true)
    elseif cmd == "" or cmd == "help" then
        say("/aquifer toggle - open or close the bag (also /aq)")
        say("/aquifer settings - settings window")
        say("/aq bank or /aqb - read-only bank memory (visit your bank to save it)")
        say("Bind: the d-pad picks an action slot, [X] places, [O] cancels, L2/R2 changes page.")
        say("/aq recover - restore Bags controls; /aq notice - toggle the optional focus notice")
        say("/aq bindcancel - close the action-slot picker")
        say("/aquifer minimap on|off - minimap icon")
        say("/aquifer search word - grey out other items")
        say("/aquifer cols 8 - slots per row (4 to 20)")
        say("/aquifer default on|off - on = use the normal bag again")
        say("/aquifer pad on|off - controller d-pad moves in the grid")
        say("/aquifer scale 1 - window size (0.5 to 2)")
        say("/aquifer reset - put the window back")
        say("Controller (PlayStation): X or Triangle on an item = item menu (Use, Equip, Bind, Split, Share, Destroy); Triangle on an empty slot = bag menu (Cleanup, Sell Junk, Hide empty slots); Square = quick Equip/Use; Circle = close; d-pad = move.")
        say("/aquifer glyphs - show which button pictures were found; /aquifer glyph cross AtlasName sets one")
        say("/aquifer hide on|off - hide empty slots (also a tick box in settings and an entry in the Triangle bag menu)")
        say("/aquifer probe - list the client's bind / gamepad names (send to Claude)")
        say("L2/R2: switch between Aquifer and open stock windows. Cross (Xbox A): Sell item, Deposit, Attach on Send Mail, or Trade, as shown below the grid. Triangle > Pick up: hold an item for manual placement.")
        say("/aquifer config - show settings")
        say("Alt + drag moves the window.")
    elseif cmd == "toggle" then GB.Toggle()
    elseif cmd == "settings" or cmd == "options" then GB.ToggleSettings()
    elseif cmd == "minimap" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /aquifer minimap on  or  off") end
        GB.SetMinimapHidden(on == "off")
        say("Minimap icon: " .. (DB.minimap.hide and "hidden" or "shown"))
    elseif cmd == "search" then GB.SetQuery(arg); if search then search:SetText(arg) end
    elseif cmd == "cols" or cmd == "columns" then
        local v = tonumber(arg)
        if not v then return say("Use a number, like /aquifer cols 8") end
        GB.SetCols(v); say("Columns: " .. DB.columns)
        if pending then say("In combat. Will apply after.") end
    elseif cmd == "default" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /aquifer default on  or  off") end
        GB.SetEnabled(on == "off")
        say(DB.enabled and "Aquifer bag is ON." or "Normal bag is back. Aquifer is OFF.")
    elseif cmd == "pad" then
        local on = arg:lower()
        if on ~= "on" and on ~= "off" then return say("Use: /aquifer pad on  or  off") end
        GB.SetPad(on == "on")
        say("Controller d-pad grid: " .. (DB.padNav and "ON" or "OFF"))
    elseif cmd == "scale" then
        local v = tonumber(arg)
        if not v then return say("Use a number, like /aquifer scale 1") end
        DB.scale = math.max(0.5, math.min(2, v))
        if frame and not inCombat() then frame:SetScale(DB.scale) end
        say("Scale: " .. DB.scale)
    elseif cmd == "reset" then
        if inCombat() then return say("Not in combat.") end
        DB.point = nil; frame:ClearAllPoints()
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 120)
        say("Window put back.")
    elseif cmd == "probe" or cmd == "bindprobe" then
        GB.Probe()
    elseif cmd == "hide" then
        GB.SetCollapsed(arg == "on" or (arg ~= "off" and not DB.collapsed)); say("Hide empty slots: " .. (DB.collapsed and "ON" or "OFF"))
    elseif cmd == "glyphs" then
        for _, l in ipairs(GB.GlyphReport()) do say(l) end
    elseif cmd == "glyph" then
        local btn, atlas = arg:match("^(%S+)%s+(%S+)$")
        if not (btn and GLYPH_TEXT[btn:lower()]) then return say("Use: /aquifer glyph cross|circle|square|triangle AtlasName") end
        DB.glyph = DB.glyph or {}; DB.glyph[btn:lower()] = atlas; GB.ResetGlyphs()
        if footer then footer.shownKey = nil end
        say(btn:lower() .. " glyph set to " .. atlas .. (atlasExists(atlas) and "" or " (not found in the client, text fallback stays)"))
    elseif cmd == "config" then
        say("Aquifer: " .. (DB.enabled and "ON" or "OFF (normal bag)"))
        say("Columns: " .. DB.columns .. "   Scale: " .. DB.scale)
        say("Controller d-pad grid: " .. (DB.padNav and "ON" or "OFF"))
    else say("Unknown. Type /aquifer help") end
end
GB.Slash = slash
SLASH_AQUIFER1 = "/aquifer"
SLASH_AQUIFER2 = "/aq"
SlashCmdList.AQUIFER = slash

-- ---------- events ----------
local ev = CreateFrame("Frame", "AquiferEvents")
ev:SetScript("OnUpdate", function(_, elapsed)
    GB.DebugPoll(elapsed)
end)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED", "CURSOR_CHANGED", "ACTIONBAR_SLOT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_MONEY", "BAG_UPDATE_COOLDOWN", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, e, a1, a2)
    if e=="CURSOR_CHANGED" or e=="ACTIONBAR_SLOT_CHANGED" or e=="PLAYER_REGEN_DISABLED" or e=="PLAYER_REGEN_ENABLED" then GB.DebugTrace(e,a1) end
    if (e == "ADDON_ACTION_BLOCKED" or e == "ADDON_ACTION_FORBIDDEN") and a1 == addonName then
        DB.bindBlocked = { event = e, action = tostring(a2 or "unknown") }
        if bindHandoff then
            if bindCursorBusy() and ClearCursor then ClearCursor() end
            GB.CloseActionPicker(true)
        end
        say2("Placement blocked. The bug report has the details.")
        return
    end
    if e == "ADDON_LOADED" and a1 == addonName then
        -- Migrate settings from the old Waterys Satchel, Tidepool or GridBag addon (once, only if it has none yet).
        if not AquiferDB then
            AquiferDB = {}
            if type(WaterysSatchelDB) == "table" then
                for k, v in pairs(WaterysSatchelDB) do AquiferDB[k] = v end
            end
            if next(AquiferDB) == nil and type(TidepoolDB) == "table" then
                for k, v in pairs(TidepoolDB) do AquiferDB[k] = v end
            end
            if next(AquiferDB) == nil and type(GridBagDB) == "table" then
                for k, v in pairs(GridBagDB) do AquiferDB[k] = v end
            end
        end
        DB = AquiferDB
        -- Preserve the captured ring, but stop the diagnostic build's enabled flag once.
        if DB.debugBuild~="2.2.7" then DB.debugEnabled=false; DB.debugBuild="2.2.7" end
        if type(DB.minimap) ~= "table" then DB.minimap = {} end
        for k, v in pairs(MM_DEFAULT) do if DB.minimap[k] == nil then DB.minimap[k] = v end end
        for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = v end end
        GB.DB = DB
        GB.DebugTrace("addon loaded","2.2.7")
    elseif e == "PLAYER_LOGIN" then
        DB = AquiferDB or DB
        build(); buildMinimap(); buildSettings(); hookAll()
        GB.Layout()
    elseif e == "PLAYER_REGEN_DISABLED" then
        hoverSlot=nil; GB.HideSlotTooltip()
        if frame then GB.SetEsc(false) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if pickerAttrStuck then
            pickerAttrStuck = false
            if nav then SecureHandlerExecute(nav, "self:SetAttribute('bindinghandoff', nil); self:RunAttribute('rebind')") end
        end
        if frame then GB.SetEsc(true) end
        if pendingFocusRemoval then GB.UnregisterControllerFocus() end
        if frame and frame:IsShown() then GB.RegisterControllerFocus(); GB.RefreshInteraction() end
        if frame and pending then GB.Layout() end
        if frame and frame:IsShown() then GB.Refresh(); GB.SyncControllerFocus() end
        if focusRecoveryPending then focusRecoveryPending=nil; GB.RecoverControllerFocus() end
    elseif frame and frame:IsShown() then
        if e == "BAG_UPDATE" and not inCombat() then
            -- bag sizes can change when a bag is swapped
            local n = 0
            for _, s in ipairs(GB.BuildOrder(currentSizes())) do n = n + 1 end
            if n ~= shownCount or DB.collapsed then GB.Layout() else GB.Refresh() end
        else GB.Refresh() end
    end
end)
