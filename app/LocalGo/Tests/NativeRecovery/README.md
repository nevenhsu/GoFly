# Native recovery regression

Run from the research workspace:

```sh
bash app/LocalGo/Tests/NativeRecovery/run.sh
```

The harness compiles the production `LiveLocationEngine.swift` and
`LocalGoPairingIdentity.swift` with fake JIT/native functions. It simulates a
cached identity tunnel dying during lock/network changes, a restored VPN
path, and failures that must prevent native clear. It checks that stop can
retry and startup can run again without reusing the dead identity tunnel.
It also counts connections to ensure normal position updates reuse the
dedicated identity tunnel and a stale connection rebuilds only once. Each
case runs in its own process to isolate the production static cache.

This does not exercise native tunnel allocation, DDI service connections, VPN routing, iOS lockscreen
behavior, or real location restoration. Validate those on an unplugged phone
after installation: set a location, lock/unlock, switch Wi-Fi/4G, stop, confirm
real location in another app, then start and set again. If VPN is Connected
but the local endpoint is unreachable, reconnect it before retrying stop.

Generated modules and executables are kept under `work/localgo-lock-recovery`.
