#!/usr/bin/env python3
"""flutter-ai-testing MCP server: lets any MCP client (Claude Code, Codex,
Cursor, Copilot, ...) start a Flutter app on a device and drive it.

    python3 server.py          # speaks MCP over stdio

Standard library only. Needs: Flutter (or fvm), `marionette_mcp` (dart pub
global activate marionette_mcp 0.7.0), adb for Android, Xcode for iOS.

The app must have flutter-ai-testing installed (install.sh): an
ai-testing.conf and a Marionette entrypoint with the app tools.

Behind the scenes it runs one `marionette_mcp` per device and passes its tools
through, each with an optional `device` argument, so several devices can be
driven side by side. App logs go to a file and are never returned: debug
output can contain personal data.
"""
import json
import os
import pathlib
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

VERSION = "0.1.0"
# Longest wait for one Marionette call (AI_TESTING_CALL_TIMEOUT overrides).
CALL_TIMEOUT = float(os.environ.get("AI_TESTING_CALL_TIMEOUT", "45"))
HERE = pathlib.Path(__file__).resolve().parent

INSTRUCTIONS = """\
Tools to test a Flutter app on Android and iOS the way a person does.

1. list_devices, then start_app(app_dir, device). It builds, installs, grants OS
   permissions and connects; the first build can take minutes. If it returns
   "starting", call app_status until it is running.
2. Drive the app with tap / enter_text / scroll_to / swipe / press_back_button,
   targeting controls by test key (see the app's docs/test-keys.md). Read the
   screen with get_interactive_elements.
3. Each action's reply ends with "after: {...}", the where_am_i answer once the
   screen has settled: page stack, *_screen keys on screen (bottom page
   first), open dialogs, loading, signed in. Check it before the next step.
   While loading is true, call where_am_i again until it is false.

Rules:
- Reach pages the normal way, by tapping. The app's uiOnly... tools skip the
  user path: use them only when asked to check one page's layout, and say so.
- Never type real people's data. Use the test account the user gives you for
  that run, and don't write it to any file.
- Don't take screenshots of pages that show personal data unless asked.
- On Android, Back on the first page closes the app: prefer the page's own
  back buttons.
- OS dialogs (permissions, keyboard) are not visible to these tools.
- The app's own guide is docs/AUTOMATION-TESTING.md (page map, test cases).
"""

# Marionette tools not passed through: the server manages connections, and
# logs can contain personal data.
HIDDEN_TOOLS = {"connect", "disconnect", "get_logs"}

# Passed-through tools that change the screen: their reply also carries the
# where_am_i answer after the screen settles.
ACTION_TOOLS = {"tap", "secondary_tap", "double_tap", "long_press", "swipe", "pinch_zoom",
                "press_back_button", "scroll_to", "enter_text", "press_key", "hot_restart",
                "hot_reload", "call_custom_extension"}

# Safe status messages recognised in the run log. The log itself is never returned.
PROBLEMS = [
    (re.compile(r"refusing:"), "refused: the compile-time host is not a test host (see ai-testing.conf)"),
    (re.compile(r"missing .*ai-testing\.conf|APP_ID is not set"), "ai-testing.conf is missing or has no APP_ID"),
    (re.compile(r"Gradle task \S+ failed|BUILD FAILED"), "Android build failed: run the app once by hand to see the error"),
    (re.compile(r"Error \(Xcode\)|Could not build the application"), "iOS build failed: run the app once by hand to see the error"),
    (re.compile(r"No supported devices|No devices found|not found.*device", re.I), "device not found"),
    (re.compile(r"Lost connection to device"), "lost connection to the device (app closed or crashed)"),
    (re.compile(r"Target file .* not found"), "Marionette entrypoint not found (TARGET in ai-testing.conf)"),
]


def log(msg):
    print(f"[flutter-ai-testing] {msg}", file=sys.stderr, flush=True)


def newest_fvm_bin():
    """Highest numbered fvm Flutter (named channels like `stable` last)."""
    def order(path):
        name = path.parent.name
        nums = [int(p) for p in name.split(".") if p.isdigit()]
        return (len(nums) == len(name.split(".")), nums)
    versions = sorted(pathlib.Path.home().glob("fvm/versions/*/bin"), key=order, reverse=True)
    return str(versions[0]) if versions else None


