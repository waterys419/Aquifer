# Aquifer

**Aquifer is built for controller players.** It puts all your bags in one neat grid, and you move through it with the d-pad on a PlayStation or Xbox controller. You can still use the mouse too.

WoW: Forever (client folder `_forever_`).

## Features

- All your bags in one grid, with a water-blue look
- Move one slot at a time with the d-pad
- Item menu and bag menu you can use with the controller
- Search box: items that don't match are greyed out
- Shows free slots, your money and item cooldowns
- Minimap button to open your bag and change settings
- Saved bank view, including your other characters on the same account
- L2 / R2 (LT / RT) switches between your bag and an open bank, vendor, trade or other window

## Controller buttons

Labels are PlayStation first, Xbox in brackets.

| Button | On an item | On an empty slot |
|---|---|---|
| **D-pad** | Move the yellow frame one slot | Move the yellow frame one slot |
| **X** (A) / **Triangle** (Y) | Item menu: Use, Equip, Bind, Split, Share in Chat, Destroy | Bag menu: Cleanup, Sell Junk, Hide empty slots, View bank |
| **Square** (X) | Quick action: Equip gear, or Use anything else | Nothing |
| **Circle** (B) | Close the menu, then the bag | Close the menu, then the bag |

Turn controller movement off with `/aq pad off`, or with the **Controller d-pad in bag** checkbox in settings.

## Mouse

- **Left click** a slot to pick up an item or drop it into a slot
- **Right click** an item to use it
- **Alt + drag** the window to move it (out of combat). It remembers where you put it.

## Install

1. Download Aquifer from CurseForge, then install it with the **CurseForge app**.
   - Or download the zip and put the `Aquifer` folder in `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game, or type `/reload`.

## Commands

Every command works with `/aquifer` or the short `/aq`.

| Command | What it does |
|---|---|
| `/aq help` | List the commands in chat |
| `/aq toggle` | Open or close the bag |
| `/aq settings` | Open the settings window |
| `/aq bank` or `/aqb` | Open or close your saved bank view |
| `/aq search word` | Grey out items that don't match (empty text clears it) |
| `/aq cols 8` | Slots per row (4 to 20, default 8) |
| `/aq scale 1` | Window size (0.5 to 2, default 1) |
| `/aq hide on` / `off` | Hide empty slots |
| `/aq pad on` / `off` | Turn controller movement on or off |
| `/aq minimap on` / `off` | Show or hide the minimap button |
| `/aq default on` / `off` | `off` uses Aquifer; `on` brings back the normal bags |
| `/aq reset` | Put the window back where it started |
| `/aq config` | Show your current settings in chat |

## Bank view

Visit your bank once and Aquifer saves what is in it. Open the saved view any time with `/aq bank`, `/aqb`, or Triangle on an empty bag slot, then choose **View bank**.

- The saved view is read only. Clicking an item won't move or sell it.
- It shows the last time you visited the bank, with a snapshot date and time.
- **Next character** lets you look at the banks of your other characters on this account.

## Settings

Open the settings window with `/aq settings` or by right-clicking the minimap button.

- Hide minimap icon
- Controller d-pad in bag
- Use Aquifer instead of normal bag
- Hide empty slots
- Columns (slots per row)

## Author

Made by Audrey. Source and issues: https://github.com/waterys419/Aquifer

Licensed under the MIT License. See the LICENSE file in the download.

## Bind to action bar

Choose an item, press **Triangle**, then **Bind**. A picker shows your controller buttons laid out like your on-screen bars (for example **X**, **L2 + X**, **L2 + R2 + Triangle**). Move with the **d-pad**, press **X** to place the item on that button, or **O** to cancel. **L1/R1** switch pages. Works out of combat.

## Known issues

- **In combat, Aquifer pauses controller input.** This is a Blizzard restriction. Your selection comes back when combat ends.
- **Identical stacks:** if items move while you switch windows, the yellow selection can jump to another stack of the same item.
- **Only tested on WoW Forever (1.60.1) with gamepad mode on.** Other clients, or other bag addons running at the same time, may conflict with Aquifer.
- **If Aquifer ever stops responding to your controller,** type `/reload` to restore it.

## Report a bug

Type **/aq bug** after a problem. Choose **Select all**, press **Ctrl+C**, and paste the text with the steps you took in either place:

- the **Comments** section here on CurseForge, or
- **github.com/waterys419/Aquifer/issues**

If you saw a **Lua error** popup, please copy that error text too (use the arrows in the error box to get the first one). The report includes versions, gamepad settings, detected loaded bag addons and recent events recorded quietly. Character and realm names are replaced with placeholders; account details, chat messages and inventory contents are not included. Nothing is sent automatically. You do not need to enable /aq debug first.
