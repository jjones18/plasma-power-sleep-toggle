# Plasma Power & Battery Sleep Toggle

A custom KDE Plasma 6 Power & Battery widget with separate sleep-inhibition modes and an optional automatic timeout.

The applet keeps the familiar Plasma power-profile interface while adding explicit controls for:

- blocking system sleep while still allowing normal display idle and screen locking;
- blocking system sleep and screen locking together;
- keeping either mode active indefinitely; or
- selecting a duration in minutes and returning to normal automatically when the countdown expires.

The Plasma applet ID is `org.kde.plasma.battery.sleepcustom`.

## Timer behavior

- `0` minutes is displayed as **Indefinitely**.
- The duration control supports values through one week (`10080` minutes).
- The `-` and `+` buttons use 15-minute steps, while the value remains directly editable.
- An active timed inhibition displays the remaining time.
- Changing the duration while inhibition is active restarts the countdown with the new duration.
- At expiration, the applet releases whichever manual inhibition mode is active.
- The selected duration is saved in the applet configuration. An active countdown is intentionally not restored after Plasma exits because its runtime D-Bus inhibitors are released at the same time.

## Relevant project paths

- `applets/batterymonitor_sleepcustom/` — custom applet QML, metadata, and configuration
- `applets/batterymonitor_sleepcustom/plugin/` — inhibition and power-profile backend
- `autotests/custom_widget_smoke_test.py` — focused source-level smoke test
- `scripts/install-user.sh` — user-local build/install helper with atomic shared-library replacement

The rest of the tree supplies the PowerDevil source and CMake context needed to build the derived applet.

## Build and test

Run the focused smoke test:

```bash
python3 autotests/custom_widget_smoke_test.py
```

Configure and build the custom targets:

```bash
cmake -S . -B build-custom-widget \
    -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo

cmake --build build-custom-widget \
    --target batterymonitor_sleepcustomplugin org.kde.plasma.battery.sleepcustom \
    -j"$(nproc)"
```

If KDE development dependencies are supplied through a local prefix, add the appropriate `CMAKE_PREFIX_PATH` during configuration. The development machine currently uses an ignored `.deps/prefix/usr` tree for this purpose.

Install the already-configured build into the current user's Plasma/Qt paths:

```bash
./scripts/install-user.sh
```

The installer uses atomic file replacement because overwriting a shared library in place while Plasma has it mapped can crash `plasmashell`. Restart `plasma-plasmashell.service` only when it is acceptable to release any active manual inhibition.

## Upstream provenance

This project is derived from KDE PowerDevil:

- Upstream source: <https://invent.kde.org/plasma/powerdevil>
- Base snapshot: `9dc03dfce3ce785f32f061414ef3cb380dfb402b`

This working repository intentionally has an independent Git history and no upstream remote. The upstream project is retained here as attribution and as a source reference, not as this repository's Git parent.

## Licensing

The imported KDE source, derived files, copyright notices, and SPDX identifiers retain their original licenses. See `COPYING`, `LICENSES/`, and the headers in individual source files.
