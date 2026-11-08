# Manual test checklist

Run these on a real Mac before a release. Each line is one step and its expected result.
Legend: ✅ passed (date), ☐ not yet verified on hardware.
Never run these on a Mac whose fans you cannot watch. In every case the fan must end up on Automatic.

## Already verified

- ✅ 2026-11-08 Task 2 gate: `sudo boreasctl set 0 3500 --hold 20` → the fan reaches about 3500 rpm and returns to Automatic when the hold expires.
- ✅ 2026-11-08 Task 2 gate: Ctrl-C during `boreasctl set` → fan 0 reports Automatic afterwards.
- ✅ 2026-11-08 `kill -9` the app while a profile drives the fan → fan returns to Automatic within 3 s.
- ✅ 2026-11-08 Quit Boreas (menu bar → Quit, or AppleScript quit) → fan returns to Automatic within 1 s.
- ✅ 2026-11-08 After the app disconnects, the helper exits by itself (idle exit) within about 10 s.
- ✅ 2026-11-08 Relaunch the app → the helper starts on demand and the active profile is re-applied within 2 s.
- ✅ 2026-11-08 Install → status "requires approval" → approve "Allow in the Background" → status becomes enabled.

## Safety rules (spec section 7)

- ☐ Rule 2: put the Mac to sleep with a profile active → fans are on Automatic while asleep; after wake the profile is re-applied (app connected).
- ☐ Rule 2: wake the Mac with the app quit → fans stay on Automatic.
- ✅ 2026-11-08 Rule 3: `sudo launchctl kill TERM system/com.kaandikec.boreas.helper` while Boreas drives the fan → fan returns to Automatic. (Result: fixed 4900 rpm → `otomatik` at t+1 s; because the app was still open it relaunched the helper and re-applied the setting at t+2 s.)
- ☐ Rule 3: Remove the helper from Settings while a profile is active → fan returns to Automatic before the helper is unregistered.
- ☐ Rule 4: quit Boreas, edit `~/Library/Application Support/Boreas/settings.json` so the only rule of a custom profile reads `"source":{"kind":"sensor","value":"smc:ZZZZ"}` (a sensor this Mac does not have), relaunch, make that profile active with the fan on Profile → within 2 s the fan is on Automatic (`boreasctl fans` agrees) and the editor shows the rule's source as "(missing) smc:ZZZZ".
- ☐ Rule 5: with the fan on a low fixed speed under heavy CPU+GPU load, the safety-sensor average passes 100 °C → fan goes to max, and returns to the profile once the average is below 90 °C.
- ☐ Rule 6: set a fixed speed outside the fan's range (drag the slider to both ends) → the value is clamped to the fan's real min–max.
- ✅ 2026-11-08 Authorization: run an ad-hoc-signed test client (different identity than Boreas) that connects to the helper's Mach service → the connection is rejected; the fan state is unchanged. (Result: "Couldn't communicate with a helper application"; fan stayed Automatic.)

## Install and service

- ☐ Close every window but leave the app running → the profile keeps driving the fan (the loop lives in the helper).
- ☐ Single instance: with Boreas running, launch a second copy (`open -n /Applications/Boreas.app`) → the second copy quits at once, the first stays in control and the fan state does not change.
- ☐ First launch from the DMG-installed copy in /Applications → welcome screen explains the one-time "Allow in the Background" step.
- ☐ Approval guide panel: on a Turkish macOS, the floating guide appears beside System Settings (not on top of the toggle) and closes itself once the helper is enabled.
- ☐ Approval guide panel: on an English macOS, same placement and auto-close.
- ☐ Run the app from outside /Applications → onboarding shows the "Move Boreas to Applications" hint before Install.
- ☐ Remove (Settings) → fans return to Automatic, the helper disappears from Login Items, status shows not installed.
- ☐ Remove Anyway (a hung or unreachable helper) → the helper is unregistered even though the reset call fails.
- ☐ Reinstall → the helper is replaced and registered again; if approval is required again, the guide panel shows.
- ☐ Upgrade: install a newer build over an older one → the helper is re-registered and reports the new version.
- ☐ Launch at login: turn it on in Settings, log out and in → Boreas starts in the menu bar; turn it off → it does not start.
- ☐ Fresh settings: delete `~/Library/Application Support/Boreas/settings.json`, launch → defaults, no crash.
- ☐ Corrupt settings: write garbage into `settings.json`, launch → defaults, and the broken file is kept as `settings.broken-<date>.json`.

## Fan and sensors

- ☐ Fans table: actual, min, max and mode match `boreasctl fans`.
- ☐ Automatic → Fixed → Automatic from the menu bar panel → the fan follows and ends on Automatic.
- ☐ Fixed speed slider in the main window → the fan reaches the requested rpm within a few seconds.
- ☐ Selecting each built-in profile (Silent, Performance) → the fan speed follows the curve under load.
- ☐ A Mac with no fans (MacBook Air): the app shows only sensors, does not offer service installation, does not crash.
- ☐ Sensors: hide, star and rename a sensor → the choice survives a restart; the active profile keeps working.

## Profile editor

- ☐ °C: drag a curve point → the point follows the pointer and stays between its neighbours.
- ☐ °C: double-click empty chart space → a point is added there.
- ☐ °C: right-click a point → it is removed (the last two points cannot be removed).
- ☐ °F: the same three gestures (drag, double-click add, right-click remove) work, and the axis and point labels read in °F; the saved curve is unchanged when switched back to °C.
- ☐ Duplicate a built-in profile → a draft opens in the editor and is only saved on Save; a duplicate name is rejected.
- ☐ Editing a sensor-source rule whose sensor is missing → shows "(missing) <id>" and stays editable.

## Turkish UI

- ☐ Menu bar panel in Turkish: no label is cut off or overlaps (fan names, mode picker, profile names, buttons).
- ☐ Settings in Turkish: all rows and buttons fit; long explanations wrap instead of truncating.
- ☐ Main window in Turkish: the sidebar, fans table and sensors list fit at the minimum window width.
- ☐ Profile editor in Turkish: toolbar, rule rows and hysteresis/smoothing labels fit.
- ☐ Switch the system language back to English → no leftover Turkish strings.

## Release package

- ✅ 2026-11-08 Release gate: install from the exported DMG build (not Debug), Install Helper, approve, run a profile, `kill -9` the app → Automatic; Quit → Automatic. (Result: Performance ~2300 rpm; kill -9 → Automatic in 4 s; Quit → Automatic in 1 s. After switching from a Debug-signed install, launchd kept a Development launch constraint; the app detected the unreachable helper and re-registered it once automatically.)
- ✅ 2026-11-08 Notarization: the v0.1.0 app was notarized through the Xcode account; a quarantined copy taken from the DMG is accepted by Gatekeeper (`source=Notarized Developer ID`).

- ☐ `scripts/release.sh <version>` (with notary credentials) finishes; the Gatekeeper check on a quarantined copy of the app taken from the DMG reports `accepted` (`spctl -a -vv -t exec`).
- ☐ Only when the build machine has a local Developer ID Application identity: the DMG is signed, notarized and stapled, and `spctl -a -vv -t install Boreas-<version>.dmg` reports `accepted`. Without that identity the DMG is intentionally unsigned and carries the notarized, stapled app.
- ☐ Download the DMG (quarantine flag set), open it → the window shows the aurora background, Boreas.app on the left and the Applications shortcut on the right.
- ☐ Drag Boreas to Applications and launch it → opens without a Gatekeeper prompt.
