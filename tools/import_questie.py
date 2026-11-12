#!/usr/bin/env python3
"""Convert QuestieDB's Forever data into WGA Companion's compact quest database.

QuestieDB (https://github.com/Questie/QuestieDB) is GPL-3.0 licensed, which is why
WGA Companion is GPL-3.0 too. The data files are Lua table literals; this script parses
them as text (it never runs any Lua) and writes addon/WGACompanion/Data/QuestDB.lua.

Usage:  python3 tools/import_questie.py /path/to/QuestieDB [flavor] [/path/to/Questie]
        flavor defaults to Forever. With a Questie checkout, holiday quests are flagged as
        events and unconditionally blacklisted quests (not in the game) are dropped.

Output (all coordinates are 0-100 on a uiMapID):
  CM.Data.QDB = {
    q = { [questID] = { name, reqLevel, questLevel, side, classMask, starts, ends, objectives,
                        preGroup, preSingle, exclusiveTo, nextInChain, flags, reqSkill, zoneOrSort } },
      side: "A", "H" or nil (both);  starts/ends: { npcs, objects };
      objectives: { {kind, id or {ids}, text}, ... }  kind: "n" npc, "o" object, "i" item, "k" kill credit
    n = { [npcID] = { name, { [uiMapID] = "x,y x,y ..." } } },
    o = { [objectID] = { name, { [uiMapID] = "..." } } },
    i = { [itemID] = { name, {npcIDs}, {objectIDs} } },
    d = { [dungeonAreaID] = { name, {alternative area IDs}, {uiMapID, x, y} entrance } },
    r = { [npcID] = { name, minLevel, maxLevel, rank (2 rare elite, 4 rare), { [uiMapID] = "x,y ..." } } },
    f = { [npcID] = { name, side ("A", "H" or "AH"), { [uiMapID] = "x,y ..." } } },  flight masters
    k = { [npcID] = { name, side, { [uiMapID] = "x,y ..." } } },  innkeepers (where a hearthstone takes you)
  }
  zoneOrSort: the AreaTable zone a quest belongs to (a dungeon's area ID for dungeon quests).
"""
import os
import re
import sys

MAX_SPAWNS_PER_MAP = 24          # keep the file small; evenly sampled
ALLIANCE_MASK = 1 | 4 | 8 | 64   # Human, Dwarf, Night Elf, Gnome
HORDE_MASK = 2 | 16 | 32 | 128   # Orc, Undead, Tauren, Troll
# Forever's extra race bits seen in requiredRaces (2^32 with Alliance, 2^33 with Horde)
ALLIANCE_MASK |= 1 << 32
HORDE_MASK |= 1 << 33

TOKEN = re.compile(r'''
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*)
  | (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
  | (?P<num>-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z_0-9]*)
  | (?P<sym>[{}\[\]=,;])
''', re.S | re.X)

ESC = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}


def tokens(text):
    pos, n = 0, len(text)
    out = []
    while pos < n:
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"cannot parse near: {text[pos:pos + 60]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind == "ws":
            continue
        v = m.group(kind)
        if kind == "str":
            body = v[1:-1]
            v = re.sub(r"\\(.)", lambda e: ESC.get(e.group(1), e.group(1)), body)
            out.append(("s", v))
        elif kind == "num":
            out.append(("v", int(v, 16) if v.lower().startswith(("0x", "-0x")) else (float(v) if any(c in v for c in ".eE") else int(v))))
        elif kind == "name":
            if v in ("nil", "true", "false"):
                out.append(("v", {"nil": None, "true": True, "false": False}[v]))
            else:
                out.append(("n", v))
        else:
            out.append(("y", v))
    return out


class Parser:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def take(self, sym=None):
        tok = self.t[self.i]
        if sym is not None and tok != ("y", sym):
            raise ValueError(f"expected {sym}, got {tok} at token {self.i}")
        self.i += 1
        return tok

    def value(self):
        k, v = self.peek()
        if (k, v) == ("y", "{"):
            return self.table()
        self.i += 1
        if k in ("s", "v"):
            return v
        raise ValueError(f"unexpected token {k} {v}")

    def table(self):
        """Lua table -> dict of key -> value (positional keys start at 1, nils kept out)."""
        self.take("{")
        out, pos = {}, 1
        while self.peek() != ("y", "}"):
            k, v = self.peek()
            if (k, v) == ("y", "["):
                self.take("[")
                key = self.value()
                self.take("]")
                self.take("=")
                val = self.value()
                if val is not None:
                    out[key] = val
            elif k == "n" and self.t[self.i + 1] == ("y", "="):
                self.i += 2
                val = self.value()
                if val is not None:
                    out[v] = val
            else:
                val = self.value()
                if val is not None:
                    out[pos] = val
                pos += 1
            if self.peek() in (("y", ","), ("y", ";")):
                self.i += 1
        self.take("}")
        return out


def lua_block(path, var):
    text = open(path, encoding="utf-8").read()
    m = re.search(re.escape(var) + r"\s*=\s*\[\[\s*return\s*(\{.*?\})\s*\]\]", text, re.S)
    if not m:
        raise SystemExit(f"{var} not found in {path}")
    return Parser(tokens(m.group(1))).table()


