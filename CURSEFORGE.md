# GearQuipper Forever

**Quick-switch your gear sets on WoW Forever, straight from the character sheet.**

GearQuipper Forever is a tweaked port of **GearQuipper**, the gear-set manager by Benjamin Bober, which has not been updated since 2023. It brings GearQuipper's look and workflow to WoW Forever's client, and adds a few improvements along the way.

---

## Features

- **Gear sets.** Save full sets, or partial sets that only manage the slots you tick (a weapon swap or a fishing set, for example). Two identical rings, trinkets or weapons are handled correctly.
- **Character sheet panel.** A side panel next to your character window lists your sets. One click equips a set, and a "Current set" label shows what you are wearing.
- **Quick bars.** Hover an equipment slot to see every item from your bags (and your other slots) that fits it, then click one to equip it. The item tooltip moves aside so it never covers the bar. Hold **Alt** for Blizzard's own flyout.
- **A set per spec.** Bind a set to each spec and GearQuipper swaps your gear as soon as you change spec.
- **Automatic swaps on events.** Mount, dismount, entering or leaving a battleground, zone, combat, swimming, stealth, druid forms, warrior stances, paladin auras, joining a party or raid, PvP flag, AFK, and more.
- **Fast switching.** Each step of a switch starts as soon as the server has moved the previous items, with no fixed waits.
- **Combat-aware.** Armor changes requested in combat are queued and done as soon as combat ends. Weapons swap in combat whenever the game allows it.
- **Bank support.** Push a whole set into your bank tabs, or pull it back into your bags, in one click.
- **Set info in tooltips.** Item tooltips list the sets an item belongs to. Press **Left Alt** over an item to compare it with each of your sets.
- **Data broker launcher** for Titan Panel, ChocolateBar and similar addons, plus an options page in the game's Settings.

## What changed from the original GearQuipper

- Rebuilt for WoW Forever's modern client: the tabbed bank, the new item links, and the game's new restrictions.
- **No Lua errors in battlegrounds, dungeons or raids.** The game now hides some player information from addons there (AFK status, for example), and GearQuipper Forever handles that safely.
- Quick bars open on mouse-over, not only on click, and the tooltip is moved out of their way.
- Much faster set switching, and spec-change swaps that start right after the spec change.
- About 20 bugs from the original fixed.
- **Removed:**
  - Action bar management: WoW Forever already swaps action bars with your spec.
  - Spell upranking.
  - The experimental custom-script editor.

## Getting started

1. Open your character sheet and click the **GQ** button to open the panel.
2. Put on a set of gear, click **Add set…** and give it a name. Repeat for each set.
3. Click a set in the list to switch to it, or hover an equipment slot to swap single items.
4. For automatic swaps, untick **Disable events** under the event list, then use **Add event…**. For example, add "on talents change → Primary → your first spec's set".

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
- **Languages:** English and German.
- Bug reports and suggestions are welcome in the comments.

## Credits

- **Original GearQuipper:** Benjamin Bober.
- **WoW Forever port:** NervzZ.
