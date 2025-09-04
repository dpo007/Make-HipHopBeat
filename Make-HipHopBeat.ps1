<#
.SYNOPSIS
  Programmatically generate and play a simple hip-hop beat (no samples).

.DESCRIPTION
  Synthesizes drum sounds using pure DSP math (sine, noise, envelopes) and
  sequences them on a 16-step grid. Exports a 44.1kHz 16-bit PCM WAV and plays it.

.PARAMETER Bpm
  Tempo in beats per minute.

.PARAMETER Bars
  Number of bars to render.

.PARAMETER Swing
  Swing amount in [0..0.25]. 0.12-0.18 is typical hip-hop feel.
  Swing delays odd 16th steps by (Swing * 16th_duration).

.PARAMETER OutPath
  Optional path for the rendered WAV. If omitted, a temp file is used.

.PARAMETER Style
  Hip-hop style preset that configures BPM, swing, and instrument selection.
  BoomBap: 92 BPM, moderate swing, classic 90s feel
  OldSchool: 108 BPM, light swing, 80s breakbeat style
  Crunk: 80 BPM, minimal swing, heavy 808s and hat rolls

.PARAMETER AddClap
  Adds synthesized handclap layered on the 2 and 4 backbeats if set.

.PARAMETER AddBass
  Adds synthesized bass line if set.

.PARAMETER Use808
  Uses 808-style bass instead of regular bass (automatically enables bass).

.PARAMETER AddBrass
  Adds brass stabs if set.

.PARAMETER AddScratch
  Adds scratch sound effects if set.

.PARAMETER UseAll
  Forces all available instruments to be used (equivalent to -AddClap -AddBass -AddBrass -AddScratch).

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Bpm 88 -Bars 4 -Swing 0.16

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Bpm 110 -AddBass -AddClap

.EXAMPLE
  .\Make-HipHopBeat.ps1 -UseAll -Bpm 95

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Use808 -Bpm 75 -Swing 0.20

.NOTES
  All synthesis is in-script: no samples, no external modules.
#>
[CmdletBinding()]
param(
  [ValidateSet('BoomBap','OldSchool','Crunk')] [string]$Style = 'BoomBap',
  [ValidateRange(60,180)] [int]$Bpm = 0,  # 0 means use style default
  [ValidateRange(1,64)]  [int]$Bars = 4,
  [ValidateRange(0.0,0.25)] [double]$Swing = -1.0,  # -1 means use style default
  [string]$OutPath,
  [switch]$AddClap,
  [switch]$AddBass,
  [switch]$Use808,
  [switch]$AddBrass,
  [switch]$AddScratch,
  [switch]$AddShaker,
  [switch]$UseAll
)

# -------------------- Style presets configuration --------------------
# Apply style presets if Bpm or Swing weren't explicitly set
switch($Style) {
  'BoomBap' {
    if ($Bpm -eq 0) { $Bpm = 92 }
    if ($Swing -eq -1.0) { $Swing = 0.16 }
    # Classic 90s sound - moderate everything
    $StyleClap = $true
    $StyleBass = $true
    $StyleBrass = $false
    $StyleScratch = $true
    $StyleShaker = $true  # Classic boom bap loves shakers
    $Style808 = $false
  }
  'OldSchool' {
    if ($Bpm -eq 0) { $Bpm = 108 }
    if ($Swing -eq -1.0) { $Swing = 0.08 }
    # 80s breakbeat style - faster, tighter
    $StyleClap = $true
    $StyleBass = $true
    $StyleBrass = $true
    $StyleScratch = $false
    $StyleShaker = $true  # Shakers common in old school
    $Style808 = $false
  }
  'Crunk' {
    if ($Bpm -eq 0) { $Bpm = 80 }
    if ($Swing -eq -1.0) { $Swing = 0.02 }
    # Heavy, slow, minimal swing
    $StyleClap = $true
    $StyleBass = $true
    $StyleBrass = $false
    $StyleScratch = $true
    $StyleShaker = $false  # Crunk is more minimal
    $Style808 = $true  # Force 808 bass for crunk
  }
}

# Fallback defaults if still default values
if ($Bpm -eq 0) { $Bpm = 92 }
if ($Swing -eq -1.0) { $Swing = 0.16 }

# -------------------- Core audio settings --------------------
$SampleRate = 44100
$Channels = 2  # Stereo output

# -------------------- Instrument selection --------------------
# Determine which instruments to include
if ($UseAll) {
  # UseAll overrides individual switches and style
  $UseClap = $true
  $UseBass = $true
  $UseBrass = $true
  $UseScratch = $true
  $UseShaker = $true
} else {
  # Merge individual switches with style presets (switches take priority)
  $UseClap = $AddClap -or $StyleClap
  $UseBass = $AddBass -or $StyleBass -or $Use808 -or $Style808
  $UseBrass = $AddBrass -or $StyleBrass
  $UseScratch = $AddScratch -or $StyleScratch
  $UseShaker = $AddShaker -or $StyleShaker
}

# Handle 808 preference
if ($Use808 -or $Style808) {
  $Use808 = $true
  $UseBass = $true  # 808 implies bass
}

Write-Host "🎤 YO! Setting up the beat lab..." -ForegroundColor Cyan
Write-Host "🎵 Configuring that $Style flavor at $Bpm BPM with $Bars bars..." -ForegroundColor Yellow

Write-Host "`n🔥 TRACK LINEUP:" -ForegroundColor Magenta
Write-Host "  🥁 Kick: LOCKED AND LOADED (centerpiece)"
Write-Host "  🥁 Snare: READY TO CRACK (backbeat power)"
Write-Host "  🎩 Hat: ON DECK (that crispy top)"
Write-Host "  👏 Clap: $(if($UseClap){'CLAPPING BACK'}else{'SITTING THIS ONE OUT'})"
Write-Host "  🔊 Bass: $(if($UseBass){if($Use808){'808 BOOMING'}else{'BASS DROPPING'}}else{'SILENT TREATMENT'})"
Write-Host "  🎺 Brass: $(if($UseBrass){'HORNS UP'}else{'NO BRASS TODAY'})"
Write-Host "  🎧 Scratch: $(if($UseScratch){'TURNTABLES SPINNING'}else{'DECKS OFF'})"
Write-Host "  🥤 Shaker: $(if($UseShaker){'ADDING THAT TEXTURE'}else{'KEEPING IT CLEAN'})"

