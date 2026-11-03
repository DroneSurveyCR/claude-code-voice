# Claude Code Voice

Talk to Claude Code and hear it talk back, hands-free. Windows, free, and the speech
recognition runs on your own PC.

- **Claude speaks** a short summary every time it finishes (or needs your permission).
- **You speak** by tapping a key. It sends when you pause.
- **Conversation mode**: after Claude finishes talking, the mic opens by itself, so you can go
  back and forth without touching the keyboard.
- Works in the VS Code extension and the terminal, with several windows open at once.

## Install

You need **Windows 10/11** and **Python 3.10+** ([python.org](https://www.python.org/downloads/),
tick "Add python.exe to PATH").

1. Download this repo (green **Code** button, then **Download ZIP**) and unzip it.
2. Double-click **`install.cmd`**.
3. Wait a few minutes. The first run downloads a ~250 MB speech model.
4. Open a **new** Claude Code chat.

The installer backs up your Claude `settings.json` first, adds two hooks (it never removes your
other settings), and starts the voice tool at login. Options: `install.ps1 -NoAutostart`,
`-NoStart`, `-SkipModel`.

## Use

| Do this | What happens |
|---|---|
| Tap **Ctrl+Space** | Mic opens (high beep). Talk, pause, it sends. Tap again to cancel. |
| Tap **Ctrl+Alt+V** | Turn conversation mode on/off. When on, the mic opens after each reply. |
| Say **"stop listening"** (alone) | Turns conversation mode off. |
| End a sentence with **"send it"** | Presses Enter for you. |

Change the voice or speed: edit `%USERPROFILE%\.claude\voice\voice.txt`
(line 1 the voice, line 2 the speed). List voices with `python -m edge_tts --list-voices`.

## Good to know

- **Use headphones.** Otherwise the mic can hear Claude's own voice. The tool has guards
  (mic closed while a voice plays, it removes sentences that match what Claude just said, and it
  drops your message if you switch windows), but headphones are the real fix.
- With several windows, voices queue one at a time and start with the project folder name.
- Voice output uses Microsoft's free online neural voices (edge-tts), so it needs internet and
  falls back to the built-in Windows voice if offline. Speech recognition is fully local.
- It types into whichever window is in front, so keep the Claude chat box focused.
- VS Code's own mic button is separate and ignores these guards.

## How it works

- `hooks/speak.ps1` - Claude Code `Stop` and `Notification` hooks. Reads the last reply, cleans out
  file paths and code, speaks it, and signals the listener.
- `voice/ptt.py` - background tool: local [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
  transcription, global hotkeys, pause detection, echo guards.
- `merge_settings.py` - safely adds/removes the hooks in `settings.json`.

## Uninstall

Run `uninstall.ps1`. It removes the hooks, the startup shortcut and the files.
