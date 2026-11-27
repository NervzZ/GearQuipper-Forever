# GearQuipper Forever

**Bringing back the beloved GearQuipper addon for WoW Forever!**

Quick-switch your gear sets straight from the character sheet. GearQuipper Forever is a port of **GearQuipper**, the gear-set manager by Benjamin Bober, which has not been updated since 2023. It keeps GearQuipper's workflow, brings it to WoW Forever's client, and adds a few improvements along the way.

---

## Features

- **Gear sets.** Save full sets, or partial sets that only manage the slots you tick (a weapon swap or a fishing set, for example). Two identical rings, trinkets or weapons are handled correctly.
- **A panel on the character sheet.** The GearQuipper panel docks next to your character window, with a **Sets** tab and an **Events** tab. Each set gets a row with its icon, a tick on the set you are wearing and a badge for the spec it is bound to. Click a set to equip it, or right-click it to save your worn gear into it, make it a partial set, pick its colour, move it to or from the bank, or delete it. **New set** saves what you wear as a new set, **Save** updates the current one.
- **Set colours.** Give each set a colour. It shows on the set's name in the list, in item tooltips (also for the gear you are wearing) and on the "Current set" label on the character sheet.
- **Quick bars.** Hover an equipment slot to see every item from your bags (and your other slots) that fits it, then click one to equip it. The bars look like Blizzard's equipment flyout, with rarity borders, and the item tooltip moves aside so it never covers the bar. Hold **Alt** for Blizzard's own flyout.
- **A set per spec.** Bind a set to each spec and GearQuipper swaps your gear as soon as you change spec.
- **Automatic swaps on events.** Mount, dismount, entering or leaving a battleground, zone, combat, swimming, stealth, druid forms, warrior stances, paladin auras, joining a party or raid, PvP flag, AFK, and more. You add and remove bindings right in the Events tab.
- **Fast switching.** Each step of a switch starts as soon as the server has moved the previous items, with no fixed waits.
- **Combat-aware.** Armor changes requested in combat are queued and done as soon as combat ends. Weapons are swapped in combat when the game allows it.
- **Bank support.** Push a whole set into your bank tabs, or pull it back into your bags, in one click.
- **Set info in tooltips.** Item tooltips list the sets an item belongs to. Press **Left Alt** over an item to compare it with each of your sets.
- **Sell protection.** At a vendor, the items of your sets are greyed out with a small red cross in your bags (Blizzard's bags and EllesmereUI's bags), and a right-click asks before it sells one. An item sold another way, for example by a junk-seller addon, is bought back at once and GearQuipper asks whether to sell it after all. Spare copies, more than your sets need, are not protected.
- **Delete protection.** When you delete an item that belongs to a set, the game's delete prompt stays locked until you confirm in GearQuipper's warning.
- **Works with UI suites.** GearQuipper follows EllesmereUI's look while its character-sheet skin is on, and keeps the stock Blizzard look otherwise. ElvUI support is included but untested: reports welcome.
- **Data broker launcher** for Titan Panel, ChocolateBar and similar addons, plus an options page in the game's Settings (sell and delete protection can be turned off there).

## What changed from the original GearQuipper

- Rebuilt for WoW Forever's modern client: the tabbed bank, the new item links, and the game's new restrictions.
- **No Lua errors in battlegrounds, dungeons or raids.** The game now hides some player information from addons there (AFK status, for example), and GearQuipper Forever handles that safely.
- **A new panel:** one window docked to the character sheet, with Sets and Events tabs in today's Blizzard style. Event bindings are made inside the panel instead of a separate window, and the old "Disable events" box is now **Enable event bindings**.
- Quick bars open on mouse-over, not only on click, look like Blizzard's equipment flyout, and the tooltip is moved out of their way.
- Much faster set switching, and spec-change swaps that start right after the spec change.
- **New:** set colours, sell and delete protection for set items, and the UI-suite looks.
- About 20 bugs from the original fixed.
- **Removed:**
  - Action bar management: WoW Forever already swaps action bars with your spec.
  - Spell upranking.
  - The experimental custom-script editor.

## Getting started

1. Open your character sheet and click the **GQ** button to open the panel.
2. Put on a set of gear, click **New set** and give it a name. Repeat for each set.
3. Click a set in the list to switch to it, or hover an equipment slot to swap single items. Right-click a set for more options.
4. For automatic swaps, open the **Events** tab, tick **Enable event bindings**, then click **Add binding**. For example, add "on talents change → Primary → your first spec's set".

> Gear you change by hand is saved into the current set while the GearQuipper panel is open. You can change this in the options.

## Commands

Type `/gq` on its own to show the list in game.

| Command | What it does |
|---|---|
| `/gq switch <set>` | Switches to a set. |
| `/gq switch <set1> <set2> …` | Cycles through the listed sets, one per use. Put it in a macro and bind it to a key. |
| `/gq switch` | Cycles through all your sets. |
| `/gq save [set]` | Saves your current gear into the named set, or into the current set. |
| `/gq toggleevents` | Turns automatic event swaps on or off. |
| `/gq affectshelmet` | Toggles whether the current set controls helmet visibility. |
| `/gq affectscloak` | Toggles whether the current set controls cloak visibility. |
| `/gq reset` | Resets all GearQuipper data, after a confirmation. |

Set names with spaces go in quotes: `/gq switch "Fire Resistance"`.
Two special names also work with `switch`:
- `$PREVIOUS`: the set you wore before.
- `$PREVIOUSEQUIPMENT`: exactly the gear you had on before the last switch.

## Notes

- **Use only one gear manager at a time.** EqManager, for example, switches GearQuipper off when both are loaded.
- **Delete protection covers the game's delete prompt.** An addon that deletes items by itself, without that prompt, is not stopped.
- **Languages:** English and German.
- Bug reports and suggestions are welcome in the comments.

## Credits

- **Original GearQuipper:** Benjamin Bober.
- **WoW Forever port:** NervzZ.