# -------------------- Utility: write stereo WAV ---------------------
function Write-Wav16 {
  param(
    [string]$Path,
    [double[]]$LeftSamples,
    [double[]]$RightSamples,
    [int]$SampleRate = 44100
  )

  $fs = $null
  $bw = $null

  try {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter($fs)

    $byteRate = $SampleRate * 2 * 2 # 16-bit stereo
    $blockAlign = 2 * 2
    $dataBytes = $LeftSamples.Length * 2 * 2  # L + R samples * 2 bytes each
    $riffSize = 36 + $dataBytes

    # RIFF header
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
    $bw.Write([UInt32]$riffSize)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))

    # fmt chunk
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
    $bw.Write([UInt32]16)               # PCM chunk size
    $bw.Write([UInt16]1)                # PCM format
    $bw.Write([UInt16]$Channels)        # channels (stereo)
    $bw.Write([UInt32]$SampleRate)      # sample rate
    $bw.Write([UInt32]$byteRate)        # byte rate
    $bw.Write([UInt16]$blockAlign)      # block align
    $bw.Write([UInt16]16)               # bits per sample

    # data chunk
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
    $bw.Write([UInt32]$dataBytes)

    # Interleave L/R samples
    for ($i = 0; $i -lt $LeftSamples.Length; $i++) {
      # Left sample
      $vL = [Math]::Max(-1.0, [Math]::Min(1.0, $LeftSamples[$i])) # hard clip
      $i16L = [int][Math]::Round($vL * 32767.0)
      $bw.Write([Int16]$i16L)

      # Right sample
      $vR = [Math]::Max(-1.0, [Math]::Min(1.0, $RightSamples[$i])) # hard clip
      $i16R = [int][Math]::Round($vR * 32767.0)
      $bw.Write([Int16]$i16R)
    }

    $bw.Flush()
  }
  catch {
    Write-Host "❌ Error writing WAV file: $($_.Exception.Message)" -ForegroundColor Red
    throw
  }
  finally {
    # Ensure proper cleanup of file handles
    if ($null -ne $bw) {
      try { $bw.Dispose() } catch { }
    }
    if ($null -ne $fs) {
      try { $fs.Dispose() } catch { }
    }
  }
}# -------------------- DSP helpers --------------------
$rand = New-Object System.Random

function Add-MixInto {
  param(
    [double[]]$Dest,
    [double[]]$Src,
    [int]$StartIndex,
    [double]$Gain = 1.0
  )
  $n = [Math]::Min($Src.Length, [Math]::Max(0, $Dest.Length - $StartIndex))
  for ($i = 0; $i -lt $n; $i++) {
    $Dest[$StartIndex + $i] += $Src[$i] * $Gain
  }
}

# -------------------- Stereo mixing functions --------------------
function Add-MixIntoStereo {
    param(
        [double[]]$L, [double[]]$R,
        [double[]]$Src, [int]$StartIndex,
        [double]$Gain = 1.0, [double]$Pan = 0.0
    )
    # Equal-power panning: -1 = hard left, 0 = center, +1 = hard right
    $pl = [Math]::Sqrt(0.5 * (1 - $Pan))
    $pr = [Math]::Sqrt(0.5 * (1 + $Pan))

    $n = [Math]::Min($Src.Length, [Math]::Max(0, $L.Length - $StartIndex))
    for($i=0; $i -lt $n; $i++){
        $idx = $StartIndex + $i
        if($idx -ge $L.Length){ break }
        $L[$idx] += $Gain * $pl * $Src[$i]
        $R[$idx] += $Gain * $pr * $Src[$i]
    }
}

# Haas effect for width (subtle L/R delay)
function Add-HaasStereo {
    param(
        [double[]]$L, [double[]]$R,
        [double[]]$Src, [int]$StartIndex,
        [double]$Gain = 1.0, [double]$Pan = 0.0, [double]$HaasMs = 9
    )
    $haas = [int]($HaasMs / 1000.0 * $SampleRate)

    for($i=0; $i -lt $Src.Length; $i++){
        $idx = $StartIndex + $i
        if($idx -ge $L.Length){ break }

        # Left on-time, right delayed (or vice versa based on pan)
        if ($Pan -le 0) {
            # Pan left: left on-time, right delayed
            $L[$idx] += $Gain * $Src[$i]
            $rIdx = $idx + $haas
            if($rIdx -lt $R.Length){ $R[$rIdx] += $Gain * $Src[$i] }
        } else {
            # Pan right: right on-time, left delayed
            $R[$idx] += $Gain * $Src[$i]
            $lIdx = $idx + $haas
            if($lIdx -lt $L.Length){ $L[$lIdx] += $Gain * $Src[$i] }
        }
    }
}

# Stereo slapback send for space
function Add-SlapbackStereo {
    param([double[]]$L,[double[]]$R,[double[]]$Src,[int]$Start,[double]$Ms=85,[double]$Gain=0.18,[double]$Pan=0.0)
    $d=[int]($Ms/1000.0*$SampleRate)
    $pl = [Math]::Sqrt(0.5*(1 - $Pan))
    $pr = [Math]::Sqrt(0.5*(1 + $Pan))

    for($i=0;$i -lt $Src.Length;$i++){
        $idx = $Start + $d + $i
        if($idx -ge $L.Length){ break }
        # Mirror-ish: send more to the opposite side of the dry
        $L[$idx] += $Gain * $pr * $Src[$i]
        $R[$idx] += $Gain * $pl * $Src[$i]
    }
}

