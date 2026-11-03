# Claude Code Voice - installer (Windows).
# Gives Claude Code a spoken voice (replies read aloud) and voice input (hands-free back-and-forth).
param(
  [string]$ClaudeDir = (Join-Path $env:USERPROFILE ".claude"),
  [switch]$NoAutostart,   # do not add the Startup shortcut
  [switch]$NoStart,       # do not launch the voice-input tool at the end
  [switch]$SkipModel      # skip the speech-model download (it downloads on first launch instead)
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$voiceDir = Join-Path $ClaudeDir "voice"
$hooksDir = Join-Path $ClaudeDir "hooks"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Step "Checking Python"
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { throw "Python 3.10+ is required. Install it from https://www.python.org/downloads/ (tick 'Add python.exe to PATH'), then run this again." }
$ver = (python -c "import sys; print('%d.%d' % sys.version_info[:2])").Trim()
if ([version]$ver -lt [version]"3.10") { throw "Python $ver found, but 3.10 or newer is required." }
Write-Host "Python $ver OK"

Step "Installing the voice (edge-tts)"
python -m pip install --user --quiet --disable-pip-version-check edge-tts
python -c "import edge_tts" 2>$null
if ($LASTEXITCODE -ne 0) { throw "edge-tts did not install." }

Step "Checking uv (runs the speech-recognition tool in its own Python)"
$uv = Get-Command uv -ErrorAction SilentlyContinue
if ($uv) { $uvCmd = "uv" }
else {
  python -m pip install --user --quiet --disable-pip-version-check uv
  $uvCmd = "python -m uv"
}
Invoke-Expression "$uvCmd --version" | Out-Host

Step "Copying files to $ClaudeDir"
New-Item -ItemType Directory -Force $voiceDir, $hooksDir | Out-Null
Copy-Item (Join-Path $here "voice\ptt.py") $voiceDir -Force
Copy-Item (Join-Path $here "hooks\speak.ps1") $hooksDir -Force
if (-not (Test-Path (Join-Path $voiceDir "voice.txt"))) { Copy-Item (Join-Path $here "voice\voice.txt") $voiceDir }
$run = "$uvCmd run --python 3.12 --with faster-whisper --with sounddevice --with keyboard --with numpy python `"$voiceDir\ptt.py`" small.en"
Set-Content -Path (Join-Path $voiceDir "start-voice.cmd") -Value "@echo off`r`n$run" -Encoding ascii

Step "Adding the speak hooks to Claude Code settings (a backup is made first)"
python (Join-Path $here "merge_settings.py") add (Join-Path $ClaudeDir "settings.json") (Join-Path $hooksDir "speak.ps1")

if (-not $NoAutostart) {
  Step "Starting the voice-input tool automatically at login"
  $lnk = Join-Path ([Environment]::GetFolderPath("Startup")) "ClaudeVoice.lnk"
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $s.TargetPath = "cmd.exe"
  $s.Arguments = "/c `"$voiceDir\start-voice.cmd`" > `"$voiceDir\ptt.log`" 2>&1"
  $s.WindowStyle = 7
  $s.Save()
}

if (-not $SkipModel) {
  Step "Downloading the speech model (one time, about 250 MB, a few minutes)"
  Invoke-Expression "$uvCmd run --python 3.12 --with faster-whisper python -c `"from faster_whisper import WhisperModel; WhisperModel('small.en', device='cpu', compute_type='int8'); print('model ready')`"" | Out-Host
}

if (-not $NoStart) {
  Step "Starting voice input"
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*voice*ptt.py*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Start-Process cmd.exe -ArgumentList "/c", "`"$voiceDir\start-voice.cmd`" > `"$voiceDir\ptt.log`" 2>&1" -WindowStyle Hidden
}

Write-Host "`nDone." -ForegroundColor Green
Write-Host @"

Start a NEW Claude Code chat (hooks load when a chat starts). Then:
  - Claude reads its replies aloud when it finishes.
  - Ctrl+Space      open the mic now, talk, pause = it sends. Press again to cancel.
  - Ctrl+Alt+V      turn hands-free conversation mode on/off (mic opens after each reply).
  - Say "stop listening" (on its own) to turn conversation mode off.
  - Different voice or speed: edit $voiceDir\voice.txt
Headphones are best: they stop the mic from hearing Claude's voice.
"@
