-- Offline harness for GridBag. Run: lua5.1 tests/runtime.lua
local source = arg[1] or 'GridBag.lua'
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
function M:RegisterForClicks() end
function M:SetFrameLevel(v) self.level=v end
function M:GetFrameLevel() return self.level or 1 end
function M:SetTexture(t) self.texture=t end
function M:SetBackdropBorderColor(r,g,b) self.border={r,g,b} end
function M:StartMoving() protected(self);self.moving=true end
function M:StopMovingOrSizing() self.moving=false end
function M:ClearBindings() self.bindings={} end
function M:ClearBinding(k) self.bindings[k]=nil end
function M:SetBindingClick(p,key,target,button) self.bindings[key]={target,button} end
for _,k in ipairs({'SetFrameStrata','SetClampedToScreen','SetMovable','EnableMouse','RegisterForDrag','SetBackdrop','SetBackdropColor','SetScale','SetTexCoord','SetDesaturated','SetHighlightTexture'}) do M[k]=function() end end
CreateFrame=frame
UIParent=frame('Frame','UIParent')
UISpecialFrames={}; SlashCmdList={}
tinsert=table.insert
local alt=false
function IsAltKeyDown() return alt end
function InCombatLockdown() return combat end
function SecureHandlerExecute(f,snip)
    local fn=assert(loadstring(snip));setfenv(fn,setmetatable({self=f},{__index=_G}));secure=true;local ok,err=pcall(fn);secure=false;assert(ok,err)
end
NUM_BAG_SLOTS=4
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

assert(loadfile(source))('GridBag')
GridBagDB={columns=8}
emit('ADDON_LOADED','GridBag')
emit('PLAYER_LOGIN')
local GB=GridBag
local N=GB.Neighbors

