"""Read the per-class spell lists of the Italian SRD 5.1.

Its spell descriptions don't name the classes (the 5.2.1 ones do), so the
lists help pairing the Italian spells with the English ones. The input is
the output of `pdftotext` (poppler) without -layout.
"""
import re

from match import CLASSES


def class_lists(raw_text, spell_names):
    """Return {italian spell name: [class keys]}."""
    lines = raw_text.split("\n")
    names = {n.lower(): n for n in spell_names}
    out, cls, pending, unknown = {}, None, "", []
    start = next(i for i, l in enumerate(lines) if l.strip() == "Incantesimi da bardo")
    for l in lines[start:]:
        t = l.strip()
        m = re.match(r"^Incantesimi da (\w+)$", t)
        if m and m.group(1) in CLASSES:
            cls = CLASSES[m.group(1)]
            continue
        if not t or re.match(r"^(\d\s*[°º] livello|Trucchetti.*)$", t) \
                or t.startswith("Rivendita") or t.startswith("Systems Reference"):
            continue
        if t == "Descrizioni degli incantesimi" or (cls == "warlock" and len(t) > 45):
            break
        key = (pending + " " + t).strip().lower() if pending else t.lower()
        if key in names:  # names that wrap on two lines
            out.setdefault(names[key], []).append(cls)
            pending = ""
        elif t.lower() in names:
            if pending:
                unknown.append(pending)
            out.setdefault(names[t.lower()], []).append(cls)
            pending = ""
        else:
            pending = key
    if unknown or pending:
        print("class lists: unknown names", unknown + ([pending] if pending else []))
    return out
