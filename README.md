# Aquifer

One combined bag, shown as a plain grid, for **WoW: Forever** (client folder `_forever_`). It replaces your separate bags with a single window, and you can move around it with a controller d-pad.

- All bags in one grid, with a water-blue look.
- Search box: items that don't match are greyed out.
- Shows free slots, your money, and item cooldowns.
- Minimap button to open the bag and change settings.
- Controller d-pad moves one slot per press.

## Install

1. Download this repo (green **Code** button → **Download ZIP**).
2. Unzip it and rename the folder to `Aquifer`.
3. Put it in `World of Warcraft/_forever_/Interface/AddOns/`.
4. Restart the game, or type `/reload`.

## Controller d-pad

While the bag is open, the d-pad moves a yellow frame from slot to slot, exactly one slot per press, in the direction you press. X or Triangle on an item opens its menu (Use, Equip, Bind, Split, Share in Chat, Destroy - only what fits the item). Triangle on an empty slot opens the bag menu (Cleanup, Sell Junk). Square is the quick action on the selected item: Equip if it is gear, otherwise Use if it can be used (the footer shows which). Circle closes the menu, then the bag. Hide empty slots is a tick box in settings, and an entry in the Triangle bag menu. Turn this off with `/aquifer pad off` or the **Controller d-pad in bag** checkbox.

## Minimap button

The button sits on the outer edge of the minimap, like most addon buttons.

| Action | What it does |
|---|---|
| Left click | Open or close the bag |
| Right click | Open the settings window |
| Drag | Slide the button around the minimap edge (the spot is saved) |
| Hover | Shows what the button does |

Hide it with `/aquifer minimap off` or the **Hide minimap icon** checkbox.

## Commands

Every command works with `/aquifer` or the short `/aq`.

| Command | What it does |
|---|---|
| `/aquifer help` | List all commands in chat |
| `/aquifer toggle` | Open or close the bag |
| `/aquifer settings` | Open the settings window |
| `/aquifer minimap on` / `off` | Show or hide the minimap button |
| `/aquifer search word` | Grey out every item that doesn't match |
| `/aquifer cols 8` | Slots per row (4 to 20, default 8) |
| `/aquifer scale 1` | Window size (0.5 to 2, default 1) |
| `/aquifer hide on` / `off` | Hide empty slots |
| `/aquifer probe` | List bind / gamepad names in this client (also saved to the SavedVariables) |
| `/aquifer pad on` / `off` | Turn controller d-pad movement on or off |
| `/aquifer default on` / `off` | `on` brings the normal bags back; `off` uses the Aquifer |
| `/aquifer reset` | Put the window back at its starting spot |
| `/aquifer config` | Show your current settings in chat |

**Move the window:** hold **Alt** and left-drag it (out of combat). The position is saved.

## Settings window

Open it with `/aquifer settings` or right-click the minimap button.

- **Hide minimap icon**
- **Controller d-pad in bag**
- **Hide empty slots**
- **Use Aquifer instead of normal bag**
- **Columns** buttons to change slots per row.

## Offline checks

From the repository folder, run `lua5.1 tests/runtime.lua`. It mocks the client and checks grid order, d-pad neighbors, minimap button, search, money and combat safety. In-game checks are still needed.

Author: Audrey

## Bind an item to a controller action bar

1. **Restart the game completely** after installing Aquifer (the renamed folder needs a restart).
2. Outside combat, choose **Bind** in Aquifer's item menu. Aquifer closes and releases all its controller keys. It prints one hint with the item and its bag/slot.
3. **Press your normal Bags button yourself** (the hint shows the configured Bags key when available). Aquifer will leave Blizzard's bag open. Select the named item, then **More Actions → Bind to Action Bar**.
4. Select the desired action bar with your normal left/right modifiers, then press the D-pad or a face button. Test left, right and both modifiers. Blizzard's unmodified face slots for Interact/Back remain reserved.
5. Finish or cancel binding. Close Blizzard's bags and dialog, then type **`/aq bindcancel`** to return to Aquifer. If in combat, the return waits until combat ends.

Bind is a manual handoff, not a direct dialog opener. It never clicks a stock button or calls a stock binding/focus method. Duplicate clicks do nothing. Temporary stock-window hides, repeated bag toggles and roster/bag events do not end handoff. This prevents Aquifer from hiding/replacing stock bags or reclaiming the face/shoulder keys during binding. It remains suspended until you explicitly return, even if you never opened a stock bag. No focus preselection is attempted.

The exported client's `EnterEditMode` enters `SELECT_ACTION_TO_PICKUP`; it does not import a held cursor item. Therefore this version does not pick up the item or promise an unsupported cursor-to-edit shortcut. The supported stock item menu starts Bind from the player's own input. `/aquifer probe` records protected-call errors during handoff.

Offline checks: `lua5.1 tests/runtime.lua`, `lua5.1 tests/stock-bind.lua`, `lua5.1 tests/stock-focus.lua` (the last two read Audrey's UI export). They test duplicate callbacks, brief stock-window closures, hook suppression, all override owners, explicit return/combat deferral, stock routing and the reported restricted callback. They cannot prove native taint behavior or physical controller input. Confirm in game that the bags stay open, no popup appears, and face/shoulder combinations work before public release.