# Pan wobble for shakers (simulates hand movement)
function Add-WobblePan {
    param(
        [double[]]$L, [double[]]$R,
        [double[]]$Src, [int]$StartIndex,
        [double]$Gain = 1.0, [double]$BasePan = 0.0, [double]$Depth = 0.08, [double]$RateHz = 0.35
    )
    $randomPhase = Get-Random -Minimum 0.0 -Maximum 6.28

    for($i=0; $i -lt $Src.Length; $i++){
        $t = ($i / $SampleRate)
        $pan = $BasePan + $Depth * [Math]::Sin(2*[Math]::PI*$RateHz*$t + $randomPhase)

        # Equal-power panning per sample
        $pl = [Math]::Sqrt(0.5*(1 - $pan))
        $pr = [Math]::Sqrt(0.5*(1 + $pan))
        $idx = $StartIndex + $i
        if($idx -ge $L.Length){ break }
        $L[$idx] += $Gain * $pl * $Src[$i]
        $R[$idx] += $Gain * $pr * $Src[$i]
    }
}

function Set-NormalizedLevel {
  param([double[]]$Samples, [double]$Target = 0.95)
  $max = 0.0
  foreach ($s in $Samples) { $a = [Math]::Abs($s); if ($a -gt $max) { $max = $a } }
  if ($max -gt 0) {
    $g = $Target / $max
    for ($i=0; $i -lt $Samples.Length; $i++) { $Samples[$i] *= $g }
  }
}

# Simple one-pole highpass (difference) for noise brightening
function Set-HighpassFilter {
  param([double[]]$x, [double]$alpha = 0.98)
  $y = New-Object double[] $x.Length
  $prev = 0.0
  for ($i=0; $i -lt $x.Length; $i++) {
    $y[$i] = $alpha * ($y[[Math]::Max(0,$i-1)]) + $x[$i] - $prev
    $prev = $x[$i]
  }
  return ,$y
}

# Exponential decay envelope
function New-ExponentialEnvelope {
  param([int]$Len, [double]$tau) # tau in seconds
  $env = New-Object double[] $Len
  for ($i=0; $i -lt $Len; $i++) {
    $t = $i / $SampleRate
    $env[$i] = [Math]::Exp(-$t / $tau)
  }
  return ,$env
}

# Multiply arrays
function Invoke-ArrayMultiply {
  param([double[]]$a, [double[]]$b)
  $n = [Math]::Min($a.Length, $b.Length)
  $out = New-Object double[] $n
  for ($i=0; $i -lt $n; $i++) { $out[$i] = $a[$i] * $b[$i] }
  return ,$out
}

# -------------------- Drum Synths --------------------
function New-SynthKick {
  param([double]$LengthSec = 0.25, [double]$f0 = 120, [double]$f1 = 40)
  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0
  for ($i=0; $i -lt $len; $i++) {
    $t = $i / $SampleRate
    # exponential freq sweep f(t) = f1 + (f0 - f1)*exp(-t*k)
    $k = 8.0
    $f = $f1 + ($f0 - $f1) * [Math]::Exp(-$k * $t)
    $phase += (2.0 * [Math]::PI * $f) / $SampleRate
    $out[$i] = [Math]::Sin($phase)
  }
  # amplitude envelope: quick thump
  $env = New-ExponentialEnvelope -Len $len -tau 0.12
  $out = Invoke-ArrayMultiply $out $env
  # subtle saturation
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(2.5 * $out[$i]) }
  return ,$out
}

function New-SynthSnare {
  param([double]$LengthSec = 0.25)
  $len = [int]($LengthSec * $SampleRate)
  $tone = New-Object double[] $len
  $noise = New-Object double[] $len
  $phase = 0.0
  $f = 190.0
  for ($i=0; $i -lt $len; $i++) {
    $phase += (2.0 * [Math]::PI * $f) / $SampleRate
    $tone[$i] = [Math]::Sin($phase)
    $noise[$i] = ($rand.NextDouble() * 2.0 - 1.0)
  }
  $toneEnv  = New-ExponentialEnvelope -Len $len -tau 0.08
  $noiseEnv = New-ExponentialEnvelope -Len $len -tau 0.05
  $tone  = Invoke-ArrayMultiply $tone  $toneEnv
  $noise = Invoke-ArrayMultiply $noise $noiseEnv
  $noise = Set-HighpassFilter $noise 0.995
  $out = New-Object double[] $len
  for ($i=0; $i -lt $len; $i++) { $out[$i] = 0.4*$tone[$i] + 0.9*$noise[$i] }
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(2.0 * $out[$i]) }
  return ,$out
}

function New-SynthHat {
  param([double]$LengthSec = 0.12)
  $len = [int]($LengthSec * $SampleRate)
  $noise = New-Object double[] $len
  for ($i=0; $i -lt $len; $i++) { $noise[$i] = ($rand.NextDouble() * 2.0 - 1.0) }
  $noise = Set-HighpassFilter $noise 0.995
  $env = New-ExponentialEnvelope -Len $len -tau 0.03
  $out = Invoke-ArrayMultiply $noise $env
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.6 * $out[$i]) }
  return ,$out
}

function New-SynthOpenHat {
  param([double]$LengthSec = 0.30)
  $len = [int]($LengthSec * $SampleRate)
  $noise = New-Object double[] $len
  for ($i=0; $i -lt $len; $i++) { $noise[$i] = ($rand.NextDouble() * 2.0 - 1.0) }
  $noise = Set-HighpassFilter $noise 0.997  # Even brighter than closed hat
  $env = New-ExponentialEnvelope -Len $len -tau 0.12  # Longer sustain for open sound
  $out = Invoke-ArrayMultiply $noise $env
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.4 * $out[$i]) }
  return ,$out
}

function New-SynthClap {
  param([double]$LengthSec = 0.35)
  # 3 quick noise bursts spaced ~15ms for a classic clap smear
  $base = New-SynthSnare -LengthSec $LengthSec
  $len = $base.Length
  $burst = New-Object double[] $len
  $delSamp = [int](0.015 * $SampleRate)
  $noiseBurst = New-Object double[] $len
  for ($i=0; $i -lt $len; $i++) { $noiseBurst[$i] = ($rand.NextDouble()*2-1.0) }
  $noiseBurst = Set-HighpassFilter $noiseBurst 0.997
  $env = New-ExponentialEnvelope -Len $len -tau 0.06
  $noiseBurst = Invoke-ArrayMultiply $noiseBurst $env

  Add-MixInto -Dest $burst -Src $noiseBurst -StartIndex 0     -Gain 0.9
  Add-MixInto -Dest $burst -Src $noiseBurst -StartIndex $delSamp     -Gain 0.6
  Add-MixInto -Dest $burst -Src $noiseBurst -StartIndex (2*$delSamp) -Gain 0.4

  $out = New-Object double[] $len
  for ($i=0; $i -lt $len; $i++) { $out[$i] = 0.6*$burst[$i] }
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.8 * $out[$i]) }
  return ,$out
}

