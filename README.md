# MacOS Tiling

Free macOS window tiling manager — Windows 10/11 snap behavior via keyboard shortcuts and drag-to-snap. Alternative to Raycast Pro / Magnet.

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
| `⌥ ↓` | Move down / double-press to minimize |
| `⌥ ↑ + ⌥ →` | Top-right quarter |
| `⌥ ↑ + ⌥ ←` | Top-left quarter |

## Install

**Requirements:** macOS 13+, Swift (Xcode Command Line Tools)

```bash
git clone https://github.com/manoli101/MacOS-Tiling.git
cd MacOS-Tiling
bash Scripts/install.sh
```

Then grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility → enable MacOS Tiling). Permission is permanent — never asked again after this.

## Reinstall / Update

```bash
bash Scripts/install.sh
```

No need to re-grant permissions on the same Mac.

## Uninstall

```bash
bash Scripts/uninstall.sh
```
