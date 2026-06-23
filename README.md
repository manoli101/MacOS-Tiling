# Tyler

Free macOS window tiling manager — Windows 10/11 snap behavior via keyboard shortcuts and drag-to-snap. Alternative to Raycast Pro / Magnet.

[![Download](https://img.shields.io/badge/Download-Tyler%20v1.1-blue?style=for-the-badge)](https://github.com/manoli101/MacOS-Tiling/releases/latest/download/Tyler-1.1.dmg)

## Features

- **Keyboard shortcuts** — `⌥ + Arrow` to snap windows
- **Drag to snap** — drag a window to any screen edge for a preview and auto-snap
- **Multi-monitor** — repeat `⌥→` / `⌥←` to move windows across monitors
- **Quarter snapping** — combine Up/Down with Left/Right to reach any quarter
- **Persistent permissions** — Accessibility permission granted once, never asked again

## Shortcuts

| Keys | Action |
|------|--------|
| `⌥ →` | Right half (repeat → next monitor) |
| `⌥ ←` | Left half (repeat → prev monitor) |
| `⌥ ↑` | Top half → then maximize |
| `⌥ ↓` | Center → restore → minimize |
| `⌥ ↑ + ⌥ →` | Top-right quarter |
| `⌥ ↑ + ⌥ ←` | Top-left quarter |

## Install

### Option A — DMG (easiest)

1. Download **Tyler-1.1.dmg** from the badge above
2. Open the DMG and drag **Tyler.app** to Applications
3. Open Tyler — macOS will block it (Gatekeeper warning)
4. Go to **System Settings → Privacy & Security** → scroll down → **"Open Anyway"**
5. Grant **Accessibility** when prompted → System Settings → Privacy & Security → Accessibility → enable Tyler

> **Why the warning?** Tyler is open source and unsigned by Apple (notarization costs $99/year). You can review all the code in this repo before running it.

### Option B — Build from source (permissions persist across updates)

**Requirements:** macOS 13+, Swift (Xcode Command Line Tools)

```bash
git clone https://github.com/manoli101/MacOS-Tiling.git
cd MacOS-Tiling
bash Scripts/install.sh
```

Grant Accessibility permission once — it is remembered permanently across reinstalls.

## Reinstall / Update

```bash
bash Scripts/install.sh
```

No need to re-grant permissions on the same Mac.

## Uninstall

```bash
bash Scripts/uninstall.sh
```

## Support

If Tyler saves you time, consider [buying me a coffee ☕](https://github.com/sponsors/manoli101)
