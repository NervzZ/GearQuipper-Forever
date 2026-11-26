"""Offline test harness for GearQuipper Forever (WoW Forever, Interface 16001).

Usage (from the repo root; any Python with `lupa` works, e.g. the porting venv):
    python tools/harness/run.py                 run every scenario
    python tools/harness/run.py spec bank       run scenarios whose file name contains "spec" or "bank"
    python tools/harness/run.py -v              also print chat, notes and full tracebacks
    python tools/harness/run.py --latency 0.2   server applies item moves 0.2 s after the request (realistic)
    python tools/harness/run.py --echo-chat     print chat lines as they happen
    python tools/harness/run.py --addon reference/GearQuipper-TBC-54/GearQuipper-TBC
                                                run against another copy (the original fails: harness check)

Each scenario gets a fresh Lua 5.1 state: tools/harness/wowmock.lua (the simulated client), the default test
character (unless the scenario opts out), the addon files in TOC order (.lua with varargs addonName/addonTable,
.xml through a small XML loader), SavedVariables (if the scenario provides them), then ADDON_LOADED,
PLAYER_LOGIN, PLAYER_ENTERING_WORLD(true, false) and one frame. Then the scenario runs.

A scenario file returns either `function(H, gq)` or a table
    { setup = function(H) ... end,       -- before the addon loads (inventory, player state)
      run = function(H, gq) ... end,
      savedVariables = {GQ_DATA = ...},   -- optional: SavedVariables of an earlier session
      relog = function(H, gq) ... end,    -- optional: second session, started with run's SavedVariables
      relogSetup = function(H) ... end,   -- optional: setup of the second session
      latency = 0.2,                      -- optional, overrides --latency
      noAddon = true,                     -- optional: test the mock only
      noDefaultCharacter = true }         -- optional: start with empty bags and no gear
Every script handler, timer callback and hook runs in an error trap (like BugGrabber); any recorded Lua error,
failed assertion or scenario error makes the scenario FAIL. Exit code 1 when any scenario fails.
"""
import argparse
import os
import re
import sys
import time
import traceback
import xml.parsers.expat

from lupa import lua51

