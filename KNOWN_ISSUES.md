# Known issues

**Destroying items with the controller doesn't work yet.**
Choosing **Destroy** from Aquifer's item menu is blocked by the game ("an interface action was blocked because of an addon"), and nothing gets deleted. The game only lets its own bag code delete items.
*Workaround:* destroy the item from the normal bag, or drag it out with the mouse. The next update makes Destroy open the normal bag at that item, so you can finish there.

**After that blocked popup, the controller can get confused.**
You may see a Lua error such as "Frame is not tracked by FrameControlsManager" or "Invalid frame handle", and the d-pad may stop moving the selection.
*Workaround:* type `/reload`. This is fixed in the next update.

**Controller input pauses in combat.**
This is a Blizzard restriction, not a bug. Your selection comes back when combat ends.

**Identical stacks can swap places.**
If items move while you're switching windows, the yellow selection can jump to another stack of the same item.

**Only tested on WoW Forever with gamepad mode on.**
Other clients, or other bag addons running at the same time, may conflict with Aquifer.

**If Aquifer ever stops responding to your controller,** type `/reload`.

**Found a bug?** Open an issue at https://github.com/waterys419/Aquifer/issues with what you pressed, step by step. Aquifer's built-in bug report text helps a lot.