function New-SynthShaker {
  param([double]$LenSec=0.12)
  $len=[int]($LenSec*$SampleRate)
  $out = New-Object double[] $len
  $rand = New-Object System.Random

  for($i=0;$i -lt $len;$i++){
    # white noise burst
    $n = 2*$rand.NextDouble()-1
    # band-pass effect (shakers live around 2–8kHz)
    $bp = $n - 0.98*$(if ($i -gt 0) { $out[$i-1] } else { 0 })
    # envelope (fast in, medium out)
    $env = [Math]::Exp(-15.0*($i/$SampleRate))
    $out[$i] = [Math]::Tanh(1.6 * $bp * $env)
  }

  ,$out
}

# -------------------- New Instruments --------------------
function New-SynthBass {
  param([double]$LengthSec = 0.5, [double]$frequency = 80)
  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i=0; $i -lt $len; $i++) {
    $t = $i / $SampleRate
    # Sub bass with slight frequency modulation for warmth
    $vibrato = 1.0 + 0.02 * [Math]::Sin(6.0 * 2.0 * [Math]::PI * $t)
    $currentFreq = $frequency * $vibrato
    $phase += (2.0 * [Math]::PI * $currentFreq) / $SampleRate

    # Square wave with low-pass filtering for warmth
    $square = if ([Math]::Sin($phase) -gt 0) { 1.0 } else { -1.0 }
    # Add sub harmonic
    $sub = 0.3 * [Math]::Sin($phase * 0.5)
    $out[$i] = 0.7 * $square + $sub
  }

  # Apply envelope - longer sustain for bass
  $env = New-ExponentialEnvelope -Len $len -tau 0.25
  $out = Invoke-ArrayMultiply $out $env

  # Soft saturation
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.5 * $out[$i]) }
  return ,$out
}

function New-Synth808 {
  param([double]$LenSec = 0.6, [double]$f0 = 48, [double]$Drive = 1.3)
  $len = [int]($LenSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate
    # Quick down-chirp: punch then settle to fundamental
    $f = $f0 + 22.0 * [Math]::Exp(-20.0 * $t)
    $phase += (2.0 * [Math]::PI * $f) / $SampleRate
    $env = [Math]::Exp(-2.2 * $t)  # Long but decaying envelope
    $out[$i] = $env * [Math]::Sin($phase)
  }

  # Heavy saturation for that 808 character
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh($Drive * $out[$i]) }
  return ,$out
}

function New-SynthBrass {
  param([double]$LengthSec = 0.15, [double]$frequency = 220)
  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i=0; $i -lt $len; $i++) {
    $phase += (2.0 * [Math]::PI * $frequency) / $SampleRate

    # Sawtooth wave with harmonics for brass-like sound
    $saw = 0.0
    for ($h=1; $h -le 8; $h++) {
      $harmonic = [Math]::Sin($phase * $h) / $h
      $saw += $harmonic
    }
    $out[$i] = $saw * 0.3
  }

  # Sharp attack, quick decay envelope
  $env = New-ExponentialEnvelope -Len $len -tau 0.08
  # Add attack punch
  for ($i=0; $i -lt [Math]::Min(100, $len); $i++) {
    $env[$i] *= (1.0 + 2.0 * [Math]::Exp(-$i * 0.05))
  }
  $out = Invoke-ArrayMultiply $out $env

  # Hard saturation for punch
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(3.0 * $out[$i]) }
  return ,$out
}

function New-SynthScratch {
  param([double]$LengthSec = 0.2)
  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len

  # Create scratch by modulating noise with a quick frequency sweep
  for ($i=0; $i -lt $len; $i++) {
    $t = $i / $SampleRate
    $noise = ($rand.NextDouble() * 2.0 - 1.0)

    # Frequency modulation for scratch effect
    $scratchFreq = 200.0 + 800.0 * [Math]::Sin(15.0 * 2.0 * [Math]::PI * $t)
    $phase = $scratchFreq * $t * 2.0 * [Math]::PI
    $carrier = [Math]::Sin($phase)

    $out[$i] = $noise * $carrier * 0.8
  }

  # Highpass to make it scratchy
  $out = Set-HighpassFilter $out 0.97

  # Quick envelope
  $env = New-ExponentialEnvelope -Len $len -tau 0.04
  $out = Invoke-ArrayMultiply $out $env

  # Heavy saturation for gritty sound
  for ($i=0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(4.0 * $out[$i]) }
  return ,$out
}

# Additional scratch variation with crossfader gate effect
function New-SynthScratchWicky {
  param([double]$LenSec=0.25)
  $len=[int]($LenSec*$SampleRate)
  $out=New-Object double[] $len
  $rand=New-Object System.Random
  $phase=0.0
  for($i=0;$i -lt $len;$i++){
    $t=$i/$SampleRate
    # varispeed sweep up then down
    $f = (600 + 1800*[Math]::Sin(2*[Math]::PI*3.0*$t))
    $phase += (2*[Math]::PI*$f)/$SampleRate
    # tone+noise mix
    $tone = 0.5*[Math]::Sin($phase)
    $noi  = 0.5*(2*$rand.NextDouble()-1)
    $sig  = $tone + $noi
    # crossfader gate (square LFO ~ 12 Hz)
    $gate = if (([Math]::Sin(2*[Math]::PI*12.0*$t) -ge 0)) { 1.0 } else { 0.0 }
    $env  = [Math]::Exp(-3.2*$t)
    $out[$i] = [Math]::Tanh(1.6 * $sig * $gate * $env)
  }
  ,$out
}

