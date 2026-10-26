# maiden and the REPL websockets: reproduced exposure, and the fix (Phase 4)

Reproduced headless on this container (Linux, no norns running: `ws-wrapper` around `cat` stands in for the REPL, and the
`maiden` built by `linux/maiden-build.sh`). The test is `linux/tests/maiden_test.sh`; the real-browser run is
`docs/port/repro/maiden_exposure.js` (Chromium of Playwright, build 1194).

## Before the fix (stock behavior; the Mac port is the same)

`linux/tests/maiden_test.sh`, failures only (10 of 27 checks), full output `docs/port/known-issues-logs/maiden-before.txt`:

```
FAIL  another website is refused: got 'echo=ping-from-test ', want 'closed '
FAIL  another port on 127.0.0.1 is refused: got 'echo=ping-from-test ', want 'closed '
FAIL  origin 'null' (a file:// page, a sandboxed iframe) is refused: got 'echo=ping-from-test ', want 'closed '
FAIL  page on another site: POST install is refused: got '201', want '403'
FAIL  nothing was installed by it: got 'note.lua victim ', want 'note.lua '
FAIL  page on another site: GET of dust is refused: got '200', want '403'
FAIL  rebinding: Host evil.example is refused: got '200', want '403'
FAIL  rebinding: a wrong port in Host is refused: got '200', want '403'
FAIL  unit status is not served: got '503', want '404'
FAIL  unit restart is not served: got '503', want '404'
```

- A WebSocket handshake to the REPL port with `Origin: http://evil.example` (what a browser sends from any web page) is accepted and the
  text the "page" sends is read by the child process. With norns that is Lua (`os.execute`) or SuperCollider code, as the user.
- In a **real browser**: a page on `http://evil.example` opens `ws://127.0.0.1:<REPL port>` and gets an answer
  (`"ws": "open, REPL answered: ..."`).
- maiden answers a POST that carries `Origin: http://evil.example` and installs the script (`201`), reads dust for any `Host`.
- **Not reproduced in the browser:** the cross-site POST. Chromium 1194 refused to send it (`Failed to fetch`, probably its private network
  access rule for requests from a public site to the loopback); that is a browser behavior, not a protection of maiden: `curl` with the same headers is
  answered, and Firefox and Safari were not tried here.

## After the fix

- `ws-wrapper` (opt-in by `WS_WRAPPER_ALLOWED_ORIGINS`, unset on the Mac, so the Mac behaves as before): a connection whose `Origin` is not in the list is closed before anything is read from it
  or sent to it. Connections without an `Origin` header (`maiden-repl`, scripts) are kept. Real browser: `"ws": "open, then closed by the server"`.
- maiden (`linux/patches/maiden-linux-guard-and-units.patch`, applied after the Mac's host-flag patch which it does not change): when it listens on the loopback only, a request whose `Host` is not `127.0.0.1:<port>`,
  `localhost:<port>` or `[::1]:<port>`, or whose `Origin` is present and is not one of those, gets `403`.
- `linux/tests/maiden_test.sh`: 27 of 27 pass (`known-issues-logs/maiden-after.txt`). maiden's own page in the browser still connects to its REPL port with the list set (checked with Chromium: the websocket to `:5555` stays open).

## Limits

- A program running as the user on the same machine is not stopped by any of this: it can connect without an `Origin` header. That is the same as on the device.
- The check is on `Origin`, which browsers set and a page cannot change. It does not help against a browser that does not send it (none of the current ones).