def tool_env():
    """PATH with pub's bin folder and a Dart SDK: marionette_mcp exits at
    start-up when it can't find `dart`."""
    env = dict(os.environ)
    extra = [os.path.expanduser("~/.pub-cache/bin")]
    if not shutil.which("dart"):
        if env.get("FLUTTER_BIN"):
            extra.append(str(pathlib.Path(env["FLUTTER_BIN"]).parent))
        if newest_fvm_bin():
            extra.append(newest_fvm_bin())
    env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
    return env


ENV = tool_env()


def flutter_cmd():
    # Not `fvm flutter`: outside an fvm project it prints nothing.
    if ENV.get("FLUTTER_BIN"):
        return [ENV["FLUTTER_BIN"]]
    found = shutil.which("flutter", path=ENV["PATH"])
    if found:
        return [found]
    raise ToolError("flutter not found: put it on PATH or set FLUTTER_BIN")


def run_script():
    for candidate in (HERE / "marionette-run.sh", HERE.parent / "scripts" / "marionette-run.sh"):
        if candidate.is_file():
            return candidate
    raise ToolError("marionette-run.sh not found next to the server")


def key_script(name):
    for candidate in (HERE / name, HERE.parent / "scripts" / name):
        if candidate.is_file():
            return candidate
    raise ToolError(f"{name} not found next to the server")


def conf_value(app_dir, name, default=""):
    path = app_dir / "ai-testing.conf"
    if not path.is_file():
        return default
    value = default
    for line in path.read_text().splitlines():
        if line.startswith(name + "="):
            value = line.split("=", 1)[1].strip()
    return value


class ToolError(Exception):
    pass


class Marionette:
    """One marionette_mcp child process, connected to one app."""

    def __init__(self):
        exe = shutil.which("marionette_mcp", path=ENV["PATH"])
        if not exe:
            raise ToolError("marionette_mcp not found: dart pub global activate marionette_mcp 0.7.0")
        self.p = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, env=ENV)
        self.n = 0
        self.lock = threading.Lock()
        # Replies are read on a thread so a request can time out: an app in the
        # background draws no frames, and a tap then never answers.
        self.replies = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.request("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                    "clientInfo": {"name": "flutter-ai-testing", "version": VERSION}})
        self.notify("notifications/initialized")
        self.uri = None
        self.namespace = None

    def notify(self, method):
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
        self.p.stdin.flush()

    def _read(self):
        for line in self.p.stdout:
            try:
                self.replies.put(json.loads(line))
            except ValueError:
                pass
        self.replies.put(None)

    def request(self, method, params, timeout=CALL_TIMEOUT):
        with self.lock:
            self.n += 1
            self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method,
                                           "params": params}) + "\n")
            self.p.stdin.flush()
            deadline = time.time() + timeout
            while True:
                try:
                    reply = self.replies.get(timeout=max(0.1, deadline - time.time()))
                except queue.Empty:
                    raise ToolError(
                        f"no answer from the app within {timeout:.0f}s: it may be in the background, "
                        "behind another app, or stopped at a breakpoint. Bring it to the front and retry.")
                if reply is None:
                    raise ToolError("marionette_mcp stopped")
                if reply.get("id") == self.n:  # late replies to timed-out calls are skipped
                    if "error" in reply:
                        raise ToolError(reply["error"].get("message", "marionette error"))
                    return reply["result"]

    def call(self, name, args):
        return self.request("tools/call", {"name": name, "arguments": args})

    def connect(self, uri):
        result = self.call("connect", {"uri": uri})
        if result.get("isError"):
            raise ToolError(text_of(result) or "could not connect")
        self.uri = uri
        self.namespace = None

    def close(self):
        try:
            self.p.kill()
        except Exception:
            pass


def text_of(result):
    return "".join(c.get("text", "") for c in result.get("content", []) if c.get("type") == "text")


