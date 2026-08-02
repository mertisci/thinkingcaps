# ThinkingCaps — Design Doc

Date: 2026-08-01

## Purpose

While `claude` (Claude Code) is processing a request in the terminal, the MacBook's
built-in CapsLock LED blinks. When it finishes, the LED returns to its normal state
(reflecting the actual CapsLock on/off state). The physical CapsLock key keeps its
normal function throughout — pressing it still toggles uppercase typing exactly as
before; we never touch that behavior.

ThinkingCaps ships as a lightweight macOS menu bar app, distributed as a DMG and
published on GitHub as a public, MIT-licensed repo. All project files (docs, code,
UI strings, README) are in English so it's usable by anyone who finds it, not just
the author.

## Non-goals

- No Windows/Linux support.
- No integration with tools other than Claude Code (Cursor, Copilot, etc.) — v1.
- No code signing / Apple notarization — v1 ships unsigned; README explains how to
  bypass the Gatekeeper warning (right-click > Open).
- No guaranteed support for external (USB/Bluetooth) keyboards — target is the
  built-in MacBook keyboard.
- No GitHub Actions release automation — v1 DMG is built and uploaded manually.
- No dropdown menu on left-click, and no in-app UI for uninstalling the Claude Code
  hook — see "Known limitations" below.

## Architecture

Three parts:

1. **Claude Code hook integration** — On first launch, the app automatically adds
   `UserPromptSubmit` and `Stop` hooks to `~/.claude/settings.json`. The installer
   merges into any existing hooks array rather than overwriting it, so it won't
   clobber hooks the user already configured for other purposes.
2. **ThinkingCaps.app** — A Swift + AppKit menu bar app (`NSStatusItem`). Contains:
   - A local unix socket server (listens for hook messages)
   - CapsLock LED control logic (IOKit HID)
   - A counter of active "thinking" sessions (see "Data Flow")
   - An enabled/disabled flag toggled by clicking the icon
3. **Local socket communication** — When a hook fires, Claude Code runs a short-lived
   shell command that writes `start <session_id>` or `stop <session_id>` to a unix
   socket via `nc -U`. Socket path: `~/Library/Application Support/ThinkingCaps/ctl.sock`.
   If the app isn't running, the write silently fails — the hook always exits 0 and
   never blocks or breaks Claude Code's normal flow.

## First-Run Onboarding (added 2026-08-02)

ThinkingCaps needs macOS **Input Monitoring** permission to control the CapsLock
LED (confirmed during implementation: without it, HID device elements are
invisible to the app and LED writes are impossible). A small native setup
window — all UI text in English — guides the user through this:

- **Launch decision** (pure, unit-testable logic):
  - Permission missing → show the **Permission screen** (always, including when
    the user revoked the permission later).
  - Permission granted but onboarding never completed → show the **Success
    screen** once.
  - Otherwise → no window at all; the app goes straight to its menu bar
    steady state.
- **Permission screen:** explains in one short paragraph why Input Monitoring
  is needed; a **Grant Permission** button triggers the system permission
  request AND deep-links to System Settings > Privacy & Security > Input
  Monitoring; a live status line polls the permission every second and the
  window advances to the Success screen automatically when it's granted. A
  note warns that macOS may quit and reopen the app when the checkbox is
  toggled — setup resumes automatically after the relaunch (completion state
  lives in `UserDefaults`, so the relaunched app knows to show the Success
  screen).
- **Success screen:** "You're all set!" plus a 3-line usage summary (LED
  blinks while Claude Code is thinking; left-click the icon to toggle On/Off;
  right-click for Launch at Login and Quit) and a note that the Claude Code
  hooks were installed automatically. A **Done** button (or closing the
  window) marks onboarding complete.
- The menu bar icon is present the entire time — the wizard never blocks the
  app's normal functions.

Components: `OnboardingFlow.initialScreen(permissionGranted:hasCompletedOnboarding:)
-> OnboardingScreen?` (pure logic), `InputMonitoringPermission`
(`IOHIDCheckAccess`/`IOHIDRequestAccess` wrapper), `OnboardingWindowController`
(programmatic AppKit window with two swappable content views).

## Menu Bar Interaction

