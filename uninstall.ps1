# Removes Claude Code Voice: hooks, startup shortcut, running tool, and its files.
param([string]$ClaudeDir = (Join-Path $env:USERPROFILE ".claude"))
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*voice*ptt.py*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
python (Join-Path $here "merge_settings.py") remove (Join-Path $ClaudeDir "settings.json")
Remove-Item (Join-Path ([Environment]::GetFolderPath("Startup")) "ClaudeVoice.lnk") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ClaudeDir "hooks\speak.ps1") -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ClaudeDir "voice") -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Claude Code Voice removed. Your settings.json keeps a .bak-voice-* backup from install."
