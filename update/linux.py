#!/usr/bin/env python3
"""Manage opt-in FXT Chrome updates for the current Linux user."""

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.request import urlopen
from zipfile import ZipFile

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
UNIT = "fxtteam-chrome-update"


def version(folder):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    number = manifest["version"]
    if (manifest["name"] != "FXT Team New Tab" or manifest["manifest_version"] != 3
            or manifest["chrome_url_overrides"]["newtab"] != "newtab.html"
            or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", number)):
        raise ValueError("Unexpected extension manifest")
    return tuple((list(map(int, number.split("."))) + [0, 0])[:4])


def check():
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
                with urlopen(address, timeout=60) as response, file.open("wb") as out:
                    shutil.copyfileobj(response, out)
            with archive.open("rb") as package:
                subprocess.run(["ssh-keygen", "-Y", "verify", "-I", "fxt-release",
                                "-n", "fxtteam-chrome", "-f", str(TOOLS / "allowed_signers"),
                                "-s", str(signature)], stdin=package, check=True)
            candidate = stage / "candidate"
            with ZipFile(archive) as package:
                package.extractall(candidate)
            next_version = version(candidate)
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
    if action == "check":
        check()
    elif action == "enable":
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("check", "enable", "disable", "status"))
    try:
        main(parser.parse_args().action)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