class Session:
    """An app started (or attached) on one device."""

    def __init__(self, device, app_dir):
        self.device = device
        self.app_dir = app_dir
        self.proc = None
        self.log_path = None
        self.marionette = None
        self.uri_file = app_dir / conf_value(app_dir, "URI_DIR", ".marionette") / (
            re.sub(r"[^A-Za-z0-9_.-]", "_", device) + ".uri")

    def state(self):
        if self.proc is not None and self.proc.poll() is not None:
            return f"exited ({self.proc.returncode})"
        if self.marionette and self.marionette.uri:
            return "running"
        return "starting" if self.proc else "attached"

    def problem(self):
        if not self.log_path or not self.log_path.is_file():
            return None
        text = self.log_path.read_text(errors="ignore")
        for pattern, message in PROBLEMS:
            if pattern.search(text):
                return message
        return None

    def try_connect(self):
        if self.marionette and self.marionette.uri:
            return True
        if not self.uri_file.is_file():
            return False
        uri = self.uri_file.read_text().strip()
        if not uri:
            return False
        if self.marionette is None:
            self.marionette = Marionette()
        self.marionette.connect(uri)
        return True

    def stop(self):
        if self.marionette:
            self.marionette.close()
            self.marionette = None
        if self.proc and self.proc.poll() is None:
            try:
                self.proc.stdin.write("q")  # flutter run's own quit: stops the app too
                self.proc.stdin.flush()
                self.proc.wait(timeout=15)
            except Exception:
                pass
        if self.proc:
            # The script runs flutter run, which runs more tools: end the whole group.
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass

    def summary(self):
        return {"device": self.device, "app": str(self.app_dir), "state": self.state(),
                "problem": self.problem()}


SESSIONS = {}


def app_dir_arg(args):
    raw = args.get("app_dir") or os.environ.get("AI_TESTING_APP_DIR") or os.getcwd()
    path = pathlib.Path(raw).expanduser().resolve()
    for folder in [path, *path.parents]:
        if (folder / "pubspec.yaml").is_file():
            return folder
    raise ToolError(f"no Flutter app (pubspec.yaml) at or above {path}")


def session_for(args):
    device = args.get("device")
    if device:
        if device not in SESSIONS:
            raise ToolError(f"no app on {device}: call start_app or attach first")
        return SESSIONS[device]
    live = [s for s in SESSIONS.values() if s.state() in ("running", "attached", "starting")]
    if len(live) == 1:
        return live[0]
    if not live:
        raise ToolError("no app running: call start_app (or attach) first")
    raise ToolError(f"several apps running, pass device: {[s.device for s in live]}")


def connected(session):
    if not session.try_connect():
        raise ToolError(f"app on {session.device} is {session.state()}, not connected yet: call app_status")
    return session.marionette


# ---------------------------------------------------------------- own tools

def t_list_devices(args):
    out = subprocess.run(flutter_cmd() + ["devices", "--machine"], capture_output=True, text=True,
                         env=ENV, timeout=120)
    try:
        devices = json.loads(out.stdout[out.stdout.index("["):])
    except ValueError:
        raise ToolError("flutter devices failed")
    rows = [{"id": d["id"], "name": d["name"], "platform": d.get("targetPlatform"),
             "emulator": d.get("emulator")} for d in devices
            if d.get("targetPlatform", "").startswith(("android", "ios"))]
    return json.dumps(rows, indent=1)


def t_start_app(args):
    device = args.get("device") or ""
    if not device:
        raise ToolError("pass device (see list_devices)")
    app_dir = app_dir_arg(args)
    if not (app_dir / "ai-testing.conf").is_file():
        raise ToolError(f"{app_dir} has no ai-testing.conf: install flutter-ai-testing first (install.sh)")
    old = SESSIONS.get(device)
    if old and old.state() in ("running", "starting"):
        if old.app_dir == app_dir:
            return wait_for(old, int(args.get("wait_seconds", 300)))
        old.stop()
    session = Session(device, app_dir)
    session.log_path = session.uri_file.with_suffix(".log")
    session.log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        session.uri_file.unlink()
    except FileNotFoundError:
        pass
    env = dict(ENV, AI_TESTING_APP_DIR=str(app_dir))
    extra = args.get("flutter_args") or []
    if isinstance(extra, str):
        extra = extra.split()
    logfile = open(session.log_path, "w")
    session.proc = subprocess.Popen(["bash", str(run_script()), device, *extra], cwd=app_dir,
                                    stdin=subprocess.PIPE, stdout=logfile, stderr=subprocess.STDOUT,
                                    text=True, env=env, start_new_session=True)
    SESSIONS[device] = session
    log(f"starting {app_dir.name} on {device} (log: {session.log_path})")
    return wait_for(session, int(args.get("wait_seconds", 300)))


