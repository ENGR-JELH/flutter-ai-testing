#!/usr/bin/env python3
"""Evaluates one Dart expression in the running debug app (flutter-ai-testing).

For diagnosing app state the screen doesn't show, such as a navigation guard's
contents. Read the value only: never evaluate code that changes state, and
never print personal data.

    python3 -I vmeval.py <ws uri> <library uri suffix> <expression> [<expression on result>]

The library is the one whose URI ends with the suffix, for example
`components/navigation_utils_animated.dart`. Private members of that library
are visible. The optional second expression runs on the object the first one
returns, which reaches that object's private fields.

Needs the `websockets` package (pip install websockets).
"""
import asyncio
import json
import sys

import websockets


async def main(uri, lib_suffix, expr, expr2):
    async with websockets.connect(uri, max_size=None) as ws:
        n = 0

        async def call(method, **params):
            nonlocal n
            n += 1
            await ws.send(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params}))
            while True:
                reply = json.loads(await ws.recv())
                if reply.get("id") == n:
                    return reply

        vm = (await call("getVM"))["result"]
        for isolate in vm["isolates"]:
            info = (await call("getIsolate", isolateId=isolate["id"]))["result"]
            libs = [lib for lib in info.get("libraries", []) if lib["uri"].endswith(lib_suffix)]
            if not libs:
                continue
            reply = await call("evaluate", isolateId=isolate["id"], targetId=libs[0]["id"], expression=expr)
            result = reply.get("result", reply.get("error"))
            if expr2 and result.get("id"):
                reply = await call("evaluate", isolateId=isolate["id"], targetId=result["id"], expression=expr2)
                result = reply.get("result", reply.get("error"))
            print(result.get("valueAsString") or result.get("message") or json.dumps(result)[:300])
            return
        print("library not found")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    asyncio.run(main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None))
