"""Static checks for the GearQuipper Forever addon.

Usage: python tools/check.py [addon_dir]
Needs `lupa` (Lua 5.1 compile check). Exit code 1 when any ERROR is found.

Checks:
  1. TOC: every listed file exists; Interface is 16001.
  2. Lua: every .lua file listed in the TOC (or referenced from XML) compiles under Lua 5.1.
  3. XML: well-formed; <Script file="..."/> and <Include file="..."/> targets exist.
  4. Cross-reference: every `c:Name(` / `gearquipper:Name(` call has a `function c:Name` definition.
  5. Banned APIs: legacy globals that do not exist on WoW Forever, the restricted combat log, flavor checks.
  6. Secret-sensitive APIs: unit-state reads that must go through c:ReadState / c:SafeCall.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "GearQuipper-Forever")
LIBS = "libs" + os.sep

errors, warnings = [], []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def rel(path):
    return os.path.relpath(path, ADDON).replace("\\", "/")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


# ---------------------------------------------------------------- TOC
tocs = [f for f in os.listdir(ADDON) if f.endswith(".toc")]
if len(tocs) != 1:
    err(f"expected exactly one .toc in {ADDON}, found {tocs}")
    print("\n".join("ERROR " + e for e in errors))
    sys.exit(1)
toc_path = os.path.join(ADDON, tocs[0])
toc_files = []
interface = None
for line in read(toc_path).splitlines():
    s = line.strip()
    if s.startswith("## Interface:"):
        interface = s.split(":", 1)[1].strip()
    elif s and not s.startswith("#"):
        toc_files.append(s.replace("\\", os.sep))
if interface is None or "16001" not in interface:
    err(f"{tocs[0]}: Interface should list 16001 (got {interface!r})")
for f in toc_files:
    if not os.path.exists(os.path.join(ADDON, f)):
        err(f"{tocs[0]}: listed file missing: {f}")

# ---------------------------------------------------------------- XML
lua_files = [f for f in toc_files if f.endswith(".lua")]
for f in toc_files:
    if not f.endswith(".xml"):
        continue
    path = os.path.join(ADDON, f)
    if not os.path.exists(path):
        continue
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        err(f"{rel(path)}: XML parse error: {e}")
        continue
    base = os.path.dirname(path)
    for el in tree.iter():
        tag = el.tag.split("}")[-1]
        if tag in ("Script", "Include") and el.get("file"):
            target = os.path.normpath(os.path.join(base, el.get("file").replace("\\", os.sep)))
            if not os.path.exists(target):
                err(f"{rel(path)}: {tag} file missing: {el.get('file')}")
            elif target.endswith(".lua"):
                lua_files.append(os.path.relpath(target, ADDON))

# ---------------------------------------------------------------- Lua compile (5.1)
try:
    import lupa.lua51 as lua51

    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    compile_ = L.eval("function(src, name) local f, e = loadstring(src, name); if f then return true, '' end; return false, e end")
    for f in lua_files:
        src = read(os.path.join(ADDON, f))
        ok, msg = compile_(src, "@" + f.replace(os.sep, "/"))
        if not ok:
            err(f"Lua compile: {msg}")
except ImportError:
    warn("lupa not installed: Lua compile check skipped (pip install lupa)")

# ---------------------------------------------------------------- sources for text checks
own = [f for f in lua_files if not f.startswith(LIBS)]
sources = {f.replace(os.sep, "/"): read(os.path.join(ADDON, f)) for f in own}
xml_sources = {f.replace(os.sep, "/"): read(os.path.join(ADDON, f)) for f in toc_files if f.endswith(".xml")}


def strip_comments(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


code = {f: strip_comments(s) for f, s in sources.items()}

# ---------------------------------------------------------------- cross-reference
defined = set()
for src in code.values():
    defined.update(re.findall(r"function\s+(?:c|gearquipper)[:.]([A-Za-z_]\w*)", src))
    defined.update(re.findall(r"\b(?:c|gearquipper)\.([A-Za-z_]\w*)\s*=\s*function", src))
for f, src in list(code.items()) + [(f, s) for f, s in xml_sources.items()]:
    for n, line in enumerate(src.splitlines(), 1):
        for name in re.findall(r"\b(?:c|gearquipper):([A-Za-z_]\w*)\s*\(", line):
            if name not in defined:
                err(f"{f}:{n}: call to undefined c:{name}()")

# ---------------------------------------------------------------- banned APIs
BANNED = [
    (r"(?<![\w.:])GetContainerItem(Link|Info|ID|Cooldown)\s*\(", "use c:GetContainerItem*/C_Container"),
    (r"(?<![\w.:])GetContainerNum(Slots|FreeSlots)\s*\(", "use c:GetContainerNum*/C_Container"),
    (r"(?<![\w.:])PickupContainerItem\s*\(", "use c:PickupContainerItem"),
    (r"(?<![\w.:])UseContainerItem\s*\(", "never equip via UseContainerItem (sells/banks items)"),
    (r"(?<![\w.:])ContainerIDToInventoryID\s*\(", "use c:ContainerIDToInventoryID"),
    (r"(?<![\w.:])GetItemInfo(Instant)?\s*\(", "use c:GetItemInfo / c:GetItemInfoInstant"),
    (r"(?<![\w.:])EquipItemByName\s*\(", "use c:EquipItemByName"),
    (r"(?<![\w.:])GetItemQualityColor\s*\(", "use c:GetItemQualityColor"),
    (r"(?<![\w.:])GetItemGem\s*\(", "no gems on Forever"),
    (r"(?<![\w.:])GetSpellInfo\s*\(", "use c:GetSpellName / C_Spell"),
    (r"(?<![\w.:])GetSpell(Link|Subtext)\s*\(", "use C_Spell"),
    (r"(?<![\w.:])UnitBuff\s*\(|(?<![\w.:])UnitAura\s*\(", "auras are secret in combat/PvP; use stance-bar helpers"),
    (r"(?<![\w.:])CastingInfo\s*\(", "use UnitCastingInfo('player') via c:SafeCall"),
    (r"(?<![\w.:])GetAddOn(Info|Metadata)\s*\(|(?<![\w.:])IsAddOnLoaded\s*\(", "use c:GetAddOnInfo / C_AddOns"),
    (r"COMBAT_LOG_EVENT_UNFILTERED|CombatLogGetCurrentEventInfo", "combat log is restricted on Forever"),
    (r"InterfaceOptions(_AddCategory|Frame_OpenToCategory|FrameOkay)", "use the Settings API (c:RegisterSettingsPanel)"),
    (r"(?<![\w.:])getglobal\s*\(", "use _G"),
    (r"(?<![\w.:])BANK_CONTAINER\b|NUM_BANKBAGSLOTS|BankButtonIDToInvSlotID", "bank is tabbed on Forever; use c:GetBankBagIds"),
    (r"OnTooltipSetItem", "use c:AddItemTooltipPostCall"),
    (r"(?<![\w.:])GetActiveTalentGroup\s*\(", "use c:GetActiveSpecGroup"),
    (r"\bIs(Classic|TbcClassic|WotlkClassic|NewApi)\s*\(", "Forever is the only target; remove flavor branches"),
    (r"(?<![\w.:])loadstring\s*\(", "user scripts are dropped"),
    (r"(?<![\w.:])EasyMenu\s*\(", "EasyMenu does not exist on Forever"),
]
for f, src in code.items():
    if f.endswith("gearquipper-compatibility.lua"):
        continue
    for n, line in enumerate(src.splitlines(), 1):
        for pattern, why in BANNED:
            if re.search(pattern, line):
                err(f"{f}:{n}: banned API ({why}): {line.strip()[:120]}")

for f, src in xml_sources.items():
    for name in ("OptionsButtonTemplate", "OptionsSliderTemplate", "OptionsBoxTemplate"):
        if name in src:
            err(f"{f}: template {name} does not exist on the modern client")
for f, src in code.items():
    for n, line in enumerate(src.splitlines(), 1):
        for name in ("OptionsButtonTemplate", "OptionsSliderTemplate", "OptionsBoxTemplate"):
            if name in line:
                err(f"{f}:{n}: template {name} does not exist on the modern client")

# ---------------------------------------------------------------- secret-sensitive reads
SECRET_APIS = r"(?<![\w.:])(UnitIsAFK|UnitIsDND|UnitIsPVP|IsMounted|UnitOnTaxi|IsStealthed|IsSwimming|IsSubmerged|IsInGroup|IsInRaid|UnitIsDeadOrGhost|UnitCastingInfo|UnitChannelInfo|UnitCreatureType|UnitAffectingCombat|GetShapeshiftForm)\b"
for f, src in code.items():
    if f.endswith("gearquipper-compatibility.lua"):
        continue
    for n, line in enumerate(src.splitlines(), 1):
        m = re.search(SECRET_APIS, line)
        if m and not re.search(r"ReadState|SafeCall", line):
            err(f"{f}:{n}: {m.group(1)} must be read through c:ReadState / c:SafeCall: {line.strip()[:120]}")

UNIT_EVENTS = r'RegisterEvent\(\s*"(UNIT_\w+|PLAYER_FLAGS_CHANGED|PLAYER_SPECIALIZATION_CHANGED)"'
for f, src in code.items():
    for n, line in enumerate(src.splitlines(), 1):
        m = re.search(UNIT_EVENTS, line)
        if m:
            err(f"{f}:{n}: {m.group(1)} fires for every unit (nameplates!); use RegisterUnitEvent(event, \"player\")")

# ---------------------------------------------------------------- report
for w in warnings:
    print("WARN  " + w)
for e in errors:
    print("ERROR " + e)
print(f"\n{len(errors)} error(s), {len(warnings)} warning(s); {len(lua_files)} Lua files, {len(defined)} c:functions defined")
sys.exit(1 if errors else 0)