def wait_for(session, seconds):
    deadline = time.time() + max(0, seconds)
    while True:
        if session.try_connect():
            return json.dumps(session.summary())
        if session.proc and session.proc.poll() is not None:
            raise ToolError(json.dumps(session.summary()))
        if time.time() > deadline:
            return json.dumps(dict(session.summary(), note="still starting: call app_status later"))
        time.sleep(2)


def t_attach(args):
    device = args.get("device") or ""
    if not device:
        raise ToolError("pass device")
    session = Session(device, app_dir_arg(args))
    if not session.try_connect():
        raise ToolError(f"no saved address {session.uri_file}: start the app with start_app or marionette-run.sh")
    SESSIONS[device] = session
    return json.dumps(session.summary())


def t_app_status(args):
    for session in SESSIONS.values():
        if session.state() == "starting":
            try:
                session.try_connect()
            except ToolError:
                pass
    return json.dumps([s.summary() for s in SESSIONS.values()], indent=1) if SESSIONS else "no apps started"


def t_stop_app(args):
    session = session_for(args)
    session.stop()
    SESSIONS.pop(session.device, None)
    return f"stopped the app on {session.device}"


def t_where_am_i(args):
    marionette = connected(session_for(args))
    if not marionette.namespace:
        listing = text_of(marionette.call("list_custom_extensions", {}))
        match = re.search(r"([\w-]+)\.whereAmI", listing)
        if not match:
            raise ToolError("the app registers no <ns>.whereAmI tool: is flutter-ai-testing installed in it?")
        marionette.namespace = match.group(1)
    result = marionette.call("call_custom_extension",
                             {"extension": f"{marionette.namespace}.whereAmI", "args": {}})
    body = text_of(result)
    if "{" not in body:
        raise ToolError(body or "whereAmI failed")
    answer = json.loads(body[body.index("{"):])
    for noise in ("type", "method", "status"):
        answer.pop(noise, None)
    return json.dumps(answer)


def run_key_script(name, args):
    app_dir = app_dir_arg(args)
    out = subprocess.run([sys.executable, "-I", str(key_script(name))], cwd=app_dir,
                         capture_output=True, text=True, timeout=300)
    text = (out.stdout + out.stderr).strip()
    if out.returncode:
        raise ToolError(text)
    return text


OWN_TOOLS = {
    "list_devices": (t_list_devices, "Android and iOS devices, emulators and simulators that can run the app.", {}),
    "start_app": (t_start_app,
                  "Build, install and launch the app's Marionette entrypoint on a device, grant OS permissions "
                  "and connect. Waits up to wait_seconds (default 300); the first build can take minutes. "
                  "Starting again on the same device and app just waits for it.",
                  {"app_dir": {"type": "string", "description": "Flutter app folder (default: the server's working directory)"},
                   "device": {"type": "string", "description": "Device id from list_devices"},
                   "wait_seconds": {"type": "integer", "description": "How long to wait for the app (default 300)"},
                   "flutter_args": {"type": "array", "items": {"type": "string"},
                                    "description": "Extra flutter run arguments"}}),
    "attach": (t_attach, "Connect to an app already started with marionette-run.sh (reads its saved address).",
               {"app_dir": {"type": "string"}, "device": {"type": "string"}}),
    "app_status": (t_app_status, "State of each started app: starting, running, exited, and a known problem if any. "
                   "Never returns log text.", {}),
    "stop_app": (t_stop_app, "Stop the app on a device.", {"device": {"type": "string"}}),
    "where_am_i": (t_where_am_i, "Read-only. Page stack by name, *_screen keys on screen (bottom page first), open "
                   "dialogs by type, loading, signed in, and app facts. Call it after every step.",
                   {"device": {"type": "string"}}),
    "check_keys": (lambda a: run_key_script("check_test_keys.py", a),
                   "Check the app's test keys (fails on keys that look like contact data).",
                   {"app_dir": {"type": "string"}}),
    "key_index": (lambda a: run_key_script("gen_test_key_index.py", a),
                  "Regenerate the app's test-key index (docs/test-keys.md by default).",
                  {"app_dir": {"type": "string"}}),
}

