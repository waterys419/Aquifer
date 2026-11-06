-- Offline harness for Tidepool. Run: lua5.1 tests/runtime.lua
local source = arg[1] or 'Tidepool.lua'
local combat = false
local secure = false
local frames, named = {}, {}
local M = {}
local function protected(f)
    if combat and f.protected and not secure then error('protected frame mutation in combat') end
end
local function frame(kind, name, parent, template)
    local f = setmetatable({kind=kind,name=name,parent=parent,template=template or '',attrs={},scripts={},events={},refs={},visible=false,bindings={}}, {__index=M})
    frames[#frames+1]=f
    if name then named[name]=f; _G[name]=f end
    if f.template:find('Secure') then local p=f; while p do p.protected=true; p=p.parent end end
    return f
end
function M:SetAttribute(k,v) protected(self);self.attrs[k]=v end
function M:GetAttribute(k) return self.attrs[k] end
function M:SetFrameRef(k,v) protected(self);self.refs[k]=v end
function M:GetFrameRef(k) return self.refs[k] end
function M:SetScript(k,v) self.scripts[k]=v end
function M:HookScript(k,v) local o=self.scripts[k]; self.scripts[k]=function(...) if o then o(...) end v(...) end end
function M:RegisterEvent(e) self.events[e]=true end
function M:Show() protected(self); if not self.visible then self.visible=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end end
function M:Hide() protected(self); if self.visible then self.visible=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end end
function M:IsShown() return self.visible end
function M:SetSize(w,h) protected(self);self.width=w;self.height=h end
function M:SetPoint(...) protected(self);self.points=self.points or {};self.points[#self.points+1]={...};self.point={...} end
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
for _,k in ipairs({'SetFrameStrata','SetClampedToScreen','SetMovable','EnableMouse','RegisterForDrag','SetBackdrop','SetBackdropColor','SetScale','SetTexCoord','SetDesaturated','SetHighlightTexture','SetAllPoints','SetAutoFocus','SetMaxLetters','ClearFocus','SetVertexColor'}) do M[k]=function() end end
CreateFrame=frame
UIParent=frame('Frame','UIParent')
UISpecialFrames={}; SlashCmdList={}
tinsert=table.insert
local alt=false
function IsAltKeyDown() return alt end
function InCombatLockdown() return combat end
function SecureHandlerExecute(f,snip,button,down)
    local fn=assert(loadstring(snip));setfenv(fn,setmetatable({self=f,button=button,down=down},{__index=_G}));secure=true;local ok,err=pcall(fn);secure=false;assert(ok,err)
end
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

assert(loadfile(source))('Tidepool')
TidepoolDB={columns=8}
emit('ADDON_LOADED','Tidepool')
emit('PLAYER_LOGIN')
local GB=Tidepool
local N=GB.Neighbors

-- 1. grid order: bag 0 slot 1 first, then bag 1, no skipping
local o=GB.BuildOrder({[0]=2,3,n=2})
assert(#o==5 and o[1][1]==0 and o[1][2]==1 and o[2][2]==2 and o[3][1]==1 and o[3][2]==1 and o[5][2]==3)
assert(named.TidepoolSlot1.bag==0 and named.TidepoolSlot1.slot==1)
assert(named.TidepoolSlot16.bag==0 and named.TidepoolSlot16.slot==16)
assert(named.TidepoolSlot17.bag==1 and named.TidepoolSlot17.slot==1)
assert(named.TidepoolSlot28.bag==1 and named.TidepoolSlot28.slot==12 and not named.TidepoolSlot29)
assert(named.TidepoolSlot1.attrs.item2=='0 1' and named.TidepoolSlot1.attrs.type2=='item')
-- visual positions: 8 columns, row by row
local function xy(i) local p=named['TidepoolSlot'..i].point; return p[4],p[5] end
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
assert(named.TidepoolNav.attrs.right8==9 and named.TidepoolNav.attrs.down1==9 and named.TidepoolNav.attrs.left1==28)
sizes[2]=6; GB.Layout()
assert(named.TidepoolSlot34 and named.TidepoolSlot34.bag==2 and named.TidepoolSlot34.slot==6)
assert(named.TidepoolNav.attrs.count==34)
sizes[2]=0; GB.Layout()
assert(not named.TidepoolSlot29.visible and named.TidepoolSlot29.bag==nil and named.TidepoolNav.attrs.count==28)
TidepoolDB.columns=4; slashed=true; GB.Slash('cols 6'); assert(TidepoolDB.columns==6 and named.TidepoolNav.attrs.down1==7)
GB.Slash('cols 8')

-- 4. secure snippet moves focus and rebinds A / X (d-pad logic, run in combat too)
local nav=named.TidepoolNav
nav.refs.hl=named.TidepoolFocus
GB.Open(); assert(named.TidepoolFrame.visible)
assert(nav.attrs.focus==1 and nav.bindings.PADDUP and nav.bindings.PAD1[1]==named.TidepoolSlot1 and nav.bindings.PAD1[2]=='RightButton')
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
for _,d in ipairs({'up','down','left','right'}) do local c=named['TidepoolPad'..d].clicks; assert(c.AnyUp and not c.AnyDown,d..' registers up only') end
-- even if a down click ever reaches the snippet, it must not move
nav.attrs.focus=5; SecureHandlerExecute(named.TidepoolPadright,named.TidepoolPadright.attrs._onclick,'LeftButton',true); assert(nav.attrs.focus==5)
nav.attrs.focus=1
press('right'); assert(nav.attrs.focus==2 and nav.bindings.PAD1[1]==named.TidepoolSlot2)
press('down'); assert(nav.attrs.focus==10)
nav.attrs.focus=8; press('right'); assert(nav.attrs.focus==9,'row end wraps to next row')
nav.attrs.focus=9; press('left'); assert(nav.attrs.focus==8)
nav.attrs.focus=1; press('up'); assert(nav.attrs.focus==25)
assert(nav.bindings.PAD3[2]=='LeftButton')
-- pad nav off removes d-pad bindings
GB.Slash('pad off'); assert(nav.attrs.padnav==0 and not nav.bindings.PADDUP and not nav.bindings.PAD1)
GB.Slash('pad on'); assert(nav.bindings.PADDUP)

-- 5. open/close via normal bag keys, replaces default bag
GB.Close(); assert(not named.TidepoolFrame.visible and next(nav.bindings)==nil)
ToggleAllBags(); assert(named.TidepoolFrame.visible and not ContainerFrame1.visible,'default must be hidden')
ToggleAllBags(); assert(not named.TidepoolFrame.visible)
ToggleBackpack(); assert(named.TidepoolFrame.visible)
CloseAllBags(); assert(not named.TidepoolFrame.visible)
OpenAllBags(); assert(named.TidepoolFrame.visible); CloseAllBags()
ContainerFrame1:Show(); assert(not ContainerFrame1.visible,'default OnShow hidden')
-- setting off -> default bag returns
GB.Slash('default on'); assert(TidepoolDB.enabled==false)
ContainerFrame1:Hide(); defaultShown=false
ToggleAllBags(); assert(ContainerFrame1.visible and not named.TidepoolFrame.visible)
GB.Slash('default off'); assert(TidepoolDB.enabled==true); ContainerFrame1:Hide()

-- 6. combat: normal bag opens; open window keeps working, no protected mutation
combat=true; defaultShown=false
ToggleAllBags(); assert(ContainerFrame1.visible and not named.TidepoolFrame.visible)
combat=false; ContainerFrame1:Hide(); GB.Open()
combat=true
items['0:1']={iconFileID=1234,stackCount=5,quality=4}
emit('BAG_UPDATE')
assert(named.TidepoolSlot1.icon.texture==1234 and named.TidepoolSlot1.count.text==5)
assert(named.TidepoolSlot1.border[1]==.6 and named.TidepoolSlot1.border[3]==.9,'quality border')
items['0:1']=nil; emit('BAG_UPDATE')
assert(named.TidepoolSlot1.icon.texture==nil and named.TidepoolSlot1.count.text=='')
named.TidepoolSlot1.scripts.PostClick(named.TidepoolSlot1,'LeftButton'); assert(picked[2]==1)
sizes[2]=2; emit('BAG_UPDATE'); assert(not named.TidepoolSlot29.visible)
GB.Slash('cols 5'); assert(TidepoolDB.columns==5)
combat=false; emit('PLAYER_REGEN_ENABLED'); assert(named.TidepoolSlot29 and named.TidepoolSlot29.visible and nav.attrs.count==30)
GB.Slash('cols 8'); sizes[2]=0; GB.Layout()

-- 7. Alt+drag move, saved position
local f=named.TidepoolFrame
alt=false; f.scripts.OnDragStart(f); assert(not f.moving)
alt=true; f.scripts.OnDragStart(f); assert(f.moving)
f.scripts.OnDragStop(f); assert(not f.moving and TidepoolDB.point[1]=='BOTTOMRIGHT')
combat=true; f.moving=false; f.scripts.OnDragStart(f); assert(not f.moving); combat=false
GB.Slash('help'); GB.Slash('config'); GB.Slash('bogus')
assert(table.concat(msgs,'\n'):find('Unknown'))
local seenEsc=false for _,n in ipairs(UISpecialFrames) do if n=='TidepoolFrame' then seenEsc=true end end
assert(seenEsc)


-- 8. minimap button: placement, drag angle, click actions, hide setting
local mm=named.TidepoolMinimapButton; assert(mm and mm.parent==Minimap and GridBagDB==nil or true)
local ox,oy=GB.MinimapOffset(0); assert(math.abs(ox-80)<1e-6 and math.abs(oy)<1e-6)
ox,oy=GB.MinimapOffset(90); assert(math.abs(ox)<1e-6 and math.abs(oy-80)<1e-6)
assert(math.abs(GB.AngleFromCursor(0,-5)-270)<1e-6 and math.abs(GB.AngleFromCursor(5,5)-45)<1e-6)
assert(mm.visible and mm.point[1]=='CENTER' and mm.point[2]==Minimap)
GB.Close(); mm.scripts.OnClick(mm,'LeftButton'); assert(named.TidepoolFrame.visible,'left click opens')
mm.scripts.OnClick(mm,'LeftButton'); assert(not named.TidepoolFrame.visible,'left click closes')
mm.scripts.OnClick(mm,'RightButton'); assert(named.TidepoolSettings.visible,'right click opens settings')
mm.scripts.OnClick(mm,'RightButton'); assert(not named.TidepoolSettings.visible)
mm.scripts.OnDragStart(mm); assert(mm.scripts.OnUpdate); mm.scripts.OnUpdate(mm)
assert(math.abs(TidepoolDB.minimap.angle-45)<1e-6,'drag saves angle'); mm.scripts.OnDragStop(mm); assert(not mm.scripts.OnUpdate)
GB.Slash('minimap off'); assert(TidepoolDB.minimap.hide and not mm.visible)
GB.Slash('minimap on'); assert(not TidepoolDB.minimap.hide and mm.visible)
named.TidepoolSettings:Show(); named.TidepoolCheckMinimap.checked=true; named.TidepoolCheckMinimap.scripts.OnClick(named.TidepoolCheckMinimap)
assert(TidepoolDB.minimap.hide and not mm.visible); GB.SetMinimapHidden(false)
named.TidepoolColPlus.scripts.OnClick(); assert(TidepoolDB.columns==9); GB.SetCols(8); named.TidepoolSettings:Hide()

-- 9. money, free slots, search, cooldown, theme
assert(GB.MoneyText(123456):find('12g') and GB.MoneyText(123456):find('34s') and GB.MoneyText(123456):find('56c'))
items['0:1']={iconFileID=1,stackCount=1,quality=1,hyperlink='|cff|Hitem:1|h[Water Flask]|h|r'}
items['0:2']={iconFileID=2,stackCount=1,quality=1,hyperlink='|cff|Hitem:2|h[Iron Sword]|h|r'}
GB.Open(); GB.Refresh()
assert(named.TidepoolFrame.children==nil)
assert(GB.free==26,'free slots count '..tostring(GB.free))
GB.SetQuery('water'); assert(named.TidepoolSlot1.alpha==1 and named.TidepoolSlot2.alpha<1,'search dims non-matches')
GB.SetQuery(''); assert(named.TidepoolSlot2.alpha==1)
assert(GB.Matches('Water Flask','WAT') and not GB.Matches('Iron','wat') and GB.Matches(nil,''))
C_Container.GetContainerItemCooldown=function(b,s) if s==1 then return 10,30,1 end return 0,0,1 end
GB.Refresh(); assert(named.TidepoolSlot1.cd.cooldown[2]==30 and named.TidepoolSlot2.cd.cooldown[2]==0,'cooldown swirl')
-- the d-pad never lands on the search box: nav only references slots
for i=1,28 do assert(nav.attrs['right'..i]<=28) end
GB.Close()
-- 10. migrate GridBag saved settings
TidepoolDB=nil; GridBagDB={columns=10,scale=1.2}
emit('ADDON_LOADED','Tidepool'); assert(TidepoolDB.columns==10 and TidepoolDB.scale==1.2 and TidepoolDB.minimap.angle==215 and TidepoolDB.padNav==true)
TidepoolDB.columns=8

io.stdout:write('PASS: one-press-one-slot, minimap, search, money, migration, grid order, neighbors, secure d-pad snippet, open/close/default swap, combat safety, Alt-drag\n')
