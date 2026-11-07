-- Read-only bank memory. Never use live bag buttons or stock navigation/focus.
local GB = Aquifer
local bankOpen, dirty, elapsed = false, false, 0
local window, controls, cells = nil, {}, {}
local selected, focus, query = nil, 1, ""
local COLS, ROWS, SLOT, GAP, PAD, TOP = 8, 8, 37, 4, 8, 90
local function combat() return InCombatLockdown() end
local function ref(f, k, v) SecureHandlerSetFrameRef(f, k, v) end
local function memory()
    local db = GB.DB
    if not db then return end
    db.bankMemory = db.bankMemory or { schema = 1, characters = {} }
    db.bankMemory.characters = db.bankMemory.characters or {}
    return db.bankMemory.characters
end
function GB.BankCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if name and realm then return realm .. "/" .. name, name, realm end
end
function GB.BankBagIDs()
    local enum = Enum and Enum.BagIndex or {}
    local ids = { enum.Bank or BANK_CONTAINER or -1 }
    for i = 1, (NUM_BANKBAGSLOTS or 7) do
        ids[#ids + 1] = enum["BankBag_" .. i] or ((NUM_BAG_SLOTS or 4) + i)
    end
    local reagent = enum.Reagentbank or REAGENTBANK_CONTAINER
    if reagent and (not IsReagentBankUnlocked or IsReagentBankUnlocked()) then ids[#ids + 1] = reagent end
    return ids
end
local function size(bag)
    local fn = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    return fn and fn(bag) or 0
end
local function readItem(bag, slot)
    local icon, count, quality, link, itemID
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then icon, count, quality, link, itemID = info.iconFileID, info.stackCount, info.quality, info.hyperlink, info.itemID end
    elseif GetContainerItemInfo then
        local locked, readable, lootable
        icon, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
    end
    local getLink = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
    if not link and getLink then link = getLink(bag, slot) end
    return { bag = bag, slot = slot, icon = icon, count = count or 0, quality = quality, link = link,
        itemID = itemID, occupied = (icon or link or itemID) and true or false }
end
function GB.CaptureBank()
    if not bankOpen then return false end -- closing the bank may invalidate live data
    local chars = memory()
    local key, name, realm = GB.BankCharacterKey()
    local bags = GB.BankBagIDs()
    if not chars or not key or size(bags[1]) == 0 then return false end -- not ready; retain the old snapshot
    local snapshot = { name = name, realm = realm, taken = time(), slots = {}, free = 0, total = 0 }
    local incomplete = false
    for _, bag in ipairs(bags) do
        for slot = 1, size(bag) do
            local item = readItem(bag, slot)
            snapshot.slots[#snapshot.slots + 1] = item
            if not item.occupied then snapshot.free = snapshot.free + 1
            elseif not item.link then incomplete = true end
        end
    end
    snapshot.total = #snapshot.slots
    chars[key] = snapshot
    dirty = incomplete -- retry links that have not arrived yet
    if window and window:IsShown() and selected == key and not combat() then GB.RenderBank() end
    return true
end
function GB.BankSnapshot(key)
    local chars = memory()
    return chars and chars[key or GB.BankCharacterKey()]
end
local function tooltip(cell)
    if not (cell and cell.item and cell.item.link) then GameTooltip:Hide(); return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(cell.item.link)
    GameTooltip:Show()
end
function GB.RenderBank()
    if not window or combat() then return end
    local snap = GB.BankSnapshot(selected)
    local entries = snap and snap.slots or {}
    local total = #entries
    focus = math.max(1, math.min(focus, total))
    COLS = math.max(4, math.min(20, GB.DB.columns or 8))
    local capacity = COLS * ROWS
    local page = math.floor((focus - 1) / capacity)
    local first = page * capacity + 1
    local visible = math.min(capacity, math.max(0, total - first + 1))
    local rows = math.max(1, math.ceil(visible / COLS))
    window:SetSize(math.max(340, PAD * 2 + COLS * (SLOT + GAP) - GAP), TOP + rows * (SLOT + GAP) + 70)
    window:SetScale(GB.DB.scale or 1)
    window.character:SetText(snap and (snap.name .. " - " .. snap.realm) or (selected or "Bank"))
    window.snapshot:SetText(snap and ("Snapshot: " .. date("%Y-%m-%d %H:%M", snap.taken)) or "No snapshot yet. Visit your bank first.")
    window.free:SetText(snap and (snap.free .. " / " .. snap.total .. " free slots (saved)") or "Read-only bank memory")
    window.page:SetText("Page " .. (page + 1) .. " / " .. math.max(1, math.ceil(total / capacity)))
    window.focus:Hide()
    for i = 1, math.max(visible, #cells) do
        local cell = cells[i]
        if i <= visible then
            if not cell then
                cell = CreateFrame("Button", "AquiferBankSlot" .. i, window, "BackdropTemplate")
                cell:SetSize(SLOT, SLOT)
                cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
                cell:SetBackdropColor(0.04, 0.12, 0.2, 0.85)
                cell.icon = cell:CreateTexture(nil, "ARTWORK")
                cell.icon:SetPoint("TOPLEFT", 2, -2); cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
                cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
                cell.count:SetPoint("BOTTOMRIGHT", -3, 3)
                cell:SetScript("OnEnter", tooltip)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
                -- No action attributes, click/drag handlers or item pickup methods.
                cells[i] = cell
            end
            local item = entries[first + i - 1]
            cell.item, cell.index = item, first + i - 1
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + ((i - 1) % COLS) * (SLOT + GAP), -TOP - math.floor((i - 1) / COLS) * (SLOT + GAP))
            cell.icon:SetTexture(item.icon)
            cell.count:SetText(item.count > 1 and item.count or "")
            local color = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
            if item.occupied and color then cell:SetBackdropBorderColor(color.r, color.g, color.b, 1)
            else cell:SetBackdropBorderColor(0.16, 0.34, 0.48, 1) end
            local name = item.link and (item.link:match("%[(.-)%]") or item.link)
            cell:SetAlpha(GB.Matches(name, query) and 1 or 0.25)
            cell:Show()
            if cell.index == focus then
                window.focus:ClearAllPoints(); window.focus:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
                window.focus:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0); window.focus:Show()
            end
        elseif cell then cell:Hide(); cell.item = nil end
    end
    window.first, window.visibleSlots, window.selectedIndex = first, visible, focus
end
function GB.BankMove(direction)
    if not window or not window:IsShown() or combat() then return end
    local snap = GB.BankSnapshot(selected)
    if not snap or #snap.slots == 0 then return end
    local nb = GB.Neighbors(#snap.slots, COLS)
    focus = nb[direction][focus] or 1
    GB.RenderBank()
    tooltip(cells[focus - window.first + 1])
end
function GB.BankPage(delta)
    if combat() then return end
    local snap = GB.BankSnapshot(selected)
    local n = snap and #snap.slots or 0
    local capacity = COLS * ROWS
    local page = math.floor((focus - 1) / capacity)
    local pages = math.max(1, math.ceil(n / capacity))
    focus = ((page + delta) % pages) * capacity + 1
    GB.RenderBank()
end
function GB.CycleBankCharacter()
    if combat() then return end
    local keys = {}; for key in pairs(memory() or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    if #keys == 0 then return end
    local nextIndex = 1
    for i, key in ipairs(keys) do if key == selected then nextIndex = i % #keys + 1 end end
    selected, focus = keys[nextIndex], 1
    GB.RenderBank()
end
local BIND = [[
self:ClearBindings()
if self:GetAttribute("padnav") == 1 then
    self:SetBindingClick(true, "PADDUP", self:GetFrameRef("up"), "LeftButton")
    self:SetBindingClick(true, "PADDDOWN", self:GetFrameRef("down"), "LeftButton")
    self:SetBindingClick(true, "PADDLEFT", self:GetFrameRef("left"), "LeftButton")
    self:SetBindingClick(true, "PADDRIGHT", self:GetFrameRef("right"), "LeftButton")
    self:SetBindingClick(true, "PAD2", self:GetFrameRef("close"), "LeftButton")
    -- Read-only view: don't let face buttons activate a stock item behind it.
    self:SetBindingClick(true, "PAD1", self:GetFrameRef("noop"), "LeftButton")
    self:SetBindingClick(true, "PAD3", self:GetFrameRef("noop"), "LeftButton")
    self:SetBindingClick(true, "PAD4", self:GetFrameRef("noop"), "LeftButton")
end
]]
local CLOSE = [[if down then return end
local w = self:GetFrameRef("window")
w:ClearBindings(); w:Hide()
]]
local COMBAT = [[if newstate == "1" then self:ClearBindings(); self:Hide() end]]
GB.BankCombatSnippet = COMBAT
local function build()
    window = CreateFrame("Frame", "AquiferBank", UIParent, "SecureHandlerStateTemplate,BackdropTemplate")
    GB.BankWindow = window
    window:SetFrameStrata("HIGH"); window:SetClampedToScreen(true); window:SetMovable(true); window:EnableMouse(true)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    window:SetBackdropColor(0.02, 0.09, 0.15, 0.94); window:SetBackdropBorderColor(0.2, 0.6, 0.85, 1)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) if not combat() and IsAltKeyDown() then self:StartMoving() end end)
    window:SetScript("OnDragStop", function(self) if not combat() then self:StopMovingOrSizing() end end)
    local function label(text, x, y)
        local f = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f:SetPoint("TOPLEFT", window, "TOPLEFT", x, y); f:SetText(text); return f
    end
    window.title = label("Bank", 8, -8)
    window.character = label("", 8, -29)
    window.snapshot = label("", 8, -70)
    window.search = CreateFrame("EditBox", "AquiferBankSearch", window, "InputBoxTemplate")
    window.search:SetSize(170, 20); window.search:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -45)
    window.search:SetAutoFocus(false); window.search:SetMaxLetters(80)
    window.search:SetScript("OnTextChanged", function(self) query = self:GetText(); GB.RenderBank() end)
    window.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    window.free = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.free:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 48)
    window.page = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.page:SetPoint("BOTTOM", window, "BOTTOM", 0, 28)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 8, 8); hint:SetText("Read only | D-pad: move | Circle: close")
    local function button(name, text, w, point, x, y, fn)
        local b = CreateFrame("Button", name, window, "UIPanelButtonTemplate")
        b:SetSize(w, 20); b:SetPoint(point, window, point, x, y); b:SetText(text)
        b:SetScript("OnClick", function() if not combat() then fn() end end); return b
    end
    button("AquiferBankCharacter", "Next character", 110, "TOPRIGHT", -32, -4, GB.CycleBankCharacter)
    button("AquiferBankPrevious", "<", 30, "BOTTOMLEFT", 8, 24, function() GB.BankPage(-1) end)
    button("AquiferBankNext", ">", 30, "BOTTOMRIGHT", -8, 24, function() GB.BankPage(1) end)
    window.focus = CreateFrame("Frame", nil, window, "BackdropTemplate")
    window.focus:SetFrameLevel(window:GetFrameLevel() + 10)
    window.focus:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    window.focus:SetBackdropBorderColor(1, 0.9, 0.2, 1)
    local noop = CreateFrame("Button", "AquiferBankNoAction", window, "SecureHandlerClickTemplate")
    noop:RegisterForClicks("AnyUp"); ref(window, "noop", noop)
    for _, dir in ipairs({ "up", "down", "left", "right", "close" }) do
        local b = CreateFrame("Button", "AquiferBank_" .. dir, window, "SecureHandlerClickTemplate")
        b:RegisterForClicks("AnyUp"); ref(window, dir, b)
        if dir == "close" then
            ref(b, "window", window); b:SetAttribute("_onclick", CLOSE)
            b:SetSize(22, 22); b:SetPoint("TOPRIGHT", window, "TOPRIGHT", -4, -4)
            local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetPoint("CENTER"); t:SetText("X")
        else
            b:SetScript("PostClick", function(_, button, down)
                if button == "LeftButton" and not down then GB.BankMove(dir) end
            end)
        end
        controls[dir] = b
    end
    window:SetScript("OnHide", function(self)
        self.search:ClearFocus(); GameTooltip:Hide()
        if not combat() then SecureHandlerExecute(self, "self:ClearBindings()") end
    end)
    window:SetAttribute("_onstate-combat", COMBAT)
    RegisterStateDriver(window, "combat", "[combat] 1; 0")
    window:Hide()
