#!/usr/bin/env python3
"""Build the WGA Companion region price pack from the Battle.net API.

WoW Forever's auction data lives in the (undocumented) `dynamic-forever-{region}`
namespace under /data/wow/ruleset/{id}/auctions/. Every ruleset returns the same
houses, so we read them through one ruleset only.

Env:
  BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET  (required)
  WGA_REGION      us | eu | kr | tw          (default us)
  WGA_RULESET_ID  ruleset to read through    (default: first one the index lists)
  WGA_OUT         output folder for the data addon (default dist/WGACompanion_Data)

Output: Prices.lua defining WGACompanionData plus a WGACompanion_Data.toc.
Only the Python standard library is used.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REGION = os.environ.get("WGA_REGION", "us").lower()
API = f"https://{REGION}.api.blizzard.com"
NAMESPACE = f"dynamic-forever-{REGION}"
OUT = os.environ.get("WGA_OUT", "dist/WGACompanion_Data")
INTERFACE = "16001"


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def token():
    cid = os.environ.get("BLIZZARD_CLIENT_ID")
    secret = os.environ.get("BLIZZARD_CLIENT_SECRET")
    if not cid or not secret:
        sys.exit("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET are not set (add them as repository secrets).")
    req = urllib.request.Request(
        "https://oauth.battle.net/token",
        data=b"grant_type=client_credentials",
        headers={"Authorization": "Basic " + base64.b64encode(f"{cid}:{secret}".encode()).decode(),
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def get(path, tok, tries=3):
    url = API + path + ("&" if "?" in path else "?") + urllib.parse.urlencode({"namespace": NAMESPACE, "locale": "en_US"})
    for attempt in range(tries):
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}", "Accept-Encoding": "identity"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (404, 403):
                log(f"  {e.code} for {path}")
                return None
            log(f"  HTTP {e.code} for {path}, retrying")
        except (urllib.error.URLError, TimeoutError) as e:
            log(f"  network error {e} for {path}, retrying")
        time.sleep(2 * (attempt + 1))
    return None


def find_ruleset(tok):
    rid = os.environ.get("WGA_RULESET_ID")
    if rid:
        return int(rid)
    for path in ("/data/wow/ruleset/index", "/data/wow/ruleset/"):
        idx = get(path, tok)
        if idx:
            log("ruleset index:", json.dumps(idx)[:2000])
            for key in ("rulesets", "results"):
                for r in idx.get(key, []) or []:
                    rid = r.get("id") or (r.get("data") or {}).get("id")
                    if rid:
                        return int(rid)
    sys.exit("Could not discover a ruleset id. Set WGA_RULESET_ID (see the job log for the index response).")


def summarize(entries):
    """entries: list of (unit_price, quantity). Returns (min, market, total_qty).
    market = price at the 15th percentile of listed quantity (cheapest 15% of supply),
    which ignores single outlier listings the way most price addons do."""
    if not entries:
        return None
    entries.sort()
    total = sum(q for _, q in entries)
    cutoff = max(1, total * 0.15)
    acc, spent, n = 0, 0, 0
    for price, q in entries:
        take = min(q, cutoff - acc)
        if take <= 0:
            break
        spent += price * take
        acc += take
    market = int(spent / acc) if acc else entries[0][0]
    return entries[0][0], market, total


def collect(data, commodities):
    items = {}
    for a in (data or {}).get("auctions", []):
        item = a.get("item") or {}
        iid = item.get("id")
        q = a.get("quantity") or 1
        if commodities:
            price = a.get("unit_price")
        else:
            # only plain items: random-suffix / bonus variants would skew a per-itemID price
            if item.get("bonus_lists") or item.get("modifiers") or item.get("rand"):
                continue
            buyout = a.get("buyout")
            price = buyout / q if buyout else None
        if iid and price:
            items.setdefault(iid, []).append((int(price), int(q)))
    return items


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def main():
    tok = token()
    ruleset = find_ruleset(tok)
    log(f"region={REGION} ruleset={ruleset}")
    index = get(f"/data/wow/ruleset/{ruleset}/auctions/", tok)  # trailing slash is required
    if not index:
        sys.exit("Auction index unavailable (Blizzard may have changed the Forever endpoints).")
    log("auction index:", json.dumps(index)[:3000])
    houses_meta = index.get("auctions") or index.get("auction_houses") or []

    out_houses = []
    for h in houses_meta:
        hid = h.get("id") or (h.get("key", {}).get("href", "").rstrip("/").split("/")[-1].split("?")[0])
        name = h.get("name") or ""
        if isinstance(name, dict):
            name = name.get("en_US") or next(iter(name.values()), "")
        try:
            hid = int(hid)
        except (TypeError, ValueError):
            continue
        items = collect(get(f"/data/wow/ruleset/{ruleset}/auctions/{hid}", tok), False)
        for iid, lst in collect(get(f"/data/wow/ruleset/{ruleset}/auctions/{hid}/commodities", tok), True).items():
            items.setdefault(iid, []).extend(lst)
        prices = {iid: summarize(lst) for iid, lst in items.items()}
        prices = {k: v for k, v in prices.items() if v}
        log(f"house {hid} '{name}': {len(prices)} items")
        if prices:
            out_houses.append((hid, name, prices))

    if not out_houses:
        sys.exit("No auction data returned for any house.")

    now = int(time.time())
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "Prices.lua"), "w", encoding="utf-8") as f:
        f.write(f"-- Generated by the WGA Companion price job. Region {REGION}, {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime(now))}.\n")
        f.write("-- Each item: \"min,market,quantity\" in copper per unit.\n")
        f.write(f"WGACompanionData = {{ generated = {now}, region = {lua_str(REGION)}, ruleset = {ruleset}, houses = {{\n")
        for hid, name, prices in out_houses:
            f.write(f"  [{hid}] = {{ name = {lua_str(name)}, items = {{\n")
            for iid in sorted(prices):
                mn, mk, q = prices[iid]
                f.write(f'    [{iid}]="{mn},{mk},{q}",\n')
            f.write("  } },\n")
        f.write("} }\n")
    with open(os.path.join(OUT, "WGACompanion_Data.toc"), "w", encoding="utf-8") as f:
        f.write(f"## Interface: {INTERFACE}\n## Title: |cffffd100WGA Companion|r Data\n"
                f"## Notes: Region auction prices for WGA Companion ({REGION}, {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime(now))}).\n"
                f"## Author: Whirlwind Gaming Academy\n## Version: {now}\n\nPrices.lua\n")
    summary = {"generated": now, "region": REGION, "ruleset": ruleset,
               "houses": [{"id": h, "name": n, "items": len(p)} for h, n, p in out_houses]}
    with open(os.path.join(os.path.dirname(OUT) or ".", "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    log(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
