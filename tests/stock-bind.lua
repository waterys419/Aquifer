-- Read-only check against Audrey's exported stock dispatcher and placement utility.
-- This validates routing/placement logic, NOT WoW's native taint engine or hardware input.
local root=arg[1] or '/mnt/a/Games/World of Warcraft/_forever_/BlizzardInterfaceCode/Interface/AddOns'
local env=setmetatable({import=function() return {} end},{__index=_G})
local function loadStock(file)
    local fn=assert(loadfile(root..'/'..file));setfenv(fn,env);fn()
end
loadStock('Blizzard_GamepadActionBars/ActionBarEditFrame.lua')
loadStock('Blizzard_GamepadActionBars/ActionBindingUtil.lua')
local keys={'PADDUP','PADDRIGHT','PADDDOWN','PADDLEFT','PAD1','PAD2','PAD3','PAD4'}
env.GetBindingKey=function(binding) return keys[tonumber(binding:match('(%d+)$'))] end
env.GamepadRadial={IsShown=function() return false end}
env.C_GamepadUI={IsValidGamepadActionStorageSlotIndex=function(id) return id>0 end}
env.GetActionInfo=function() end -- empty test slots
local cursor, placed, offset, exits=nil,{},0,0
env.C_Item={PickupItem=function(id) cursor=id end}
env.ClearCursor=function() cursor=nil end
env.GetCursorInfo=function() if cursor then return 'item',cursor end end
env.PlaceAction=function(id) assert(cursor==101);placed[#placed+1]=id;cursor=nil end
env.UIErrorsFrame={AddMessage=function(_,msg) error('unexpected stock error: '..tostring(msg)) end}
local bar={GetActionButtonByIndex=function(_,index)
    -- Top-bar face controls are reserved by stock; L/R/both select other bars.
    local id=(offset==0 and index>=5) and 0 or offset+index
    return {GetID=function() return id end}
end}
local dialog=setmetatable({PageUnit={GetActiveBar=function() return bar end,IsPossessBarActiveBarForPageUnit=function() return false end}}, {__index=env.GamepadActionBarEditFrameMixin})
function dialog:DisplayItemAction(id) assert(id==101) end
function dialog:EnterBindingMode() self.activeMode='BIND_ACTION' end
function dialog:ExitBindingMode() self.activeMode='INACTIVE';exits=exits+1 end
dialog:UpdateButtonToListenFor()
for _,barOffset in ipairs({0,8,16,24}) do
    offset=barOffset
    for index,key in ipairs(keys) do
        dialog:BindItem(101)
        local before=#placed
        local propagate=dialog:AttemptBindDown(key)
        if offset==0 and index>=5 then
            assert(#placed==before and propagate,'stock reserved face slot must stay reserved')
        else
            assert(#placed==before+1 and placed[#placed]==offset+index and not propagate, key..' not placed')
        end
    end
end
assert(#placed==28 and exits==28)
print('PASS: exported stock BindItem -> AttemptBindDown -> CaptureActionInput -> placement utility -> PlaceAction: 4 D-pad plus 24 L/R/both-modifier routes; reserved face slots unchanged')
