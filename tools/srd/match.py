"""Pair the spells of an Italian SRD with the English 5e-database entries.

Spells are compared on level, school, components, concentration, ritual,
classes, range and the dice that appear in the text; the best scores win.
The few pairs this gets wrong are fixed in overrides-<edition>.json.
"""
import re
from collections import Counter

SCHOOL = {"abiurazione": "abjuration", "ammaliamento": "enchantment", "divinazione": "divination",
          "evocazione": "conjuration", "illusione": "illusion", "invocazione": "evocation",
          "necromanzia": "necromancy", "trasmutazione": "transmutation"}
CLASSES = {"bardo": "bard", "chierico": "cleric", "druido": "druid", "mago": "wizard",
           "paladino": "paladin", "ranger": "ranger", "stregone": "sorcerer", "warlock": "warlock"}


def range_key(r):
    r = r.lower()
    for k, v in (("incantatore", "self"), ("personale", "self"), ("contatto", "touch"), ("illimitat", "unlimited"),
                 ("vista", "sight"), ("speciale", "special"), ("self", "self"), ("touch", "touch"),
                 ("unlimited", "unlimited"), ("sight", "sight"), ("special", "special")):
        if r.startswith(k):
            return v
    m = re.match(r"([\d.,]+)\s*(metri|chilometri|km|feet|foot|miles?)", r)
    if not m:
        return r
    u = m.group(2)
    n = float(m.group(1).replace(".", "").replace(",", ".")) if u == "metri" else float(m.group(1).replace(",", "."))
    if u == "metri":
        return round(n / 0.3)
    if u in ("chilometri", "km"):
        return round(n / 1.5 * 5280)
    if u.startswith("mile"):
        return round(n * 5280)
    return round(n)


def para_text(p):
    return p if isinstance(p, str) else p["row"]


def it_level_school(s):
    h = s["head"].lower()
    m = re.match(r"trucchetto di (\w+)", h)
    if m:
        return 0, m.group(1)
    m = re.match(r"(\w+) di (\d)", h)
    return int(m.group(2)), m.group(1)


def it_classes(s, lists):
    m = re.search(r"\(([^)]*)\)\s*$", s["head"])
    if m and any(c.strip() in CLASSES for c in m.group(1).split(",")):
        return {CLASSES[c.strip()] for c in m.group(1).split(",") if c.strip() in CLASSES}
    return set(lists.get(s["name"], []))


def it_info(s, lists):
    lvl, school = it_level_school(s)
    text = " ".join(para_text(p) for p in s["paras"])
    comp = set(re.findall(r"\b[VSM]\b", s["fields"]["comp"].split("(")[0]))
    conc = "concentrazione" in s["fields"]["dur"].lower()
    rit = "rituale" in s["head"].lower() or "rituale" in s["fields"]["time"].lower()
    return (lvl, SCHOOL[school], comp, conc, rit, Counter(re.findall(r"\d+d\d+", text)),
            it_classes(s, lists), range_key(s["fields"]["range"]))


def en_text(s):
    text = " ".join(s["desc"]) if isinstance(s.get("desc"), list) else s.get("description", "")
    hl = s.get("higher_level") or ""
    return text + " " + (" ".join(hl) if isinstance(hl, list) else hl)


def en_info(s):
    return (s["level"], s["school"]["index"], set(s["components"]), s["concentration"], s["ritual"],
            Counter(re.findall(r"\d+d\d+", en_text(s))), {c["index"] for c in s["classes"]}, range_key(s["range"]))


def score(a, b):
    if a[0] != b[0] or a[1] != b[1]:
        return -1
    sc = (a[2] == b[2]) * 3 + (a[3] == b[3]) * 3 + (a[4] == b[4]) * 2
    inter = sum((a[5] & b[5]).values())
    union = sum((a[5] | b[5]).values())
    sc += 4 * (inter / union if union else 1)
    sc += 6 * (len(a[6] & b[6]) / len(a[6] | b[6]) if a[6] | b[6] else 1)
    sc += 4 * (a[7] == b[7])
    return sc


def pair(it, en, overrides, lists):
    """Return {italian name: english index}; stops if something is left unpaired."""
    pairs = dict(overrides)
    used = set(pairs.values())
    infos = {e["index"]: en_info(e) for e in en}
    cand = []
    for s in it:
        if s["name"] in pairs:
            continue
        a = it_info(s, lists)
        for idx, b in infos.items():
            if idx not in used:
                sc = score(a, b)
                if sc >= 0:
                    cand.append((sc, s["name"], idx))
    cand.sort(reverse=True)
    for sc, name, idx in cand:
        if name not in pairs and idx not in used:
            pairs[name] = idx
            used.add(idx)
    missing_it = [s["name"] for s in it if s["name"] not in pairs]
    missing_en = [e["index"] for e in en if e["index"] not in used]
    if missing_it or missing_en:
        raise SystemExit(f"unpaired: {missing_it} / {missing_en} - add them to the overrides")
    return pairs