-- 1. grid order: bag 0 slot 1 first, then bag 1, no skipping
local o=GB.BuildOrder({[0]=2,3,n=2})
assert(#o==5 and o[1][1]==0 and o[1][2]==1 and o[2][2]==2 and o[3][1]==1 and o[3][2]==1 and o[5][2]==3)
assert(named.GridBagSlot1.bag==0 and named.GridBagSlot1.slot==1)
assert(named.GridBagSlot16.bag==0 and named.GridBagSlot16.slot==16)
assert(named.GridBagSlot17.bag==1 and named.GridBagSlot17.slot==1)
assert(named.GridBagSlot28.bag==1 and named.GridBagSlot28.slot==12 and not named.GridBagSlot29)
assert(named.GridBagSlot1.attrs.item2=='0 1' and named.GridBagSlot1.attrs.type2=='item')
-- visual positions: 8 columns, row by row
local function xy(i) local p=named['GridBagSlot'..i].point; return p[4],p[5] end
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
assert(named.GridBagNav.attrs.right8==9 and named.GridBagNav.attrs.down1==9 and named.GridBagNav.attrs.left1==28)
sizes[2]=6; GB.Layout()
assert(named.GridBagSlot34 and named.GridBagSlot34.bag==2 and named.GridBagSlot34.slot==6)
assert(named.GridBagNav.attrs.count==34)
sizes[2]=0; GB.Layout()
assert(not named.GridBagSlot29.visible and named.GridBagSlot29.bag==nil and named.GridBagNav.attrs.count==28)
GridBagDB.columns=4; slashed=true; GB.Slash('cols 6'); assert(GridBagDB.columns==6 and named.GridBagNav.attrs.down1==7)
GB.Slash('cols 8')

-- 4. secure snippet moves focus and rebinds A / X (d-pad logic, run in combat too)
local nav=named.GridBagNav
nav.refs.hl=named.GridBagFocus
GB.Open(); assert(named.GridBagFrame.visible)
assert(nav.attrs.focus==1 and nav.bindings.PADDUP and nav.bindings.PAD1[1]==named.GridBagSlot1 and nav.bindings.PAD1[2]=='RightButton')
local function press(d) combat=true; SecureHandlerExecute(named['GridBagPad'..d],named['GridBagPad'..d].attrs._onclick); combat=false end
press('right'); assert(nav.attrs.focus==2 and nav.bindings.PAD1[1]==named.GridBagSlot2)
press('down'); assert(nav.attrs.focus==10)
nav.attrs.focus=8; press('right'); assert(nav.attrs.focus==9,'row end wraps to next row')
nav.attrs.focus=9; press('left'); assert(nav.attrs.focus==8)
nav.attrs.focus=1; press('up'); assert(nav.attrs.focus==25)
assert(nav.bindings.PAD3[2]=='LeftButton')
-- pad nav off removes d-pad bindings
GB.Slash('pad off'); assert(nav.attrs.padnav==0 and not nav.bindings.PADDUP and not nav.bindings.PAD1)
GB.Slash('pad on'); assert(nav.bindings.PADDUP)

-- 5. open/close via normal bag keys, replaces default bag
GB.Close(); assert(not named.GridBagFrame.visible and next(nav.bindings)==nil)
ToggleAllBags(); assert(named.GridBagFrame.visible and not ContainerFrame1.visible,'default must be hidden')
ToggleAllBags(); assert(not named.GridBagFrame.visible)
ToggleBackpack(); assert(named.GridBagFrame.visible)
CloseAllBags(); assert(not named.GridBagFrame.visible)
OpenAllBags(); assert(named.GridBagFrame.visible); CloseAllBags()
ContainerFrame1:Show(); assert(not ContainerFrame1.visible,'default OnShow hidden')
-- setting off -> default bag returns
GB.Slash('default on'); assert(GridBagDB.enabled==false)
ContainerFrame1:Hide(); defaultShown=false
ToggleAllBags(); assert(ContainerFrame1.visible and not named.GridBagFrame.visible)
GB.Slash('default off'); assert(GridBagDB.enabled==true); ContainerFrame1:Hide()

-- 6. combat: normal bag opens; open window keeps working, no protected mutation
combat=true; defaultShown=false
ToggleAllBags(); assert(ContainerFrame1.visible and not named.GridBagFrame.visible)
combat=false; ContainerFrame1:Hide(); GB.Open()
combat=true
items['0:1']={iconFileID=1234,stackCount=5,quality=4}
emit('BAG_UPDATE')
assert(named.GridBagSlot1.icon.texture==1234 and named.GridBagSlot1.count.text==5)
assert(named.GridBagSlot1.border[1]==.6 and named.GridBagSlot1.border[3]==.9,'quality border')
items['0:1']=nil; emit('BAG_UPDATE')
assert(named.GridBagSlot1.icon.texture==nil and named.GridBagSlot1.count.text=='')
named.GridBagSlot1.scripts.PostClick(named.GridBagSlot1,'LeftButton'); assert(picked[2]==1)
sizes[2]=2; emit('BAG_UPDATE'); assert(not named.GridBagSlot29.visible)
GB.Slash('cols 5'); assert(GridBagDB.columns==5)
combat=false; emit('PLAYER_REGEN_ENABLED'); assert(named.GridBagSlot29 and named.GridBagSlot29.visible and nav.attrs.count==30)
GB.Slash('cols 8'); sizes[2]=0; GB.Layout()

-- 7. Alt+drag move, saved position
local f=named.GridBagFrame
alt=false; f.scripts.OnDragStart(f); assert(not f.moving)
alt=true; f.scripts.OnDragStart(f); assert(f.moving)
f.scripts.OnDragStop(f); assert(not f.moving and GridBagDB.point[1]=='BOTTOMRIGHT')
combat=true; f.moving=false; f.scripts.OnDragStart(f); assert(not f.moving); combat=false
GB.Slash('help'); GB.Slash('config'); GB.Slash('bogus')
assert(table.concat(msgs,'\n'):find('Unknown'))
local seenEsc=false for _,n in ipairs(UISpecialFrames) do if n=='GridBagFrame' then seenEsc=true end end
assert(seenEsc)

io.stdout:write('PASS: grid order, neighbors, secure d-pad snippet, open/close/default swap, combat safety, Alt-drag\n')
