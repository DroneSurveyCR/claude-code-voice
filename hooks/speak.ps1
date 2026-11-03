param([string]$Mode = "stop")
# Claude Code hook: speaks a short summary aloud. Reads hook JSON from stdin.
# Several windows can finish at once: speech is queued (one voice at a time), each line starts
# with the project folder name, and the mic only opens if that project's window is in front.
$raw = [Console]::In.ReadToEnd()
$text = ""
$project = ""
$cwd = ""
try {
  $j = $raw | ConvertFrom-Json
  if ($j.cwd) { $cwd = [string]$j.cwd; $project = (Split-Path $cwd -Leaf) }
  if ($Mode -eq "notify" -and $j.message) { $text = [string]$j.message }
  elseif ($j.transcript_path -and (Test-Path $j.transcript_path)) {
    $last = Get-Content $j.transcript_path -Tail 60 | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } |
      Where-Object { $_.type -eq "assistant" } | Select-Object -Last 1
    if ($last) {
      $text = ($last.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join " "
    }
  }
} catch {}
$text = $text -replace '```[\s\S]*?```', ' '
$text = $text -replace '\[([^\]]*)\]\([^)]*\)', '$1'
$text = $text -replace 'https?://\S+', ''
$text = $text -replace '[A-Za-z]:\\\S*', ''
$text = $text -replace '~?/[\w.\-/]{3,}', ''
$text = $text -replace '\b[\w\-]+\.(ps1|py|json|md|cmd|js|jsx|ts|tsx|html|css|sql|env|mp3|txt|yml|yaml|sh)\b', ''
$text = ($text -replace '[`*#|>_\[\]]', '' -replace '\s+', ' ').Trim()
if (-not $text) { $text = if ($Mode -eq "notify") { "I need your attention." } else { "Done." } }
$cap = if ($Mode -eq "notify") { 110 } else { 280 }  # permission prompts stay short
if ($text.Length -gt $cap) { $text = $text.Substring(0, $cap) }
if ($project) { $text = (($project -replace '[-_]+', ' ') + ": " + $text) }

$voiceDir = Join-Path $env:USERPROFILE ".claude\voice"
# Voice and speed live in voice.txt (two lines: voice name, then rate like +30%). Edit it any time.
$voice = "en-US-AndrewNeural"; $rate = "+30%"
if (Test-Path "$voiceDir\voice.txt") {
  $cfg = @(Get-Content "$voiceDir\voice.txt" | Where-Object { $_.Trim() })
  if ($cfg.Count -ge 1) { $voice = $cfg[0].Trim() }
  if ($cfg.Count -ge 2) { $rate = $cfg[1].Trim() }
}
$mp3 = Join-Path $env:TEMP "claude-speak-$PID.mp3"
$txt = Join-Path $env:TEMP "claude-speak-$PID.txt"

# One voice at a time across all windows: wait for our turn.
$mutex = New-Object System.Threading.Mutex($false, "Global\ClaudeSpeakQueue")
$have = $false
try { $have = $mutex.WaitOne(90000) } catch [System.Threading.AbandonedMutexException] { $have = $true }
try {
  $ok = $false
  # Tell the voice-input tool we are speaking (it keeps the mic closed) and what we said.
  New-Item -ItemType File -Path "$voiceDir\speaking.flag" -Force | Out-Null
  # Keep the last few spoken lines (from any window) so echoes can be filtered out.
  $prev = @(); if (Test-Path "$voiceDir\last_spoken.txt") { $prev = @(Get-Content "$voiceDir\last_spoken.txt" -Tail 5) }
  [IO.File]::WriteAllLines("$voiceDir\last_spoken.txt", [string[]]($prev + $text), (New-Object Text.UTF8Encoding $false))
  try {
    [IO.File]::WriteAllText($txt, $text, (New-Object Text.UTF8Encoding $false))
    python -m edge_tts --voice $voice --rate=$rate --file $txt --write-media $mp3 2>$null
    if ((Test-Path $mp3) -and (Get-Item $mp3).Length -gt 0) {
      Add-Type -AssemblyName PresentationCore
      $p = New-Object System.Windows.Media.MediaPlayer
      $p.Open([Uri]$mp3)
      $t = 0
      while (-not $p.NaturalDuration.HasTimeSpan -and $t -lt 50) { Start-Sleep -Milliseconds 100; $t++ }
      if ($p.NaturalDuration.HasTimeSpan) {
        $p.Play()
        Start-Sleep -Milliseconds ([int]$p.NaturalDuration.TimeSpan.TotalMilliseconds + 300)
        $ok = $true
      }
      $p.Close()
    }
  } catch {}
  Remove-Item $mp3, $txt -ErrorAction SilentlyContinue
  if (-not $ok) {
    Add-Type -AssemblyName System.Speech
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.Speak($text)
  }
  Remove-Item "$voiceDir\speaking.flag" -ErrorAction SilentlyContinue

  # Conversation mode: open the mic only if this project's window is the one in front.
  if ($Mode -eq "stop" -and (Test-Path "$voiceDir\convo.on")) {
    $front = $true
    if ($project) {
      Add-Type -Namespace Win -Name Fg -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr h, System.Text.StringBuilder s, int n);
'@
      $sb = New-Object System.Text.StringBuilder 512
      [void][Win.Fg]::GetWindowText([Win.Fg]::GetForegroundWindow(), $sb, 512)
      $front = $sb.ToString().ToLower().Contains($project.ToLower())
    }
    if ($front) {
      Start-Sleep -Milliseconds 400
      New-Item -ItemType File -Path "$voiceDir\listen.now" -Force | Out-Null
    }
  }
} finally {
  Remove-Item "$voiceDir\speaking.flag" -ErrorAction SilentlyContinue
  if ($have) { $mutex.ReleaseMutex() }
}
