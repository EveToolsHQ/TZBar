# TZBar

[![Swift](https://img.shields.io/badge/Swift-f54a2a?logo=swift&logoColor=white&style=flat-square)](#) [![macOS](https://img.shields.io/badge/macOS-black?logo=apple&style=flat-square)](#)

A native macOS menu bar app for world clocks. Add time zones, name them, pin favorites to the bar, and check times at a glance.

**[Download TZBar](https://evetools.app/en/tzbar)**

## Features

- **Menu bar clocks:** Open the globe (or a pinned clock) to see all your zones in one menu
- **Pin to menu bar:** Show emoji and live time for any clock directly in the bar
- **Time scrubber:** Drag to preview times across all zones for another moment today (great for meetings and "are they awake yet?")
- **City search:** Add places by name, the app resolves the time zone for you
- **Custom labels & emoji:** Rename clocks ("Tokyo office", "Mom") and pick flags or emoji
- **Day phase icons:** Optional sun/moon hints for morning, day, evening, and night
- **Launch at login:** Optional, off by default

## Built for efficiency

TZBar is a menu bar utility, not a background service.

- **Icon-only mode:** no timers, no periodic work-idle CPU and memory stay negligible while the menu is closed
- **Pinned mode:** clocks update on each local minute boundary only (`:00`), not on a fast poll loop
- Native **AppKit**, no sync stack, no widgets, just clocks when you need them

Requires **macOS 15** or later.

## Use cases

- Coordinating with remote teams across time zones
- Scheduling international calls without mental math
- Tracking home time while traveling
- Staying in touch with family and friends abroad

## Build from source

```bash
make run      # debug build and launch
make build    # release TZBar.app bundle
```

## License

This project uses the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use and modify the software for noncommercial purposes.
