-- Waterys Satchel: one combined bag as a plain grid, with explicit controller neighbors. (was GridBag)
local addonName = ...
local GB = {}
_G.WaterysSatchel = GB

local DEFAULTS = { enabled = true, columns = 8, scale = 1, padNav = true, collapsed = false }
local MM_DEFAULT = { angle = 215, hide = false }
-- Frame refs: the global SecureHandlerSetFrameRef works even when BackdropTemplate wipes the secure template's methods (WoW Forever crash at :SetFrameRef, Nov 6).
local function SetRef(f, k, v) if SecureHandlerSetFrameRef then SecureHandlerSetFrameRef(f, k, v) else f:SetFrameRef(k, v) end end
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

-- Which entries the item menu offers for one item. Pure: takes the link and stack count.
-- Use only if the item is usable, Equip only if it is equippable, Split only for stacks.
function GB.ItemMenuKeys(link, count)
    local k = { bind = true, link = true, destroy = true }
    if count and count > 1 then k.split = true end
    if link then
        if IsEquippableItem and IsEquippableItem(link) then k.equip = true end
        local usable = false
        if GetItemSpell and GetItemSpell(link) then usable = true end
        if not usable and GetItemInfoInstant then
            local _, _, _, _, _, classID = GetItemInfoInstant(link)
            if classID == 0 then usable = true end   -- consumable
        end
        if not usable and not k.equip and IsUsableItem and IsUsableItem(link) then usable = true end
        k.use = usable
    end
    return k
end

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
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetBagItem then GameTooltip:SetBagItem(self.bag, self.slot) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    slots[i] = b
    SetRef(nav, "s" .. i, b)
    return b
end

-- The restricted menu snippet reads these slot attributes (m_<key>, hasitem). Only outside combat.
local MENU_KEYS = { "use", "equip", "bind", "split", "link", "destroy" }
local function updateSlotMenu(b)
    if inCombat() or not b.bag then return end
    local icon, count, _, _, link = itemInfo(b.bag, b.slot)
    local k = icon and GB.ItemMenuKeys(link, count) or {}
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
if nav:GetAttribute("padnav") == 1 then
  nav:SetBindingClick(true, "PADDUP", nav:GetFrameRef("up"), "LeftButton")
  nav:SetBindingClick(true, "PADDDOWN", nav:GetFrameRef("down"), "LeftButton")
  nav:SetBindingClick(true, "PADDLEFT", nav:GetFrameRef("left"), "LeftButton")
  nav:SetBindingClick(true, "PADDRIGHT", nav:GetFrameRef("right"), "LeftButton")
  nav:SetBindingClick(true, "PAD1", nav:GetFrameRef("itemopen"), "LeftButton")
  nav:SetBindingClick(true, "PAD2", nav:GetFrameRef("closebag"), "LeftButton")
  nav:SetBindingClick(true, "PAD3", nav:GetFrameRef("quick"), "LeftButton")
  nav:SetBindingClick(true, "PAD4", nav:GetFrameRef("triopen"), "LeftButton")