end
function GB.CloseBank()
    if window and window:IsShown() and not combat() then window:Hide() end
end
function GB.OpenBank()
    if combat() or (GB.IsBindingHandoff and GB.IsBindingHandoff()) then return end
    if not window then build() end
    if window:IsShown() then GB.CloseBank(); return end
    GB.Close() -- one controller owner at a time; never opens a stock bag
    selected, focus = GB.BankCharacterKey(), 1
    GB.RenderBank(); window:Show()
    window:SetAttribute("padnav", GB.DB.padNav and 1 or 0)
    SecureHandlerExecute(window, BIND)
end
SLASH_AQUIFERBANK1 = "/aqb"
SlashCmdList.AQUIFERBANK = function() GB.OpenBank() end
local events = CreateFrame("Frame", "AquiferBankEvents")
for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do events:RegisterEvent(event) end
-- This event is absent on some classic clients. Only register if storage exists.
if REAGENTBANK_CONTAINER or (Enum and Enum.BagIndex and Enum.BagIndex.Reagentbank) then
    pcall(events.RegisterEvent, events, "PLAYERREAGENTBANKSLOTS_CHANGED")
end
events:SetScript("OnEvent", function(_, event, bag)
    if event == "BANKFRAME_CLOSED" then bankOpen, dirty = false, false; return end
    if event == "BANKFRAME_OPENED" then bankOpen, dirty = true, true; GB.CaptureBank(); return end
    if not bankOpen then return end
    if event == "BAG_UPDATE" then
        local relevant = false
        for _, id in ipairs(GB.BankBagIDs()) do if id == bag then relevant = true end end
        if not relevant then return end
    end
    GB.CaptureBank() -- capture before a quick close can invalidate the bank data
    dirty = true -- also refresh after the rest of this update batch arrives
end)
events:SetScript("OnUpdate", function(_, dt)
    if not bankOpen or not dirty then return end
    elapsed = elapsed + (dt or 0)
    if elapsed >= 0.2 then elapsed = 0; GB.CaptureBank() end
end)
