# WGA Companion (WoW Forever addon)

The official companion addon of Whirlwind Gaming Academy.

Quest guides with a waypoint arrow, plus the economy tools Forever doesn't have yet. Version 0.2.0.
Built for **WoW: Forever** (interface 16001, modern addon API). It will not load on Classic Era.

## Install
Copy the `WGA Companion` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart or `/reload`.
If the AddOns list says "Out of date", tick "Load out of date AddOns" and report the client's interface number.

## Features
- **Step guides (Zygor-style)**: step window that auto-advances on quest accept / objectives done / turn-in / level / items; skip and back buttons; chains to the next guide; per-character progress. `/wga guide`, `/wga guides`.
- **Waypoint arrow**: points to the current step (or a rare), shows distance in yards, colour-coded, and drops the built-in map pin. Right-click to clear, drag to move. `/wga arrow`.
- **Quest location harvester**: remembers where every quest is picked up, completed and handed in (account-wide); guide steps without coordinates use it.
- **Route recorder**: `/wga record start`, play, `/wga record stop`, then `load` to follow it or `export` to share it as a guide file.
- **Quest reward advisor**: marks the reward choice worth the most gold.
- **Auction scanner**: `CM Scan` button on the AH (full scan, 15-minute cooldown); normal browsing and commodity searches are recorded too. Market value = median of daily lows (14 days).
- **Tooltips**: AH min, market, vendor buy, and an "Auction it" / "Vendor it" verdict after the 5% cut.
- **Crafting profit**: `CM Profit` button on the profession window; cost, sale value and profit per recipe.
- **Vendors**: learns vendor prices, sells greys, lists vendor-to-AH flips. `/wga bags` for what to auction vs vendor.
- **Rare & treasure finder**: alerts from minimap vignettes, nameplates, mouseover and target, with coords and arrow. `/wga watch <npc>`.
- **Reference**: Forever's new zones and 9 new dungeons, Classic zones/dungeons, profession routes, gold tips.

## Commands
`/wga` window · `/wga guide [name]` · `/wga guides` · `/wga reset` · `/wga arrow` · `/wga record start|stop|load|export` · `/wga scan` · `/wga price <item>` · `/wga bags` · `/wga watch|unwatch <npc>` · `/wga rares` · `/wga tooltip` · `/wga junk`

## Limits
- Addons can't reach the internet: prices come from your scans, guides/data are bundled or recorded.
- Combat-time values that Forever hides from addons are skipped.
