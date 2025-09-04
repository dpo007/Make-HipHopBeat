# 🎛️ Make‑HipHopBeat.ps1 — Boom‑Bap in a Box

> **Self‑contained, sample‑free hip‑hop beat generator for Windows (PowerShell).**
> Pure DSP math (sine, noise, envelopes), 16‑step sequencing, swing, and a touch of console swagger. Exports a 44.1kHz/16‑bit WAV and can play it back automatically. No VSTs, no downloads, no internet — **just your PC and PowerShell.**

---

## 🎶 Why this slaps
- **Zero samples:** All sounds are synthesized (kick, snare, hats, open‑hats) plus **optional**: clap, sub‑bass/808, brass stabs, shaker, and scratch FX.
- **Real groove:** 16‑step grid with **swing** (0–0.25). Defaults per style for that “head‑nod” feel.
- **Stereo sauce:** Equal‑power panning, Haas widening, slapback on snares, light saturation, then a gentle master limiter & normalization.
- **Style presets:** `BoomBap`, `OldSchool`, `Crunk` — each with distinct BPM, swing, instrument mix, and pattern flavor.
- **Hands‑off render:** Writes a temp WAV by default (or your chosen `-OutPath`) and plays it back.

> 🧪 **Under the hood:** You’ll see amplitude envelopes, noise bursts for snare, FM-ish wobble for scratches, randomized pattern variations, and subtle bus processing — all in PowerShell.

---

## 🚀 Quick start
```powershell
# From a PowerShell prompt in the repo folder
# (Optional) If Windows blocked the file because it came from the web:
Unblock-File .\Make-HipHopBeat.ps1

# Fire up a classic 90s groove:
.\Make-HipHopBeat.ps1 -Style BoomBap -Bars 4

# Save to a WAV (and auto‑play it):
.\Make-HipHopBeat.ps1 -Style OldSchool -Bars 8 -OutPath .\mybeat.wav
```

### Requirements
- Windows 10/11
- PowerShell 5.1 or 7+
- A working audio device (for playback)

> If you only want the file and **no auto‑play**, just keep the generated `.wav` and stop the player with `Ctrl+C` if needed.

---

## 🧩 Parameters (the control room)
| Param | Type | Default | Notes |
|---|---|---:|---|
| `-Style` | `BoomBap \| OldSchool \| Crunk` | `BoomBap` | Preset BPM, swing, instruments & patterns. |
| `-Bpm` | `int` (60–180) | style default | Set `0` to use the style’s tempo. |
| `-Bars` | `int` (1–64) | `4` | Total bars to render. |
| `-Swing` | `double` (0.0–0.25) | style default | 0.12–0.18 = pocket sweet spot. |
| `-OutPath` | `string` | temp file | Where to write the WAV. |
| `-AddClap` | `switch` | off | Layer clap with snare. |
| `-AddBass` | `switch` | off (style‑dependent) | Synth sub‑bass line. |
| `-Use808` | `switch` | off | Forces 808‑style bass (implies `-AddBass`). |
| `-AddBrass` | `switch` | off | Short brass stabs for attitude. |
| `-AddScratch` | `switch` | off | Turntablism‑flavored FX. |
| `-AddShaker` | `switch` | off | Extra texture on the top end. |
| `-UseAll` | `switch` | off | YOLO: enable **all** extras at once. |

> Switches **override** style defaults. `-UseAll` wins over everything.

---

## 🎚️ Style presets (pick your flavor)
- **BoomBap** — ~92 BPM, ~0.16 swing, steady 8ths on hats, classic 2 & 4 snare, subtle Haas width. Shaker left, hats right, kick/snare/bass center.
- **OldSchool** — busier 16ths, breakbeat‑ish kicks, minimal open‑hat. Faster, more motion, still pocket.
- **Crunk** — weighty low end, hype hats and claps, more open‑hat moments and brass/scratch energy.

Each preset sets up: instrument selection, panning, delays, variation density, and small humanized offsets.

---

## 🍳 Recipes (copy/paste and chef it up)
**Straight head‑nod (boom‑bap):**
```powershell
.\Make-HipHopBeat.ps1 -Style BoomBap -Bars 8 -AddShaker
```

**Golden‑era w/ clap and bass:**
```powershell
.\Make-HipHopBeat.ps1 -Style OldSchool -Bars 8 -AddClap -AddBass
```

**Club‑leaning rumble:**
```powershell
.\Make-HipHopBeat.ps1 -Style Crunk -Bars 8 -Use808 -AddBrass
```

**All‑in chaos (fun to try once 😅):**
```powershell
.\Make-HipHopBeat.ps1 -UseAll -Bars 4
```

**Dial your own pocket:**
```powershell
.\Make-HipHopBeat.ps1 -Style BoomBap -Bpm 88 -Swing 0.18 -Bars 16 -AddClap -AddBass -AddShaker
```

---

## 🧠 “Scholarly” nods (authentic feel)
- **Swinged 16ths** to push the “e”/“a” grid later and create that Dilla‑ish lean.
- **Backbeat on 2 & 4**, with hats running steady (plus occasional extra 16ths).
- **Micro‑variation** maps per 16‑step block to avoid robotic repetition.
- **Panning discipline**: kick/bass center, hats and shakers split, claps slightly alternating, subtle Haas width.
- **Gentle bus saturation** then **normalize** for consistent loudness without crushing the transients.

---

## 🛠️ Troubleshooting
- **No sound?** Make sure your Windows audio device is set and not in exclusive use. Try saving `-OutPath .\test.wav` and play it in a media player.
- **Execution policy blocks it?** Run `Unblock-File` or start the shell with a policy that allows local scripts.
- **Glitches on playback?** Rendering is offline (clean), but playback uses `System.Media.SoundPlayer`. If it stutters, just open the WAV in your DAW/player.

---

## 📦 Project structure
```
├─ Make-HipHopBeat.ps1   # the whole beat lab in one script
└─ README.md             # you are here
```

---

## 📝 License
MIT — do what you do. If you make something dope, **drop a link in your README and tag your beat “PowerShell‑Produced.”**

---

## 🙌 Credits
Big ups to the drum machine pioneers and the code‑slingers who ain’t afraid to make music with math. 🎹🧮
