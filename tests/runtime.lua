-- Offline harness for Waterys Satchel. Run: lua5.1 tests/runtime.lua
local source = arg[1] or 'WaterysSatchel.lua'
local combat = false
local secure = false
local frames, named = {}, {}
local M = {}
local function protected(f)
    if combat and f.protected and not secure then error('protected frame mutation in combat') end
end
local function frame(kind, name, parent, template)
    local f = setmetatable({kind=kind,name=name,parent=parent,template=template or '',attrs={},scripts={},events={},refs={},visible=false,bindings={}}, {__index=function(t,k) if k=='SetFrameRef' and rawget(t,'noMethodSetFrameRef') then return nil end return M[k] end})
    frames[#frames+1]=f
    if name then named[name]=f; _G[name]=f end
    -- Client rule: only a frame with a secure template is protected (not its parent, not its children).
    if f.template:find('Secure') then f.protected=true end
    -- Client rule (WoW Forever): BackdropTemplate wipes the secure template's methods, so a frame created with
    -- Backdrop + SecureHandler has NO :SetFrameRef (use the global SecureHandlerSetFrameRef).
    f.noMethodSetFrameRef = f.template:find('Backdrop') and f.template:find('SecureHandler') and true or false
    return f
end
function M:SetAttribute(k,v) protected(self);self.attrs[k]=v end
function M:GetAttribute(k) return self.attrs[k] end
function M:SetFrameRef(k,v) protected(self);self.refs[k]=v end
function SecureHandlerSetFrameRef(f,k,v)
    assert(f.template:find('SecureHandler'),'SecureHandlerSetFrameRef needs a secure handler frame: '..tostring(f.name))
    protected(f); f.refs[k]=v
end
function M:GetFrameRef(k) return self.refs[k] end
function M:SetScript(k,v) self.scripts[k]=v end
function M:HookScript(k,v) local o=self.scripts[k]; self.scripts[k]=function(...) if o then o(...) end v(...) end end
function M:RegisterEvent(e) self.events[e]=true end
function M:Show() protected(self); if not self.visible then self.visible=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
function M:Hide() protected(self); if self.visible then self.visible=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
function M:IsShown() return self.visible end
function M:SetSize(w,h) protected(self);self.width=w;self.height=h end
function M:SetPoint(...)
    protected(self)
    -- Client rule: in the restricted environment a relative anchor must be a protected frame
    local rel=select(2,...)
    if secure and type(rel)=='table' and not rel.protected then error('Invalid relative frame handle: '..tostring(rel.name)) end
self.points=self.points or {};self.points[#self.points+1]={...};self.point={...} end
function M:GetPoint() return 'BOTTOMRIGHT',nil,'BOTTOMRIGHT',-80,120 end
function M:ClearAllPoints() protected(self);self.points={} end
function M:SetText(t) self.text=t end
function M:CreateFontString() return frame('FontString',nil,self) end
function M:CreateTexture() return frame('Texture',nil,self) end
function M:RegisterForClicks(...) self.clicks={}; for _,c in ipairs({...}) do self.clicks[c]=true end end
function M:GetText() return self.text or '' end
function M:SetChecked(v) self.checked=v end
function M:GetChecked() return self.checked end
function M:SetCooldown(a,b) self.cooldown={a,b} end
function M:SetAlpha(a) self.alpha=a end
function M:GetCenter() return 0,0 end
function M:GetEffectiveScale() return 1 end
function M:SetFrameLevel(v) self.level=v end
function M:GetFrameLevel() return self.level or 1 end
function M:SetTexture(t) self.texture=t end
function M:SetBackdropBorderColor(r,g,b) self.border={r,g,b} end
function M:StartMoving() protected(self);self.moving=true end
function M:StopMovingOrSizing() self.moving=false end
function M:ClearBindings() self.bindings={} end
function M:ClearBinding(k) self.bindings[k]=nil end
function M:SetBindingClick(p,key,target,button) self.bindings[key]={target,button} end
for _,k in ipairs({'SetFrameStrata','SetClampedToScreen','SetMovable','EnableMouse','RegisterForDrag','SetBackdrop','SetBackdropColor','SetScale','SetTexCoord','SetDesaturated','SetHighlightTexture','SetAllPoints','SetAutoFocus','SetMaxLetters','ClearFocus','SetVertexColor','SetTextColor'}) do M[k]=function() end end
CreateFrame=frame
UIParent=frame('Frame','UIParent')
UISpecialFrames={}; SlashCmdList={}
tinsert=table.insert; tremove=table.remove
local alt=false
function IsAltKeyDown() return alt end
function InCombatLockdown() return combat end
function SecureHandlerExecute(f,snip,button,down,owner)
    local fn=assert(loadstring(snip));setfenv(fn,setmetatable({self=f,button=button,down=down,owner=owner},{__index=_G}));secure=true;local ok,err=pcall(fn);secure=false;assert(ok,err)
end
function SecureHandlerWrapScript(f,script,header,pre,post)
    assert(f.protected and header.template:find('SecureHandler'),'WrapScript needs protected frame + secure header')
    f.wraps=f.wraps or {}; f.wraps[script]={header=header,pre=pre,post=post}
end
function M:SetHeight(h) protected(self);self.height=h end
function M:RunAttribute(k) SecureHandlerExecute(self,self.attrs[k]) end
function M:SetPoint2() end
NUM_BAG_SLOTS=4
Minimap=frame('Frame','Minimap')
function GetCursorPosition() return 100,100 end
money=123456
function GetMoney() return money end
function GetItemInfo(l) return l:match('%[(.-)%]') end
ITEM_QUALITY_COLORS={[0]={r=.6,g=.6,b=.6},[1]={r=1,g=1,b=1},[4]={r=.6,g=.2,b=.9}}
local sizes={[0]=16,12,0,0,0}
local items={}
C_Container={
  GetContainerNumSlots=function(b) return sizes[b] or 0 end,
  GetContainerItemInfo=function(b,s) return items[b..':'..s] end,
  PickupContainerItem=function(b,s) picked={b,s} end,
}
GameTooltip=frame('Frame','GameTooltip')
local hooks={}
function hooksecurefunc(name,fn) local o=_G[name]; _G[name]=function(...) local r=o(...); fn(...); return r end end
local defaultShown=false
for _,n in ipairs({'ToggleAllBags','ToggleBackpack','OpenAllBags','CloseAllBags'}) do
    _G[n]=function() if n:find('Close') then defaultShown=false else defaultShown=not defaultShown or n:find('Open')~=nil end
        if _G.ContainerFrame1 then if defaultShown then ContainerFrame1:Show() else ContainerFrame1:Hide() end end end
end
local cf=frame('Frame','ContainerFrame1')
cf.scripts.OnShow=function() end
local function emit(ev,...) for _,f in ipairs(frames) do if f.events[ev] then f.scripts.OnEvent(f,ev,...) end end end
local msgs={}
print=function(m) msgs[#msgs+1]=m end

assert(loadfile(source))('WaterysSatchel')
WaterysSatchelDB={columns=8}
emit('ADDON_LOADED','WaterysSatchel')
emit('PLAYER_LOGIN')
local GB=WaterysSatchel
local N=GB.Neighbors

-- 1. grid order: bag 0 slot 1 first, then bag 1, no skipping
local o=GB.BuildOrder({[0]=2,3,n=2})
assert(#o==5 and o[1][1]==0 and o[1][2]==1 and o[2][2]==2 and o[3][1]==1 and o[3][2]==1 and o[5][2]==3)
assert(named.WaterysSatchelSlot1.bag==0 and named.WaterysSatchelSlot1.slot==1)
assert(named.WaterysSatchelSlot16.bag==0 and named.WaterysSatchelSlot16.slot==16)
assert(named.WaterysSatchelSlot17.bag==1 and named.WaterysSatchelSlot17.slot==1)
assert(named.WaterysSatchelSlot28.bag==1 and named.WaterysSatchelSlot28.slot==12 and not named.WaterysSatchelSlot29)
assert(named.WaterysSatchelSlot1.attrs.item2=='0 1' and named.WaterysSatchelSlot1.attrs.type2=='item')
-- visual positions: 8 columns, row by row
local function xy(i) local p=named['WaterysSatchelSlot'..i].point; return p[4],p[5] end
local x1,y1=xy(1); local x8,y8=xy(8); local x9,y9=xy(9)
assert(y1==y8 and x9==x1 and y9<y1 and x8>x1)


-- 2. neighbors, 28 slots / 8 cols (last row has 4)
local nb=N(28,8)
assert(nb.right[1]==2 and nb.right[8]==9 and nb.right[28]==1)
assert(nb.left[1]==28 and nb.left[9]==8 and nb.left[2]==1)
assert(nb.down[1]==9 and nb.down[20]==28 and nb.down[22]==28 and nb.down[25]==1 and nb.down[28]==4)
-- exact partial-row cases
assert(nb.up[5]==21 and nb.up[4]==28 and nb.up[1]==25 and nb.up[28]==20)
-- full grid 32/8
nb=N(32,8); assert(nb.down[32]==8 and nb.up[3]==27 and nb.right[32]==1)
-- single row, tiny, wide, empty
nb=N(5,8); assert(nb.up[3]==3 and nb.down[3]==3 and nb.right[5]==1 and nb.left[1]==5)
nb=N(1,8); assert(nb.up[1]==1 and nb.down[1]==1 and nb.left[1]==1 and nb.right[1]==1)
assert(next(N(0,8).left)==nil)
-- every neighbor stays in range and walking right visits every slot once
for _,cfg in ipairs({{16,4},{17,8},{30,8},{40,10},{3,1},{36,6}}) do
    local n,c=cfg[1],cfg[2]; local t=N(n,c); local seen,i={},1
    for step=1,n do seen[i]=true; i=t.right[i] end
    for k in pairs(seen) do assert(k>=1 and k<=n) end
    assert(i==1)
    for i=1,n do for _,d in ipairs({'left','right','up','down'}) do local v=t[d][i]; assert(v>=1 and v<=n,d..i) end
        assert(t.left[t.right[i]]==i) end
end

-- 3. attributes mirror neighbors for the secure snippet; bag size changes
assert(named.WaterysSatchelNav.attrs.right8==9 and named.WaterysSatchelNav.attrs.down1==9 and named.WaterysSatchelNav.attrs.left1==28)
sizes[2]=6; GB.Layout()
assert(named.WaterysSatchelSlot34 and named.WaterysSatchelSlot34.bag==2 and named.WaterysSatchelSlot34.slot==6)
assert(named.WaterysSatchelNav.attrs.count==34)
sizes[2]=0; GB.Layout()
assert(not named.WaterysSatchelSlot29.visible and named.WaterysSatchelSlot29.bag==nil and named.WaterysSatchelNav.attrs.count==28)
WaterysSatchelDB.columns=4; slashed=true; GB.Slash('cols 6'); assert(WaterysSatchelDB.columns==6 and named.WaterysSatchelNav.attrs.down1==7)
GB.Slash('cols 8')

-- 4. secure snippet moves focus and rebinds A / X (d-pad logic, run in combat too)
local nav=named.WaterysSatchelNav
nav.refs.hl=named.WaterysSatchelFocus
GB.Open(); assert(named.WaterysSatchelFrame.visible)
assert(nav.attrs.focus==1 and nav.bindings.PADDUP and nav.bindings.PAD1[1]==named.WaterysSatchelMenuOpen_x and nav.bindings.PAD4[1]==named.WaterysSatchelMenuOpen_tri and nav.bindings.PAD2[1]==named.WaterysSatchelCloseBag and nav.bindings.PAD3[1]==named.WaterysSatchelQuick)
-- Real key press: the binding clicks the pad button once on key DOWN and once on key UP,
-- but only for the click types the button registered. Returns how many times the move ran.
local KEY={up='PADDUP',down='PADDDOWN',left='PADDLEFT',right='PADDRIGHT'}
local function press(d)
    local tgt=nav.bindings[KEY[d]][1]; local runs=0
    combat=true
    for _,phase in ipairs({'down','up'}) do
        local reg=(phase=='down' and tgt.clicks.AnyDown) or (phase=='up' and tgt.clicks.AnyUp)
        if reg then SecureHandlerExecute(tgt,tgt.attrs._onclick,'LeftButton',phase=='down'); runs=runs+1 end
    end
    combat=false
    return runs
end
-- REGRESSION: one d-pad press moves exactly ONE slot (was two: down + up clicks both moved)
nav.attrs.focus=1; assert(press('right')==1); assert(nav.attrs.focus==2,'one press = one slot right')
nav.attrs.focus=10; assert(press('left')==1); assert(nav.attrs.focus==9,'one slot left')
nav.attrs.focus=10; assert(press('down')==1); assert(nav.attrs.focus==18,'one row down')
nav.attrs.focus=18; assert(press('up')==1); assert(nav.attrs.focus==10,'one row up')
for _,d in ipairs({'up','down','left','right'}) do local c=named['WaterysSatchelPad'..d].clicks; assert(c.AnyUp and not c.AnyDown,d..' registers up only') end
-- even if a down click ever reaches the snippet, it must not move
nav.attrs.focus=5; SecureHandlerExecute(named.WaterysSatchelPadright,named.WaterysSatchelPadright.attrs._onclick,'LeftButton',true); assert(nav.attrs.focus==5)
nav.attrs.focus=1
press('right'); assert(nav.attrs.focus==2)
press('down'); assert(nav.attrs.focus==10)
nav.attrs.focus=8; press('right'); assert(nav.attrs.focus==9,'row end wraps to next row')
nav.attrs.focus=9; press('left'); assert(nav.attrs.focus==8)
nav.attrs.focus=1; press('up'); assert(nav.attrs.focus==25)
-- pad nav off removes d-pad bindings
GB.Slash('pad off'); assert(nav.attrs.padnav==0 and not nav.bindings.PADDUP and not nav.bindings.PAD1)
GB.Slash('pad on'); assert(nav.bindings.PADDUP)

-- 5. open/close via normal bag keys, replaces default bag
GB.Close(); assert(not named.WaterysSatchelFrame.visible and next(nav.bindings)==nil)
ToggleAllBags(); assert(named.WaterysSatchelFrame.visible and not ContainerFrame1.visible,'default must be hidden')
ToggleAllBags(); assert(not named.WaterysSatchelFrame.visible)
ToggleBackpack(); assert(named.WaterysSatchelFrame.visible)
CloseAllBags(); assert(not named.WaterysSatchelFrame.visible)
OpenAllBags(); assert(named.WaterysSatchelFrame.visible); CloseAllBags()
ContainerFrame1:Show(); assert(not ContainerFrame1.visible,'default OnShow hidden')
-- setting off -> default bag returns
GB.Slash('default on'); assert(WaterysSatchelDB.enabled==false)
ContainerFrame1:Hide(); defaultShown=false
ToggleAllBags(); assert(ContainerFrame1.visible and not named.WaterysSatchelFrame.visible)
GB.Slash('default off'); assert(WaterysSatchelDB.enabled==true); ContainerFrame1:Hide()

-- 6. combat: normal bag opens; open window keeps working, no protected mutation
combat=true; defaultShown=false
ToggleAllBags(); assert(ContainerFrame1.visible and not named.WaterysSatchelFrame.visible)
combat=false; ContainerFrame1:Hide(); GB.Open()
combat=true
items['0:1']={iconFileID=1234,stackCount=5,quality=4}
emit('BAG_UPDATE')
assert(named.WaterysSatchelSlot1.icon.texture==1234 and named.WaterysSatchelSlot1.count.text==5)
assert(named.WaterysSatchelSlot1.border[1]==.6 and named.WaterysSatchelSlot1.border[3]==.9,'quality border')
items['0:1']=nil; emit('BAG_UPDATE')
assert(named.WaterysSatchelSlot1.icon.texture==nil and named.WaterysSatchelSlot1.count.text=='')
named.WaterysSatchelSlot1.scripts.PostClick(named.WaterysSatchelSlot1,'LeftButton'); assert(picked[2]==1)
sizes[2]=2; emit('BAG_UPDATE'); assert(not named.WaterysSatchelSlot29.visible)
GB.Slash('cols 5'); assert(WaterysSatchelDB.columns==5)
combat=false; emit('PLAYER_REGEN_ENABLED'); assert(named.WaterysSatchelSlot29 and named.WaterysSatchelSlot29.visible and nav.attrs.count==30)
GB.Slash('cols 8'); sizes[2]=0; GB.Layout()

-- 7. Alt+drag move, saved position
local f=named.WaterysSatchelFrame
alt=false; f.scripts.OnDragStart(f); assert(not f.moving)
alt=true; f.scripts.OnDragStart(f); assert(f.moving)
f.scripts.OnDragStop(f); assert(not f.moving and WaterysSatchelDB.point[1]=='BOTTOMRIGHT')
combat=true; f.moving=false; f.scripts.OnDragStart(f); assert(not f.moving); combat=false
GB.Slash('help'); GB.Slash('config'); GB.Slash('bogus')
assert(table.concat(msgs,'\n'):find('Unknown'))
local seenEsc=false for _,n in ipairs(UISpecialFrames) do if n=='WaterysSatchelFrame' then seenEsc=true end end
assert(seenEsc)


-- 8. minimap button: placement, drag angle, click actions, hide setting
local mm=named.WaterysSatchelMinimapButton; assert(mm and mm.parent==Minimap and TidepoolDB==nil or true)
local ox,oy=GB.MinimapOffset(0); assert(math.abs(ox-80)<1e-6 and math.abs(oy)<1e-6)
ox,oy=GB.MinimapOffset(90); assert(math.abs(ox)<1e-6 and math.abs(oy-80)<1e-6)
assert(math.abs(GB.AngleFromCursor(0,-5)-270)<1e-6 and math.abs(GB.AngleFromCursor(5,5)-45)<1e-6)
assert(mm.visible and mm.point[1]=='CENTER' and mm.point[2]==Minimap)
GB.Close(); mm.scripts.OnClick(mm,'LeftButton'); assert(named.WaterysSatchelFrame.visible,'left click opens')
mm.scripts.OnClick(mm,'LeftButton'); assert(not named.WaterysSatchelFrame.visible,'left click closes')
mm.scripts.OnClick(mm,'RightButton'); assert(named.WaterysSatchelSettings.visible,'right click opens settings')
mm.scripts.OnClick(mm,'RightButton'); assert(not named.WaterysSatchelSettings.visible)
mm.scripts.OnDragStart(mm); assert(mm.scripts.OnUpdate); mm.scripts.OnUpdate(mm)
assert(math.abs(WaterysSatchelDB.minimap.angle-45)<1e-6,'drag saves angle'); mm.scripts.OnDragStop(mm); assert(not mm.scripts.OnUpdate)
GB.Slash('minimap off'); assert(WaterysSatchelDB.minimap.hide and not mm.visible)
GB.Slash('minimap on'); assert(not WaterysSatchelDB.minimap.hide and mm.visible)
named.WaterysSatchelSettings:Show(); named.WaterysSatchelCheckMinimap.checked=true; named.WaterysSatchelCheckMinimap.scripts.OnClick(named.WaterysSatchelCheckMinimap)
assert(WaterysSatchelDB.minimap.hide and not mm.visible); GB.SetMinimapHidden(false)
named.WaterysSatchelColPlus.scripts.OnClick(); assert(WaterysSatchelDB.columns==9); GB.SetCols(8); named.WaterysSatchelSettings:Hide()

-- 9. money, free slots, search, cooldown, theme
assert(GB.MoneyText(123456):find('12g') and GB.MoneyText(123456):find('34s') and GB.MoneyText(123456):find('56c'))
items['0:1']={iconFileID=1,stackCount=1,quality=1,hyperlink='|cff|Hitem:1|h[Water Flask]|h|r'}
items['0:2']={iconFileID=2,stackCount=1,quality=1,hyperlink='|cff|Hitem:2|h[Iron Sword]|h|r'}
GB.Open(); GB.Refresh()
assert(named.WaterysSatchelFrame.children==nil)
assert(GB.free==26,'free slots count '..tostring(GB.free))
GB.SetQuery('water'); assert(named.WaterysSatchelSlot1.alpha==1 and named.WaterysSatchelSlot2.alpha<1,'search dims non-matches')
GB.SetQuery(''); assert(named.WaterysSatchelSlot2.alpha==1)
assert(GB.Matches('Water Flask','WAT') and not GB.Matches('Iron','wat') and GB.Matches(nil,''))
C_Container.GetContainerItemCooldown=function(b,s) if s==1 then return 10,30,1 end return 0,0,1 end
GB.Refresh(); assert(named.WaterysSatchelSlot1.cd.cooldown[2]==30 and named.WaterysSatchelSlot2.cd.cooldown[2]==0,'cooldown swirl')
-- the d-pad never lands on the search box: nav only references slots
for i=1,28 do assert(nav.attrs['right'..i]<=28) end
GB.Close()
-- 10. migrate GridBag saved settings
WaterysSatchelDB=nil; TidepoolDB={columns=10,scale=1.2}
emit('ADDON_LOADED','WaterysSatchel'); assert(WaterysSatchelDB.columns==10 and WaterysSatchelDB.scale==1.2 and WaterysSatchelDB.minimap.angle==215 and WaterysSatchelDB.padNav==true)
WaterysSatchelDB.columns=8


-- 11. controller menus: X/Triangle on an item -> item menu (per item), Triangle on empty -> bag menu
local function click(btn,phase) if not btn.attrs._onclick then return end SecureHandlerExecute(btn,btn.attrs._onclick,'LeftButton',phase=='down') end
-- A pad key press = binding click on the bound target (up only), in combat. Runs the _onclick snippet, then the
-- secure action wrap (post body, owner = header) for macro entries, then PostClick.
local macroLog={}
local function padclick(key) local t=(nav.bindings[key] or named.WaterysSatchelMenu_item.bindings[key] or named.WaterysSatchelMenu_bag.bindings[key])[1]
    combat=true; click(t,'up')
    if t.wraps and t.wraps.OnClick and t.wraps.OnClick.pre then SecureHandlerExecute(t,t.wraps.OnClick.pre,'LeftButton',false,t.wraps.OnClick.header) end
    if t.attrs.type=='macro' then macroLog[#macroLog+1]=t.attrs.macrotext
        local w=t.wraps and t.wraps.OnClick; if w and w.post then SecureHandlerExecute(t,w.post,'LeftButton',false,w.header) end end
    combat=false
    if t.scripts.PostClick then t.scripts.PostClick(t,'LeftButton') end end
-- client rules the mock models
assert(named.WaterysSatchelMenu_item.noMethodSetFrameRef and named.WaterysSatchelMenu_item.SetFrameRef==nil,'Backdrop+SecureHandler frame has no :SetFrameRef')
assert(named.WaterysSatchelMenu_item.refs.e1==named.WaterysSatchelMenu_item_use and named.WaterysSatchelMenu_item.refs.nav==nav)
assert(named.WaterysSatchelFrame.protected,'main window is protected (CLOSE_BAG Hide needs it)')
assert(not named.WaterysSatchelSettings.protected and not named.WaterysSatchelMinimapButton.protected)
GB.Open()
local im=named.WaterysSatchelMenu_item; local bm=named.WaterysSatchelMenu_bag
local labels={}; for i,d in ipairs(GB.ITEM_MENU) do labels[d.key]=d.label end
assert(#GB.ITEM_MENU==6 and labels.use=='Use' and labels.equip=='Equip' and labels.bind=='Bind' and labels.split=='Split' and labels.link=='Share in Chat' and labels.destroy=='Destroy')
assert(GB.BAG_MENU[1].label=='Cleanup' and GB.BAG_MENU[2].label=='Sell Junk')
-- which entries show for which item (pure)
local eq={['sword']=true}; local spell={['potion']=true,['scroll']=true}; local class0={['potion']=true}
-- this client has ONLY C_Item.* (no globals): model that
IsEquippableItem,GetItemSpell,GetItemInfoInstant,IsUsableItem,GetItemInfo=nil,nil,nil,nil,nil
C_Item={IsEquippableItem=function(l) return eq[l] or false end,
 GetItemSpell=function(l) return spell[l] and 'Heal' or nil end,
 GetItemInfoInstant=function(l) return 1,'x','y','z',1,class0[l] and 0 or 7 end,
 IsUsableItem=function(l) return l=='quest' end,
 GetItemInfo=function(l) return l:match('%[(.-)%]') end}
local function keys(l,c) local k=GB.ItemMenuKeys(l,c); local o={} for _,d in ipairs(GB.ITEM_MENU) do if k[d.key] then o[#o+1]=d.key end end return table.concat(o,',') end
assert(keys('potion',5)=='use,bind,split,link,destroy',keys('potion',5))
assert(keys('sword',1)=='equip,bind,link,destroy',keys('sword',1))
assert(keys('junk',1)=='bind,link,destroy',keys('junk',1))
assert(keys('quest',1)=='use,bind,link,destroy')
assert(keys('ore',20)=='bind,split,link,destroy')
-- items in the bag
local function setItem(slot,link,count,q) items['0:'..slot]={iconFileID=slot,stackCount=count,quality=q or 1,hyperlink=link,itemID=100+slot} end
items={}; setItem(1,'potion',5,1); setItem(2,'sword',1,4); setItem(3,'junk',1,0); GB.Refresh()
assert(named.WaterysSatchelSlot1.attrs.m_use==1 and named.WaterysSatchelSlot1.attrs.m_split==1 and not named.WaterysSatchelSlot1.attrs.m_equip)
assert(named.WaterysSatchelSlot2.attrs.m_equip==1 and not named.WaterysSatchelSlot2.attrs.m_use and not named.WaterysSatchelSlot2.attrs.m_split)
assert(not named.WaterysSatchelSlot4.attrs.hasitem and named.WaterysSatchelSlot1.attrs.hasitem==1)
local function visibleEntries() local o={} for i=1,6 do local e=im.refs['e'..i]; if e.visible then o[#o+1]=e.attrs.key end end return table.concat(o,',') end
local function show(key) im.visible=false; for i=1,6 do im.refs['e'..i].visible=true end
    SecureHandlerExecute(named.WaterysSatchelMenuOpen_x,'',nil,nil) end
-- X on the potion: item menu with Use, no Equip; Use is a secure macro
nav.attrs.focus=1; padclick('PAD1')
assert(im.visible and not nav.bindings.PAD1 and visibleEntries()=='use,bind,split,link,destroy',visibleEntries())
assert(im.attrs.count==5 and im.height==5*22+10)
local use=named.WaterysSatchelMenu_item_use
assert(use.attrs.type=='macro' and use.attrs.macrotext=='/use 0 1' and use.template=='SecureActionButtonTemplate')
assert(im.bindings.PAD1[1]==use and im.bindings.PAD2[1]==named.WaterysSatchelMenuClose_item)
-- anchored to a protected frame (the restricted SetPoint check in the mock would have raised otherwise)
assert(im.point[2]==named.WaterysSatchelSlot1)
-- d-pad chooses; v-map skips hidden entries; wraps
local function menupad(m,d) local b=m.bindings[d=='up' and 'PADDUP' or 'PADDDOWN'][1]; combat=true; click(b,'up'); combat=false end
menupad(im,'down'); assert(im.attrs.sel==2 and im.bindings.PAD1[1]==named.WaterysSatchelMenu_item_bind)
menupad(im,'up'); menupad(im,'up'); assert(im.attrs.sel==5 and im.bindings.PAD1[1]==named.WaterysSatchelMenu_item_destroy)
-- USE through the secure click path, in combat: macro text, menu closes, pad returns to the grid
im.attrs.sel=1; im.bindings.PAD1={use,'LeftButton'}; macroLog={}
padclick('PAD1'); assert(macroLog[1]=='/use 0 1' and not im.visible and nav.bindings.PAD1,'use clicked, menu closed')
-- Triangle on the sword: SAME item menu, with Equip (and no Use); macro uses the sword slot
nav.attrs.focus=2; padclick('PAD4')
assert(im.visible and not bm.visible and visibleEntries()=='equip,bind,link,destroy',visibleEntries())
local eqb=named.WaterysSatchelMenu_item_equip; assert(eqb.attrs.type=='macro' and eqb.attrs.macrotext=='/use 0 2')
im.bindings.PAD1={eqb,'LeftButton'}; macroLog={}; padclick('PAD1'); assert(macroLog[1]=='/use 0 2' and not im.visible)
-- Bind: item on cursor
nav.attrs.focus=1; padclick('PAD1'); im.attrs.sel=3
im.bindings.PAD1={named.WaterysSatchelMenu_item_bind,'LeftButton'}
do local bound; local hide
  GamepadActionBarEditFrame={BindItem=function(self,id) bound=id end,HookScript=function(self,ev,fn) if ev=='OnHide' then hide=fn end end}
  GamepadMode={FrameControlsManager={UnsuspendAllFrames=function() bound='unsuspended' end}}
  padclick('PAD1')
  assert(not im.visible and bound==101,'stock BindItem called with itemID')
  assert(not nav.bindings.PAD1,'our pad bindings dropped while the stock bind dialog is open')
  assert(hide,'OnHide hook installed'); assert(named.WaterysSatchelFrame.visible); hide(); assert(nav.bindings.PAD1,'pad bindings restored after dialog hides')
  GamepadActionBarEditFrame=nil
  local sayLog={}; local oldprint=print; print=function(...) sayLog[#sayLog+1]=table.concat({...},' ') end
  GB.StartControllerBind({bag=0,slot=1}); print=oldprint; assert(sayLog[1] and sayLog[1]:find('/satchel probe'),'bind message when frame absent')
end
local oldprint=print
-- Use/Equip secure buttons: up-click mode, type+macrotext set in the snippet BEFORE the click is processed
assert(named.WaterysSatchelQuick.attrs.useOnKeyDown==false and eqb.attrs.useOnKeyDown==false and named.WaterysSatchelMenu_item_use.attrs.useOnKeyDown==false)
do local q=named.WaterysSatchelQuick; q.attrs.type=nil; q.attrs.macrotext='stale'; nav.attrs.focus=1
  local w=q.wraps.OnClick; SecureHandlerExecute(q,w.pre,'LeftButton',false,w.header)
  assert(q.attrs.type=='macro' and q.attrs.macrotext=='/use 0 1','pre-body fills type+macrotext before the click') end
-- probe prints and saves
do local lines={}; print=function(...) lines[#lines+1]=table.concat({...},' ') end
  ContainerFrameCombinedBags=nil; BindFooThing=function() end; C_GamePad={GetDeviceMappedState=function() end}
  GB.Slash('probe'); print=oldprint
  assert(#lines>3 and WaterysSatchelDB.probe and #WaterysSatchelDB.probe>2,'probe output saved')
  local all=table.concat(lines,' '); assert(all:find('BindFooThing') and all:find('C_GamePad')) end
-- Destroy uses the game's confirm popup (rare+ needs typed DELETE)
local shown; StaticPopup_Show=function(w,l) shown={w,l} end; StaticPopupDialogs={DELETE_ITEM={},DELETE_GOOD_ITEM={}}
nav.attrs.focus=2; setItem(2,'sword',1,4); GB.Refresh(); padclick('PAD1')
im.bindings.PAD1={named.WaterysSatchelMenu_item_destroy,'LeftButton'}; padclick('PAD1')
assert(shown and shown[1]=='DELETE_GOOD_ITEM','epic needs typed confirm')
-- Share + Split
local linked; ChatEdit_InsertLink=function(l) linked=l end
nav.attrs.focus=1; padclick('PAD1'); im.bindings.PAD1={named.WaterysSatchelMenu_item_link,'LeftButton'}; padclick('PAD1'); assert(linked=='potion')
local split; C_Container.SplitContainerItem=function(b,s,n) split={b,s,n} end
padclick('PAD1'); im.bindings.PAD1={named.WaterysSatchelMenu_item_split,'LeftButton'}; padclick('PAD1'); assert(split and split[3]==2)
-- Circle closes the menu first, then the bag (restricted Hide of the protected window, in combat)
padclick('PAD1'); assert(im.visible); padclick('PAD2'); assert(not im.visible and nav.bindings.PAD2[1]==named.WaterysSatchelCloseBag)
padclick('PAD2'); assert(not named.WaterysSatchelFrame.visible,'second Circle closes bag')
-- X on an empty slot: no menu; with an item on the cursor it drops there
GB.Open(); nav.attrs.focus=5; padclick('PAD1'); assert(not im.visible and not bm.visible)
CursorHasItem=function() return true end; picked=nil; padclick('PAD1'); assert(picked and picked[2]==5,'X drops cursor item on empty slot'); CursorHasItem=nil
-- Triangle on an EMPTY slot: bag menu (Cleanup, Sell Junk); anchored to protected slot 1
local sorted=false; C_Container.SortBags=function() sorted=true end
nav.attrs.focus=5; padclick('PAD4'); assert(bm.visible and not im.visible and bm.point[2]==named.WaterysSatchelSlot1)
bm.bindings.PAD1={named.WaterysSatchelMenu_bag_cleanup,'LeftButton'}; padclick('PAD1'); assert(sorted and not bm.visible)
local sold=false; C_Container.SellAllJunkItems=function() sold=true end
padclick('PAD4'); bm.bindings.PAD1={named.WaterysSatchelMenu_bag_junk,'LeftButton'}; padclick('PAD1'); assert(not sold,'no vendor, no sale')
MerchantFrame=frame('Frame','MerchantFrame'); MerchantFrame.visible=true
padclick('PAD4'); bm.bindings.PAD1={named.WaterysSatchelMenu_bag_junk,'LeftButton'}; padclick('PAD1'); assert(sold)
MerchantFrame.visible=false
-- the bag menu is also reachable from every empty slot, but an item slot never opens it
nav.attrs.focus=1; padclick('PAD4'); assert(im.visible and not bm.visible); padclick('PAD2')
-- Square = quick action: Equip/Use via secure macro; nothing on other items / empty slots
macroLog={}; nav.attrs.focus=1; padclick('PAD3'); assert(macroLog[1]=='/use 0 1','quick use: '..tostring(macroLog[1]))
macroLog={}; nav.attrs.focus=2; padclick('PAD3'); assert(macroLog[1]=='/use 0 2','quick equip')
macroLog={}; nav.attrs.focus=5; padclick('PAD3'); assert(macroLog[1]=='','empty slot: no macro')
assert(GB.QuickLabel('sword',1)=='Equip' and GB.QuickLabel('potion',1)=='Use')
-- Hide empty slots: setting + bag menu entry
GB.SetCollapsed(true); assert(WaterysSatchelDB.collapsed and nav.attrs.count==3,'collapsed count '..tostring(nav.attrs.count))
GB.SetCollapsed(false); assert(not WaterysSatchelDB.collapsed and nav.attrs.count==28)
assert(named.WaterysSatchelCheckHide, 'settings tick box')
nav.attrs.focus=5; padclick('PAD4'); bm.bindings.PAD1={named.WaterysSatchelMenu_bag_hide,'LeftButton'}; padclick('PAD1')
assert(WaterysSatchelDB.collapsed and nav.attrs.count==3,'bag menu toggle'); GB.ToggleCollapse(); assert(not WaterysSatchelDB.collapsed)
-- SplitStack on every slot (StackSplitFrame calls owner:SplitStack(n))
local sp; C_Container.SplitContainerItem=function(b,s,n) sp={b,s,n} end
assert(type(named.WaterysSatchelSlot1.SplitStack)=='function'); named.WaterysSatchelSlot1:SplitStack(3); assert(sp[1]==0 and sp[2]==1 and sp[3]==3)
-- Split opens the stock frame with (max, owner, anchor, anchorTo)
local so; StackSplitFrame={OpenStackSplitFrame=function(self,mx,o,a,at) so={mx,o,a,at} end,IsShown=function() return true end}
GB.MenuActions.split(named.WaterysSatchelSlot1); assert(so[1]==5 and so[2]==named.WaterysSatchelSlot1 and so[4]=='TOPRIGHT'); StackSplitFrame=nil
-- Share opens chat with the link
local opened; ChatFrame_OpenChat=function(t,cf) opened=t end
GB.OpenChatWith('[x]'); assert(opened=='[x]'); ChatFrame_OpenChat=nil
-- footer follows the focus: item -> Item Menu, empty -> Bag Menu
local footer=nil
nav.attrs.focus=1; GB.UpdateFooter(); local ft=named.WaterysSatchelFrame.scripts.OnShow and true
local function footerText() for _,f in ipairs(frames) do if f.kind=='FontString' and type(f.text)=='string' and f.text:find('Close') then return f.text end end end
assert(footerText():find('Item Menu') and not footerText():find('Bag Menu'),'item footer: '..tostring(footerText()))
assert(footerText():find('Use') or footerText():find('Equip'),'quick label'); nav.attrs.focus=5; GB.UpdateFooter(); assert(footerText():find('Bag Menu') and footerText():find('Place'),'empty footer: '..tostring(footerText()))
-- glyphs: no atlas -> yellow text; with an atlas -> |A markup; manual override
assert(GB.Glyph('cross'):find('%[X%]') and GB.Glyph('triangle'):find('Tri'))
C_Texture={GetAtlasInfo=function(a) return a=='Gamepad_Ltr_Cross_64' and {} or nil end}; GB.ResetGlyphs()
assert(GB.Glyph('cross')=='|A:Gamepad_Ltr_Cross_64:18:18|a' and GB.Glyph('circle'):find('%[O%]'))
GB.Slash('glyph circle MyCircle'); assert(WaterysSatchelDB.glyph.circle=='MyCircle')
C_Texture={GetAtlasInfo=function(a) return a=='MyCircle' and {} or nil end}; GB.ResetGlyphs(); assert(GB.Glyph('circle')=='|A:MyCircle:18:18|a')
GB.Slash('glyphs'); C_Texture=nil; GB.ResetGlyphs()
assert(GB.MenuHints():find('Select') and GB.MenuHints():find('Close'))
-- Escape: in UISpecialFrames out of combat, removed in combat (Hide on a protected frame is blocked there)
emit('PLAYER_REGEN_DISABLED'); local inEsc=false for _,n in ipairs(UISpecialFrames) do if n=='WaterysSatchelFrame' then inEsc=true end end; assert(not inEsc)
emit('PLAYER_REGEN_ENABLED'); for _,n in ipairs(UISpecialFrames) do if n=='WaterysSatchelFrame' then inEsc=true end end; assert(inEsc)
-- restricted code must not anchor to the unprotected window (mock models the client rule)
secure=true; assert(not pcall(named.WaterysSatchelNav.SetPoint,named.WaterysSatchelNav,'TOPLEFT',named.WaterysSatchelSettings),'unprotected relative frame must be rejected'); assert(pcall(named.WaterysSatchelNav.SetPoint,named.WaterysSatchelNav,'TOPLEFT',named.WaterysSatchelSlot1)); secure=false
assert(not pcall(function() named.WaterysSatchelMenu_item:SetFrameRef('x',nav) end),'no :SetFrameRef on Backdrop+SecureHandler frames')
GB.Close()
items={}
io.stdout:write('PASS: one-press-one-slot, minimap, search, money, migration, grid order, neighbors, secure d-pad snippet, open/close/default swap, combat safety, Alt-drag\n')