def seq(t):
    """dict with 1..n keys -> list (ignores holes)"""
    if not isinstance(t, dict):
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


def ids(t):
    return [x for x in seq(t) if isinstance(x, int)]


def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 2))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list):
        # trailing nils trimmed; inner nils kept positionally
        while v and v[-1] is None:
            v = v[:-1]
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(f"[{lua(k)}]={lua(x)}" for k, x in sorted(v.items(), key=lambda kv: str(kv[0]))) + "}"
    raise TypeError(type(v))


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    root = sys.argv[1]
    flavor = sys.argv[2] if len(sys.argv) > 2 else "Forever"
    low = flavor[0].lower() + flavor[1:]
    d = os.path.join(root, "data", flavor)
    quests = lua_block(os.path.join(d, f"{low}QuestDB.lua"), "QuestieDB.questData")
    npcs = lua_block(os.path.join(d, f"{low}NpcDB.lua"), "QuestieDB.npcData")
    objects = lua_block(os.path.join(d, f"{low}ObjectDB.lua"), "QuestieDB.objectData")
    items = lua_block(os.path.join(d, f"{low}ItemDB.lua"), "QuestieDB.itemData")
    zf = os.path.join(root, "support", flavor, "Zones", "areaIdToUiMapId.lua")
    area = lua_block(zf, "ZoneDB.private.areaIdToUiMapId")
    area.update(lua_block(zf, "ZoneDB.private.areaIdToUiMapIdOverride"))
    events, blacklist = set(), set()
    if len(sys.argv) > 3:
        corr = os.path.join(sys.argv[3], "Database", "Corrections")
        hol = os.path.join(corr, "Holidays", "quests")
        for fn in os.listdir(hol):
            events.update(int(x) for x in re.findall(r'eventQuests,\s*\{\s*"[^"]*",\s*(\d+)', open(os.path.join(hol, fn), encoding="utf-8").read()))
        bl = open(os.path.join(corr, "QuestieQuestBlacklist.lua"), encoding="utf-8").read()
        blacklist.update(int(x) for x in re.findall(r"\[(\d+)\]\s*=\s*true\b", bl))
        print(f"{len(events)} holiday quests flagged, {len(blacklist)} blacklisted quests dropped")
    print(f"parsed {len(quests)} quests, {len(npcs)} npcs, {len(objects)} objects, {len(items)} items, {len(area)} zones")

    need_n, need_o, need_i = set(), set(), set()
    out_q = {}
    for qid, q in quests.items():
        if not isinstance(q, dict) or not isinstance(qid, int) or qid in blacklist:
            continue
        races = q.get(6) or 0
        side = None
        if races:
            a, h = bool(races & ALLIANCE_MASK), bool(races & HORDE_MASK)
            side = "A" if a and not h else ("H" if h and not a else None)
        st, en = q.get(2) or {}, q.get(3) or {}
        starts = [ids(st.get(1)), ids(st.get(2))]
        ends = [ids(en.get(1)), ids(en.get(2))]
        need_n.update(starts[0] + ends[0])
        need_o.update(starts[1] + ends[1])
        objs = []
        ob = q.get(10) or {}
        for e in seq(ob.get(1)):
            if isinstance(e, dict) and isinstance(e.get(1), int):
                objs.append(["n", e[1], e.get(2)]); need_n.add(e[1])
        for e in seq(ob.get(2)):
            if isinstance(e, dict) and isinstance(e.get(1), int):
                objs.append(["o", e[1], e.get(2)]); need_o.add(e[1])
        for e in seq(ob.get(3)):
            if isinstance(e, dict) and isinstance(e.get(1), int):
                objs.append(["i", e[1], e.get(2)]); need_i.add(e[1])
        for e in seq(ob.get(5)):
            if isinstance(e, dict):
                group = ids(e.get(1))
                if group:
                    objs.append(["k", group, e.get(3)]); need_n.update(group)
        for it in ids(q.get(21)):  # required source items: where to get them
            need_i.add(it)
        skill = q.get(18)
        out_q[qid] = [q.get(1), q.get(4), q.get(5), side, q.get(7) or None, starts, ends, objs,
                      ids(q.get(12)) or None, ids(q.get(13)) or None, ids(q.get(16)) or None,
                      q.get(22) or None, ((q.get(24) or 0) | (2 if qid in events else 0)) or None, seq(skill) or None,
                      q.get(17) or None]

    out_i = {}
    for iid in sorted(need_i):
        it = items.get(iid)
        if not isinstance(it, dict):
            continue
        drops_n, drops_o = ids(it.get(2)), ids(it.get(3))
        need_n.update(drops_n)
        need_o.update(drops_o)
        out_i[iid] = [it.get(1), drops_n or None, drops_o or None]

    def spawns(raw):
        out = {}
        for zone, pts in (raw or {}).items():
            m = area.get(zone, zone)
            if not m:
                continue
            pts = [p for p in seq(pts) if isinstance(p, dict) and isinstance(p.get(1), (int, float)) and p[1] >= 0]
            if not pts:
                continue
            if len(pts) > MAX_SPAWNS_PER_MAP:
                step = len(pts) / MAX_SPAWNS_PER_MAP
                pts = [pts[int(i * step)] for i in range(MAX_SPAWNS_PER_MAP)]
            packed = " ".join(f"{round(p[1], 1):g},{round(p[2], 1):g}" for p in pts)
            out[m] = (out[m] + " " + packed) if m in out else packed
        return out or None

    out_n = {}
    for nid in sorted(need_n):
        n = npcs.get(nid)
        if isinstance(n, dict):
            out_n[nid] = [n.get(1), spawns(n.get(7))]
    out_o = {}
    for oid in sorted(need_o):
        o = objects.get(oid)
        if isinstance(o, dict):
            out_o[oid] = [o.get(1), spawns(o.get(4))]

    # Dungeons: name, alternative area IDs (quests may use those) and the entrance on the outdoor map
    out_d = {}
    df = os.path.join(root, "support", flavor, "Zones", "dungeons.lua")
    if os.path.exists(df):
        m = re.search(r"local dungeons\s*=\s*(\{.*?\n\})", open(df, encoding="utf-8").read(), re.S)
        body = m.group(1) if m else "{}"
        # faction-dependent entrances: keep the Alliance one (both sit at the same dungeon)
        body = re.sub(r"\(isHorde and (\{[^{}]*\})\) or (\{[^{}]*\})", r"\2", body)
        dungeons = Parser(tokens(body)).table()
        for did, e in dungeons.items():
            if not isinstance(e, dict) or not isinstance(did, int):
                continue
            ent = None
            for loc in seq(e.get(4)):
                um = area.get(loc.get(1)) if isinstance(loc, dict) else None
                if um:
                    ent = [um, loc.get(2), loc.get(3)]
                    break
            out_d[did] = [e.get(1), ids(e.get(2)) or None, ent]
        print(f"{len(out_d)} dungeons")

    # Rares: every NPC ranked rare or rare elite that has a known spawn
    out_r = {}
    for nid, n in npcs.items():
        if isinstance(n, dict) and n.get(6) in (2, 4):
            sp = spawns(n.get(7))
            if sp:
                out_r[nid] = [n.get(1), n.get(4), n.get(5), n.get(6), sp]
    print(f"{len(out_r)} rares")

    # Flight masters (npcFlags bit 8 in Forever/Classic), so the guide can send you to ones you lack
    FLIGHT_MASTER = 8
    out_f = {}
    for nid, n in npcs.items():
        if isinstance(n, dict) and isinstance(n.get(15), int) and n.get(15) & FLIGHT_MASTER and n.get(13):
            sp = spawns(n.get(7))
            if sp:
                out_f[nid] = [n.get(1), n.get(13), sp]
    print(f"{len(out_f)} flight masters")

    out_k = {}
    for nid, n in npcs.items():
        if isinstance(n, dict) and n.get(14) == "Innkeeper" and n.get(13):
            sp = spawns(n.get(7))
            if sp:
                out_k[nid] = [n.get(1), n.get(13), sp]
    print(f"{len(out_k)} innkeepers")

    dest = os.path.join(os.path.dirname(__file__), "..", "addon", "WGACompanion", "Data", "QuestDB.lua")
    with open(dest, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- GENERATED by tools/import_questie.py from QuestieDB " + flavor + " data. Do not edit by hand.\n")
        f.write("-- Quest, NPC, object and item data (c) the Questie team and contributors, GPL-3.0.\n")
        f.write("-- https://github.com/Questie/QuestieDB\n")
        f.write("local _, CM = ...\nCM.Data = CM.Data or {}\nCM.Data.QDB = { q = {\n")
        for qid in sorted(out_q):
            f.write(f"[{qid}]={lua(out_q[qid])},\n")
        f.write("}, n = {\n")
        for k in sorted(out_n):
            f.write(f"[{k}]={lua(out_n[k])},\n")
        f.write("}, o = {\n")
        for k in sorted(out_o):
            f.write(f"[{k}]={lua(out_o[k])},\n")
        f.write("}, i = {\n")
        for k in sorted(out_i):
            f.write(f"[{k}]={lua(out_i[k])},\n")
        f.write("}, r = {\n")
        for k in sorted(out_r):
            f.write(f"[{k}]={lua(out_r[k])},\n")
        f.write("}, f = {\n")
        for k in sorted(out_f):
            f.write(f"[{k}]={lua(out_f[k])},\n")
        f.write("}, k = {\n")
        for k in sorted(out_k):
            f.write(f"[{k}]={lua(out_k[k])},\n")
        f.write("}, d = {\n")
        for k in sorted(out_d):
            f.write(f"[{k}]={lua(out_d[k])},\n")
        f.write("} }\n")
    print(f"wrote {dest}: {len(out_q)} quests, {len(out_n)} npcs, {len(out_o)} objects, {len(out_i)} items, "
          f"{os.path.getsize(dest) // 1024} KB")


if __name__ == "__main__":
    main()
