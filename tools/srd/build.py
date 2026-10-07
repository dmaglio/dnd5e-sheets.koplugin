"""Build the spell lists in spells/ from the System Reference Documents.

    python tools/srd/build.py <work dir>

Sources (all CC-BY-4.0, downloaded into <work dir> if missing):
- English: the SRD 5.1 and 5.2.1 spells as JSON from 5e-bits/5e-database
- Italian: the official translations of SRD 5.1 and 5.2.1 (PDF)

The Italian spells are read from the PDFs and paired with the English ones,
so that both languages share the same spell ids, classes and flags.
Needs PyMuPDF (pip install pymupdf) and pdftotext (poppler).
"""
import json
import os
import re
import subprocess
import sys
import unicodedata
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pymupdf  # noqa: E402

from classes_it51 import class_lists  # noqa: E402
from extract_it import extract  # noqa: E402
from match import pair  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "spells")

EN_JSON = "https://raw.githubusercontent.com/5e-bits/5e-database/main/src/{ed}/en/5e-SRD-Spells.json"
IT_PDF = {
    "2014": "https://media.dndbeyond.com/compendium-images/srd/5.1/SRD_CC_v5.1_IT.pdf",
    "2024": "https://media.dndbeyond.com/compendium-images/srd/5.2/IT_SRD_CC_v5.2.1.pdf",
}
SOURCES = {
    ("2014", "en"): "System Reference Document 5.1 by Wizards of the Coast LLC, "
                    "via 5e-bits/5e-database. CC-BY-4.0.",
    ("2024", "en"): "System Reference Document 5.2.1 by Wizards of the Coast LLC, "
                    "via 5e-bits/5e-database. CC-BY-4.0.",
    ("2014", "it"): "System Reference Document 5.1 (traduzione italiana) di Wizards of the Coast LLC. CC-BY-4.0.",
    ("2024", "it"): "System Reference Document 5.2.1 (traduzione italiana) di Wizards of the Coast LLC. CC-BY-4.0.",
}
HIGHER = {"2014": "At Higher Levels.", "2024": "Using a Higher-Level Spell Slot."}


def fetch(url, path):
    if not os.path.exists(path):
        print("downloading", url)
        urllib.request.urlretrieve(url, path)
    return path


def sort_key(name):
    return "".join(c for c in unicodedata.normalize("NFD", name.lower()) if not unicodedata.combining(c))


def md_clean(text):
    """5e-database marks labels as ***Label.***: keep them as **Label.**"""
    return re.sub(r"\*\*\*([^*]+)\*\*\*", r"**\1**", text).strip()


def join_paras(paras):
    """The text format read by the plugin: paragraphs separated by a blank line,
    rows of a table (cells separated by " | ") by a newline; "## " starts a
    sub-heading, **bold** and *italic* inside a paragraph."""
    out = ""
    prev_row = False
    for p in paras:
        is_row = isinstance(p, dict)
        text = p["row"] if is_row else p
        if not text:
            continue
        if out:
            out += "\n" if (is_row and prev_row) else "\n\n"
        out += text
        prev_row = is_row
    return out


def en_paras(s, ed):
    if "desc" in s:
        lines = s["desc"]
    else:
        lines = s.get("description", "").split("\n")
    paras = []
    for l in lines:
        l = md_clean(l)
        if not l:
            continue
        if l.startswith("|"):
            if re.fullmatch(r"[|\-: ]+", l):
                continue  # markdown table separator
            paras.append({"row": " | ".join(c.strip() for c in l.strip("|").split("|"))})
        else:
            paras.append(l)
    hl = s.get("higher_level")
    if hl:
        hl = hl if isinstance(hl, list) else [hl]
        prefix = "Cantrip Upgrade." if ed == "2024" and s["level"] == 0 else HIGHER[ed]
        first = True
        for h in hl:
            h = md_clean(h)
            if h:
                if first:
                    h = "**" + prefix + "** " + h
                paras.append(h)
                first = False
    return paras


def en_entry(s, ed):
    return {
        "id": s["index"],
        "name": s["name"],
        "level": s["level"],
        "school": s["school"]["name"],
        "classes": sorted(c["index"] for c in s["classes"]),
        "time": s["casting_time"],
        "range": s["range"],
        "comp": ", ".join(s["components"]),
        "material": (s.get("material") or "").strip(),
        "duration": s["duration"],
        "conc": s["concentration"],
        "ritual": s["ritual"],
        "text": join_paras(en_paras(s, ed)),
    }


def it_entry(s, en):
    head = s["head"]
    school = re.match(r"(?:Trucchetto di )?(\w+)", head).group(1)
    comp = s["fields"]["comp"]
    material = ""
    m = re.match(r"^(.*?)\s*\((.*)\)\s*$", comp)
    if m:
        comp, material = m.group(1), m.group(2)
    return {
        "id": en["id"],
        "name": s["name"],
        "level": en["level"],
        "school": school[0].upper() + school[1:],
        "classes": en["classes"],
        "time": s["fields"]["time"],
        "range": s["fields"]["range"],
        "comp": comp.strip(),
        "material": material.strip(),
        "duration": s["fields"]["dur"],
        "conc": en["conc"],
        "ritual": en["ritual"],
        "text": join_paras(s["paras"]),
    }