end
]]
local NAV_SETUP = [[
local nav = self
nav:SetAttribute("focus", 1)
local b = nav:GetFrameRef("s1")
local hl = nav:GetFrameRef("hl")
if b and hl then hl:ClearAllPoints(); hl:SetPoint("CENTER", b, "CENTER"); hl:Show() end
nav:RunAttribute("rebind")
]]
-- After a re-layout: keep focus inside the new slot count and put the yellow box back.
local NAV_CLAMP = [[
local nav = self
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
}
local BAG_MENU = {
  { key = "cleanup", label = "Cleanup" },
  { key = "junk",    label = "Sell Junk" },
  { key = "hide",    label = "Hide empty slots" },
}
GB.ITEM_MENU, GB.BAG_MENU = ITEM_MENU, BAG_MENU
-- Run by X (mode "x") and Triangle (mode "tri"). Item under focus -> item menu, built from the
-- m_<key> attributes on the slot. Empty slot -> bag menu for Triangle, nothing for X.
-- Anchors only to protected frames (secure slot buttons / the menu itself).
local MENU_OPEN = [[
if down then return end
local nav = self:GetFrameRef("nav")
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
    nav:SetAttribute("count", n)
    nav:SetAttribute("padnav", DB.padNav and 1 or 0)
    GB.Refresh()
    if frame:IsShown() and not (GB.itemMenu:IsShown() or GB.bagMenu:IsShown()) then SecureHandlerExecute(nav, NAV_CLAMP) end
end


-- ---------- controller button hints (footer) ----------
-- The stock UI draws PlayStation art from the client's atlas. This client ships no readable UI
-- code, so the exact atlas names could not be read from disk. We probe likely names at run time
-- (and /satchel glyph <button> <atlas> can set one by hand). Fallback: plain yellow text.
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
    if not (footer and frame and frame:IsShown() and nav) then return end
    local b = slots[nav:GetAttribute("focus") or 1]
    local icon, count, _, _, link
    if b and b.bag then icon, count, _, _, link = itemInfo(b.bag, b.slot) end
    local onItem = icon and true or false
    local quick = onItem and GB.QuickLabel(link, count) or nil
    local key = (onItem and "i" or "e") .. tostring(quick)
    if footer.shownKey ~= key then footer.shownKey = key; footer:SetText(GB.GridHints(onItem, quick)) end
end

local function menuSlot()
    local m = GB.itemMenu
    local i = m and m:GetAttribute("slotindex")
    local b = i and slots[i]
    if b and b.bag then return b end
end
local function say2(m) print("|cff66ccffWaterys Satchel|r " .. m) end
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
-- Bind on a controller: use the stock gamepad binding flow (Blizzard_GamepadSharedUtility:
-- PromptedBindings / InputBindingStack). The client's UI source is packed, so the entry points are
-- probed at run time; /satchel probe lists what this client really has.
function GB.StartControllerBind(b)
    say2("Bind: send /satchel probe output to Claude")
    return false
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
    add("probe: " .. #names .. " global names (full list saved in WaterysSatchelDB.probe)")
    local line = ""
    for _, n in ipairs(names) do
        if #line + #n > 200 then say2(line); line = "" end
        line = line .. n .. " "
    end
    if line ~= "" then say2(line) end
    local cv = GetCVar and GetCVar("GamePadEnable")
    add("GamePadEnable=" .. tostring(cv))
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
    -- Bind: item goes on the cursor so it can be dropped on an action bar button; key binding mode opens too.
    bind = function(b)
        GB.StartControllerBind(b)
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
    local m = CreateFrame("Frame", "WaterysSatchelMenu_" .. kind, parent, "SecureHandlerBaseTemplate,BackdropTemplate")
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
    local mhl = CreateFrame("Frame", "WaterysSatchelMenuFocus_" .. kind, m, "BackdropTemplate")
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
        local e = CreateFrame("Button", "WaterysSatchelMenu_" .. kind .. "_" .. def.key, m,
            secureAction and "SecureActionButtonTemplate" or "SecureActionButtonTemplate,SecureHandlerClickTemplate")
        e:SetSize(140, 20)
        e:SetPoint("TOPLEFT", m, "TOPLEFT", 5, -5 - (i - 1) * 22)
        e:RegisterForClicks("AnyUp") -- up only: a bound key sends down + up
        e:SetAttribute("key", def.key)
        e:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        e.label = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        e.label:SetPoint("LEFT", 6, 0)
        e.label:SetText(def.label)
        e.def = def
        if secureAction then
            e:SetAttribute("type", "macro")
            e:SetAttribute("useOnKeyDown", false)
            e:SetAttribute("macrotext", "")   -- snippet fills "/use <bag> <slot>" when the menu opens
            SecureHandlerWrapScript(e, "OnClick", m, "return nil, true", MENU_SHUT)  -- WoW Forever rejects a nil pre-body; returning a message makes the post-body run
        else
            SetRef(e, "menu", m)
            e:SetAttribute("_onclick", MENU_CLOSE)
        end
        e:SetScript("PostClick", function()
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
        local btn = CreateFrame("Button", "WaterysSatchelMenuPad_" .. kind .. d, m, "SecureHandlerClickTemplate")
        btn:SetAttribute("dir", d)
        SetRef(btn, "menu", m)
        btn:SetAttribute("_onclick", MENU_MOVE)
        btn:RegisterForClicks("AnyUp")
        SetRef(m, d, btn)
    end
    local cb = CreateFrame("Button", "WaterysSatchelMenuClose_" .. kind, m, "SecureHandlerClickTemplate")
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
    local xo = newOpener("WaterysSatchelMenuOpen_x", "x", im, bm, parent)
    xo:SetScript("PostClick", menuOpened)
    local to = newOpener("WaterysSatchelMenuOpen_tri", "tri", im, bm, parent)
    GB.openX, GB.openTri = xo, to
    SetRef(nav, "itemopen", xo)
    SetRef(nav, "triopen", to)
    for _, m in ipairs({ im, bm }) do m.hint:SetText(GB.MenuHints()) end
    GB.UpdateMenuLabels()
    local cl = CreateFrame("Button", "WaterysSatchelCloseBag", parent, "SecureHandlerClickTemplate")
    SetRef(cl, "frame", parent)
    cl:SetAttribute("_onclick", CLOSE_BAG)
    cl:RegisterForClicks("AnyUp")
    SetRef(nav, "closebag", cl)
    -- Square: quick action on the focused item (Equip if equippable, else Use if usable). A secure
    -- macro button; the pre-body of the wrap fills "/use <bag> <slot>" from the focused slot.
    local qa = CreateFrame("Button", "WaterysSatchelQuick", parent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
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

-- ---------- window ----------
-- Escape closes the window only out of combat: Hide() on a protected frame is blocked in combat.
function GB.SetEsc(on)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "WaterysSatchelFrame" then table.remove(UISpecialFrames, i) end
    end
    if on then table.insert(UISpecialFrames, "WaterysSatchelFrame") end
end
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
    -- Secure template on purpose: restricted snippets (Circle = CLOSE_BAG) may only Hide a protected frame.
    -- Consequence: show / hide / move / resize only outside combat (all of those are guarded below).
    frame = CreateFrame("Frame", "WaterysSatchelFrame", UIParent, "SecureHandlerBaseTemplate,BackdropTemplate")
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
    search = CreateFrame("EditBox", "WaterysSatchelSearch", frame, "InputBoxTemplate")
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

    nav = CreateFrame("Frame", "WaterysSatchelNav", frame, "SecureHandlerBaseTemplate")
    hl = CreateFrame("Frame", "WaterysSatchelFocus", frame, "BackdropTemplate")
    hl:SetSize(SLOT + 4, SLOT + 4)
    hl:SetFrameLevel(frame:GetFrameLevel() + 20)
    hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
    hl:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    hl:Hide()
    SetRef(nav, "hl", hl)
    buildMenu(frame)
    for _, d in ipairs({ "up", "down", "left", "right" }) do
        local btn = CreateFrame("Button", "WaterysSatchelPad" .. d, frame, "SecureHandlerClickTemplate")
        btn:SetAttribute("dir", d)
        SetRef(btn, "nav", nav)
        btn:SetAttribute("_onclick", NAV_MOVE)
        -- ONE click event per press: a key bound with SetBindingClick sends a down click AND an
-- up click. Registering for both ran the move twice (two slots per press). Up only.
        btn:RegisterForClicks("AnyUp")
        SetRef(nav, d, btn)
    end
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc > 0.1 then acc = 0; GB.UpdateFooter() end
    end)
    frame:SetScript("OnShow", function() footer.shownKey = nil; GB.Refresh(); GB.UpdateFooter() end)
    frame:SetScript("OnHide", function()
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
    f:SetSize(240, 216); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.02, 0.09, 0.15, 0.96); f:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10); t:SetText("|cff55ccffSettings|r")
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
        check("WaterysSatchelCheckHide", -112, "Hide empty slots", function() return DB.collapsed end, function(v) GB.SetCollapsed(v) end),
    }
    local cl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cl:SetPoint("TOPLEFT", 14, -152)
    f.colText = cl
    local function colBtn(name, x, txt, d)
        local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
        b:SetSize(26, 22); b:SetPoint("TOPLEFT", x, -174); b:SetText(txt)
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
        say("Controller (PlayStation): X or Triangle on an item = item menu (Use, Equip, Bind, Split, Share, Destroy); Triangle on an empty slot = bag menu (Cleanup, Sell Junk, Hide empty slots); Square = quick Equip/Use; Circle = close; d-pad = move.")
        say("/satchel glyphs - show which button pictures were found; /satchel glyph cross AtlasName sets one")
        say("/satchel hide on|off - hide empty slots (also a tick box in settings and an entry in the Triangle bag menu)")
        say("/satchel probe - list the client's bind / gamepad names (send to Claude)")
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
        if not (btn and GLYPH_TEXT[btn:lower()]) then return say("Use: /satchel glyph cross|circle|square|triangle AtlasName") end
        DB.glyph = DB.glyph or {}; DB.glyph[btn:lower()] = atlas; GB.ResetGlyphs()
        if footer then footer.shownKey = nil end
        say(btn:lower() .. " glyph set to " .. atlas .. (atlasExists(atlas) and "" or " (not found in the client, text fallback stays)"))
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
    "ITEM_LOCK_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_MONEY", "BAG_UPDATE_COOLDOWN" }) do ev:RegisterEvent(e) end
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
    elseif e == "PLAYER_REGEN_DISABLED" then
        if frame then GB.SetEsc(false) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if frame then GB.SetEsc(true) end
        if frame and pending then GB.Layout() end
        if frame and frame:IsShown() then GB.Refresh() end
    elseif frame and frame:IsShown() then
        if e == "BAG_UPDATE" and not inCombat() then
            -- bag sizes can change when a bag is swapped
            local n = 0
            for _, s in ipairs(GB.BuildOrder(currentSizes())) do n = n + 1 end
            if n ~= shownCount or DB.collapsed then GB.Layout() else GB.Refresh() end
        else GB.Refresh() end
    end
end)