- **Left-click** the icon: toggles ThinkingCaps **On**/**Off**. This is the only
  purpose of a left-click — there is no dropdown menu.
  - **On**: the app is armed. Incoming start/stop signals from Claude Code trigger
    LED blinking as described in "Data Flow".
  - **Off**: the app ignores incoming signals entirely. No blinking happens, and the
    LED simply reflects the real CapsLock state.
  - The icon itself visually differs between On and Off (e.g. filled vs. outline)
    so the state is clear at a glance. It does not itself animate/blink while a
    thinking session is active — only the physical LED does that, keeping the icon
    simple (two states, not three).
- **Right-click** the icon: opens a minimal context menu with exactly these items:
  - **Blink Caps Lock Light** (checkbox, default ON) — whether the physical
    CapsLock LED blinks during thinking sessions
  - **Blink Menu Bar Icon** (checkbox, default OFF) — whether the menu bar
    icon itself blinks during thinking sessions, alternating between the
    filled and outline CapsLock symbols each tick
  - **Blink Speed** (submenu, radio group): **Slow** (0.8s per toggle),
    **Normal** (0.45s, default), **Fast** (0.25s)
  - (separator)
  - **Launch at Login** (checkbox, toggled via `SMAppService`)
  - **Quit ThinkingCaps**

## Blink Outputs (added 2026-08-02)

The blink signal fans out to two independent outputs, each toggleable from the
right-click menu and persisted in `UserDefaults`:

- **Caps Lock LED** (default enabled) — the original behavior.
- **Menu bar icon** (default disabled) — the icon alternates between the
  filled (`capslock.fill`) and outline (`capslock`) symbols at the same
  cadence as the LED (changed 2026-08-02 from the original
  disappear/reappear style, per user feedback).

Users may enable either, both, or neither. Turning an output off mid-blink
immediately restores that output's resting state (LED back to the real
CapsLock state; icon back to the normal On/Off image), so nothing is left
frozen on a lit frame. The master left-click On/Off toggle is unchanged and
sits above both outputs (Off = no signals processed at all).

**Blink speed** (added later 2026-08-02): a "Blink Speed" submenu offers Slow
(0.8s per toggle), Normal (0.45s, default), and Fast (0.25s). The chosen speed
applies to both outputs, persists in `UserDefaults`, and takes effect
immediately — including mid-session (the running blink timer is rescheduled
live). Additionally, on normal quit the app stops any active blink session
and restores both outputs' resting states before exiting, so quitting
mid-blink can't leave the LED frozen on.

## Data Flow

1. User sends a request to `claude` in the terminal.
2. Claude Code fires the `UserPromptSubmit` hook → hook writes `start <session_id>`
   to the socket.
3. ThinkingCaps adds `session_id` to its set of active sessions (only takes effect
   if the app is currently **On**). If the set went from empty to non-empty, it
   starts the LED blink loop (~400–500ms toggle interval).
4. Claude Code finishes and fires the `Stop` hook → hook writes `stop <session_id>`
   to the socket.
5. ThinkingCaps removes `session_id` from the set. If the set is now empty, it stops
   blinking and leaves the LED reflecting the real CapsLock state.

If multiple terminal windows are running `claude` concurrently, blinking continues
until every session has stopped (i.e. the set is empty).

## Error Handling & Edge Cases

- **Interrupted session** (Ctrl+C, crash, etc.): the `Stop` hook may never fire.
  Each `session_id` is stored with a timestamp; if no `stop` arrives within 10
  minutes, the session is auto-expired from the set (prevents blinking forever).
- **Hook message while the app isn't running**: `nc -U` fails to connect; the hook
  still exits 0 — Claude Code is never blocked or slowed down.
- **App is Off when a hook message arrives**: message is received but ignored; no
  state change, no blinking.
- **Existing hooks already in `~/.claude/settings.json`**: the installer must merge
  into the existing hooks array/structure, not overwrite it.
- **Sleep/wake**: on wake, the app re-evaluates its session set and LED state from
  scratch (assumption: `Stop` already fired before sleep in the common case; the
  10-minute timeout is the backstop otherwise).
- **App relaunched**: the socket file is recreated; any previous session set is
  lost (acceptable — this is a non-critical visual feature).

## Known Limitations (v1)

- Quitting the app or fully uninstalling it does **not** remove the hook lines from
  `~/.claude/settings.json` automatically. If the app isn't running, those hooks are
  harmless no-ops (see error handling above), but a user who wants a truly clean
  uninstall must remove the lines by hand. Automatic uninstall may be added later.
- Rebuilding the app from source invalidates the ad-hoc code signature's identity,
  which silently invalidates any previously granted Input Monitoring permission for
  normally-launched (LaunchServices) instances — the onboarding wizard simply
  reappears and the user re-grants. End users installing from the DMG are
  unaffected (no rebuilds).
- The LED targeting is filtered to the built-in keyboard (product name containing
  "Internal Keyboard"); external keyboards' CapsLock LEDs are deliberately not
  driven, and a hypothetical future Mac whose internal keyboard reports a
  different product name would silently fall back to no-op (no crash).

## Packaging & Distribution

1. **Step 0 — Technical spike:** Before writing the real app, build a minimal
   command-line test program using the IOKit HID Manager to locate the built-in
   keyboard's CapsLock LED element and toggle it directly. This validates:
   - Does the LED visibly blink?
   - Does this affect the real CapsLock modifier (typing) state? (It must not.)
   - Is any special permission (e.g. Input Monitoring) required?
   - **Fallback if this fails:** blink the menu bar icon itself instead of the LED,
     driven by the same start/stop signal.
2. Set up an Xcode project (Swift + AppKit, minimal menu bar app).
3. Build the `.app` and package it into a simple "drag to Applications" **DMG**
   (via `hdiutil`, run manually).
4. **Public GitHub repo**: README (install steps + how to bypass the Gatekeeper
   warning: right-click > Open), MIT LICENSE.
5. "Launch at Login" is managed via macOS's modern `ServiceManagement`
   (`SMAppService`) API, toggled from the right-click menu — no manually installed
   LaunchAgent plist.

## Test Plan

This is a visual/hardware feature, so verification is manual rather than automated:

- Confirm via the Step 0 spike that LED control works and doesn't affect real
  CapsLock typing behavior.
- With the app running and On, send a real `claude` request in the terminal and
  observe the LED blinking, then stopping when the request finishes.
- Run `claude` in two terminal windows at once; confirm blinking continues after
  one finishes as long as the other is still active.
- Toggle the app to Off, run a `claude` request, confirm no blinking occurs.
- Run `claude` while the app isn't running at all; confirm no errors or delays.
- Quit and relaunch the app; confirm it comes back up cleanly and hooks still work.

## Open Risks

- **Biggest risk:** Apple's changes to internal keyboard/CapsLock LED management in
  recent macOS/hardware generations may make direct user-space LED control
  unreliable on the built-in MacBook keyboard. This is tested first via the Step 0
  spike; if it fails, the app falls back to blinking the menu bar icon instead.
