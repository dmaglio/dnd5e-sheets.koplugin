"""Extract spells from the Italian SRD PDFs (5.1 and 5.2.1) into JSON.

Usage: python extract_it.py <pdf> <first page> <last page> <out.json>
(pages are 0-based and must cover the "Descrizioni degli incantesimi" chapter)

Text blocks are read column by column, top to bottom. A spell starts with a
12pt heading followed by an italic "<School> di N° livello" / "Trucchetto di
<School>" line; then come the four bold-labelled fields, then the body.
Blocks that sit side by side inside a column are table cells: they are put
back together row by row, cells separated by " | ".
"""
import json, re, sys
import pymupdf

LEVEL_RE = re.compile(r"^(?:[A-Za-zÀ-ú]+ di \d\s*[°º] livello|Trucchetto di [A-Za-zÀ-ú]+)")
FIELDS = {"Tempo di lancio": "time", "Gittata": "range", "Componenti": "comp",
          "Componente": "comp", "Durata": "dur"}
SHY = "­"
# Typos in the official PDFs
FIXES = {"5° li Eroismoello": "5° livello"}
# Text after the last spell that is not part of it
STOP = ("Trappole", "Trappole nel gioco", "Glossario delle", "Glossario delle regole")


def clean(text):
    for a, b in FIXES.items():
        text = text.replace(a, b)
    return text


def skip(spans, text):
    return spans[0]["size"] < 9 or text.startswith("Rivendita vietata") or text.startswith("Systems Reference")


def side_by_side(a, b):
    """True if blocks a and b share some height but no width."""
    ax0, ay0, ax1, ay1 = a["bbox"]
    bx0, by0, bx1, by1 = b["bbox"]
    v_overlap = min(ay1, by1) - max(ay0, by0)
    return v_overlap > 3 and (ax1 <= bx0 + 1 or bx1 <= ax0 + 1)


def table_rows(blocks):
    """Rebuild a table from its cell blocks: returns [("row", text) | ("text", text)].
    Plain lines before the first and after the last real row (a paragraph
    that shares the block with the table) come back as "text"."""
    frags = []
    for b in blocks:
        for l in b["lines"]:
            spans = [s for s in l["spans"] if s["text"].strip()]
            if not spans:
                continue
            text = clean("".join(s["text"] for s in spans)).strip()
            if skip(spans, text):
                continue
            frags.append((round(spans[0]["origin"][1]), l["bbox"][0], text))
    frags.sort()
    rows = []  # each row: [y of its last line, [[x, text], ...]]
    for y, x, text in frags:
        if rows and abs(y - rows[-1][0]) < 3:
            rows[-1][1].append([x, text])
            continue
        if rows and y - rows[-1][0] < 14 and len(rows[-1][1]) > 1 and x > min(c[0] for c in rows[-1][1]) + 5:
            # wrapped line of a cell: join it to the cell above that starts nearest
            cell = min(rows[-1][1], key=lambda c: abs(c[0] - x))
            cell[1] = cell[1][:-1] + text if cell[1].endswith(SHY) else cell[1] + " " + text
            rows[-1][0] = y
            continue
        rows.append([y, [[x, text]]])
    multi = [i for i, r in enumerate(rows) if len(r[1]) > 1]
    out = []
    trailing = False
    for i, (_, r) in enumerate(rows):
        r.sort()
        if multi and i > multi[-1] and len(r) == 1 and (trailing or len(r[0][1]) > 25):
            trailing = True
        if multi and len(r) == 1 and (trailing or (i < multi[0] and len(r[0][1]) > 25)):
            out.append(("text", r[0][1]))
        else:
            out.append(("row", " | ".join(c[1] for c in r)))
    return out


def has_row(b):
    """True if two lines of the block sit on the same baseline (a table row)."""
    ls = [l for l in b["lines"] if "".join(s["text"] for s in l["spans"]).strip()]
    base = lambda l: next(s for s in l["spans"] if s["text"].strip())["origin"][1]
    for i, a in enumerate(ls):
        for o in ls[i + 1:]:
            if abs(base(a) - base(o)) < 2 and (a["bbox"][2] <= o["bbox"][0] + 1 or o["bbox"][2] <= a["bbox"][0] + 1):
                return True
    return False


def lines(doc, first, last):
    """Yield lines as (page, new_block, x, font, size, text, spans), column by column.
    A table comes out as one line per row with font "table"."""
    for pno in range(first, last + 1):
        page = doc[pno]
        mid, h = page.rect.width / 2, page.rect.height
        cols = {0: [], 1: []}
        for b in page.get_text("dict")["blocks"]:
            if not b.get("lines") or b["bbox"][1] > h - 50:
                continue
            cols[0 if b["bbox"][0] < mid - 10 else 1].append(b)
        for col in (0, 1):
            blocks = sorted(cols[col], key=lambda b: b["bbox"][1])
            cell = [has_row(b) or any(side_by_side(b, o) for o in blocks if o is not b) for b in blocks]
            xs = [l["bbox"][0] for b in blocks for l in b["lines"] if "".join(s["text"] for s in l["spans"]).strip()]
            col_x = min(xs) if xs else 0
            i = 0
            while i < len(blocks):
                if cell[i]:
                    j = i
                    while j < len(blocks) and cell[j]:
                        j += 1
                    prev_kind = None
                    for kind, row in table_rows(blocks[i:j]):
                        if kind == "row":
                            yield pno, True, 0, "table", 10, row, None, 0
                        else:
                            fake = [{"font": "Cambria", "size": 10, "bbox": (col_x, 0, 0, 0), "text": row}]
                            yield pno, prev_kind != "text", col_x, "Cambria", 10, row, fake, col_x
                        prev_kind = kind
                    i = j
                    continue
                first_line = True
                bxs = [l["bbox"][0] for l in blocks[i]["lines"] if "".join(s["text"] for s in l["spans"]).strip()]
                block_x = min(bxs) if bxs else col_x
                for l in blocks[i]["lines"]:
                    spans = [s for s in l["spans"] if s["text"].strip()]
                    if not spans:
                        continue
                    text = clean("".join(s["text"] for s in spans))
                    if skip(spans, text):
                        continue
                    yield pno, first_line, spans[0]["bbox"][0], spans[0]["font"], spans[0]["size"], text, spans, block_x
                    first_line = False
                i += 1