# Errors in the official Italian PDFs, fixed after extraction. Each fix must
# change the text, so that a new edition of the PDF that no longer needs it
# stops the build instead of being silently skipped.
def _move_flood_paragraph(text):
    """Controllare acqua: the end of "Inondazione" sits between "Gorgo" and "Inondazione"."""
    paras = text.split("\n\n")
    paras = [p for p in paras if not p.startswith("Il livello dell'acqua rimane elevato")]
    i = next(i for i, p in enumerate(paras) if p.startswith("**Inondazione.**"))
    paras.insert(i + 1, "Il livello dell'acqua rimane elevato finché l'incantesimo non termina o finché "
                 "l'incantatore non sceglie un effetto diverso. Se questo effetto ha prodotto un'onda, "
                 "l'onda si ripete all'inizio del turno successivo dell'incantatore fintanto che "
                 "l'effetto di inondazione permane.")
    return "\n\n".join(paras)


def _ally_sentence(text):
    """"...quando l'incantesimo termina ed è un alleato per il personaggio...":
    the PDF breaks this sentence in two paragraphs (in Insetto gigante with a
    stray full stop too)."""
    return re.sub(r"termina\.?(?:\n\n| )ed è un alleato per il personaggio",
                  "termina ed è un alleato per il personaggio", text, count=1)


def _insect_ally(text):
    """Insetto gigante: the sentence after "...l'incantesimo termina." lost its beginning."""
    return re.sub(r"termina\.?(?:\n\n| )ed è un alleato per il personaggio e i suoi alleati\.",
                  "termina. La creatura diventa un alleato per l'incantatore e i suoi alleati.", text, count=1)


def _elemental_slot(text):
    """Evoca elementale is a 5th level spell: the damage grows above the 5th, not the 4th."""
    return text.replace("per ogni slot di livello superiore al 4º.", "per ogni slot di livello superiore al 5º.")


TEXT_FIXES = {
    ("2024", "it"): {
        "conjure-elemental": _elemental_slot,
        "control-water": _move_flood_paragraph,
        "giant-insect": _insect_ally,
        "summon-dragon": _ally_sentence,
    },
}


def apply_fixes(entries, ed, lang):
    fixes = dict(TEXT_FIXES.get((ed, lang), {}))
    for e in entries:
        fix = fixes.pop(e["id"], None)
        if fix:
            fixed = fix(e["text"])
            if fixed == e["text"]:
                raise SystemExit(f"text fix for {e['id']} ({ed} {lang}) changed nothing")
            e["text"] = fixed
    if fixes:
        raise SystemExit(f"text fixes for missing spells: {list(fixes)}")
    return entries


def lua_str(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, list):
        return "{" + ",".join(lua_value(x) for x in v) + "}"
    return lua_str(v)


FIELDS = ("id", "name", "level", "school", "classes", "time", "range", "comp", "material",
          "duration", "conc", "ritual", "text")


def write_lua(path, source, entries):
    entries = sorted(entries, key=lambda e: sort_key(e["name"]))
    with open(path, "w", encoding="utf-8") as f:
        f.write("-- Generated by tools/srd/build.py: do not edit.\n")
        f.write("-- " + source + "\n")
        f.write("return {\n")
        for e in entries:
            parts = []
            for k in FIELDS:
                v = e[k]
                if v in (False, "") and k not in ("level",):
                    continue
                parts.append(f"{k}={lua_value(v)}")
            f.write("{" + ",".join(parts) + "},\n")
        f.write("}\n")
    print(f"{path}: {len(entries)} spells, {os.path.getsize(path) // 1024} KiB")


def spell_pages(pdf):
    doc = pymupdf.open(pdf)
    pages = [i for i, p in enumerate(doc) if "Tempo di lancio:" in p.get_text()]
    return pages[0], min(pages[-1] + 1, len(doc) - 1)


def main(work):
    os.makedirs(work, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for ed in ("2014", "2024"):
        en_raw = json.load(open(fetch(EN_JSON.format(ed=ed), os.path.join(work, f"spells-{ed}-en.json"))))
        en = {s["index"]: en_entry(s, ed) for s in en_raw}
        write_lua(os.path.join(OUT, f"{ed}_en.lua"), SOURCES[(ed, "en")], en.values())

        pdf = fetch(IT_PDF[ed], os.path.join(work, os.path.basename(IT_PDF[ed])))
        first, last = spell_pages(pdf)
        it = extract(pdf, first, last)
        lists = {}
        if ed == "2014":
            raw = subprocess.run(["pdftotext", pdf, "-"], capture_output=True, text=True, check=True).stdout
            lists = class_lists(raw, [s["name"] for s in it])
        overrides = json.load(open(os.path.join(HERE, f"overrides-{ed}.json")))
        pairs = pair(it, en_raw, overrides, lists)
        write_lua(os.path.join(OUT, f"{ed}_it.lua"), SOURCES[(ed, "it")],
                  apply_fixes([it_entry(s, en[pairs[s["name"]]]) for s in it], ed, "it"))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "srd-work")
