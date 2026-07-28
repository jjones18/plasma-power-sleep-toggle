from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
APPLET_DIR = ROOT / 'applets' / 'batterymonitor_sleepcustom'
PLUGIN_DIR = APPLET_DIR / 'plugin'
APPLET_CMAKE = APPLET_DIR / 'CMakeLists.txt'

failures = []

for path in [
    APPLET_DIR / 'metadata.json',
    APPLET_CMAKE,
    APPLET_DIR / 'main.qml',
    APPLET_DIR / 'PopupDialog.qml',
    APPLET_DIR / 'InhibitionItem.qml',
    PLUGIN_DIR / 'inhibitmonitor_p.h',
    PLUGIN_DIR / 'inhibitmonitor_p.cpp',
    PLUGIN_DIR / 'inhibitioncontrol.h',
    PLUGIN_DIR / 'inhibitioncontrol.cpp',
]:
    if not path.exists():
        failures.append(f'missing file: {path.relative_to(ROOT)}')

if not failures:
    metadata = (APPLET_DIR / 'metadata.json').read_text()
    applet_cmake = APPLET_CMAKE.read_text()
    main_qml = (APPLET_DIR / 'main.qml').read_text()
    main_config = (APPLET_DIR / 'main.xml').read_text()
    popup_dialog = (APPLET_DIR / 'PopupDialog.qml').read_text()
    inhibition_item = (APPLET_DIR / 'InhibitionItem.qml').read_text()
    inhibit_header = (PLUGIN_DIR / 'inhibitmonitor_p.h').read_text()
    inhibit_cpp = (PLUGIN_DIR / 'inhibitmonitor_p.cpp').read_text()
    control_header = (PLUGIN_DIR / 'inhibitioncontrol.h').read_text()
    control_cpp = (PLUGIN_DIR / 'inhibitioncontrol.cpp').read_text()

    checks = [
        ('custom applet plugin id', 'org.kde.plasma.battery.sleepcustom' in applet_cmake),
        ('custom widget name', 'Power & Battery (Sleep Toggle)' in metadata),
        ('custom plugin import URI', 'org.kde.plasma.private.batterymonitor.sleepcustom' in main_qml),
        ('sleep-only switch label', 'Manually Block Sleep Only' in inhibition_item),
        ('full switch label preserved', 'Manually Block Sleep and Screen Locking' in inhibition_item),
        ('sleep-only backend method declaration', 'inhibitSleepOnly' in control_header),
        ('sleep-only backend method implementation', 'InhibitionControl::inhibitSleepOnly' in control_cpp),
        ('sleep-only monitor API', 'void inhibitSleepOnly' in inhibit_header),
        ('sleep-only monitor implementation', 'InhibitMonitor::inhibitSleepOnly' in inhibit_cpp),
        ('duration setting', 'inhibitionDurationMinutes' in main_config),
        ('runtime countdown timer', 'id: inhibitionCountdownTimer' in main_qml),
        ('timeout releases full inhibition', 'inhibitionChangeRequested(false)' in main_qml),
        ('timeout releases sleep-only inhibition', 'sleepOnlyInhibitionChangeRequested(false)' in main_qml),
        ('duration reaches popup', 'inhibitionRemainingSeconds: batterymonitor.inhibitionRemainingSeconds' in main_qml),
        ('duration reaches inhibition UI', 'inhibitionRemainingSeconds: dialog.inhibitionRemainingSeconds' in popup_dialog),
        ('indefinite duration UI', 'Indefinitely' in inhibition_item),
        ('remaining duration UI', 'Returns to normal in %1' in inhibition_item),
    ]
    for label, ok in checks:
        if not ok:
            failures.append(f'failed check: {label}')

if failures:
    print('FAIL')
    for item in failures:
        print(item)
    sys.exit(1)

print('PASS')
