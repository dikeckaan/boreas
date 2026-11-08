# Boreas

[English](README.md) · [Türkçe](README.tr.md)

Boreas is a free, open-source fan controller for Apple Silicon Macs. It lives in the menu bar, shows every fan and temperature sensor, and lets you either pin a fan to a fixed speed or drive it with a temperature curve you draw yourself. It has no telemetry, no account and no network access.

Boreas is an independent project: it is not affiliated with, and not derived from, Macs Fan Control.

Screenshots (coming): main window, menu bar panel, profile editor. They will live in `docs/screenshots/`.

<!-- TODO: docs/screenshots/main-window.png, docs/screenshots/menu-bar.png, docs/screenshots/profile-editor.png -->

## Requirements

- A Mac with Apple Silicon (arm64).
- macOS 15 or later.

## Install

1. Download `Boreas-<version>.dmg` from the [Releases page](https://github.com/dikeckaan/boreas/releases/latest) and open it. The app inside is signed with Developer ID and notarized by Apple.
2. Drag **Boreas** onto **Applications**, then open it from there.
3. Boreas needs a small root helper to write fan speeds. Press **Install Helper** on the welcome screen, then open **System Settings → General → Login Items & Extensions** and switch on **Boreas** under **Allow in the Background**. This approval is needed once; a small guide panel points to the switch.

Remove the helper any time from Boreas → Settings → **Remove**.

## Safety

Boreas never leaves a fan stuck in manual mode. These rules cannot be switched off. Hardware status as of 2026-11-08, on the notarized release build (details in [docs/manual-test-checklist.md](docs/manual-test-checklist.md)):

1. If the app quits, crashes or is killed, the helper puts all fans back on Automatic within a few seconds. *Verified on hardware: `kill -9` → Automatic in 3–4 s, Quit → Automatic in 1 s.*
2. Before sleep the fans go to Automatic; after wake the active profile is re-applied if the app is running. *Unit-tested; sleep/wake not yet verified on hardware.*
3. When the helper itself stops (SIGTERM, removal, update), fans go to Automatic. *Verified on hardware: SIGTERM → Automatic within 1 s.*
4. If a sensor cannot be read or reports a nonsense value (NaN, 0, above 150 °C), rules that depend on it are ignored; with no valid rule left, the fan returns to Automatic. *Unit-tested.*
5. A critical-temperature ceiling watches a fixed set of CPU and GPU safety sensors. If their 5-second average passes 100 °C, the fan goes to maximum whatever the profile says, until the average drops below 90 °C. You cannot hide these sensors from it. If neither these sensors nor a CPU/GPU fallback give a valid reading for more than 5 seconds, every fan under Boreas's control goes back to Automatic until they do; a helper that cannot load its sensor catalog refuses manual control altogether. *Unit-tested; not yet verified under real load.*
6. Fixed speeds are clamped to the fan's real minimum and maximum. *Unit-tested.*

Also verified on hardware: the helper exits by itself when idle, a relaunched app re-applies the profile, and the `boreasctl set` write gate returns the fan to Automatic. An unauthorized (ad-hoc signed) client is rejected by the helper — verified on hardware.

## Tested hardware

Tested on a **Mac mini (M6), macOS 27.2**.

**Community testing wanted:** other chips (M1 to M5, Pro/Max/Ultra) and MacBooks expose different SMC keys and sensors. If Boreas works, or does not, on your Mac, please open an issue with the output of `boreasctl fans` and `boreasctl sensors --raw`.

## Build from source

Requirements: Xcode 27 (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and an Apple Developer team (the helper is registered through `SMAppService`, which needs a signed build).

```sh
git clone https://github.com/dikeckaan/boreas.git
cd boreas
cp Config/Signing.xcconfig.example Config/Signing.xcconfig   # then edit
xcodegen generate
open Boreas.xcodeproj
```

`Config/Signing.xcconfig` is gitignored and contains your Team ID:

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Run the unit tests with `cd Packages/BoreasCore && swift test`. Build a release DMG with `scripts/release.sh <version>`. It notarizes with the `boreas-notary` notarytool keychain profile if you have one, otherwise through the Apple ID signed in to Xcode (no password needed). `--skip-notarize` makes a dry run; see the script header.

### Forking

The identifier `com.kaandikec` is baked in. A fork that ships its own build must replace it everywhere it appears, or its helper will collide with (or refuse) the original:

- `project.yml`: `bundleIdPrefix`, both `PRODUCT_BUNDLE_IDENTIFIER` values and the path of the launchd plist.
- `Helper/main.swift`: the app identifier in the client code-signing requirement (`identifier "com.kaandikec.boreas"`).
- `Packages/BoreasCore/Sources/BoreasCore/Helper/HelperXPC.swift`: `boreasHelperMachServiceName`.
- `Helper/com.kaandikec.boreas.helper.plist`: the file name, `Label`, the `MachServices` key and `AssociatedBundleIdentifiers`.
- `App/Services/HelperInstaller.swift`: `plistName` (must match the plist file name).
- `scripts/ExportOptions.plist`: `teamID` (your own Team ID).

## boreasctl

`boreasctl` is a command-line tool built from the same package, for debugging and hardware bring-up:

```sh
swift build --package-path Packages/BoreasCore                          # builds Packages/BoreasCore/.build/debug/boreasctl
swift run --package-path Packages/BoreasCore boreasctl fans          # fan table
swift run --package-path Packages/BoreasCore boreasctl sensors       # temperature sensors
swift run --package-path Packages/BoreasCore boreasctl sensors --raw # without the catalog: raw names and ids
swift run --package-path Packages/BoreasCore boreasctl keys TC       # SMC keys with a prefix
sudo Packages/BoreasCore/.build/debug/boreasctl set 0 3500 --hold 20   # drive fan 0 for 20 s, then back to Automatic
sudo Packages/BoreasCore/.build/debug/boreasctl auto                   # all fans to Automatic
```

Writing needs root. `set` always hands the fan back to Automatic when the hold expires or the process is interrupted.

## Contributing to the sensor catalog

Sensor names, groups and the safety set come from `Packages/BoreasCore/Sources/BoreasCore/Resources/sensor-catalog.json`. Each entry looks like:

```json
{
  "match": "hid:PMU tdie{n}",
  "nameEN": "CPU die {n}",
  "nameTR": "CPU kalıp {n}",
  "group": "cpu",
  "featured": false,
  "safety": false,
  "suspect": false,
  "hotspot": true
}
```

- `match` is `smc:<KEY>` or `hid:<product name>`; `{n}` captures a number and can be reused in the names.
- `group` is `cpu`, `gpu`, or another group listed in the catalog; `featured` shows the sensor by default.
- `safety` adds the sensor to the critical-temperature ceiling. Only verified CPU/GPU die sensors belong there; please attach readings under load.
- `suspect` marks keys whose meaning is not confirmed; `hotspot` marks per-core hotspots that group averages skip.

To add your Mac's sensors: run `boreasctl sensors --raw`, compare readings against load (idle and a CPU/GPU stress), add entries, run `swift test`, and open a pull request noting the model and macOS version.

## License

[MIT](LICENSE). Copyright (c) 2026 Abdurrahman Kaan Dikeç.
