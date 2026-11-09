-- Copy-only user report: no network requests, no character/account inventory data.
local GB=Aquifer
function GB.RedactBugText(text)
    local names={}
    local function add(value,label)
        if type(value)=='string' and value~='' then names[#names+1]={value,label} end
    end
    if UnitName then add(UnitName('player'),'<character>') end
    if UnitFullName then local name,realm=UnitFullName('player');add(name,'<character>');add(realm,'<realm>') end
    if GetRealmName then add(GetRealmName(),'<realm>') end
    if GetNormalizedRealmName then add(GetNormalizedRealmName(),'<realm>') end
    local chars=GB.DB and GB.DB.bankMemory and GB.DB.bankMemory.characters
    for _,record in pairs(chars or {}) do add(record.name,'<character>');add(record.realm,'<realm>') end
    table.sort(names,function(a,b) return #a[1]>#b[1] end)
    for _,entry in ipairs(names) do
        local pattern=entry[1]:gsub('(%W)','%%%1')
        text=text:gsub(pattern,function() return entry[2] end)
    end
    return text
end
function GB.BuildBugReport()
    local version,build,_,interface
    if GetBuildInfo then version,build,_,interface=GetBuildInfo() end
    local addons=C_AddOns or _G
    local meta=addons.GetAddOnMetadata or GetAddOnMetadata
    local aqversion=meta and meta('Aquifer','Version') or '2.2.6'
    local cvar=C_CVar and C_CVar.GetCVar or GetCVar
    local pad=cvar and cvar('GamePadEnable')
    local other={}
    local count=addons.GetNumAddOns or GetNumAddOns
    local info=addons.GetAddOnInfo or GetAddOnInfo
    local loaded=addons.IsAddOnLoaded or IsAddOnLoaded
    if count and info and loaded then
        for i=1,count() do
            local name=info(i)
            if type(name)=='table' then name=name.name end
            if type(name)=='string' and name~='Aquifer' and loaded(name) then
                local n=name:lower()
                if n:find('bag',1,true) or n:find('inventory',1,true) or n:find('inventorian',1,true)
                    or n:find('combuctor',1,true) or n=='elvui' or n=='tukui' or n=='pfui' then other[#other+1]=name end
            end
        end
    end
    table.sort(other)
    local lines={'Aquifer bug report','Aquifer: '..tostring(aqversion),'Client: '..tostring(version or '?')..' build '..tostring(build or '?')..' interface '..tostring(interface or '?'),
        'Locale: '..tostring(GetLocale and GetLocale() or '?'),'Gamepad: '..(pad=='1' and 'on' or pad=='0' and 'off' or 'unknown'),
        'Other loaded bag/UI addons (name-based detection): '..(#other>0 and table.concat(other,', ') or 'none detected'),
        'Character: <character>; Realm: <realm>; Account: <not collected>',
        'Recent events (last 100; no chat text or inventory included):'}
    local log=GB.DB and GB.DB.debugLog or {}
    for i=math.max(1,#log-99),#log do if type(log[i])=='string' then lines[#lines+1]=log[i] end end
    if #log==0 then lines[#lines+1]='No events recorded yet.' end
    return GB.RedactBugText(table.concat(lines,'\n'))
end
local window
function GB.ShowBugReport()
    if not window then
        window=CreateFrame('Frame','AquiferBugReport',UIParent,'BackdropTemplate')
        window:SetSize(620,430);window:SetPoint('CENTER');window:SetFrameStrata('DIALOG');window:SetClampedToScreen(true)
        window:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
        window:SetBackdropColor(.04,.06,.09,.98)
        local title=window:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',16,-14);title:SetText('Aquifer bug report')
        local close=CreateFrame('Button',nil,window,'UIPanelCloseButton');close:SetPoint('TOPRIGHT',-3,-3)
        close:SetScript('OnClick',function() window:Hide() end)
        local help=window:CreateFontString(nil,'OVERLAY','GameFontHighlight');help:SetPoint('TOPLEFT',16,-44)
        help:SetText('Paste this at github.com/waterys419/Aquifer/issues\nSelect all, then Ctrl+C to copy. Add what happened and the steps.')
        local scroll=CreateFrame('ScrollFrame',nil,window,'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT',16,-85);scroll:SetPoint('BOTTOMRIGHT',-36,48)
        local edit=CreateFrame('EditBox','AquiferBugReportText',scroll)
        edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal);edit:SetSize(560,280);edit:SetMaxLetters(0)
        edit:SetScript('OnTextChanged',function(self) if self.GetStringHeight then self:SetHeight(math.max(280,self:GetStringHeight()+20)) end end)
        edit:SetScript('OnEscapePressed',function() window:Hide() end)
        edit:SetScript('OnKeyDown',function(self,key) if key=='A' and IsControlKeyDown and IsControlKeyDown() then self:HighlightText() end end)
        scroll:SetScrollChild(edit);window.edit=edit
        local select=CreateFrame('Button','AquiferBugReportSelectAll',window,'UIPanelButtonTemplate')
        select:SetSize(130,25);select:SetPoint('BOTTOMLEFT',16,12);select:SetText('Select all')
        select:SetScript('OnClick',function() edit:SetFocus();edit:HighlightText() end)
        window:SetScript('OnHide',function() edit:ClearFocus() end)
        table.insert(UISpecialFrames,'AquiferBugReport')
    end
    window.edit:SetText(GB.BuildBugReport());window:Show();window.edit:SetFocus();window.edit:HighlightText()
end
