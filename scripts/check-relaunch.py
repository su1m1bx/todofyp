#!/usr/bin/env python3
"""Open only our app via LaunchServices; inspect only its dedicated check report."""
import json
import pathlib
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
app = root / "dist/Important Todo.app"
report = pathlib.Path.home() / "Library/Containers/dev.local.important-todo/Data/Library/Application Support/ImportantTodo/launch-check.json"
if report.exists():
    report.unlink()
launch = subprocess.Popen(["open", "-W", str(app), "--args", "--launch-check"])
deadline = time.monotonic() + 20
initial_pid = None
while time.monotonic() < deadline:
    if report.exists():
        result = json.loads(report.read_text())
        if result.get("state") == "hidden" and initial_pid is None:
            initial_pid = result["pid"]
            subprocess.run(["open", str(app)], check=True)
        elif result.get("state") == "reopened":
            result["sameProcess"] = initial_pid == result["pid"]
            print(json.dumps(result, indent=2))
            launch.wait(timeout=5)
            assert result["passed"] and result["sameProcess"] and result["ownTodoPanelCount"] == 1
            break
        elif result.get("state") == "timeout":
            raise SystemExit("FAIL: app did not receive reopen")
    time.sleep(0.1)
else:
    raise SystemExit("FAIL: no report. Quit any existing Important Todo instance before this check.")
