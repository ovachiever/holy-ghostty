---
workflow: 2
manna: mn-d856ee
track: mn-eb7a80
source: 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
base_commit: b5ffc3a81634ed9f0e847b02457011b542096982
scope: '[P1][OPS][SSH] Host hygiene: retire the KeepAlive tmux LaunchAgent, raise Studio MaxSessions, repair MacBook multiplex config'
inputs:
- 'Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.'
binding: sha256:8062a04b1484926e36f670879b34b4e4d961a10a5999e1e53110c086b622e4b2
---

# Handoff: [P1][OPS][SSH] Host hygiene: retire the KeepAlive tmux LaunchAgent, raise Studio MaxSessions, repair MacBook multiplex config

Board state is canonical in `.manna/`. This file is the work order for one item only.

## Claim

```bash
agent-do manna claim mn-d856ee
```

## Scope

[P1][OPS][SSH] Host hygiene: retire the KeepAlive tmux LaunchAgent, raise Studio MaxSessions, repair MacBook multiplex config

## Inputs

- Kernel-panic/SSH-saturation joint diagnosis 2026-09-02 (forwarded MacBook agent analysis + Studio-side verification this session). Receipts: /System/Library/LaunchDaemons/ssh.plist inetdCompatibility.Instances=42 VERIFIED via plutil; panic-base+socd-2026-08-26-201523 panicString: zalloc zone map exhausted, zone data.kalloc.1024, 20G / 21,184,272 elements; Sep-1 file is the watchdog stub.

## Work order

Ops item; needs Erik or sudo at two points. (1) STUDIO: ~/Library/LaunchAgents/com.erik.tmux.plist (present, dated Mar 9) runs 'tmux start-server' with KeepAlive=true; the command exits immediately so launchd respawn-throttles it forever, it targets the default tmux server (not Holy's -L holy) so it protects nothing — bootout and remove, or convert to a one-shot; given the zone-leak suspicion, eliminating continuous spawn churn is prudent. (2) STUDIO (sudo): /etc/ssh/sshd_config raise MaxSessions to ~110 so multiplexed masters can carry ~100 channels each; do not touch the sealed ssh.plist. (3) MACBOOK (~/Documents/AI path, TCC constraints per house memory — work via a session ON that machine): ~/.ssh/config enables ControlMaster only for aliases studio/studio-lan while Holy stores the literal 'eriks-mac-studio-1', bypassing it; add a Host block covering the literal names (and MagicDNS variants) with ControlMaster auto, ControlPersist, and a ControlPath under a 0700 dir — belt-and-suspenders until the Holy transport manager (P0 sibling) makes client config irrelevant. Acceptance: LaunchAgent gone from launchctl, sshd_config change active (sshd -T shows maxsessions), MacBook config verified with 'ssh -O check' against the literal hostname.

## Completion

1. Produce the scoped deliverables and verification receipts.
2. Update this handoff only when continuation context changed.
3. Seal changes with `agent-do manna handoff seal mn-d856ee`.
4. Commit with `Manna: mn-d856ee` and run `agent-do manna done mn-d856ee` only after the work is verified.

## Result: complete on 2026-09-02

### Mac Studio LaunchAgent

- `com.erik.tmux` had recorded 9,528 launches and was in `spawn scheduled`
  state before removal.
- `launchctl bootout gui/501/com.erik.tmux` succeeded. A fresh
  `launchctl print` now reports the service absent.
- The source plist is absent from `~/Library/LaunchAgents`, so it cannot return
  at the next login.
- The plist, its SHA-256 receipt, the complete pre-removal `launchctl print`,
  and both zero-byte process logs are recoverable under
  `/Users/erik/Library/Application Support/Holy Ghostty/Host Guard/Archive/20260902T224236Z/`.
- Archived plist SHA-256:
  `cfe38bf9dda30541788abd2fa59f8554fdf97c10403f85f993631d2eb11dc45d`.

### Mac Studio SSH capacity

- `/etc/ssh/sshd_config.d/99-holy-ghostty-maxsessions.conf` now contains
  `MaxSessions 110` and is owned by `root:wheel` with mode `0644`.
- The privileged installer ran `sshd -t` and `sshd -T`; its durable receipt
  records `effective_maxsessions=110`.
- The installer did not restart SSH or edit either protected source. Current
  hashes match its before-state hashes:
  - `/etc/ssh/sshd_config`:
    `68280c4c16be7a2c0ed49b726cdbccf6eda43d0ac0f86f87a9b6c8372779989b`
  - `/System/Library/LaunchDaemons/ssh.plist`:
    `0ab04abd68787ca61d6192324aa093dbedb3edc9a57e202333ff2b6875804013`
- Root install receipt:
  `/Library/Logs/Holy Ghostty/kernel-zone-watch/install-receipt.txt`.

### MacBook multiplexing

- The MacBook `~/.ssh/config` shared-default block now covers
  `eriks-mac-studio-1` and `eriks-mac-studio-1.tail2b07fa.ts.net`, in addition
  to the existing aliases.
- Final config SHA-256:
  `56cf4b115efb09e285590d6661833bbc146e89d9561d603b76f6cf1d27509f4f`.
- Previous config archive:
  `/Users/erik/.ssh/archive/mn-d856ee-20260902T224201Z/config` on the MacBook.
- The config and control-socket directory are mode `0600` and `0700`.
- `ssh -G` resolves `ControlMaster auto`, `ControlPersist 600`, and the
  expected socket path for both literal names.
- A real connection to `eriks-mac-studio-1` left a multiplex master at
  `/Users/erik/.ssh/sockets/erik@eriks-mac-studio-1-22`; `ssh -O check`
  returned `Master running`.
