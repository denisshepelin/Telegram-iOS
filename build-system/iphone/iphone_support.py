"""Local iPhone installation process logging and atomic state writes."""

import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import time


class IphoneInstallError(Exception):
    """An installation failure with a recovery message suitable for the terminal."""


class InstallCommands:
    """Run argument lists without a shell, retaining output in a private run log."""

    def __init__(self, root: Path, log: Path, verbose: bool = False):
        self.root = root
        self.log = log
        self.verbose = verbose

    def run(self, args: list[str], timeout: int = 120, check: bool = True) -> bytes:
        command = [str(arg) for arg in args]
        if self.verbose:
            print(shlex.join(command), file=sys.stderr)
        with self.log.open("ab+") as output:
            output.write(("\n$ " + shlex.join(command) + "\n").encode())
            output.flush()
            offset = output.tell()
            process = subprocess.Popen(
                command, cwd=self.root, stdout=output, stderr=output,
                stdin=subprocess.DEVNULL, start_new_session=True,
            )
            started = time.monotonic()
            try:
                while True:
                    try:
                        process.wait(timeout=min(30, timeout))
                        break
                    except subprocess.TimeoutExpired:
                        if time.monotonic() - started >= timeout:
                            raise IphoneInstallError(f"iPhone command timed out: {command[0]}. See {self.log}")
                        print(f"Still running {command[0]}… Log: {self.log}", file=sys.stderr)
            except BaseException:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
            output.seek(offset)
            result = output.read()
        if check and process.returncode:
            raise IphoneInstallError(
                f"iPhone command failed ({process.returncode}): {command[0]}. "
                f"See {self.log}\n{result.decode(errors='replace')[-2500:]}"
            )
        return result

    def json(self, args: list[str], name: str, timeout: int = 120) -> dict:
        """Read devicectl's supported JSON file interface instead of its console table."""
        destination = self.log.parent / f"{name}.json"
        destination.unlink(missing_ok=True)
        self.run(args + ["--json-output", str(destination), "--timeout", str(timeout)], timeout + 10)
        data = json.loads(destination.read_text())
        if data.get("info", {}).get("outcome") != "success":
            raise IphoneInstallError(f"iPhone device operation failed. See {destination}")
        return data["result"]


def write_install_state(path: Path, data: dict) -> None:
    """Replace installation metadata atomically on the same filesystem."""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)
