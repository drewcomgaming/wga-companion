# WGA Companion

The official WoW Forever addon of **Whirlwind Gaming Academy**: step-by-step quest guides with a waypoint arrow, auction pricing, crafting profit, vendor flips, rare and treasure alerts, and leveling, profession and dungeon references.

## Install
1. Download this repo's `addon/WGACompanion` folder (or a release zip) into `World of Warcraft\_forever_\Interface\AddOns\`.
2. For region-wide prices, download **WGACompanion_Data.zip** from the [prices-us release](../../releases/tag/prices-us) and unzip it next to it. It updates hourly; replace the folder and `/reload` to refresh.
3. In game: `/wga`.

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
