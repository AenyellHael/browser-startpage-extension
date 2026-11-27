"""Build the Chrome bootstrap bundle and the signed payload for GitHub Releases."""

import argparse
import base64
import json
import re
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def build_installers(source, bootstrap, output):
    data = base64.b64encode(bootstrap.read_bytes()).decode("ascii")
    for name, platform in (("install.cmd", "Windows"), ("install.sh", "Linux")):
        template = (source / "installers" / (name + ".in")).read_text(encoding="utf-8")
        script = template.replace("__BOOTSTRAP_BASE64__", data)
        if name.endswith(".cmd"):
            script = script.replace("\n", "\r\n")
        installer = output / f"install_FXT-Team-New-Tab_{platform}{Path(name).suffix}"
        installer.write_bytes(script.encode("utf-8"))
        installer.chmod(0o755)
    for platform, suffix in (("Windows", ".cmd"), ("Linux", ".sh")):
        name = f"uninstall_FXT-Team-New-Tab_{platform}{suffix}"
        text = (source / "installers" / name).read_text(encoding="utf-8")
        if suffix == ".cmd":
            text = text.replace("\n", "\r\n")
        (output / name).write_bytes(text.encode("utf-8"))
        (output / name).chmod(0o755)


def build(source, repository, key, output):
    if not re.fullmatch(r"[\w-][\w.-]*/[\w-][\w.-]*", repository, re.ASCII):
        raise ValueError("Expected GitHub OWNER/REPO")
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    files = ["manifest.json", "newtab.html", "newtab.js", "popup.html", "popup.js",
             "manual-update.js", *sorted(set(manifest["icons"].values()))]
    version = manifest["version"]
    if not re.fullmatch(r"\d+(\.\d+){1,3}", version, re.ASCII):
        raise ValueError("Expected a numeric Chrome version")
    # Trust only the public key corresponding to the key used for this release.
    pub = subprocess.check_output(["ssh-keygen", "-y", "-f", str(key)], text=True)
    kind, public = pub.split()[:2]
    if kind != "ssh-ed25519":
        raise ValueError("Use a dedicated Ed25519 release key")
    base64.b64decode(public, validate=True)
    signers = f"fxt-release {kind} {public}\n"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as temp:
        stage = Path(temp)
        payload = stage / "chrome-extension.zip"
        # Package only extension runtime files. OS update scripts stay outside Chrome.
        with ZipFile(payload, "w", ZIP_DEFLATED) as archive:
            for name in files:
                archive.write(source / name, name)
        subprocess.run(["ssh-keygen", "-Y", "sign", "-f", str(key),
                        "-n", "fxtteam-chrome", str(payload)], check=True)
        bootstrap = stage / f"fxtteam-new-tab-v{version}.zip"
        with ZipFile(bootstrap, "w", ZIP_DEFLATED) as archive:
            for name in files:
                archive.write(source / name, "extension/" + name)
            for name in ("windows.ps1", "linux.py", "native.cmd", "setup.ps1", "open-extensions.ps1"):
                archive.write(source / "update" / name, "update/" + name)
            archive.write(source / "README.md", "README.md")
            archive.writestr("update/allowed_signers", signers)
            archive.writestr("update/repository.txt", repository + "\n")
        build_installers(source, bootstrap, stage)
        for file in stage.iterdir():
            file.replace(output / file.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=Path(__file__).resolve().parent, type=Path)
    parser.add_argument("--repo", default="AenyellHael/browser-startpage-extension")
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    build(args.source.resolve(), args.repo, args.key.resolve(), args.out.resolve())