def is_label(spans):
    f = spans[0]["font"]
    return "Bold" in f and "Italic" not in f


def join(prev, t):
    if prev.endswith(SHY):
        return prev[:-1] + t.lstrip(SHY)
    return prev + " " + t.lstrip(SHY)


def extract(path, first, last):
    """Return the spells found between pages first and last (0-based)."""
    doc = pymupdf.open(path)
    spells, cur, mode, head = [], None, None, None
    stopped = False
    hanging = False
    for pno, new_block, x, font, size, text, spans, col_x in lines(doc, first, last):
        if stopped:
            break
        if font == "table":
            if cur is not None and mode == "body":
                cur["paras"].append({"row": text})
            continue
        italic = "Italic" in font and "Bold" not in font
        if size >= 11.5 and not italic and "Cambria" not in font:
            if text.strip() in STOP:
                stopped = True
                continue
            if head is not None and cur is not None:
                cur["paras"].append("## " + head)
            head = text.strip()
            continue
        if head is not None and italic:
            if LEVEL_RE.match(text.strip()):
                cur = {"name": head, "head": text.strip(), "fields": {}, "paras": [], "page": pno}
                spells.append(cur)
                head, mode = None, "head"
                continue
            if cur is not None:  # stat block inside a spell
                cur["paras"] += ["## " + head, "*" + text.strip() + "*"]
                head, mode = None, "body"
                continue
        if head is not None and cur is not None:
            cur["paras"].append("## " + head)  # sub-heading inside a spell body
            head = None
        if cur is None:
            continue
        if mode == "head":
            if italic:
                cur["head"] += " " + text.strip()
                continue
            mode = "fields"
        if mode == "fields":
            label = text.split(":")[0].strip()
            if label in FIELDS and is_label(spans):
                cur["fields"][FIELDS[label]] = text.split(":", 1)[1].strip()
                last_field = FIELDS[label]
                continue
            if "dur" not in cur["fields"] and cur["fields"]:
                cur["fields"][last_field] += " " + text.strip()
                continue
            mode = "body"
        t = text.strip()
        indented = x > col_x + 4 or text.startswith(" ")
        bullet = t.startswith("•")
        if not bullet and not new_block and cur["paras"] and isinstance(cur["paras"][-1], str) \
                and cur["paras"][-1].startswith("•"):
            indented = False  # hanging indent of a bullet item
        indented = indented or bullet
        # paragraphs that open with a bold label ("Allarme acustico.") may wrap
        # with a hanging indent: their next lines are indented, not new paragraphs
        label_start = "Bold" in font and ("Italic" in font or len(spans) > 1)
        if label_start:
            hanging = True
            n = 0
            while n < len(spans) and "Bold" in spans[n]["font"]:
                n += 1
            lead = "".join(sp["text"] for sp in spans[:n]).strip()
            rest = "".join(sp["text"] for sp in spans[n:]).strip()
            if lead:
                t = ("**" + lead + "** " + rest).strip()
        prev = cur["paras"][-1] if cur["paras"] else None
        if isinstance(prev, str) and prev.startswith("## "):
            prev = None  # never continue a sub-heading
        if isinstance(prev, str) and re.fullmatch(r"\*\*[^*]+\*\*", prev):
            if label_start and lead:
                # the label itself wraps: "**Utilizzo ... supe-**" + "**riore.** I danni..."
                cur["paras"][-1] = join(prev[:-2], t[2:])
            else:
                cur["paras"][-1] = prev + " " + t  # a label alone on its line
            continue
        if hanging and indented and not label_start and isinstance(prev, str) and prev \
                and (t[:1].islower() or prev.endswith(SHY) or not re.search(r"[.:!?»)”\"]$", prev)):
            cur["paras"][-1] = join(prev, t)
            continue
        if indented and not label_start:
            hanging = False
        if new_block and not indented and not label_start and isinstance(prev, str) and prev \
                and not prev.startswith("•") \
                and (prev.endswith(SHY) or not re.search(r"[.:!?»)”\"]$", prev) or t[:1].islower()):
            # a paragraph carried over to the next column or page
            cur["paras"][-1] = join(prev, t)
        elif not prev or not isinstance(prev, str) or new_block or indented or label_start:
            cur["paras"].append(t)
        else:
            cur["paras"][-1] = join(prev, t)
    for sp in spells:
        paras = []
        for p in sp["paras"]:
            if isinstance(p, dict):
                paras.append({"row": re.sub(r"\s+", " ", p["row"].replace(SHY, "")).strip()})
            else:
                paras.append(re.sub(r"\s+", " ", p.replace(SHY, "")).strip())
        sp["paras"] = paras
        for k, v in sp["fields"].items():
            sp["fields"][k] = re.sub(r"\s+", " ", v.replace(SHY, "")).strip()
    return spells


if __name__ == "__main__":
    found = extract(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))
    json.dump(found, open(sys.argv[4], "w"), ensure_ascii=False, indent=1)
    print(len(found), "spells")