_passthrough = None


def passthrough_tools():
    """Marionette's own tools, read once from a throwaway marionette_mcp."""
    global _passthrough
    if _passthrough is None:
        try:
            probe = Marionette()
            tools = probe.request("tools/list", {})["tools"]
            probe.close()
        except ToolError as error:
            log(f"marionette tools unavailable: {error}")
            return []
        _passthrough = []
        for tool in tools:
            if tool["name"] in HIDDEN_TOOLS:
                continue
            schema = json.loads(json.dumps(tool.get("inputSchema") or {"type": "object"}))
            schema.setdefault("type", "object")
            schema.setdefault("properties", {})["device"] = {
                "type": "string", "description": "Device id; optional when one app is running"}
            _passthrough.append({"name": tool["name"], "description": tool.get("description", ""),
                                 "inputSchema": schema})
    return _passthrough


def list_tools():
    own = [{"name": name, "description": desc,
            "inputSchema": {"type": "object", "properties": props}}
           for name, (_, desc, props) in OWN_TOOLS.items()]
    return own + passthrough_tools()


def call_tool(name, args):
    if name in OWN_TOOLS:
        return {"content": [{"type": "text", "text": OWN_TOOLS[name][0](args)}]}
    if name in HIDDEN_TOOLS:
        raise ToolError(f"{name} is managed by this server: use start_app / attach")
    if name not in {t["name"] for t in passthrough_tools()}:
        raise ToolError(f"unknown tool {name}")
    session = session_for(args)
    forwarded = {k: v for k, v in args.items() if k != "device"}
    result = connected(session).call(name, forwarded)
    if name in ACTION_TOOLS and not result.get("isError"):
        # Wait for the screen to settle (whereAmI does) and report where the
        # action led, so the next step never races a page transition.
        try:
            after = t_where_am_i({"device": session.device})
            result = dict(result, content=list(result.get("content", [])) +
                          [{"type": "text", "text": "after: " + after}])
        except ToolError:
            pass
    return result


# ---------------------------------------------------------------- MCP loop

def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def handle(msg):
    method, msg_id, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if msg_id is None:
        return  # notification
    if method == "initialize":
        reply(msg_id, {"protocolVersion": params.get("protocolVersion", "2024-11-05"),
                       "capabilities": {"tools": {}},
                       "serverInfo": {"name": "flutter-ai-testing", "version": VERSION},
                       "instructions": INSTRUCTIONS})
    elif method == "ping":
        reply(msg_id, {})
    elif method == "tools/list":
        reply(msg_id, {"tools": list_tools()})
    elif method == "tools/call":
        try:
            reply(msg_id, call_tool(params.get("name"), params.get("arguments") or {}))
        except ToolError as error:
            reply(msg_id, {"content": [{"type": "text", "text": str(error)}], "isError": True})
        except Exception as error:  # keep the server alive
            log(f"{params.get('name')} failed: {error!r}")
            reply(msg_id, {"content": [{"type": "text", "text": f"internal error: {type(error).__name__}"}],
                           "isError": True})
    else:
        reply(msg_id, error={"code": -32601, "message": f"method not found: {method}"})


def main():
    try:
        for line in sys.stdin:
            line = line.strip()
            if line:
                handle(json.loads(line))
    finally:
        for session in list(SESSIONS.values()):
            if session.proc:  # apps this server started; attached ones keep running
                session.stop()


if __name__ == "__main__":
    main()
