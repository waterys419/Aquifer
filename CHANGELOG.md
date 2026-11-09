# Changelog

## 2.2.8

Highlights since 2.2.2: Bind to action bar now works with the controller only (a picker that shows your controller buttons), Aquifer no longer gets stuck after binding, and `/aq bug` makes a copyable bug report.


- The picker now shows the controller button that fires each slot instead of slot numbers. Labels come from the client's own gamepad bindings and label art (d-pad arrows, face buttons, L1/L2/R1/R2 and combinations such as L2 + X).
- Tiles are grouped like the on-screen cross bars: top bar, left bar (left modifier), right bar (right modifier), bottom bar (both). Only slots that have a controller binding are shown.
- Placement uses the gamepad storage slot of the chosen button, so the item lands on the button the player pressed. Three standard pages, switched with the spare shoulder pair shown in the picker.

## 2.2.7

- Bind now opens an action-slot picker: d-pad moves, [X] places the item on the selected slot, [O] cancels, L2/R2 switches page 1-6 (slots 1-72). Each slot shows its current icon and number.
- No mouse cursor and no stock Bind editor: out of combat Aquifer calls the same two client functions the stock UI uses (pick up the item, then place it on the action slot) and clears a displaced action afterwards. In combat the picker refuses and stays open.
- Aquifer returns to the bag with the same item selected after placing or cancelling.

## 2.2.6

- Replace the manual stock-bag handoff with immediate pickup of the selected item for controller-cursor placement on a native action slot. [O] cancels; Aquifer returns automatically.
- Remove keyboard-key and slash-command instructions from the normal binding flow. The protected stock Bind editor is not automated; native controller-cursor placement remains an in-game test.

## 2.2.5

- Add `/aq bug`: a copyable, privacy-filtered report with client settings, detected bag addons and the last 100 quietly recorded events. Include a GitHub issue template.

- Recover after 10 seconds when Bind is chosen but the player never opens stock bags or starts native binding. Active stock binding is never timed out.
- Keep `/aq debug` available, switch it off once on upgrade, and preserve the saved trace. The recorded failure occurred before native binding started.

## 2.2.4

- Add opt-in `/aq debug` chat tracing and a saved last-200-line log for bag visibility, focus, cursor/action-slot events and stock editor mode. Toggle again to stop logging.
- The action-bar return bug remains under investigation; no further return-logic changes in this build.

## 2.2.3

- Automatically resume Aquifer after stock item binding, placement or cancellation. Wait for the edit dialog to close, the cursor to clear and combat to end; preserve short stock-window transitions.
- Fix the handoff remaining active until `/aq bindcancel` or reload, a behavior already present in 2.2.1.

## 2.2.2

- Show the native item tooltip for the controller-selected bag slot, including its sell-price information. Mouse hover remains available.
- Hide Aquifer-owned tooltips on empty slots, window handoff, combat and bag close without hiding another window's tooltip.

## 2.2.1

- Hide the focus notice by default and remove its recovery button. Use `/aq recover`; `/aq notice` enables the optional debug label.
- Show contextual Cross/X (Xbox A) hints in the existing footer: Sell item, Deposit, Attach on Send Mail, and Trade.
- Hide the sale hint for unknown prices and show Can't sell for items without sale value. Contextual hover selection respects combat and controller focus.

## 2.2.0

- Add read-only bank memory with saved snapshots, search and controller navigation.
- Integrate stock L2/R2 window switching with selection-preserving controller handoff and recovery.
- Add contextual vendor, bank and trade actions, held-item placement and an explicit return from stock item binding.