# Chirp scratch - quick high-to-low frequency sweep
function New-SynthScratchChirp {
  param([double]$LenSec=0.18)
  $len=[int]($LenSec*$SampleRate)
  $out=New-Object double[] $len
  $phase=0.0

  for($i=0;$i -lt $len;$i++){
    $t=$i/$SampleRate
    # Exponential frequency sweep from high to low
    $f = 2000 * [Math]::Exp(-8.0*$t) + 100
    $phase += (2*[Math]::PI*$f)/$SampleRate

    # Mix of tone and filtered noise
    $tone = [Math]::Sin($phase)
    $noise = (2*$rand.NextDouble()-1) * 0.3
    $sig = $tone + $noise

    # Sharp attack, quick decay
    $env = [Math]::Exp(-12.0*$t)
    $out[$i] = [Math]::Tanh(2.0 * $sig * $env)
  }
  ,$out
}

# Reverse scratch - low-to-high sweep with stutter
function New-SynthScratchReverse {
  param([double]$LenSec=0.22)
  $len=[int]($LenSec*$SampleRate)
  $out=New-Object double[] $len
  $phase=0.0

  for($i=0;$i -lt $len;$i++){
    $t=$i/$SampleRate
    # Rising frequency with wobble
    $f = 150 + 1200*$t + 300*[Math]::Sin(2*[Math]::PI*8.0*$t)
    $phase += (2*[Math]::PI*$f)/$SampleRate

    # Stutter gate effect
    $stutter = if (([Math]::Sin(2*[Math]::PI*20.0*$t) -gt -0.3)) { 1.0 } else { 0.2 }
    $sig = [Math]::Sin($phase) + 0.2*(2*$rand.NextDouble()-1)

    $env = [Math]::Exp(-4.0*$t)
    $out[$i] = [Math]::Tanh(1.8 * $sig * $stutter * $env)
  }
  ,$out
}

# -------------------- Sequence pattern --------------------
# 16-step pattern (4/4, 16ths). 1 = hit, 0 = rest.
# Style-specific patterns for different hip-hop genres

switch($Style) {
  'BoomBap' {
    # Classic 90s groove - moderate complexity
    $kick  = @(1,0,0,0, 0,1,0,0, 0,0,0,1, 0,0,1,0)  # "1, e of 2, a of 3"
    $snare = @(0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0)  # on 2 and 4
    $hat   = @(1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0)  # steady 8ths
    $hat[3] = 1; $hat[7] = 1; $hat[11] = 1; $hat[15] = 1  # extra 16th notes
    $openHat = @(0,0,0,0, 0,0,1,0, 0,0,0,0, 0,0,0,1)  # opens on "a of 2" and "a of 4"
    $bass   = @(1,0,0,0, 0,0,0,1, 0,0,1,0, 0,0,0,1)
    $brass  = @(0,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0)  # brass stab on 3
    $scratch= @(0,0,0,1, 0,0,0,0, 0,0,0,1, 0,0,0,0)  # scratch on offbeats
    $shaker = @(1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0)  # steady 8ths for boom bap texture

    # Pan configuration for classic console feel
    $KickPan = 0.0; $SnarePan = 0.0; $BassPan = 0.0  # Anchor the center
    $HatPan = 0.20; $OpenHatPan = 0.10  # Hats to the right
    $ShakerPan = -0.20  # Shaker to the left
    $ClapAlt = 0.15  # Clap alternating sides
    $BrassPan = 0.0  # Brass centered
    $ScratchPan = 0.10  # Scratch slightly right
    $SnareSlapMs = 90  # Slapback delay
    $UseHaas = $true; $HaasMs = 9  # Haas effect on hats
  }
  'OldSchool' {
    # 80s breakbeat style - more complex, faster feel
    $kick  = @(1,0,0,0, 1,0,0,0, 0,0,1,0, 0,1,0,0)  # More kicks for breakbeat feel
    $snare = @(0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0)  # classic backbeat
    $hat   = @(1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1)  # dense 16ths
    $openHat = @(0,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,0)  # minimal opens
    $bass   = @(1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,0,0)  # busier bassline
    $brass  = @(0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0)  # regular brass hits
    $scratch= @(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)  # no scratches in old school
    $shaker = @(1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1)  # steady 16ths for old school texture

    # Tighter stereo field for old school
    $KickPan = 0.0; $SnarePan = 0.0; $BassPan = 0.0
    $HatPan = 0.12; $OpenHatPan = 0.08  # Narrower spread
    $ShakerPan = -0.12
    $ClapAlt = 0.10  # Smaller clap movement
    $BrassPan = 0.05  # Brass slightly right
    $ScratchPan = 0.0
    $SnareSlapMs = 75  # Shorter slapback
    $UseHaas = $false  # No Haas for tighter sound
  }
  'Crunk' {
    # Heavy, slow, minimal - emphasis on low end
    $kick  = @(1,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0)  # Simple, heavy kicks
    $snare = @(0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0)  # backbeat only
    $hat   = @(1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0)  # base 8ths pattern
    # Dense 16ths with occasional 32nd rolls added later in rendering
    $hat[1] = 1; $hat[3] = 1; $hat[9] = 1; $hat[11] = 1
    $openHat = @(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,1,0)  # rare opens
    $bass   = @(1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,1,0)  # heavy 808 pattern
    $brass  = @(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)  # no brass in crunk
    $scratch= @(0,0,0,0, 0,0,0,1, 0,0,0,0, 0,0,0,1)  # occasional scratches
    $shaker = @(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)  # no shaker in crunk - too minimal

    # Moderate width - keep 808s centered for power
    $KickPan = 0.0; $SnarePan = 0.0; $BassPan = 0.0  # 808 bass must stay centered
    $HatPan = 0.15; $OpenHatPan = 0.10
    $ShakerPan = -0.10  # Not used but defined
    $ClapAlt = 0.10
    $BrassPan = -0.05  # Not used but defined
    $ScratchPan = 0.15  # Scratch to right
    $SnareSlapMs = 60  # Shorter, tighter slapback
    $UseHaas = $false  # Avoid Haas on dense 808s
  }
}

# -------------------- Render --------------------
# Calculate exact timing for perfect loop alignment
$secPerBeat = 60.0 / $Bpm

# For perfect gapless looping, we must have exact sample alignment
# Calculate samples per bar as the fundamental unit
$samplesPerBar = [int]([Math]::Round($secPerBeat * 4.0 * $SampleRate))
$totalSamples = $samplesPerBar * $Bars

