"""Voice input for Claude Code. Local faster-whisper, CPU. Runs in the background.
Hold Right Ctrl to speak (types text); end with "send it" to press Enter.
Ctrl+Alt+V toggles conversation mode: after Claude finishes speaking (speak.ps1 drops
listen.now), the mic opens on its own, stops after a pause, and sends the message."""
import ctypes, difflib, os, queue, re, sys, threading, time, winsound
import numpy as np
import sounddevice as sd
import keyboard
from faster_whisper import WhisperModel

MODEL = sys.argv[1] if len(sys.argv) > 1 else "small.en"
RATE = 16000
HERE = os.path.dirname(os.path.abspath(__file__))
CONVO = os.path.join(HERE, "convo.on")
TRIGGER = os.path.join(HERE, "listen.now")
FLAG = os.path.join(HERE, "speaking.flag")
LAST = os.path.join(HERE, "last_spoken.txt")
PAUSE_S, NO_SPEECH_S, MAX_S, TAIL_S = 1.4, 60, 120, 1.3


def foreground():
    return ctypes.windll.user32.GetForegroundWindow()


def speaking():
    """A voice is playing. A flag older than 45s is stale (a killed hook left it behind)."""
    try:
        return time.time() - os.path.getmtime(FLAG) < 45
    except OSError:
        return False


def _norm(s):
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).split()


def is_echo(text):
    """True if text is (mostly) something Claude said out loud recently (any window)."""
    try:
        lines = [l for l in open(LAST, encoding="utf-8").read().splitlines() if l.strip()]
    except OSError:
        return False
    heard = _norm(text)
    if len(heard) < 3:
        return False
    for line in lines:
        said = _norm(line)
        overlap = sum(w in set(said) for w in heard) / len(heard)
        if overlap >= 0.75 or difflib.SequenceMatcher(None, heard, said).ratio() > 0.5:
            return True
    return False


def strip_echo(text):
    """Drop sentences that are Claude's own voice, keep what the user said."""
    parts = re.split(r"(?<=[.!?])\s+", text)
    return " ".join(p for p in parts if not is_echo(p)).strip()

model = WhisperModel(MODEL, device="cpu", compute_type="int8")
frames, recording, send = [], False, False
auto_q, auto_on, cancel, last_fire = queue.Queue(), False, False, 0.0
lock = threading.Lock()


def cb(indata, n, t, status):
    if recording:
        frames.append(indata.copy())
    if auto_on:
        auto_q.put(indata.copy())


stream = sd.InputStream(samplerate=RATE, channels=1, dtype="float32", blocksize=1600, callback=cb)
stream.start()


def transcribe(audio, press_enter):
    if len(audio) < RATE * 0.4:
        return
    segs, _ = model.transcribe(audio, language="en", vad_filter=True, beam_size=1)
    text = " ".join(s.text.strip() for s in segs).strip()
    if not text:
        winsound.Beep(400, 120)
        return
    print("heard:", text, flush=True)
    cleaned = strip_echo(text)
    if cleaned != text:
        print("  removed Claude's voice, kept:", cleaned or "(nothing)", flush=True)
    text = cleaned
    if not text:
        return
    if re.fullmatch(r"\W*(please )?stop (listening|the voice|voice|conversation mode|the conversation)\W*", text, re.I):
        if os.path.exists(CONVO):
            toggle_convo()
        return
    m = re.search(r"[\s,.]*send it[.!?]*$", text, re.I)
    if m:
        text, press_enter = text[:m.start()].rstrip(), True
    if text:
        keyboard.write(text + (" " if not press_enter else ""))
    if press_enter:
        keyboard.send("enter")


def start(enter):
    global recording, send
    with lock:
        if recording:
            return
        frames.clear()
        send = enter
        recording = True
    winsound.Beep(900, 80)


