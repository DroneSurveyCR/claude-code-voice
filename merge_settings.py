"""Add (or remove) the voice hooks in a Claude Code settings.json without touching anything else.

usage: merge_settings.py add    <settings.json> <speak.ps1>
       merge_settings.py remove <settings.json>
"""
import json, os, shutil, sys, time

MARK = "speak.ps1"
TIMEOUT = 120  # queued voices can take a while; Claude Code kills hooks that run longer


def command(speak, mode):
    return f'powershell -NoProfile -ExecutionPolicy Bypass -File "{speak}" {mode}'


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8-sig") as f:
        text = f.read().strip()
    return json.loads(text) if text else {}


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak-voice-{time.strftime('%Y%m%d-%H%M%S')}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def ours(entry):
    return any(MARK in h.get("command", "") for h in entry.get("hooks", []))


def add(path, speak):
    data = load(path)
    hooks = data.setdefault("hooks", {})
    for event, mode in (("Stop", "stop"), ("Notification", "notify")):
        entries = hooks.setdefault(event, [])
        cmd = command(speak, mode)
        done = False
        for entry in entries:
            if ours(entry):
                for h in entry["hooks"]:
                    if MARK in h.get("command", ""):
                        h.update(type="command", command=cmd, timeout=TIMEOUT)
                done = True
        if not done:
            entries.append({"hooks": [{"type": "command", "command": cmd, "timeout": TIMEOUT}]})
    save(path, data)
    print("hooks added to", path)


def remove(path):
    data = load(path)
    hooks = data.get("hooks", {})
    for event in ("Stop", "Notification"):
        kept = [e for e in hooks.get(event, []) if not ours(e)]
        if kept:
            hooks[event] = kept
        else:
            hooks.pop(event, None)
    if not hooks:
        data.pop("hooks", None)
    save(path, data)
    print("hooks removed from", path)


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "add":
        add(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == "remove":
        remove(sys.argv[2])
    else:
        sys.exit(__doc__)
