# WGA Companion

The official WoW Forever addon of **Whirlwind Gaming Academy**: step-by-step quest guides with a waypoint arrow, auction pricing, crafting profit, vendor flips, rare and treasure alerts, and leveling, profession and dungeon references.

## Install
1. Download this repo's `addon/WGACompanion` folder (or a release zip) into `World of Warcraft\_forever_\Interface\AddOns\`.
2. For region-wide prices, download **WGACompanion_Data.zip** from the [prices-us release](../../releases/tag/prices-us) and unzip it next to it. It updates hourly; replace the folder and `/reload` to refresh.
3. In game: `/wga`.

## Minimap button

A whirlwind button sits on the minimap edge. Left-click opens the hub, right-click opens a quick menu (guides, quest icon toggles, AH scan, bag report), and dragging moves it around the edge. `/wga minimap` shows or hides it.

## Themes, settings and the quest tracker

Open **Settings** at the bottom of the hub's sidebar (or `/wga settings`). Pick one of four themes: Dark, Light, High contrast (dark) and High contrast (light). The high contrast themes use larger, outlined text. `/wga theme` cycles them from chat.

The settings page also has sliders for window, text, map icon and tracker size, plus a switch for every feature.

The WGA quest tracker replaces Blizzard's objective list while it's on. Quests are grouped by zone. Each one shows its objectives with progress bars, the distance to the next spot, and who to turn it in to once it's done.
- Click a quest to point the arrow at it.
- Shift-click a quest to open it in the quest log.
- Right-click a quest to fold it.
- Click a zone name to collapse that zone.
- Drag the header to move the tracker.

`/wga tracker` shows or hides it.

## Rares, loot swap and shopping lists

**Rare alert card.** When a rare, rare elite or treasure shows up, a card appears with its 3D model, where it is, and the loot WGA has seen it drop.
- The **Target** button targets the rare. It only works out of combat; that's a game rule.
- Click the card to point the arrow at the rare. Right-click dismisses it.
- Shift + right-click ignores that rare for good. `/wga rares unignore <name>` undoes it.
- `/wga rares test` shows a sample card.

**Keep list.** `/wga keep <shift-click item>` adds an item to your keep list or takes it off. Items your open quests need are kept automatically. Kept items are never auto-sold or offered for a swap.

**Bags-full loot swap.** When your bags are full and better loot is left behind, WGA offers to drop your cheapest bag item and loot it. "Cheapest" uses the AH price after the cut or the vendor price, whichever is higher. Only grey, white and green items are ever offered, and only after you click Swap.

**Shopping lists.** A panel opens beside the auction house. Type `Linen Cloth/20`, or shift-click an item into the box, to add it.
- Click an item to search for it. Right-click removes it.
- **Buy** gets the cheapest units of stackable goods, and you confirm the price first.
- **Search next** steps through the list.

Every module has an on/off switch in Settings.

### Efficient or Completionist

The Smart Guide has two styles, switched with the **E / C** button in the guide window header, in Settings, or with `/wga guide efficient` and `/wga guide all`.

- **Efficient** (the default) only suggests quests worth the time for levelling: within about 5 levels below to 3 above you, and no battleground, repeatable or hand-in-only quests (like cloth donations). Quests already in your log that have gone grey or are far too high move to the end of the route, marked "low value". Hover the E button to see what was skipped nearby and why.
- **Completionist** suggests every quest you can pick up, grey ones included.

Dungeon quests are tagged "dungeon" and can be switched off in Settings.

## Auto accept, turn in and rewards

Like Zygor: talk to a quest giver and WGA Companion picks the quest the guide wants, accepts it, and hands in finished quests. Quests the Efficient style would skip (cloth donations, battleground and off-level quests) are left alone; Completionist takes everything except repeatables.

For reward choices it takes a **real upgrade** when one is on offer: gear your class should wear (armor type, weapon skills, the right stats) that is at least 5 item levels better than what you have in that slot, or fills an empty slot. Otherwise it takes the reward **worth the most gold** (auction price after cut, or vendor price).

Hold **Shift** while talking to an NPC to do it by hand. Settings has switches for both; `/wga auto`, `/wga auto rewards`, `/wga auto upgrade <n>` from chat.

## Talking companion

A little guide character (Whirl, by default) sits on top of the guide window. Every time the step changes it explains, in plain words, what to do next, who to see, how far away it is and which way to go, and whether the quest is tough for your level. It also cheers on level-ups and turn-ins, and warns you about full bags, a nearly full quest log and rares nearby.

Turn on **Voice** in the speech bubble (or Settings, "Companion reads aloud") and it reads its lines out loud with the game's built-in text-to-speech. The voices are the ones installed on your computer; pick one with `/wga companion voices` and `/wga companion voice <n>`.

Click the portrait to hear the last line again, right-click to change its look. `/wga companion [on|off|voice|rate <n>|name <name>|look|say]`.

