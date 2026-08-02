# ThinkingCaps

A tiny macOS menu bar app that blinks your MacBook's built-in CapsLock LED
while [Claude Code](https://claude.com/claude-code) is thinking in the
terminal, and stops as soon as it's done. Your CapsLock key keeps working
normally the whole time.

## Install

1. Download the latest `ThinkingCaps.dmg` from the
   [Releases](../../releases) page.
2. Open the DMG and drag `ThinkingCaps.app` into `Applications`.
3. Because this app isn't signed with an Apple Developer certificate, the
   first time you open it macOS will refuse with an "unidentified developer"
   warning. To get past it: **right-click `ThinkingCaps.app` in
   `Applications` and choose "Open"**, then click "Open" again in the dialog
   that appears. You only need to do this once.
4. On first launch, ThinkingCaps shows a short **setup window**: controlling
   the CapsLock LED requires macOS's **Input Monitoring** permission. Click
   **Grant Permission** and enable ThinkingCaps in the System Settings list
   that opens. macOS may ask to quit and reopen the app — that's expected;
   setup continues automatically after the relaunch.

## Usage

- A CapsLock icon appears in your menu bar. There's no dock icon.
- **Left-click** the icon to turn ThinkingCaps on or off. The icon fills in
  when it's on.
- **Right-click** the icon for more options:
  - **Blink Caps Lock Light** — toggles blinking the CapsLock LED while
    Claude works (on by default).
  - **Blink Menu Bar Icon** — toggles blinking the menu bar icon itself
    (between its filled and outline look) while Claude works (off by
    default).
  - **Blink Speed** — a submenu to pick Slow, Normal, or Fast (Normal by
    default).
  - **Launch at Login** and **Quit ThinkingCaps**.
- The first time it runs, ThinkingCaps automatically adds two small hooks to
  `~/.claude/settings.json` so Claude Code can tell it when a request starts
  and finishes. It merges into your existing hooks — it won't remove
  anything you've already configured.

## How it works

When you send a prompt to `claude` in the terminal, a Claude Code hook
notifies ThinkingCaps over a local socket. ThinkingCaps then blinks the
CapsLock LED via IOKit until Claude Code reports it's finished. If more than
one terminal is running `claude` at once, the light keeps blinking until all
of them are done.

## Troubleshooting

If the LED never blinks, first re-check the Input Monitoring permission
(System Settings > Privacy & Security > Input Monitoring) — the setup window
reappears on launch whenever the permission is missing. If it's enabled and
the LED still doesn't blink, build and run the diagnostic tool from source:

```bash
git clone <this-repo-url>
cd thinkingcaps
swift run LEDSpike
```

It reports whether your keyboard exposes a controllable CapsLock LED, whether
Input Monitoring permission is available to it, and whether each LED write is
accepted (`ok`) or rejected (`FAILED`). `FAILED` toggles usually mean Input
Monitoring permission is missing for your terminal (the permission applies to
whatever app runs the command). Please open an issue with the full output and
mention whether the installed ThinkingCaps app's LED blinks for you.

Note for people building from source: rebuilding the app changes its ad-hoc
code signature, which makes macOS silently forget the Input Monitoring grant
for the previous build — the setup window will simply reappear; re-grant and
continue. DMG users are unaffected.

## Uninstalling

Quitting or deleting the app does not remove the hooks it added to
`~/.claude/settings.json`. If you want those gone too, open that file and
remove the `hook-notify` entries under `UserPromptSubmit` and `Stop`.

## License

MIT — see [LICENSE](LICENSE).
