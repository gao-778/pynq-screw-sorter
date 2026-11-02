"""Print runtime evidence without loading an Overlay or accessing the robot."""

import importlib.metadata
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys


def collect():
    packages = {}
    for name in ("pynq", "numpy", "jupyter", "notebook", "jupyterlab"):
        try:
            packages[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            packages[name] = None
    result = {
        "python": platform.python_version(),
        "system": platform.system(),
        "machine": platform.machine(),
        "kernel": platform.release(),
        "pointer_bits": 64 if sys.maxsize > 2**32 else 32,
        "packages": packages,
        "running_as_root": os.geteuid() == 0 if hasattr(os, "geteuid") else None,
        "hardware_access": False,
        "meaning": "Environment inventory only; not a board, DMA, inference or motion test.",
    }
    os_release = Path("/etc/os-release")
    if os_release.is_file():
        values = {}
        for line in os_release.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value.strip('"')
        result["os_release"] = {key: values.get(key) for key in ("ID", "VERSION_ID", "PRETTY_NAME")}
    model = Path("/proc/device-tree/model")
    if model.is_file():
        result["board_model"] = model.read_bytes().rstrip(b"\0").decode("utf-8", errors="replace")
    meminfo = Path("/proc/meminfo")
    if meminfo.is_file():
        result["cma"] = {
            line.split(":", 1)[0]: line.split(":", 1)[1].strip()
            for line in meminfo.read_text(encoding="ascii").splitlines()
            if line.startswith(("CmaTotal:", "CmaFree:"))
        }
    compiler = shutil.which("gcc")
    if compiler:
        try:
            process = subprocess.run([compiler, "--version"], capture_output=True, text=True, timeout=10)
            result["gcc"] = process.stdout.splitlines()[0] if process.stdout else None
        except (OSError, subprocess.TimeoutExpired):
            result["gcc"] = None
    else:
        result["gcc"] = None
    return result


if __name__ == "__main__":
    print(json.dumps(collect(), ensure_ascii=False, indent=2))