HARNESS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HARNESS))
ADDON_DIR = os.path.join(ROOT, "GearQuipper-Forever")  # --addon overrides (e.g. the original for a baseline)
ADDON_NAME = os.path.basename(ADDON_DIR)
SCENARIOS = os.path.join(HARNESS, "scenarios")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def lua_str(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        elif o > 127:
            out.append("".join("\\%03d" % b for b in ch.encode("utf-8")))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


# ---------------------------------------------------------------- TOC
def parse_toc():
    tocs = [f for f in os.listdir(ADDON_DIR) if f.endswith(".toc")]
    fields, files = {}, []
    for line in read(os.path.join(ADDON_DIR, tocs[0])).splitlines():
        s = line.strip()
        if s.startswith("##"):
            key, _, value = s[2:].partition(":")
            fields[key.strip()] = value.strip()
        elif s and not s.startswith("#"):
            files.append(s.replace("\\", "/"))
    return fields, files


# ---------------------------------------------------------------- XML
def parse_xml(path, relname):
    parser = xml.parsers.expat.ParserCreate()
    root = {"tag": "#root", "attr": {}, "kids": [], "text": "", "line": 0, "file": relname}
    stack = [root]

    def start(name, attrs):
        node = {"tag": name, "attr": dict(attrs), "kids": [], "text": "", "line": parser.CurrentLineNumber,
                "file": relname}
        stack[-1]["kids"].append(node)
        stack.append(node)

    def end(_name):
        stack.pop()

    def chars(data):
        stack[-1]["text"] += data

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = chars
    with open(path, "rb") as fh:
        parser.Parse(fh.read(), True)
    return root["kids"][0] if root["kids"] else None


def node_to_lua(node):
    parts = ["{tag=", lua_str(node["tag"]), ",line=", str(node["line"]), ",file=", lua_str(node["file"]), ",attr={"]
    for k, v in node["attr"].items():
        parts += ["[", lua_str(k), "]=", lua_str(v), ","]
    parts.append("},kids={")
    for kid in node["kids"]:
        parts += [node_to_lua(kid), ","]
    parts.append("}")
    if node["text"].strip():
        parts += [",text=", lua_str(node["text"])]
    parts.append("}")
    return "".join(parts)


# ---------------------------------------------------------------- API names (for error annotations)
def load_api_functions():
    text = read(os.path.join(HARNESS, "data", "apidata.lua"))
    section = text.split("functions = {", 1)[1].split("\n},", 1)[0]
    return set(re.findall(r'\["([^"]+)"\]', section))


API_FUNCTIONS = load_api_functions()


def annotate(msg):
    m = re.search(r"attempt to (?:call|index) (global|field|method) '(\w+)'", msg)
    if not m:
        return ""
    kind, name = m.groups()
    if kind == "global" and name[:1].isupper():
        if name in API_FUNCTIONS:
            return "  [harness gap: documented Forever API, not in the mock]"
        return "  [not a documented Forever API - legacy global?]"
    if kind == "field":
        hits = sorted(f for f in API_FUNCTIONS if f.endswith("." + name))
        if hits:
            return "  [documented as " + ", ".join(hits[:3]) + " - harness gap if the namespace is right]"
    return ""


# ---------------------------------------------------------------- one scenario
class Session:
    """One client session (fresh Lua state): mock, character, addon, login events, one scenario phase."""

    def __init__(self, scenario, phase, saved_source):
        self.scn, self.phase, self.saved_source = scenario, phase, saved_source
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.H = None
        self.has_relog = False
        self.saved_out = None

    def harness_read(self, rel):
        return read(os.path.join(HARNESS, rel))

    def bootstrap(self):
        lua = self.lua
        H = lua.table()
        H.addonName = ADDON_NAME
        H.addonDir = ADDON_NAME + "/"
        H.tocFields = lua.table_from(self.scn.toc_fields)
        H._read = self.harness_read
        H.pyprint = lambda s: print(s)
        H.echoChat = self.scn.args.echo_chat
        lua.execute(r"""
            local H = ...
            local loadstring, traceback = loadstring, debug.traceback
            function H.include(rel)
                local f, err = loadstring(H._read(rel), "@tools/harness/" .. rel)
                if not f then error(err, 2) end
                return f(H)
            end
            function H.loadChunk(src, chunkName)
                local f, err = loadstring(src, "@" .. chunkName)
                return f, err
            end
            function H.runProtected(fn, ...)
                local args = {n = select("#", ...), ...}
                local ok, err = xpcall(function() return fn(unpack(args, 1, args.n)) end, function(e)
                    return {msg = tostring(e), trace = traceback("", 2)}
                end)
                return ok, err
            end
        """, H)
        lua.execute("local H = ...; H.include('wowmock.lua')", H)
        self.H = H
        return H

    def record(self, where, msg):
        self.H.recordError(where, self.lua.table_from({"msg": msg, "trace": ""}))

    def load_lua_file(self, rel):
        H = self.H
        chunk_name = ADDON_NAME + "/" + rel
        fn, err = H.loadChunk(read(os.path.join(ADDON_DIR, rel)), chunk_name)
        if fn is None:
            self.record(chunk_name, err)
            return
        H.trap(chunk_name, fn, ADDON_NAME, H.addonTable)

    def load_xml_file(self, rel):
        H = self.H
        chunk_name = ADDON_NAME + "/" + rel
        try:
            ui = parse_xml(os.path.join(ADDON_DIR, rel), chunk_name)
        except xml.parsers.expat.ExpatError as e:
            self.record(chunk_name, "XML parse error: %s" % e)
            return
        base = os.path.dirname(rel)

        def sibling(path):
            return os.path.normpath(os.path.join(base, path.replace("\\", "/"))).replace("\\", "/")

        for node in ui["kids"] if ui else []:
            tag, attr = node["tag"], node["attr"]
            if tag == "Script" and attr.get("file"):
                self.load_lua_file(sibling(attr["file"]))
            elif tag == "Script":
                fn, err = H.loadChunk(node["text"], chunk_name)
                if fn is None:
                    self.record(chunk_name, err)
                else:
                    H.trap(chunk_name, fn)
            elif tag == "Include" and attr.get("file"):
                self.load_xml_file(sibling(attr["file"]))
            else:
                H.trap(chunk_name, H.xml.loadTop, self.lua.execute("return " + node_to_lua(node)))

    def run(self):
        """Returns (ok, message, trace)."""
        lua = self.lua
        H = self.bootstrap()
        H.addonTable = lua.table()
        H.scenarioName = self.scn.name
        H.phase = self.phase
        fn, err = H.loadChunk(read(self.scn.path), "tools/harness/scenarios/" + os.path.basename(self.scn.path))
        if fn is None:
            return False, "scenario does not compile: " + str(err), ""
        ok, spec = H.runProtected(fn)
        if not ok:
            return False, "scenario chunk failed: " + spec["msg"], spec["trace"]
        if lua.eval("type")(spec) == "function":
            spec = lua.table_from({"run": spec})
        self.has_relog = spec["relog"] is not None
        H.latency = spec["latency"] if spec["latency"] is not None else self.scn.args.latency

        if not spec["noDefaultCharacter"]:
            H.setupDefaultCharacter()
        else:
            H.setupBags()
        setup = spec["setup"] if self.phase == 1 else spec["relogSetup"]
        if setup:
            ok, e = H.runProtected(setup, H)
            if not ok:
                return False, "setup failed: " + e["msg"], e["trace"]

        gq = None
        sv_names = [n.strip() for n in self.scn.toc_fields.get("SavedVariables", "").split(",") if n.strip()]
        if not spec["noAddon"]:
            for rel in self.scn.toc_files:
                if rel.endswith(".lua"):
                    self.load_lua_file(rel)
                elif rel.endswith(".xml"):
                    self.load_xml_file(rel)
            # the client loads SavedVariables after the addon's files, before ADDON_LOADED
            if self.saved_source:
                saved = lua.execute(self.saved_source)
                for name in sv_names:
                    lua.globals()[name] = saved[name]
            elif spec["savedVariables"]:
                for k, v in spec["savedVariables"].items():
                    lua.globals()[k] = v
            H.loadedAddons[ADDON_NAME] = True
            H.fire("ADDON_LOADED", ADDON_NAME, False)
            H.fire("VARIABLES_LOADED")
            H.loggedIn = True
            H.fire("PLAYER_LOGIN")
            H.fire("PLAYER_ENTERING_WORLD", True, False)
            H.fire("ZONE_CHANGED_NEW_AREA")
            H.advance(0)
            gq = lua.globals().gearquipper
        ok, e = H.runProtected(spec["run"] if self.phase == 1 else spec["relog"], H, gq)
        if not spec["noAddon"]:
            names = lua.table_from(sv_names)
            H.checkSavedVariables(names)
            self.saved_out = H.serializeSavedVariables(names)
        if not ok:
            return False, e["msg"], e["trace"]
        return True, None, None


class Scenario:
    """A scenario file: session 1 runs `run`; if the file has `relog`, session 2 starts a new client session
    with session 1's SavedVariables (written and read back like the client does) and runs `relog`."""

    def __init__(self, path, args, toc_fields, toc_files):
        self.path, self.args = path, args
        self.name = os.path.splitext(os.path.basename(path))[0]
        self.toc_fields, self.toc_files = toc_fields, toc_files
        self.sessions = []

    def run(self):
        first = Session(self, 1, None)
        self.sessions.append(first)
        ok, msg, trace = first.run()
        if ok and first.has_relog:
            second = Session(self, 2, first.saved_out)
            self.sessions.append(second)
            ok, msg, trace = second.run()
            if msg:
                msg = "[relog session] " + msg
        return ok, msg, trace


# ---------------------------------------------------------------- reporting
def short_trace(trace, verbose):
    lines = [l.strip() for l in (trace or "").splitlines() if l.strip() and l.strip() != "stack traceback:"]
    if verbose:
        return lines
    return [l for l in lines if (ADDON_NAME + "/") in l or "scenarios/" in l][:6]


def report(scn, ok, msg, trace, elapsed, verbose):
    errors = []
    for i, session in enumerate(scn.sessions):
        if session.H is not None:
            prefix = "[relog session] " if i > 0 else ""
            errors += [(prefix, e) for e in session.H.errors.values()]
    passed = ok and not errors
    print("%s %s (%.2fs)" % ("PASS" if passed else "FAIL", scn.name, elapsed))
    if msg:
        lines = msg.splitlines()
        print("   failure: " + lines[0])
        for line in lines[1:]:
            print("      " + line)
        for line in short_trace(trace, verbose or msg.startswith("harness exception")):
            print("      " + line)
    for prefix, e in errors:
        count = " (x%d)" % e["count"] if e["count"] > 1 else ""
        print("   %sLua error in %s%s: %s%s" % (prefix, e["where"], count, e["msg"], annotate(e["msg"])))
        for line in short_trace(e["trace"], verbose):
            print("      " + line)
    if verbose:
        for session in scn.sessions:
            if session.H is not None:
                for note in session.H.notes.values():
                    print("   note: " + note)
                for line in session.H.chat.values():
                    print("   chat: " + session.H.stripColors(line))
    return passed


def main():
    ap = argparse.ArgumentParser(description="GearQuipper Forever offline harness")
    ap.add_argument("filters", nargs="*", help="run only scenarios whose file name contains one of these")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--latency", type=float, default=0.0, help="seconds before the server applies item moves")
    ap.add_argument("--echo-chat", action="store_true")
    ap.add_argument("--addon", help="addon folder to test instead of GearQuipper-Forever (folder name = addon name)")
    args = ap.parse_args()
    if args.addon:
        global ADDON_DIR, ADDON_NAME
        ADDON_DIR = os.path.abspath(args.addon)
        ADDON_NAME = os.path.basename(ADDON_DIR.rstrip("/\\"))

    toc_fields, toc_files = parse_toc()
    files = sorted(f for f in os.listdir(SCENARIOS) if f.endswith(".lua"))
    if args.filters:
        files = [f for f in files if any(flt.lower() in f.lower() for flt in args.filters)]
    if not files:
        print("no scenarios match")
        return 1

    results, notes = [], {"undefined": {}, "noop": {}, "warnings": []}
    for f in files:
        scn = Scenario(os.path.join(SCENARIOS, f), args, toc_fields, toc_files)
        t0 = time.time()
        try:
            ok, msg, trace = scn.run()
        except Exception as ex:  # harness bug or Lua error outside any trap
            ok, msg, trace = False, "harness exception: %s" % ex, traceback.format_exc()
        passed = report(scn, ok, msg, trace, time.time() - t0, args.verbose)
        results.append((scn.name, passed))
        for session in scn.sessions:
            H = session.H
            if H is None:
                continue
            rawget, g = session.lua.eval("rawget"), session.lua.globals()
            for name, entry in H.undefinedGlobals.items():
                if rawget(g, name) is None:  # still undefined at the end (not an `X = X or {}` the addon fills)
                    notes["undefined"].setdefault(name, entry["where"])
            for name, count in H.noopMethods.items():
                notes["noop"][name] = notes["noop"].get(name, 0) + count
            for w in H.warnings.values():
                if w not in notes["warnings"]:
                    notes["warnings"].append(w)

    print()
    if notes["undefined"]:
        print("Undefined globals read by addon code (nil on this mock; check they exist on Forever):")
        for name in sorted(notes["undefined"]):
            print("   %-40s first at %s" % (name, notes["undefined"][name]))
    if notes["noop"]:
        print("Widget methods the mock does not model (ran as no-ops):")
        print("   " + ", ".join(sorted(notes["noop"])))
    if notes["warnings"]:
        print("Model warnings:")
        for w in notes["warnings"]:
            print("   " + w)
    failed = [n for n, p in results if not p]
    print("\n%d scenario(s): %d passed, %d failed%s" % (len(results), len(results) - len(failed), len(failed),
                                                      (" (" + ", ".join(failed) + ")") if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
