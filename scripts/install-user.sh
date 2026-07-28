#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${BUILD_DIR:-"$root/build-custom-widget"}
applet_id=org.kde.plasma.battery.sleepcustom
qml_module_rel=org/kde/plasma/private/batterymonitor/sleepcustom
src_dir="$root/applets/batterymonitor_sleepcustom"
package_dir="$HOME/.local/share/plasma/plasmoids/$applet_id"

atomic_copy() {
    local src=$1
    local dst=$2
    local mode=${3:-644}
    local tmp

    mkdir -p "$(dirname "$dst")"
    tmp="${dst}.new.$$"
    cp "$src" "$tmp"
    chmod "$mode" "$tmp"
    mv -f "$tmp" "$dst"
}

cmake --build "$build_dir" \
    --target batterymonitor_sleepcustomplugin "$applet_id" \
    -j"$(nproc)"

built_applet="$build_dir/bin/plasma/applets/$applet_id.so"
built_qml_module="$build_dir/bin/$qml_module_rel"

# Use atomic replacements: overwriting a loaded .so in place can crash plasmashell.
for plugin_root in "$HOME/.local/lib/plugins" "$HOME/.local/lib/qt6/plugins"; do
    atomic_copy "$built_applet" "$plugin_root/plasma/applets/$applet_id.so" 755
done

for qml_root in "$HOME/.local/lib/qml" "$HOME/.local/lib/qt6/qml"; do
    for src in "$built_qml_module"/*; do
        atomic_copy "$src" "$qml_root/$qml_module_rel/$(basename "$src")" "$(stat -c '%a' "$src")"
    done
done

# plasma_add_applet supplies the binary plugin ID and warns if source metadata
# contains KPlugin.Id. KPackage registration still needs Id in its package copy,
# so add it only to the installed metadata.
mkdir -p "$package_dir"
metadata_tmp="$package_dir/metadata.json.new.$$"
python3 - "$src_dir/metadata.json" "$metadata_tmp" "$applet_id" <<'PY'
import json
import sys

source, destination, applet_id = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    metadata = json.load(handle)
metadata["KPlugin"]["Id"] = applet_id
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(metadata, handle, ensure_ascii=False, indent=4)
    handle.write("\n")
PY
chmod 644 "$metadata_tmp"
mv -f "$metadata_tmp" "$package_dir/metadata.json"

for src in "$src_dir"/*.qml; do
    atomic_copy "$src" "$package_dir/contents/ui/$(basename "$src")"
done
atomic_copy "$src_dir/main.xml" "$package_dir/contents/config/main.xml"

if ! kpackagetool6 --list --type Plasma/Applet | grep -Fqx "$applet_id"; then
    printf 'Error: %s was not registered as a Plasma applet\n' "$applet_id" >&2
    exit 1
fi

printf 'Installed %s successfully.\n' "$applet_id"
printf 'Restart plasma-plasmashell.service when it is safe to release any active manual inhibition.\n'
