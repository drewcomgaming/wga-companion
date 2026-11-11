# WGA Companion

The official WoW Forever addon of **Whirlwind Gaming Academy**: step-by-step quest guides with a waypoint arrow, auction pricing, crafting profit, vendor flips, rare and treasure alerts, and leveling, profession and dungeon references.

## Install
1. Download this repo's `addon/WGACompanion` folder (or a release zip) into `World of Warcraft\_forever_\Interface\AddOns\`.
2. For region-wide prices, download **WGACompanion_Data.zip** from the [prices-us release](../../releases/tag/prices-us) and unzip it next to it. It updates hourly; replace the folder and `/reload` to refresh.
3. In game: `/wga`.

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
