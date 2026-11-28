#!/bin/sh
set -eu
question='Удалите FXT Team New Tab в chrome://extensions во всех профилях Chrome. Удалить локальные файлы и расписание автообновлений?'
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null; then
    zenity --question --default-cancel --text="$question" || exit 0
else
    printf '%s [y/N] ' "$question"
    read -r answer || exit 0
    case "$answer" in y|Y) ;; *) exit 0;; esac
fi
python3 - <<'PY'
import fcntl
import json
import os
import subprocess
from pathlib import Path

root = Path.home() / ".local/share/fxtteam-new-tab"
if root.is_symlink():
    raise SystemExit("Unexpected installation link")
if not root.exists():
    raise SystemExit("Папка установки отсутствует.")
for name in ("extension", "extension/icons", "update", ".fxt-lock"):
    if (root / name).is_symlink():
        raise SystemExit("Unexpected link: " + name)
manifest = root / "extension/manifest.json"
if json.loads(manifest.read_text())["name"] != "FXT Team New Tab":
    raise SystemExit("Unexpected installation folder")
units = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "systemd/user"
timer = units / "fxtteam-chrome-update.timer"
service = units / "fxtteam-chrome-update.service"
lockfile = root / ".fxt-lock"
with lockfile.open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    if timer.exists() or service.exists():
        updater = str(root / "update/linux.py")
        escaped = updater.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%").replace("$", "$$")
        if not service.exists() or '"' + escaped + '" check' not in service.read_text():
            raise SystemExit("Update service points to another installation")
        if timer.exists():
            subprocess.run(["systemctl", "--user", "disable", "--now", timer.name], check=True)
        for path in (timer, service):
            path.unlink(missing_ok=True)
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    host = units.parent.parent / "google-chrome/NativeMessagingHosts/ru.fxtteam.newtab_update.json"
    if host.exists() and json.loads(host.read_text())["path"] == str(root / "update/linux.py"):
        host.unlink()
    files = ["extension/popup.html", "extension/popup.js", "extension/manual-update.js", "extension/installed.js",
             "update/native.cmd", "update/setup.ps1", "update/open-extensions.ps1", "update/install-help.html", "extension/newtab.html", "extension/newtab.js", "update/linux.py", "update/windows.ps1",
             "update/allowed_signers", "update/repository.txt", "README.md", "extension/manifest.json"]
    files.extend(f"extension/icons/icon{size}.png" for size in (16, 32, 48, 128))
    for name in files:
        (root / name).unlink(missing_ok=True)
lockfile.unlink()
for directory in (root / "extension/icons", root / "extension", root / "update", root):
    if directory.is_dir() and not any(directory.iterdir()):
        directory.rmdir()
print("FXT Team New Tab удалено. Посторонние файлы, если они были, сохранены.")
PY
