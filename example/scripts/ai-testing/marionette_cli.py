#!/usr/bin/env python3
"""Small command-line client for marionette_mcp (flutter-ai-testing).

For scripts and for agents that can't load MCP servers. One session, a list
of tool calls:

    python3 marionette_cli.py <uri|device-id> '[["tap",{"key":"x"}], ...]'
    python3 marionette_cli.py <uri|device-id> where      # <ns>.whereAmI, as JSON
    python3 marionette_cli.py list                       # the tools and their args

A device id is looked up in .marionette/<device-id>.uri (written by
marionette-run.sh) in the current app. Screenshots are saved as shot_<n>.png
in the current directory; don't take them of pages that show personal data.
"""
import base64
import json
import os
import pathlib
import shutil
import subprocess
import sys


def tool_env():
    """PATH with the Dart SDK and pub's bin folder: marionette_mcp exits at
    start-up when it can't find `dart`."""
    env = dict(os.environ)
    extra = [os.path.expanduser("~/.pub-cache/bin")]
    if not shutil.which("dart"):
        def order(path):
            name = path.parent.name
            nums = [int(p) for p in name.split(".") if p.isdigit()]
            return (len(nums) == len(name.split(".")), nums)
        versions = sorted(pathlib.Path.home().glob("fvm/versions/*/bin"), key=order, reverse=True)
        extra += [str(v) for v in versions[:1]]
        if os.environ.get("FLUTTER_BIN"):
            extra.append(str(pathlib.Path(os.environ["FLUTTER_BIN"]).parent))
    env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
    return env


def server():
    env = tool_env()
    exe = shutil.which("marionette_mcp", path=env["PATH"]) or os.path.expanduser("~/.pub-cache/bin/marionette_mcp")
    return subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, env=env)


class Client:
    def __init__(self):
        self.p = server()
        self.n = 0
        self.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                 "clientInfo": {"name": "marionette_cli", "version": "1"}})
        self.call("notifications/initialized", notify=True)

    def call(self, method, params=None, notify=False):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        if not notify:
            self.n += 1
            msg["id"] = self.n
        self.p.stdin.write(json.dumps(msg) + "\n")
        self.p.stdin.flush()
        if notify:
            return None
        while True:
            line = self.p.stdout.readline()
            if not line:
                sys.exit("marionette_mcp closed")
            reply = json.loads(line)
            if reply.get("id") == self.n:
                return reply

    def tool(self, name, args):
        return self.call("tools/call", {"name": name, "arguments": args})

    def close(self):
        self.p.kill()


def resolve_uri(target):
    if target.startswith("ws://"):
        return target
    path = pathlib.Path.cwd()
    for folder in [path, *path.parents]:
        f = folder / ".marionette" / f"{target}.uri"
        if f.is_file():
            return f.read_text().strip()
    sys.exit(f"no .marionette/{target}.uri: start the app with marionette-run.sh first")


def namespace(client):
    text = "".join(c.get("text", "") for c in client.tool("list_custom_extensions", {})["result"]["content"])
    for word in text.split():
        if word.endswith(".whereAmI:"):
            return word[: -len(".whereAmI:")]
    sys.exit("the app registers no <ns>.whereAmI tool")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    client = Client()
    try:
        if sys.argv[1] == "list":
            for t in client.call("tools/list", {})["result"]["tools"]:
                props = ", ".join(t.get("inputSchema", {}).get("properties", {}))
                print(f"- {t['name']}({props}): {t.get('description', '')[:100]}")
            return
        client.tool("connect", {"uri": resolve_uri(sys.argv[1])})
        if len(sys.argv) > 2 and sys.argv[2] == "where":
            ns = namespace(client)
            text = client.tool("call_custom_extension", {"extension": f"{ns}.whereAmI", "args": {}})
            body = text["result"]["content"][0]["text"]
            answer = json.loads(body[body.index("{"):])
            for noise in ("type", "method", "status"):
                answer.pop(noise, None)
            print(json.dumps(answer))
            return
        shot = 0
        for name, args in json.loads(sys.argv[2]):
            reply = client.tool(name, args)
            print(f"## {name} {json.dumps(args)}")
            if "error" in reply:
                print("ERROR", reply["error"])
                continue
            for content in reply["result"].get("content", []):
                if content.get("type") == "text":
                    print(content["text"][:4000])
                elif content.get("type") == "image":
                    shot += 1
                    out = pathlib.Path.cwd() / f"shot_{shot}.png"
                    out.write_bytes(base64.b64decode(content["data"]))
                    print("saved", out)
    finally:
        client.close()


if __name__ == "__main__":
    main()
