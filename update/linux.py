#!/usr/bin/env python3
"""Manage opt-in FXT Chrome updates for the current Linux user."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import struct
import tempfile
from contextlib import redirect_stdout
from pathlib import Path
from urllib.request import urlopen
from urllib.error import HTTPError, URLError
from zipfile import ZipFile

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
UNIT = "fxtteam-chrome-update"
HOST = "ru.fxtteam.newtab_update"


def version(folder):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    number = manifest["version"]
    if (manifest["name"] != "FXT Team New Tab" or manifest["manifest_version"] != 3
            or manifest["chrome_url_overrides"]["newtab"] != "newtab.html"
            or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", number)):
        raise ValueError("Unexpected extension manifest")
    return tuple((list(map(int, number.split("."))) + [0, 0])[:4])


def check(preview=False):
    if not shutil.which("ssh-keygen"):
        raise ValueError("Для проверки подписи нужен ssh-keygen. Установите клиент OpenSSH (пакет openssh-client в Ubuntu/Debian или openssh-clients в Fedora).")
    repo = (TOOLS / "repository.txt").read_text().strip()
    if not re.fullmatch(r"[\w-][\w.-]*/[\w-][\w.-]*", repo, re.ASCII):
        raise ValueError("Invalid repository.txt")
    live, backup, stage = (ROOT / p for p in ("extension", ".fxt-previous", ".fxt-stage"))
    with (ROOT / ".fxt-lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if backup.exists() and not live.exists():
            backup.rename(live)
        installed = version(live)
        for directory in (backup, stage):
            if directory.exists():
                shutil.rmtree(directory)
        stage.mkdir(mode=0o700)
        try:
            url = f"https://github.com/{repo}/releases/latest/download/chrome-extension.zip"
            archive = stage / "chrome-extension.zip"
            signature = stage / "chrome-extension.zip.sig"
            for address, file in ((url, archive), (url + ".sig", signature)):
                try:
                    with urlopen(address, timeout=60) as response, file.open("wb") as out:
                        shutil.copyfileobj(response, out)
                except HTTPError as error:
                    raise ValueError(f"GitHub вернул HTTP {error.code} для {address}. Проверьте доступ к ссылке и наличие файла в последнем релизе.") from error
                except (URLError, TimeoutError) as error:
                    raise ValueError(f"Не удалось скачать {address}. Проверьте соединение и настройки прокси. {error}") from error
            with archive.open("rb") as package:
                verification = subprocess.run(["ssh-keygen", "-Y", "verify", "-I", "fxt-release",
                                "-n", "fxtteam-chrome", "-f", str(TOOLS / "allowed_signers"),
                                "-s", str(signature)], stdin=package, capture_output=True)
                if verification.returncode:
                    detail = (verification.stderr + verification.stdout).decode(errors="replace").strip()
                    if re.search(r"(unknown|illegal|invalid|unrecognized) option[^\n]*\bY\b", detail, re.I):
                        raise ValueError("Клиент OpenSSH не поддерживает проверку подписей (-Y verify). Обновите пакет клиента OpenSSH.")
                    raise ValueError(f"Не удалось подтвердить подпись пакета. Проверьте источник установщика. {detail}")
            candidate = stage / "candidate"
            with ZipFile(archive) as package:
                package.extractall(candidate)
            next_version = version(candidate)
            if preview:
                folder = candidate if next_version > installed else live
                return json.loads((folder / "manifest.json").read_text())["version"]
            if next_version <= installed:
                print("Already up to date.")
                return
            live.rename(backup)
            try:
                candidate.rename(live)
            except OSError:
                backup.rename(live)
                raise
            shutil.rmtree(backup)
            print("Updated to", ".".join(map(str, next_version)), "— reload the extension in Chrome.")
        finally:
            shutil.rmtree(stage)


def systemctl(*args):
    subprocess.run(["systemctl", "--user", *args], check=True)


def unit_arg(value):
    # systemd expands specifiers and environment references even inside quotes.
    value = str(value)
    if any(ord(c) < 32 for c in value):
        raise ValueError("Control character in the installation path")
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%').replace('$', '$$') + '"'


def write_unit(path, content):
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, encoding="utf-8") as out:
        out.write(content)
    Path(out.name).replace(path)


def main(action):
    units = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "systemd/user"
    service, timer = (units / (UNIT + suffix) for suffix in (".service", ".timer"))
    if action == "register":
        directory = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "google-chrome/NativeMessagingHosts"
        directory.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(os.fsencode((ROOT / "extension").resolve())).hexdigest()[:32]
        extension_id = digest.translate(str.maketrans("0123456789abcdef", "abcdefghijklmnop"))
        script = TOOLS / "linux.py"
        script.chmod(0o755)
        write_unit(directory / (HOST + ".json"), json.dumps({
            "name": HOST, "description": "FXT Team signed release updater",
            "path": str(script), "type": "stdio",
            "allowed_origins": [f"chrome-extension://{extension_id}/"],
        }))
    elif action == "check":
        check()
    elif action == "enable":
        if not shutil.which("systemctl"):
            raise ValueError("Для расписания требуется пользовательский systemd. Команда systemctl отсутствует. Обновления доступны вручную через иконку расширения.")
        manager = subprocess.run(["systemctl", "--user", "show-environment"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if manager.returncode:
            detail = manager.stderr.decode(errors="replace").strip()
            raise ValueError(f"Служба systemd пользователя недоступна. Повторите запуск из своего сеанса Linux. {detail}")
        check()
        units.mkdir(parents=True, exist_ok=True)
        command = f"{unit_arg(sys.executable)} {unit_arg(TOOLS / 'linux.py')} check"
        write_unit(service, "[Unit]\nDescription=Check FXT Chrome extension release\n"
                   f"[Service]\nType=oneshot\nExecStart={command}\n")
        write_unit(timer, "[Unit]\nDescription=Daily FXT Chrome extension update\n"
                   "[Timer]\nOnCalendar=*-*-* 12:00:00\nPersistent=true\n"
                   "[Install]\nWantedBy=timers.target\n")
        systemctl("daemon-reload")
        systemctl("enable", "--now", timer.name)
    elif action == "disable":
        if timer.exists():
            systemctl("disable", "--now", timer.name)
        for path in (timer, service):
            if path.exists():
                path.unlink()
        systemctl("daemon-reload")
    else:
        systemctl("list-timers", "--all", timer.name)


def native():
    header = sys.stdin.buffer.read(4)
    if len(header) != 4:
        return
    length, = struct.unpack("=I", header)
    if not 0 < length <= 1024:
        return
    try:
        action = json.loads(sys.stdin.buffer.read(length))["action"]
        with redirect_stdout(sys.stderr):
            if action == "inspect":
                number = check(preview=True)
            elif action == "apply":
                check()
                number = json.loads((ROOT / "extension/manifest.json").read_text())["version"]
            else:
                raise ValueError("Invalid action")
        reply = {"version": number}
    except Exception as error:
        print(error, file=sys.stderr)
        reply = {"error": "update"}
    data = json.dumps(reply).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1].startswith("chrome-extension://"):
        native()
        sys.exit()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "enable", "disable", "status", "register"))
    try:
        main(parser.parse_args().action)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