# Stereo mix buffers
$mixL = New-Object double[] $totalSamples
$mixR = New-Object double[] $totalSamples

# Calculate exact step timing within a bar
$exactSamplesPerStep = $samplesPerBar / 16.0
$swingOffsetSamples = [int]([Math]::Round($Swing * $exactSamplesPerStep))

# Pre-synth voices with variations
# Create multiple variations of each instrument for more dynamic beats

Write-Host "`n🎛️ COOKING UP THE SOUNDS..." -ForegroundColor Green
Write-Host "⚡ Synthesizing drum kit variations..." -ForegroundColor DarkYellow

# Basic drums - create a few variations each
$kickVariations = @(
  (New-SynthKick -LengthSec 0.28 -f0 120 -f1 40),    # Standard
  (New-SynthKick -LengthSec 0.25 -f0 100 -f1 35),    # Tighter, lower
  (New-SynthKick -LengthSec 0.30 -f0 140 -f1 45)     # Punchier
)

$snareVariations = @(
  (New-SynthSnare -LengthSec 0.23),  # Standard
  (New-SynthSnare -LengthSec 0.20),  # Snappier
  (New-SynthSnare -LengthSec 0.26)   # Longer tail
)

$hatVariations = @(
  (New-SynthHat -LengthSec 0.10),  # Standard
  (New-SynthHat -LengthSec 0.08),  # Tighter
  (New-SynthHat -LengthSec 0.12)   # More open
)

$openHatVariations = @(
  (New-SynthOpenHat -LengthSec 0.30),  # Standard open
  (New-SynthOpenHat -LengthSec 0.25),  # Shorter open
  (New-SynthOpenHat -LengthSec 0.35)   # Longer open
)

# Clap variations
$clapVariations = @()
if ($UseClap) {
  Write-Host "👏 Crafting handclaps..." -ForegroundColor DarkCyan
  $clapVariations = @(
    (New-SynthClap -LengthSec 0.30),
    (New-SynthClap -LengthSec 0.25)
  )
}

# Bass with different notes (pentatonic-ish pattern for hip-hop)
$bassVariations = @()
if ($UseBass) {
  if ($Use808) {
    Write-Host "🔊 Dropping those 808 bombs..." -ForegroundColor Red
    # 808 frequencies (lower for that sub-bass feel)
    $bassFreqs = @(41, 46, 55, 65, 73)  # Roughly E1, F#1, A1, C2, D2
    $bassVariations = @()
    foreach ($freq in $bassFreqs) {
      $bassVariations += ,(New-Synth808 -LenSec 0.7 -f0 $freq -Drive 1.3)
    }
  } else {
    Write-Host "🎸 Laying down the bass foundation..." -ForegroundColor DarkGreen
    # Regular bass frequencies
    $bassFreqs = @(65, 73, 82, 98, 110)  # Roughly C2, D2, E2, G2, A2
    $bassVariations = @()
    foreach ($freq in $bassFreqs) {
      $bassVariations += ,(New-SynthBass -LengthSec 0.45 -frequency $freq)
    }
  }
}

# Brass with different pitches (chord tones)
$brassFreqs = @(180, 220, 270, 330)  # Various brass stab pitches
$brassVariations = @()
if ($UseBrass) {
  Write-Host "🎺 Heating up brass stabs..." -ForegroundColor Yellow
  $brassVariations = @()
  foreach ($freq in $brassFreqs) {
    $brassVariations += ,(New-SynthBrass -LengthSec 0.12 -frequency $freq)
  }
}

# Scratch variations with different characteristics - now with multiple scratch types!
$scratchVariations = @()
if ($UseScratch) {
  Write-Host "🎧 Spinning up the turntables..." -ForegroundColor Magenta
  # Mix of all scratch types for variety
  $scratchVariations = @(
    (New-SynthScratch -LengthSec 0.15),        # Standard frequency sweep
    (New-SynthScratch -LengthSec 0.10),        # Quick scratch
    (New-SynthScratch -LengthSec 0.20),        # Long scratch
    (New-SynthScratchWicky -LenSec 0.25),      # Crossfader "wicky-wick" effect
    (New-SynthScratchWicky -LenSec 0.18),      # Shorter wicky
    (New-SynthScratchChirp -LenSec 0.18),      # High-to-low chirp
    (New-SynthScratchChirp -LenSec 0.15),      # Quick chirp
    (New-SynthScratchReverse -LenSec 0.22),    # Low-to-high with stutter
    (New-SynthScratchReverse -LenSec 0.19)     # Faster reverse
  )
}

# Shaker variations with different lengths to mimic hand motion
$shakerVariations = @()
if ($UseShaker) {
  Write-Host "🥤 Shaking up some texture..." -ForegroundColor DarkMagenta
  $shakerVariations = @(
    (New-SynthShaker -LenSec 0.12),    # Standard shaker
    (New-SynthShaker -LenSec 0.08),    # Quick shake (mimics fast hand motion)
    (New-SynthShaker -LenSec 0.15)     # Longer shake (mimics slow hand motion)
  )
}

# Create consistent variation maps for the entire beat
# This ensures some repetition while still having variation
$kickVariationMap = @()
$snareVariationMap = @()
$hatVariationMap = @()
$openHatVariationMap = @()
$clapVariationMap = @()
$bassVariationMap = @()
$brassVariationMap = @()
$scratchVariationMap = @()
$shakerVariationMap = @()

# Generate variation maps for each 16-step pattern
for ($i = 0; $i -lt 16; $i++) {
  $kickVariationMap += Get-Random -Maximum $kickVariations.Length
  $snareVariationMap += Get-Random -Maximum $snareVariations.Length
  $hatVariationMap += Get-Random -Maximum $hatVariations.Length
  $openHatVariationMap += Get-Random -Maximum $openHatVariations.Length
  if ($UseClap -and $clapVariations.Length -gt 0) {
    $clapVariationMap += Get-Random -Maximum $clapVariations.Length
  }
  if ($UseBass -and $bassVariations.Length -gt 0) {
    $bassVariationMap += Get-Random -Maximum $bassVariations.Length
  }
  if ($UseBrass -and $brassVariations.Length -gt 0) {
    $brassVariationMap += Get-Random -Maximum $brassVariations.Length
  }
  if ($UseScratch -and $scratchVariations.Length -gt 0) {
    $scratchVariationMap += Get-Random -Maximum $scratchVariations.Length
  }
  if ($UseShaker -and $shakerVariations.Length -gt 0) {
    $shakerVariationMap += Get-Random -Maximum $shakerVariations.Length
  }
}