Everything is worked out inside the game from your quests and the quest database. WoW addons can't reach the internet, so this is not an online AI: it's a rule-based helper that follows the guide.

## Guide window and Smart Guide

The guide window is a small window, separate from the hub, that walks you through questing one step at a time. `/wga guide` shows or hides it.

- **Smart Guide** (the default) builds a route from your quest log, your level and where you're standing. It sends you to turn in finished quests, finish open ones, and pick up new quests nearby, in the order that means the least walking.
- **Step guides** (your recordings, or any guide you load from the hub) run in the same window. Use the S/G button in its header to switch between the two.

The current step shows a 3D model of the NPC or mob, what to do ("Talk to", "Kill", "Loot from", "Use"), where it is and how far away, and a checklist of objectives. The arrow points at it.
- Click a step under "Coming up" to make it the current step.
- The "-" button shrinks the window to just the current step.

## Dungeon journal

The hub's **Dungeons** page shows every dungeon as a card with its art, level range and number of quests. You can search by dungeon or boss name, and the button at top right switches between dungeons and raids. Open a dungeon to see three tabs:

- **Bosses:** each boss's portrait, a 3D model you can drag to turn, and its loot, with tooltips and prices. Shift-click an item to link it; ctrl-click to try it on. "Only loot my class can use" filters the list.
- **Map:** the dungeon map, with buttons for each floor and boss portraits pinned where each boss stands.
- **Quests:** the dungeon's quests and whether each is done, in your log, available, or locked behind an earlier quest or your level. Each quest lists its objectives, who starts it and where to turn it in, and has an arrow button that points to the quest giver.

**Entrance** points the arrow at the dungeon's door.

Art, bosses and loot come from the game's built-in Encounter Journal. Quests come from QuestieDB.

## Rare tracker

Every rare in the quest database (327 so far) shows on the world map at its spawn spots. If it wanders, faint dots mark the area it moves around in. The icon colour shows your progress:

- **Red:** you haven't seen it yet.
- **Pink:** you've seen it, or killed it but still miss some of its loot.
- **Green with a check:** you've killed it and have every green-or-better item it's known to drop.

Hover an icon for the rare's level, status, drops and chances. Click it to point the arrow there, or right-click to open the hub's Rares page.

The Rares page lists the rares in a zone, shows a map of their spawns, a 3D model and your progress, and the rare's drops with their chances.

Drop chances are learned from kills. Each time you loot a rare, WGA counts the kill and what dropped. Spawn data comes from QuestieDB.

## Quest navigation

With no guide loaded, the arrow points at your tracked quest (click one in the objective tracker), or the closest quest in your log. Left-click the arrow to cycle quests.

- Locations come from the bundled quest database first (NPC, object and item drop spawns for every original quest, from QuestieDB). Quests you can pick up show as "!" on the world map, and turn-ins as "?". Click any map icon to point the arrow at it.
- For content the database doesn't cover yet (most of Forever's new quests), WGA falls back to the game's own quest map data and to spots it learns: whenever you see a mob you still need, or an objective counts up, it saves where you are. Learned spots show as dots on the world map while the objective is open.
- Mobs you still need get a "!" over their nameplate. This is read from the game's own quest lines on the unit's tooltip.
- `/wga quest arrow | pins | available | marks` toggles each part, `/wga quest size 1.5` makes map icons bigger,, and `/wga quest why` shows where the arrow's location came from.

## Repo layout
| Path | What |
| --- | --- |
| `addon/WGACompanion` | The addon (Lua, interface 16001) |
| `addon/WGACompanion_Data` | Placeholder for the generated price data addon |
| `pricejob/build_prices.py` | Builds the price pack from the Battle.net API (standard library only) |
| `.github/workflows/prices.yml` | Runs the price job hourly and publishes the `prices-us` release |
| `.github/workflows/check.yml` | Lua syntax and .toc checks on every push |

## Price job setup
Add two repository secrets (Settings → Secrets and variables → Actions): `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET`, from a Battle.net developer client. Then run **Region prices** once from the Actions tab.

WoW Forever's auction endpoints (`dynamic-forever-us`, `/data/wow/ruleset/{id}/auctions/`) are undocumented and may change; the addon falls back to your own scans.

## Updating the quest database

`addon/WGACompanion/Data/QuestDB.lua` is generated, so don't edit it by hand:

```
git clone https://github.com/Questie/QuestieDB
git clone https://github.com/Questie/Questie
python3 tools/import_questie.py ../QuestieDB Forever ../Questie
```

## License and credits

WGA Companion is free software under the GNU General Public License v3.0 (see `LICENSE`).

Quest, NPC, object and item data comes from [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team and contributors, also GPL-3.0. WGA Companion is not affiliated with or endorsed by Questie.

The map objective icons in `addon/WGACompanion/Icons` are from [pfQuest](https://github.com/shagu/pfQuest) by Shagu, MIT licensed (see `Icons/MIT.txt`).
