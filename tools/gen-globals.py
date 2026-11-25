#!/usr/bin/env python3
"""Regenerate the list of globals that exist on the WoW Forever client, from reference/.

Writes two things:
  .luacheckrc                      the block between BEGIN GENERATED / END GENERATED
  reference/.forever-globals.lua   a Lua table used by tools/smoke.lua

Sources, most to least authoritative:
  1. BlizzardInterfaceResources dumps (taken from the running client): C API, FrameXML
     functions, frames, mixins, enums, global strings.
  2. A scan of wow-ui-source for top-level `NAME = ...` assignments and named XML objects
     (fonts, frames), skipping folders that only load on other game types. This catches
     plain tables and constants the dumps do not list (SlashCmdList, RAID_CLASS_COLORS, ...).

C_* namespaces get an explicit field list, so luacheck flags C_Spell.NoSuchFunction (W143).
Every other global allows any field.

Run via tools/update-reference.ps1, or directly: python tools/gen-globals.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "reference/BlizzardInterfaceResources/Resources"
SRC = ROOT / "reference/wow-ui-source/Interface/AddOns"
LUACHECKRC = ROOT / ".luacheckrc"
SMOKE_OUT = ROOT / "reference/.forever-globals.lua"

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
# Folder names that never load on the camelot (Forever) game type.
OTHER_GAME_DIRS = {"classic", "vanilla", "tbc", "wrath", "cata", "mists", "standard", "wowlabs", "plunderstorm", "wowhack"}
LUA51 = {
    "_G", "_VERSION", "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable", "ipairs", "load",
    "loadfile", "loadstring", "module", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "require",
    "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "coroutine", "debug",
    "io", "math", "os", "package", "string", "table",
}


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def quoted(path):
    return re.findall(r'^\s*"([^"]+)",?\s*$', read(path), re.M)


def loads_on_forever(path):
    parts = {p.lower() for p in path.relative_to(SRC).parts[:-1]}
    return not (parts & OTHER_GAME_DIRS) and not path.relative_to(SRC).parts[0].startswith("Blizzard_Deprecated")


def main():
    if not RES.exists() or not SRC.exists():
        sys.exit("reference/ checkouts missing; run tools/update-reference.ps1")

    plain, namespaces = set(), {}
    for fname in ("GlobalAPI.lua", "FrameXML.lua", "Frames.lua", "Mixins.lua"):
        for name in quoted(RES / fname):
            top, _, field = name.partition(".")
            if not IDENT.match(top):
                continue
            if field and top.startswith("C_"):
                namespaces.setdefault(top, set()).add(field.split(".")[0])
            else:
                plain.add(top)

    plain.update(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", read(RES / "LuaEnum.lua"), re.M))
    strings = RES / "GlobalStrings/enUS.lua"
    if strings.exists():
        plain.update(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", read(strings), re.M))

    scanned = 0
    for path in SRC.rglob("*.lua"):
        if loads_on_forever(path):
            found = re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]", read(path), re.M)
            scanned += len(found)
            plain.update(found)
    for path in SRC.rglob("*.xml"):
        if loads_on_forever(path):
            for tag in re.findall(r"<[A-Za-z]+\b[^>]*\bname=\"[A-Za-z_][A-Za-z0-9_]*\"[^>]*>", read(path)):
                # Templates are not globals, except font objects, which always are.
                if 'virtual="true"' not in tag or tag.startswith("<Font"):
                    plain.add(re.search(r'\bname="([^"]+)"', tag).group(1))

    plain -= LUA51
    plain -= set(namespaces)
    names = sorted(plain, key=lambda s: (s.lower(), s))

    lines = ["local wow = {"]
    for ns in sorted(namespaces):
        fields = ", ".join(f'"{f}"' for f in sorted(namespaces[ns]))
        lines.append(f"\t{ns} = {{ fields = {{ {fields} }} }},")
    row = "\t"
    for name in names:
        piece = f'"{name}", '
        if len(row) + len(piece) > 150:
            lines.append(row.rstrip())
            row = "\t"
        row += piece
    lines.append(row.rstrip())
    lines.append("}")
    block = "\n".join(lines)

    text = read(LUACHECKRC)
    pattern = re.compile(r"(-- BEGIN GENERATED[^\n]*\n).*?(-- END GENERATED)", re.S)
    if not pattern.search(text):
        sys.exit(".luacheckrc is missing the BEGIN GENERATED / END GENERATED markers")
    LUACHECKRC.write_text(pattern.sub(lambda m: m.group(1) + block + "\n" + m.group(2), text), encoding="utf-8", newline="\n")

    smoke = ["return {", "\tnamespaces = {"]
    for ns in sorted(namespaces):
        smoke.append(f"\t\t{ns} = {{ " + ", ".join(f"{f} = true" for f in sorted(namespaces[ns]) if IDENT.match(f)) + " },")
    smoke.append("\t},")
    smoke.append("\tfunctions = {")
    functions = {n for f in ("GlobalAPI.lua", "FrameXML.lua") for n in quoted(RES / f) if IDENT.match(n)} - LUA51
    smoke.extend(f"\t\t{n} = true," for n in sorted(functions))
    smoke.append("\t},")
    smoke.append("\tother = {")
    smoke.extend(f"\t\t{n} = true," for n in names if n not in functions)
    smoke.append("\t},")
    smoke.append("}")
    SMOKE_OUT.write_text("\n".join(smoke) + "\n", encoding="utf-8", newline="\n")

    print(f"{len(namespaces)} C_ namespaces, {len(names)} other globals ({scanned} assignments scanned from source)")


if __name__ == "__main__":
    main()
