-- Exercise the exact exported callback chain implicated by Audrey's probe.
-- The trusted/untrusted flag models the observed native restriction; this is
-- not an emulator of WoW taint and does not establish live verification.
local root=arg[1] or '/mnt/a/Games/World of Warcraft/_forever_/BlizzardInterfaceCode/Interface/AddOns'
local function noop() end
local function no() return false end
local trusted=false
local calls=0
local env=setmetatable({
    GamepadSharedUtility={BindingStack={}},
    InputUtil={RegisterForInterfaceTransitions=noop,RegisterGamepadInit=noop,RegisterGamepadUninit=noop},
    InGlue=no,UnitExists=no,UnitIsGameObject=no,UnitHasLootInteraction=no,UnitIsInInteractRange=no,
    UnitClassBase=function() return 'PRIEST' end,
    C_PetInfo={IsPetOrderMoveToPending=no},C_Spell={GetSpellTexture=function(id) return id end},
    GamepadMode={IsTargetingModifierDown=no,HasTargetingModifierVisualState=no},
    EventRegistry={TriggerEvent=noop},
    SetPreferredGamepadInteractTarget=function()
        assert(trusted,'ADDON_ACTION_FORBIDDEN / SetPreferredGamepadInteractTarget()')
        calls=calls+1
    end,
}, {__index=_G})
local function stock(path)
    local f=assert(loadfile(root..'/'..path));setfenv(f,env);f()
end
stock('Blizzard_GamepadSharedUtility/InputBindingStack/InputBindingManager.lua')
stock('Blizzard_GamepadActionBars/MainActionBarFrame.lua')
local manager=env.GamepadSharedUtility.InputBindingManager
local top={HideHighlight=noop,Right={ActionButton1={SpecialActionIcon={SetTexture=noop}}}}
local main=setmetatable({PageUnit={actionBars={topBar=top},ShowModifierIcons=noop,ActionBarModKeyDownStateCheck=noop}}, {__index=env.GamepadMainActionBarFrameMixin})
manager:BindToCoreBindingActive(function() main:UpdateActionBarFocusedState() end)
manager.bindingSetStack={{treatBindsAsCore=false}}
-- Negative control: caller remains insecure; protected callback fails at the named API.
local ok,err=pcall(manager.AssumeCoreBindingsAreUsable,manager,false)
assert(not ok and err:find('SetPreferredGamepadInteractTarget',1,true))
-- Stock hardware/secure-frame paths run the same callbacks in trusted context.
trusted=true
manager:AssumeCoreBindingsAreUsable(false)
manager:AssumeCoreBindingsAreUsable(true)
assert(calls==2)
print('PASS: exported binding-manager -> focused-state -> interact-icons chain reproduces the named forbidden call in the insecure model and succeeds for trusted stock input')
