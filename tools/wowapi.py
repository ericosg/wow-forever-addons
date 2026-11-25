#!/usr/bin/env python3
"""Look up WoW Forever API facts in the local reference checkout (no network).

Sources (see kb/01-reference-sources.md):
  reference/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated  (signatures, secret flags)
  reference/BlizzardInterfaceResources/Resources                               (flat global/event/template lists)

Usage:
  python tools/wowapi.py C_Spell.GetSpellInfo     exact function / event / table / enum name
  python tools/wowapi.py -s aura                  substring search across every kind of name
  python tools/wowapi.py -n C_UnitAuras           list everything in a namespace
  python tools/wowapi.py -g GetSpellInfo UnitAura do these globals exist on Forever at all?
  python tools/wowapi.py --secret C_UnitAuras     only show entries carrying secret/restriction flags
  python tools/wowapi.py --rebuild                re-parse after updating reference/ (cache is automatic)
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "reference/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated"
RES = ROOT / "reference/BlizzardInterfaceResources/Resources"
CACHE = ROOT / "reference/.wowapi-cache.json"

TOKEN = re.compile(
    r"""\s*(?:
      (?P<comment>--[^\n]*) |
      (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*') |
      (?P<num>-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?)) |
      (?P<name>[A-Za-z_][A-Za-z0-9_.:]*) |
      (?P<punct>[{}=,;()\[\]])
    )""",
    re.X,
)


def tokenize(text):
    pos, out = 0, []
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            if text[pos:].strip() == "":
                break
            pos += 1  # skip anything unexpected (operators etc.)
            continue
        pos = m.end()
        kind = m.lastgroup
        if kind != "comment":
            out.append((kind, m.group(kind)))
    return out


def parse_value(toks, i):
    kind, val = toks[i]
    if kind == "punct" and val == "{":
        return parse_table(toks, i + 1)
    if kind == "str":
        return val[1:-1], i + 1
    if kind == "num":
        try:
            return (int(val, 0) if re.fullmatch(r"-?(0[xX][0-9a-fA-F]+|\d+)", val) else float(val)), i + 1
        except ValueError:
            return val, i + 1
    if kind == "name":
        return {"true": True, "false": False, "nil": None}.get(val, val), i + 1
    return None, i + 1


def parse_table(toks, i):
    arr, rec = [], {}
    while i < len(toks):
        kind, val = toks[i]
        if kind == "punct" and val == "}":
            i += 1
            break
        if kind == "punct" and val in ",;":
            i += 1
            continue
        if kind == "name" and i + 1 < len(toks) and toks[i + 1] == ("punct", "="):
            rec[val], i = parse_value(toks, i + 2)
        else:
            v, i = parse_value(toks, i)
            arr.append(v)
    if rec and not arr:
        return rec, i
    if arr and not rec:
        return arr, i
    if rec:
        rec["_items"] = arr
    return rec, i


def parse_doc_file(path):
    toks = tokenize(path.read_text(encoding="utf-8", errors="replace"))
    for i, t in enumerate(toks):
        if t == ("punct", "{"):
            table, _ = parse_table(toks, i + 1)
            return table if isinstance(table, dict) else None
    return None


def build():
    index = {"functions": {}, "events": {}, "tables": {}}
    for path in sorted(DOCS.glob("*.lua")):
        doc = parse_doc_file(path)
        if not doc:
            continue
        ns = doc.get("Namespace") or ""
        system = doc.get("Name") or path.stem
        for fn in doc.get("Functions") or []:
            if isinstance(fn, dict) and fn.get("Name"):
                owner = ns or (system if doc.get("Type") == "ScriptObject" else "")
                full = f"{owner}.{fn['Name']}" if owner else fn["Name"]
                fn["_file"], fn["_system"], fn["_kind"] = path.name, system, doc.get("Type")
                index["functions"][full] = fn
        for ev in doc.get("Events") or []:
            if isinstance(ev, dict) and ev.get("LiteralName"):
                ev["_file"], ev["_system"] = path.name, system
                index["events"][ev["LiteralName"]] = ev
        for tb in doc.get("Tables") or []:
            if isinstance(tb, dict) and tb.get("Name"):
                tb["_file"] = path.name
                index["tables"][tb["Name"]] = tb
    for key, fname in (("globalapi", "GlobalAPI.lua"), ("framexml", "FrameXML.lua"), ("eventlist", "Events.lua")):
        p = RES / fname
        index[key] = sorted(set(re.findall(r'"([A-Za-z_][A-Za-z0-9_.]*)"', p.read_text(encoding="utf-8")))) if p.exists() else []
    CACHE.write_text(json.dumps(index), encoding="utf-8")
    return index


def load(rebuild=False):
    if not DOCS.exists():
        sys.exit(f"Missing {DOCS}. Run tools/update-reference.ps1 first.")
    if not rebuild and CACHE.exists() and CACHE.stat().st_mtime >= max(p.stat().st_mtime for p in DOCS.glob("*.lua")):
        return json.loads(CACHE.read_text(encoding="utf-8"))
    return build()


def fmt_field(f):
    if not isinstance(f, dict):
        return str(f)
    t = f.get("Type", "?")
    if f.get("InnerType"):
        t += f"<{f['InnerType']}>"
    s = f"{f.get('Name', '?')}: {t}"
    if f.get("Nilable"):
        s += "?"
    if "Default" in f:
        s += f" = {f['Default']}"
    extra = [k for k in f if k.startswith(("Secret", "Conditional", "NeverSecret")) and f[k]]
    if extra:
        s += "  [" + ", ".join(f"{k}={f[k]}" if f[k] is not True else k for k in extra) + "]"
    return s


FLAG = re.compile(r"Secret|Restrict|Protected|Taint|Insecure|Hardware|Combat|Synchronous|MayReturnNothing|Constant|Environment")


def flags(entry):
    out = []
    for k, v in entry.items():
        if k.startswith("_") or k in ("Arguments", "Returns", "Payload", "Fields", "Name", "Type", "LiteralName", "Documentation"):
            continue
        if FLAG.search(k) and v not in (False, None):
            out.append(k if v is True else f"{k}={v}")
    return out


def show_function(name, fn):
    args = ", ".join(a.get("Name", "?") if isinstance(a, dict) else str(a) for a in fn.get("Arguments") or [])
    rets = ", ".join(r.get("Name", "?") if isinstance(r, dict) else str(r) for r in fn.get("Returns") or [])
    print(f"\nFUNCTION {rets + ' = ' if rets else ''}{name}({args})    [{fn['_file']}]")
    fl = flags(fn)
    if fl:
        print("  flags:   " + ", ".join(fl))
    for label, key in (("arg", "Arguments"), ("ret", "Returns")):
        for f in fn.get(key) or []:
            print(f"  {label}:     {fmt_field(f)}")
    for d in fn.get("Documentation") or []:
        print(f"  doc:     {d}")


def show_event(name, ev):
    print(f"\nEVENT {name}    [{ev['_file']}]")
    fl = flags(ev)
    if fl:
        print("  flags:   " + ", ".join(fl))
    for f in ev.get("Payload") or []:
        print(f"  payload: {fmt_field(f)}")
    for d in ev.get("Documentation") or []:
        print(f"  doc:     {d}")


def show_table(name, tb):
    print(f"\n{(tb.get('Type') or 'Table').upper()} {name}    [{tb['_file']}]")
    for f in tb.get("Fields") or []:
        if isinstance(f, dict) and "EnumValue" in f:
            print(f"  {f.get('Name')} = {f['EnumValue']}")
        else:
            print(f"  {fmt_field(f)}")
    for v in tb.get("Values") or []:
        if isinstance(v, dict):
            print(f"  {v.get('Name')} = {v.get('Value')}  ({v.get('Type')})")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("-s", "--search", action="store_true", help="substring search (case-insensitive)")
    ap.add_argument("-n", "--namespace", action="store_true", help="list members of a namespace / script object")
    ap.add_argument("-g", "--globals", action="store_true", help="check whether global names exist on Forever")
    ap.add_argument("--secret", action="store_true", help="with -n/-s: only entries with secret/restriction flags")
    ap.add_argument("--rebuild", action="store_true")
    a = ap.parse_args()
    idx = load(a.rebuild)
    if not a.names:
        print(f"{len(idx['functions'])} functions, {len(idx['events'])} events, {len(idx['tables'])} tables/enums indexed.")
        return
    for q in a.names:
        if a.globals:
            hits = [src for src, key in (("C API global", "globalapi"), ("FrameXML Lua global", "framexml"), ("event", "eventlist")) if q in idx[key]]
            doc = q in idx["functions"]
            if not hits and find_lua_definition(q):
                hits = ["defined in Blizzard Lua source (run without -g for the location)"]
            print(f"{q}: " + (", ".join(hits) if hits else "NOT PRESENT on Forever") + ("  (documented)" if doc else ""))
            continue
        ql = q.lower()
        if a.namespace:
            members = sorted(k for k in idx["functions"] if k.lower().startswith(ql + "."))
            if a.secret:
                members = [k for k in members if flags(idx["functions"][k])]
            for k in members:
                fl = flags(idx["functions"][k])
                print(f"{k}" + (f"    [{', '.join(fl)}]" if fl else ""))
            if not members:
                print(f"No documented functions under '{q}'.")
            continue
        if a.search:
            for kind, key in (("function", "functions"), ("event", "events"), ("table", "tables")):
                for k in sorted(idx[key]):
                    if ql in k.lower() and (not a.secret or flags(idx[key][k])):
                        print(f"{kind:9}{k}")
            for kind, key in (("global", "globalapi"), ("framexml", "framexml")):
                for k in idx[key]:
                    if ql in k.lower() and k not in idx["functions"]:
                        print(f"{kind:9}{k}")
            continue
        found = False
        for key, show in (("functions", show_function), ("events", show_event), ("tables", show_table)):
            for k, v in idx[key].items():
                if k.lower() == ql:
                    show(k, v)
                    found = True
        if not found:
            where = [src for src, key in (("GlobalAPI", "globalapi"), ("FrameXML", "framexml")) if q in idx[key]]
            defs = find_lua_definition(q)
            for d in defs:
                print(d)
            if not defs:
                print(f"{q}: no documentation entry and no Lua definition." + (f" Listed in {', '.join(where)} (C function without docs); grep reference/wow-ui-source for usage." if where else " Not in the global dumps either: it does not exist on Forever. Try -s."))


def find_lua_definition(name):
    """Blizzard's Lua-side API (Settings.*, MenuUtil.*, mixin methods...) has no doc tables: show where it is defined."""
    src = DOCS.parent
    esc = re.escape(name).replace(r"\.", r"[.:]")
    pattern = re.compile(rf"^\s*(?:--\[\[.*?\]\]\s*)?(?:function\s+{esc}\s*\(.*\)|{esc}\s*=\s*function\s*\(.*\)|{esc}\s*=\s*[^=].*)", re.M)
    out = []
    for path in src.rglob("*.lua"):
        text = path.read_text(encoding="utf-8", errors="replace")
        if name.split(".")[-1].split(":")[-1] not in text:
            continue
        for m in pattern.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            out.append(f"LUA  {m.group(0).strip()[:160]}\n     reference/wow-ui-source/Interface/AddOns/{path.relative_to(src).as_posix()}:{line}")
    return out[:12]


if __name__ == "__main__":
    main()
