# Waterys Satchel

One combined bag, shown as a plain grid, for **WoW: Forever** (client folder `_forever_`). It replaces your separate bags with a single window, and you can move around it with a controller d-pad.

- All bags in one grid, with a water-blue look.
- Search box: items that don't match are greyed out.
- Shows free slots, your money, and item cooldowns.
- Minimap button to open the bag and change settings.
- Controller d-pad moves one slot per press.

## Install

1. Download this repo (green **Code** button → **Download ZIP**).
2. Unzip it and rename the folder to `WaterysSatchel`.
3. Put it in `World of Warcraft/_forever_/Interface/AddOns/`.
4. Restart the game, or type `/reload`.

## Controller d-pad

While the bag is open, the d-pad moves a yellow frame from slot to slot, exactly one slot per press, in the direction you press. X or Triangle on an item opens its menu (Use, Equip, Bind, Split, Share in Chat, Destroy - only what fits the item). Triangle on an empty slot opens the bag menu (Cleanup, Sell Junk). Square is the quick action on the selected item: Equip if it is gear, otherwise Use if it can be used (the footer shows which). Circle closes the menu, then the bag. Hide empty slots is a tick box in settings, and an entry in the Triangle bag menu. Turn this off with `/satchel pad off` or the **Controller d-pad in bag** checkbox.

## Minimap button

The button sits on the outer edge of the minimap, like most addon buttons.

| Action | What it does |
|---|---|
| Left click | Open or close the bag |
| Right click | Open the settings window |
| Drag | Slide the button around the minimap edge (the spot is saved) |
| Hover | Shows what the button does |

Hide it with `/satchel minimap off` or the **Hide minimap icon** checkbox.

## Commands

Every command works with `/satchel` or the short `/ws`.

| Command | What it does |
|---|---|
| `/satchel help` | List all commands in chat |
| `/satchel toggle` | Open or close the bag |
| `/satchel settings` | Open the settings window |
| `/satchel minimap on` / `off` | Show or hide the minimap button |
| `/satchel search word` | Grey out every item that doesn't match |
| `/satchel cols 8` | Slots per row (4 to 20, default 8) |
| `/satchel scale 1` | Window size (0.5 to 2, default 1) |
| `/satchel hide on` / `off` | Hide empty slots |
| `/satchel probe` | List bind / gamepad names in this client (also saved to the SavedVariables) |
| `/satchel pad on` / `off` | Turn controller d-pad movement on or off |
| `/satchel default on` / `off` | `on` brings the normal bags back; `off` uses the Satchel |
| `/satchel reset` | Put the window back at its starting spot |
| `/satchel config` | Show your current settings in chat |

**Move the window:** hold **Alt** and left-drag it (out of combat). The position is saved.

## Settings window

Open it with `/satchel settings` or right-click the minimap button.

- **Hide minimap icon**
- **Controller d-pad in bag**
- **Hide empty slots**
- **Use Waterys Satchel instead of normal bag**
- **Columns** buttons to change slots per row.

## Offline checks

From the repository folder, run `lua5.1 tests/runtime.lua`. It mocks the client and checks grid order, d-pad neighbors, minimap button, search, money and combat safety. In-game checks are still needed.

Author: Audrey

## Bind an item to a controller action bar

1. After updating, type `/reload` to clear the previous version's tainted session.
2. Choose **Bind** in Satchel's item menu outside combat. Satchel closes, releases all its keys, and a secure click opens that item's normal Blizzard bag. If it does not open, press your normal Bags button.
3. In the Blizzard bag, select the item again, then **More Actions → Bind to Action Bar**. Blizzard starts the binding dialog from its own controller input; Satchel does not call its binding or focus methods.
4. Select the desired action bar with your normal left/right modifiers, then press the D-pad or a face button. The stock unmodified face slots for Interact/Back and similar controls remain reserved.
5. Finish or cancel binding, then close the Blizzard bags. Satchel returns after all stock bag/binding windows are closed (and after combat if necessary).

If the handoff is waiting but no Blizzard window opened, `/satchel bindcancel` returns to Satchel. It does not force-close Blizzard windows. `/satchel probe` records any protected call named by the game during the handoff.

Stock bag replacement now hides the normal bags through secure frame-handle operations, avoiding addon-driven focus callbacks. No Blizzard mixin methods, global functions or binding tables are replaced. Permanent controller bindings are unchanged.

Offline checks: `lua5.1 tests/runtime.lua`; with Audrey's read-only UI export available, run `lua5.1 tests/stock-bind.lua` and `lua5.1 tests/stock-focus.lua`. They cover handoff, key release, trusted stock-button delegation, stock dispatcher routes and the callback chain reported by the probe. They do not emulate the native taint engine or physical controller input; the in-game steps above remain required before release.