# Initialize open hat choke tracking
$openTailEnd = -1

Write-Host "`n🎚️ MIXING IT DOWN..." -ForegroundColor Cyan
Write-Host "🔄 Sequencing $Bars bars with $Style groove..." -ForegroundColor Green
Write-Host "🎭 Applying stereo magic and pan positions..." -ForegroundColor Yellow

for ($bar=0; $bar -lt $Bars; $bar++) {
  if ($bar -eq 0) {
    Write-Host "🎵 Bar 1: Dropping the beat..." -ForegroundColor DarkGreen
  } elseif ($bar -eq [Math]::Floor($Bars/2)) {
    Write-Host "🔥 Halfway through - keeping that energy..." -ForegroundColor DarkYellow
  } elseif ($bar -eq ($Bars-1)) {
    Write-Host "🏁 Final bar - bringing it home..." -ForegroundColor DarkRed
  }

  for ($step=0; $step -lt 16; $step++) {
    # Calculate exact position within the bar, then add bar offset
    $stepPositionInBar = $step * $exactSamplesPerStep

    # Apply swing to odd steps (0-based: steps 1,3,5,7,9,11,13,15 are swing steps)
    if (($step % 2) -eq 1) {
      $stepPositionInBar += $swingOffsetSamples
    }

    # Calculate final position: bar start + step position
    $barStartSample = $bar * $samplesPerBar
    $start = $barStartSample + [int]([Math]::Round($stepPositionInBar))

    # Use variations for more dynamic sound
    # Kick with 808 ducking logic
    if ($kick[$step] -eq 1) {
      $kickBuf = $kickVariations[$kickVariationMap[$step]]
      # Duck kick when 808 bass hits at same time to avoid mud
      if ($Use808 -and $bass[$step] -eq 1) {
        Add-MixIntoStereo -L $mixL -R $mixR -Src $kickBuf -StartIndex $start -Gain 0.65 -Pan $KickPan  # Ducked
      } else {
        Add-MixIntoStereo -L $mixL -R $mixR -Src $kickBuf -StartIndex $start -Gain 0.95 -Pan $KickPan  # Normal
      }
    }

    if ($snare[$step] -eq 1) {
      $snareBuf = $snareVariations[$snareVariationMap[$step]]
      Add-MixIntoStereo -L $mixL -R $mixR -Src $snareBuf -StartIndex $start -Gain 0.90 -Pan $SnarePan

      # Add slapback for space (boom bap loves slapbacks)
      if ($SnareSlapMs -gt 0) {
        Add-SlapbackStereo -L $mixL -R $mixR -Src $snareBuf -Start $start -Ms $SnareSlapMs -Gain 0.16 -Pan $SnarePan
      }

      if ($UseClap -and $clapVariations.Length -gt 0) {
        $clapBuf = $clapVariations[$clapVariationMap[$step]]
        # Clap alternating sides for width
        $clapPan = if ((($bar + $step) % 2 -eq 0)) { -$ClapAlt } else { $ClapAlt }
        Add-MixIntoStereo -L $mixL -R $mixR -Src $clapBuf -StartIndex $start -Gain 0.65 -Pan $clapPan
      }
    }

    if ($hat[$step] -eq 1) {
      # Check if we need to choke an open hat first
      if ($openTailEnd -gt $start) {
        # Choke the open hat tail by reducing its volume dramatically
        for ($i = $start; $i -lt [Math]::Min($openTailEnd, $mixL.Length); $i++) {
          $mixL[$i] *= 0.15  # Reduce to 15% volume for realistic choke
          $mixR[$i] *= 0.15
        }
        $openTailEnd = -1  # Reset tail tracking
      }

      $hatBuf = $hatVariations[$hatVariationMap[$step]]

      # Use Haas effect for width if enabled by style
      if ($UseHaas) {
        Add-HaasStereo -L $mixL -R $mixR -Src $hatBuf -StartIndex $start -Gain 0.35 -Pan $HatPan -HaasMs $HaasMs
      } else {
        Add-MixIntoStereo -L $mixL -R $mixR -Src $hatBuf -StartIndex $start -Gain 0.35 -Pan $HatPan
      }

      # Crunk style: add occasional 32nd note hat rolls near bar end
      if ($Style -eq 'Crunk' -and $step -ge 12 -and (Get-Random) -lt 0.25) {
        # Add 32nd note roll after the main hat
        $stepSamp = $exactSamplesPerStep
        $maxJit = [int]($stepSamp * 0.02)  # Small timing jitter
        0..3 | ForEach-Object {
          $rollStart = $start + [int]($_ * ($stepSamp/4))  # 32nd notes = quarter of 16th
          if ($rollStart -lt $mixL.Length) {
            $rollGain = 0.15 + 0.10 * $_  # Crescendo effect
            $jitter = Get-Random -Minimum (-$maxJit) -Maximum $maxJit
            Add-MixIntoStereo -L $mixL -R $mixR -Src $hatBuf -StartIndex ($rollStart + $jitter) -Gain $rollGain -Pan $HatPan
          }
        }
      }
    }

    # Open hat logic with choke tracking
    if ($openHat[$step] -eq 1) {
      $openHatBuf = $openHatVariations[$openHatVariationMap[$step]]
      Add-MixIntoStereo -L $mixL -R $mixR -Src $openHatBuf -StartIndex $start -Gain 0.45 -Pan $OpenHatPan
      $openTailEnd = $start + $openHatBuf.Length  # Track where the open hat tail ends
    }

    # Add new instruments with variations
    if ($UseBass -and $bass[$step] -eq 1 -and $bassVariations.Length -gt 0) {
      $bassBuf = $bassVariations[$bassVariationMap[$step]]
      # 808s get more gain since they're the primary bass element
      $bassGain = if ($Use808) { 0.85 } else { 0.75 }
      Add-MixIntoStereo -L $mixL -R $mixR -Src $bassBuf -StartIndex $start -Gain $bassGain -Pan $BassPan
    }

    if ($UseBrass -and $brass[$step] -eq 1 -and $brassVariations.Length -gt 0) {
      $brassBuf = $brassVariations[$brassVariationMap[$step]]
      Add-MixIntoStereo -L $mixL -R $mixR -Src $brassBuf -StartIndex $start -Gain 0.60 -Pan $BrassPan
    }

    if ($UseScratch -and $scratch[$step] -eq 1 -and $scratchVariations.Length -gt 0) {
      # Enhanced scratch selection for more realistic turntablism
      $scratchChoice = 0

      # Pattern-based selection: different scratch types for different positions
      if ($step -ge 14) {
        # End of bar - prefer longer, dramatic scratches (wicky or reverse)
        $scratchChoice = if ((Get-Random -Maximum 2) -eq 0) {
          # 50% chance for crossfader effects (wicky variations)
          Get-Random -Minimum 3 -Maximum 5
        } else {
          # 50% chance for reverse scratches
          Get-Random -Minimum 7 -Maximum 9
        }
      } elseif (($step % 4) -eq 2) {
        # On the "e" of beats - prefer quick chirps
        $scratchChoice = Get-Random -Minimum 5 -Maximum 7
      } else {
        # General scratches - mix of everything with bias toward shorter ones
        $scratchChoice = if ((Get-Random -Maximum 4) -eq 0) {
          # 25% chance for any variation
          Get-Random -Maximum $scratchVariations.Length
        } else {
          # 75% chance for standard scratches (first 3 are original types)
          Get-Random -Maximum 3
        }
      }

      # Safety check for array bounds
      if ($scratchChoice -ge $scratchVariations.Length) {
        $scratchChoice = $scratchVariationMap[$step]
      }

      $scratchBuf = $scratchVariations[$scratchChoice]
      # Adjust gain based on scratch type for better mix balance
      $scratchGain = if ($scratchChoice -ge 3) { 0.40 } else { 0.50 }  # New scratches slightly quieter
      Add-MixIntoStereo -L $mixL -R $mixR -Src $scratchBuf -StartIndex $start -Gain $scratchGain -Pan $ScratchPan
    }

    # Shaker with wobble pan for realistic hand movement
    if ($UseShaker -and $shaker[$step] -eq 1 -and $shakerVariations.Length -gt 0) {
      $shakerBuf = $shakerVariations[$shakerVariationMap[$step]]
      # Use wobble pan for organic feel
      Add-WobblePan -L $mixL -R $mixR -Src $shakerBuf -StartIndex $start -Gain 0.25 -BasePan $ShakerPan -Depth 0.08 -RateHz 0.35
    }
  }
}

