# NuimoBar

A macOS menu-bar app that puts the Senic Nuimo controller back to work. Senic's own Mac app is no longer available; this is an independent replacement and is not affiliated with Senic.

It connects to the Nuimo over Bluetooth LE and maps its inputs to actions on your Mac, with different mappings per app.

## What it does

**Inputs:** dial, press, long press, swipes, edge taps, edge holds, hand height above the device (hover), and waves.

**Actions:**

- System volume and mute, play/pause, next and previous track
- Mission Control, App Exposé, Show Desktop, switch Space
- Any keystroke, or scrolling
- Shell commands and Shortcuts
- Show an emoji on the Nuimo

**Per-app profiles:** a Default profile applies everywhere; add a profile for an app and it takes over while that app is frontmost.

**Display:** the 9×9 LED matrix shows feedback (a volume bar, media icons) and can show an emoji when a notification banner appears, with rules per app.

## Requirements

- macOS 14 or later
- A Nuimo controller (tested on hardware 1.4, firmware 2.5.0)
- Swift toolchain (Command Line Tools is enough; Xcode is not required)

## Build and run

```bash
./build.sh --run
```

This builds with Swift Package Manager and assembles `build/NuimoBar.app`. The script signs with a local identity named "ForgeShot Dev" if one exists and falls back to ad-hoc signing; with ad-hoc signing macOS asks for permissions again after each rebuild. Change the identity name in `build.sh` to one of your own to avoid that.

On first launch macOS asks for:

- **Bluetooth**, to talk to the Nuimo.
- **Accessibility** (from the menu-bar menu), to send media keys, keystrokes and scroll events, and to see notification banners. Volume control works without it.

The Nuimo does not pair in System Settings. Wake it by pressing it and the app finds it by name.

## Drawing on the display from scripts

While the app is running, `led.sh` can draw on the Nuimo:

```bash
./led.sh emoji 🔥 3     # show an emoji for 3 seconds
./led.sh flash 5        # flash every LED five times
./led.sh all 2          # light every LED for 2 seconds
./led.sh off
```

It also accepts a raw pattern: 81 characters, row by row, with `#` for a lit LED.

## Notes

- Mappings are stored in `~/Library/Application Support/NuimoBar/config.json`.
- Notification detection reads banners through Accessibility, because macOS has no public API for it. It only sees banners that actually appear, so notifications hidden by a Focus mode are not shown.
- Mission Control actions use a private macOS call and may stop working in a future macOS release.
- If hover is erratic, use **Calibrate Hover Sensor…** in the menu with nothing above the Nuimo.
- The Bluetooth protocol follows Senic's open-source [nuimo-swift](https://github.com/getsenic/nuimo-swift) SDK.

## Licence

MIT. See [LICENSE](LICENSE).