def stop():
    global recording
    with lock:
        if not recording:
            return
        recording = False
        audio = np.concatenate(frames).flatten() if frames else np.zeros(0, "float32")
        enter = send
    winsound.Beep(600, 80)
    threading.Thread(target=transcribe, args=(audio, enter), daemon=True).start()


def listen_auto(manual=False):
    """Open the mic, wait for speech, end after a pause, then transcribe and send.
    manual=True (you pressed the hotkey): open instantly, no waiting for voices to finish."""
    global auto_on, cancel
    cancel = False
    if not manual:
        waited = 0.0
        while speaking() and waited < 90:  # never listen while a voice is playing
            time.sleep(0.2)
            waited += 0.2
        time.sleep(TAIL_S)  # let the speaker tail and room echo die down
    while not auto_q.empty():
        auto_q.get_nowait()
    auto_on = True
    winsound.Beep(1000, 80)
    buf, ambient, thr = [], [], None
    speech, silence, elapsed, interrupted = False, 0.0, 0.0, False
    win = foreground()  # the window we are listening for; text only goes there
    try:
        while elapsed < MAX_S and not recording:
            try:
                ch = auto_q.get(timeout=0.5)
            except queue.Empty:
                continue
            if cancel:  # you pressed the hotkey again
                speech = False
                break
            if speaking() and not manual:  # another window started talking: drop this listen
                speech, interrupted = False, True
                break
            dur = len(ch) / RATE
            elapsed += dur
            buf.append(ch)
            rms = float(np.sqrt(np.mean(ch ** 2)))
            if thr is None:
                ambient.append(rms)
                if len(ambient) >= 4:
                    thr = max(0.012, 3 * min(ambient))
                continue
            if rms > thr:
                speech, silence = True, 0.0
            elif speech:
                silence += dur
            if speech and silence >= PAUSE_S:
                break
            if not speech and elapsed > NO_SPEECH_S:
                break
    finally:
        auto_on = False
    if interrupted:  # re-open after the other voice finishes, with a fresh wait
        return listen_auto()
    if speech:
        if foreground() != win:  # you switched windows: do not type into the wrong one
            winsound.Beep(300, 300)
            print("  discarded (window changed while listening)", flush=True)
            return
        winsound.Beep(600, 80)
        transcribe(np.concatenate(buf).flatten(), True)


def watch_trigger():
    while True:
        time.sleep(0.15)
        if os.path.exists(TRIGGER):
            try:
                os.remove(TRIGGER)
            except OSError:
                continue
            if os.path.exists(CONVO) and not recording:
                listen_auto()


def toggle_convo():
    if os.path.exists(CONVO):
        os.remove(CONVO)
        winsound.Beep(500, 150)
        print("conversation mode OFF", flush=True)
    else:
        open(CONVO, "w").close()
        winsound.Beep(1200, 150)
        print("conversation mode ON", flush=True)


if not os.path.exists(CONVO):
    open(CONVO, "w").close()  # conversation mode is on by default at launch
threading.Thread(target=watch_trigger, daemon=True).start()
keyboard.add_hotkey("ctrl+alt+v", toggle_convo)
def hotkey_listen():
    """Ctrl+Alt+Space: open the mic now (sends after a pause); press again to cancel."""
    global cancel, last_fire
    now = time.time()
    repeat = now - last_fire < 1.0  # a held key repeats; ignore until it has been released a while
    last_fire = now
    if repeat:
        return
    if auto_on or recording:
        cancel = True
        winsound.Beep(400, 150)
        return
    threading.Thread(target=listen_auto, args=(True,), daemon=True).start()


keyboard.add_hotkey("ctrl+space", hotkey_listen, suppress=True)  # suppress: keep VS Code from also opening suggestions
keyboard.add_hotkey("ctrl+alt+space", hotkey_listen)
print(f"ready ({MODEL}). Ctrl+Space = listen now / cancel; Ctrl+Alt+V = conversation mode", flush=True)
keyboard.wait()