Write-Host "`n🎛️ FINAL MIXDOWN PROCESS..." -ForegroundColor Magenta
Write-Host "🔧 Applying master bus compression (tanh saturation)..." -ForegroundColor DarkYellow

# Gentle master bus limiting via tanh, then normalize both channels
for ($i=0; $i -lt $mixL.Length; $i++) {
  $mixL[$i] = [Math]::Tanh(1.2 * $mixL[$i])
  $mixR[$i] = [Math]::Tanh(1.2 * $mixR[$i])
}

Write-Host "📊 Analyzing peaks and normalizing stereo field..." -ForegroundColor DarkCyan

# Normalize stereo - find peak across both channels
$maxPeak = 0.0
for ($i=0; $i -lt $mixL.Length; $i++) {
  $peakL = [Math]::Abs($mixL[$i])
  $peakR = [Math]::Abs($mixR[$i])
  $peak = [Math]::Max($peakL, $peakR)
  if ($peak -gt $maxPeak) { $maxPeak = $peak }
}

if ($maxPeak -gt 0) {
  $normGain = 0.95 / $maxPeak
  for ($i=0; $i -lt $mixL.Length; $i++) {
    $mixL[$i] *= $normGain
    $mixR[$i] *= $normGain
  }
  Write-Host "✨ Normalized to 95% peak with gain of $([Math]::Round($normGain, 3))" -ForegroundColor Green
}

# Output path
if (-not $OutPath) {
  $name = "HipHopBeat_${Style}_${Bpm}bpm_${Bars}bars_stereo.wav"
  $OutPath = Join-Path $env:TEMP $name
} else {
  # Extract filename from provided path
  $name = Split-Path $OutPath -Leaf
}

Write-Host "`n💾 BOUNCING TO WAV..." -ForegroundColor Cyan
Write-Host "📁 Rendering stereo file: $name" -ForegroundColor Yellow

try {
  Write-Wav16 -Path $OutPath -LeftSamples $mixL -RightSamples $mixR -SampleRate $SampleRate
  Write-Host "✅ WAV file written successfully!" -ForegroundColor Green
}
catch {
  Write-Host "❌ Failed to write WAV file: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "🚨 Exiting due to file write error." -ForegroundColor Red
  exit 1
}

# Playback with proper resource cleanup
$player = $null
try {
  $player = New-Object System.Media.SoundPlayer $OutPath
  $player.Load()

  Write-Host "`n🎧 PLAYBACK TIME!" -ForegroundColor Green
  Write-Host "🔊 File saved: $OutPath" -ForegroundColor White
  Write-Host "🎵 Press any key after listening to exit..." -ForegroundColor DarkGreen

  $player.PlaySync()

  Write-Host "`n✨ THAT'S A WRAP! Beat completed successfully! ✨" -ForegroundColor Magenta
  Write-Host "🎤 Drop the mic... 🎤" -ForegroundColor Red
}
catch {
  Write-Host "`n❌ Error during playback: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "🔊 File still saved successfully: $OutPath" -ForegroundColor Yellow
}
finally {
  # Ensure proper cleanup of audio resources
  if ($null -ne $player) {
    try {
      $player.Stop()
      $player.Dispose()
      Write-Host "🧹 Audio player resources cleaned up." -ForegroundColor DarkGray
    }
    catch {
      # Ignore disposal errors - player might already be disposed
    }
  }

  # Force garbage collection to release any remaining handles
  [System.GC]::Collect()
  [System.GC]::WaitForPendingFinalizers()
}