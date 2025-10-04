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

.PARAMETER OutputFolder
  Optional folder path where the rendered WAV will be saved with an auto-generated name. If omitted, the temp folder is used.

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

.PARAMETER SkipPlayback
  Skips audio playback after generating the WAV file. The file will still be saved.

.PARAMETER DontMakeSeamless
  Disables seamless loop processing. By default, all beats are processed into perfect loops.

.PARAMETER TailMs
  Size of the tail window (ms) for seamless loop detection. Default: 200.

.PARAMETER SearchHeadMs
  How far into the head to search for loop match (ms). Default: 1500.

.PARAMETER XfadeMs
  Crossfade length (ms) for seamless loop. Default: 12.

.PARAMETER GridSnapWindowMs
  Max distance (ms) to nudge loop start to nearest beat boundary. Default: 30.

.PARAMETER BeatsPerBar
  Time signature beats per bar (e.g., 4 for 4/4, 3 for 3/4). Default: 4.

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Bpm 88 -Bars 4 -Swing 0.16

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Bpm 110 -AddBass -AddClap

.EXAMPLE
  .\Make-HipHopBeat.ps1 -UseAll -Bpm 95

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Use808 -Bpm 75 -Swing 0.20

.EXAMPLE
  .\Make-HipHopBeat.ps1 -Style BoomBap -Bars 4

.EXAMPLE
  .\Make-HipHopBeat.ps1 -DontMakeSeamless -UseAll -Bpm 95

.NOTES
  All synthesis is in-script: no samples, no external modules.
  By default, beats are processed into seamless loops. Use -DontMakeSeamless to disable.
#>
[CmdletBinding()]
param(
  [ValidateSet('BoomBap', 'OldSchool', 'Crunk')] [string]$Style = 'BoomBap',
  [ValidateRange(60, 180)] [int]$Bpm = 0,  # 0 means use style default
  [ValidateRange(1, 64)]  [int]$Bars = 4,
  [ValidateRange(0.0, 0.25)] [double]$Swing = -1.0,  # -1 means use style default
  [string]$OutputFolder,
  [switch]$AddClap,
  [switch]$AddBass,
  [switch]$Use808,
  [switch]$AddBrass,
  [switch]$AddScratch,
  [switch]$AddShaker,
  [switch]$UseAll,
  [switch]$SkipPlayback,
  [switch]$DontMakeSeamless,
  [int]$TailMs = 200,
  [int]$SearchHeadMs = 1500,
  [int]$XfadeMs = 12,
  [int]$GridSnapWindowMs = 30,
  [int]$BeatsPerBar = 4
)

# -------------------- Style presets configuration --------------------
# Apply style presets if Bpm or Swing weren't explicitly set
switch ($Style) {
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

# -------------------- Validate OutputFolder --------------------
if ($OutputFolder) {
  # Check if the provided path exists
  if (-not (Test-Path $OutputFolder)) {
    Write-Host "❌ ERROR: The specified OutputFolder does not exist: $OutputFolder" -ForegroundColor Red
    Write-Host "🚨 Please provide a valid folder path." -ForegroundColor Red
    exit 1
  }

  # Check if it's actually a directory (not a file)
  if (-not (Test-Path $OutputFolder -PathType Container)) {
    Write-Host "❌ ERROR: The specified OutputFolder is not a directory: $OutputFolder" -ForegroundColor Red
    Write-Host "🚨 Please provide a folder path, not a file path." -ForegroundColor Red
    exit 1
  }

  Write-Host "✅ Output folder validated: $OutputFolder" -ForegroundColor Green
}

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
}
else {
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
    # Open file stream for writing binary WAV data
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter($fs)

    # Calculate WAV file format parameters
    $byteRate = $SampleRate * 2 * 2 # 16-bit stereo (2 channels * 2 bytes)
    $blockAlign = 2 * 2              # Bytes per sample frame
    $dataBytes = $LeftSamples.Length * 2 * 2  # L + R samples * 2 bytes each
    $riffSize = 36 + $dataBytes      # Total file size minus 8 bytes

    # Write RIFF header - identifies file as WAVE format
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
    $bw.Write([UInt32]$riffSize)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))

    # Write fmt chunk - defines audio format properties
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
    $bw.Write([UInt32]16)               # PCM chunk size
    $bw.Write([UInt16]1)                # PCM format (uncompressed)
    $bw.Write([UInt16]$Channels)        # Number of channels (stereo = 2)
    $bw.Write([UInt32]$SampleRate)      # Sample rate in Hz
    $bw.Write([UInt32]$byteRate)        # Bytes per second
    $bw.Write([UInt16]$blockAlign)      # Bytes per sample frame
    $bw.Write([UInt16]16)               # Bits per sample

    # Write data chunk header
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
    $bw.Write([UInt32]$dataBytes)

    # Interleave L/R samples and write as 16-bit signed integers
    for ($i = 0; $i -lt $LeftSamples.Length; $i++) {
      # Process left sample: clamp to [-1, 1] and convert to 16-bit integer
      $vL = [Math]::Max(-1.0, [Math]::Min(1.0, $LeftSamples[$i])) # hard clip
      $i16L = [int][Math]::Round($vL * 32767.0)
      $bw.Write([Int16]$i16L)

      # Process right sample: clamp to [-1, 1] and convert to 16-bit integer
      $vR = [Math]::Max(-1.0, [Math]::Min(1.0, $RightSamples[$i])) # hard clip
      $i16R = [int][Math]::Round($vR * 32767.0)
      $bw.Write([Int16]$i16R)
    }

    # Ensure all data is written to disk
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
}

# -------------------- Seamless Loop Processing Functions --------------------

function Convert-MsToSamples {
  param([int]$Ms, [int]$SampleRate)
  # Convert milliseconds to sample count at given sample rate
  [int][math]::Round(($Ms * $SampleRate) / 1000.0)
}


function Remove-DCOffset([single[]]$x) {
  # Calculate mean value of the signal
  $sum = 0.0
  for ($i=0; $i -lt $x.Length; $i++) { $sum += $x[$i] }
  $mean = [single]($sum / [math]::Max(1,$x.Length))

  # Subtract mean from each sample to center around zero
  for ($i=0; $i -lt $x.Length; $i++) { $x[$i] = [single]($x[$i] - $mean) }
  return $x
}


function Convert-ToMono {
  param([single[]]$Interleaved, [int]$Channels)

  # If already mono, just return a copy
  if ($Channels -le 1) { return [single[]]$Interleaved.Clone() }

  # Calculate number of audio frames
  $frames = [int]($Interleaved.Length / $Channels)
  $mono = New-Object 'System.Single[]' $frames
  $idx = 0

  # Average all channels into single mono channel
  for ($f=0; $f -lt $frames; $f++) {
    $sum = 0.0
    for ($c=0; $c -lt $Channels; $c++) { $sum += $Interleaved[$idx + $c] }
    $mono[$f] = [single]($sum / $Channels)
    $idx += $Channels
  }

  return $mono
}


function Get-BestOffsetByNCCF {
  param([single[]]$Mono, [int]$TailLen, [int]$SearchLen)

  # Extract tail portion from end of audio
  $N = $Mono.Length
  $tailStart = $N - $TailLen
  if ($tailStart -lt 0) { throw "Audio too short for tailLen=$TailLen" }

  $tail = New-Object 'System.Single[]' $TailLen
  [array]::Copy($Mono, $tailStart, $tail, 0, $TailLen)

  # Calculate normalization factor for tail (RMS)
  $tailNorm = 0.0
  for ($i=0; $i -lt $TailLen; $i++) { $tailNorm += $tail[$i]*$tail[$i] }
  $tailNorm = [math]::Sqrt($tailNorm) + 1e-12

  # Search for best match using normalized cross-correlation
  $maxOffset = [math]::Min($SearchLen, $N - $TailLen - 1)
  $best = [double]::NegativeInfinity
  $bestOff = 0

  for ($off=0; $off -lt $maxOffset; $off++) {
    # Calculate correlation coefficient at this offset
    $dot = 0.0; $headNorm = 0.0
    for ($i=0; $i -lt $TailLen; $i++) {
      $hv = $Mono[$off + $i]
      $tv = $tail[$i]
      $dot += $hv * $tv
      $headNorm += $hv * $hv
    }

    # Normalized cross-correlation function (NCCF)
    $nccf = $dot / ([math]::Sqrt($headNorm) * $tailNorm + 1e-12)

    # Track the best correlation
    if ($nccf -gt $best) { $best = $nccf; $bestOff = $off }
  }

  return $bestOff
}


function Get-ZeroCrossingSnap {
  param([single[]]$X, [int]$Idx, [int]$Window)

  # Define search window around target index
  $start = [math]::Max(1, $Idx - $Window)
  $end   = [math]::Min($X.Length - 2, $Idx + $Window)
  $best = $Idx
  $bestScore = [single]::PositiveInfinity

  # Determine expected crossing direction from target location
  $left  = $X[[math]::Max(0, $Idx - 1)]
  $right = $X[[math]::Min($X.Length - 1, $Idx + 1)]
  $targetSign = [math]::Sign($right - $left)
  if ($targetSign -eq 0) { $targetSign = 1 }

  # Search for zero crossings within window
  for ($i=$start; $i -le $end; $i++) {
    $a = $X[$i-1]; $b = $X[$i]

    # Check if this is a zero crossing point
    if ( ($a -le 0 -and $b -gt 0) -or ($a -ge 0 -and $b -lt 0) ) {
      # Calculate slope direction
      $sign = [math]::Sign($X[$i+1] - $X[$i-1])

      # Penalize wrong slope direction
      $slopePenalty = if ($sign -eq 0) { 1 } elseif ($sign -eq $targetSign) { 0 } else { 2 }

      # Penalize high magnitude crossings (prefer closer to actual zero)
      $magPenalty = [math]::Abs($a) + [math]::Abs($b)

      # Calculate total score (lower is better)
      $score = [single]($slopePenalty * 10 + $magPenalty)

      if ($score -lt $bestScore) { $bestScore = $score; $best = $i }
    }
  }

  return $best
}

function Invoke-SeamCrossfadeCircular {
  param(
    [single[]]$Interleaved, [int]$Channels,
    [int]$LoopStartFrame, [int]$LoopLengthFrames, [int]$XfadeFrames
  )

  $totalFrames = [int]($Interleaved.Length / $Channels)
  if ($XfadeFrames -le 0) { return $Interleaved }
  if ($XfadeFrames * 2 -ge $LoopLengthFrames) { throw "Xfade too long for loop length." }

  # Calculate loop end position
  $loopEndFrame = $LoopStartFrame + $LoopLengthFrames

  # Apply equal-power crossfade between loop tail and head
  for ($n=0; $n -lt $XfadeFrames; $n++) {
    # Calculate crossfade position (0 to 1)
    $t = ($n + 0.5) / $XfadeFrames

    # Equal-power crossfade curves
    $gainA = [math]::Cos($t * [math]::PI / 2.0)  # tail: 1 -> 0
    $gainB = [math]::Sin($t * [math]::PI / 2.0)  # head: 0 -> 1

    # Calculate frame indices with circular wrapping
    $tailFrame = ($loopEndFrame - $XfadeFrames + $n) % $totalFrames
    if ($tailFrame -lt 0) { $tailFrame += $totalFrames }
    $headFrame = ($LoopStartFrame + $n) % $totalFrames

    # Apply crossfade to all channels
    for ($c=0; $c -lt $Channels; $c++) {
      $ti = $tailFrame * $Channels + $c
      $hi = $headFrame * $Channels + $c
      # Blend tail and head samples using crossfade curves
      $Interleaved[$hi] = [single]($Interleaved[$ti] * $gainA + $Interleaved[$hi] * $gainB)
    }
  }

  return $Interleaved
}


function Copy-CircularSegment {
  param([single[]]$Interleaved, [int]$Channels, [int]$StartFrame, [int]$LengthFrames)

  $totalFrames = [int]($Interleaved.Length / $Channels)
  $out = New-Object 'System.Single[]' ($LengthFrames * $Channels)

  # Copy samples with circular buffer logic
  for ($n=0; $n -lt $LengthFrames; $n++) {
    # Calculate source frame with wrap-around
    $srcFrame = ($StartFrame + $n) % $totalFrames
    $srcIdx = $srcFrame * $Channels
    $dstIdx = $n * $Channels

    # Copy all channels for this frame
    [array]::Copy($Interleaved, $srcIdx, $out, $dstIdx, $Channels)
  }

  return $out
}

function Invoke-SeamlessLoop {
  param(
    [double[]]$LeftChannel,
    [double[]]$RightChannel,
    [int]$SampleRate,
    [double]$Bpm,
    [int]$Bars,
    [int]$BeatsPerBar,
    [int]$TailMs,
    [int]$SearchHeadMs,
    [int]$XfadeMs,
    [int]$GridSnapWindowMs
  )

  Write-Host "`n🔁 APPLYING SEAMLESS LOOP PROCESSING..." -ForegroundColor Cyan

  # Convert stereo to interleaved single precision for processing
  $frames = $LeftChannel.Length
  $interleaved = New-Object 'System.Single[]' ($frames * 2)
  for ($i=0; $i -lt $frames; $i++) {
    $interleaved[$i * 2]     = [single]$LeftChannel[$i]
    $interleaved[$i * 2 + 1] = [single]$RightChannel[$i]
  }

  # Create mono mix for analysis
  $mono = Convert-ToMono -Interleaved $interleaved -Channels 2
  $mono = Remove-DCOffset $mono

  # Calculate parameters
  $tailLen   = [math]::Clamp((Convert-MsToSamples -Ms $TailMs -SampleRate $SampleRate), 1024, [math]::Min([int]($mono.Length/2), $SampleRate))
  $searchLen = [math]::Clamp((Convert-MsToSamples -Ms $SearchHeadMs -SampleRate $SampleRate), 1024, [math]::Min($mono.Length - $tailLen - 1, $SampleRate * 10))

  Write-Host "  🔍 Searching for optimal loop point..." -ForegroundColor Yellow

  # Find loop start using cross-correlation
  $bestOffset = Get-BestOffsetByNCCF -Mono $mono -TailLen $tailLen -SearchLen $searchLen

  # Beat grid alignment
  $samplesPerBeat = [double]$SampleRate * 60.0 / $Bpm
  $snappedStart = $bestOffset
  $nearestBeatIdx = [int]([math]::Round($snappedStart / $samplesPerBeat) * $samplesPerBeat)
  $gridWin = Convert-MsToSamples -Ms $GridSnapWindowMs -SampleRate $SampleRate

  if ([math]::Abs($nearestBeatIdx - $snappedStart) -le $gridWin) {
    # Grid snap to beat boundary, then zero crossing
    $snappedStart = Get-ZeroCrossingSnap -X $mono -Idx $nearestBeatIdx -Window $gridWin
    Write-Host "  🎵 Snapped to beat grid at $snappedStart samples" -ForegroundColor Cyan
  } else {
    # Just zero crossing snap without beat alignment
    $snappedStart = Get-ZeroCrossingSnap -X $mono -Idx $bestOffset -Window (Convert-MsToSamples -Ms 8 -SampleRate $SampleRate)
    Write-Host "  ⚠️  Loop point outside grid snap window, using correlation result" -ForegroundColor Yellow
  }

  # Calculate exact N-bar target length
  $targetFrames = [int][math]::Round($Bars * $BeatsPerBar * $samplesPerBeat)
  $xfade = Convert-MsToSamples -Ms $XfadeMs -SampleRate $SampleRate
  if ($xfade -ge [int]($targetFrames/2)) { $xfade = [int]([math]::Max(1, [int]($targetFrames/2) - 1)) }

  Write-Host "  ✂️  Loop start: $snappedStart | Target length: $targetFrames frames | Crossfade: $xfade samples" -ForegroundColor Green
  Write-Host "  📏 Exact loop duration: $Bars bars at $Bpm BPM ($([math]::Round($targetFrames / $SampleRate, 2)) seconds)" -ForegroundColor Green

  # Apply circular boundary crossfade
  $null = Invoke-SeamCrossfadeCircular -Interleaved $interleaved -Channels 2 -LoopStartFrame $snappedStart -LoopLengthFrames $targetFrames -XfadeFrames $xfade

  # Extract the exact N-bar loop segment (circular copy)
  $loopSegment = Copy-CircularSegment -Interleaved $interleaved -Channels 2 -StartFrame $snappedStart -LengthFrames $targetFrames

  # Convert back to double stereo arrays
  $loopFrames = [int]($loopSegment.Length / 2)
  $newLeft = New-Object 'System.Double[]' $loopFrames
  $newRight = New-Object 'System.Double[]' $loopFrames
  for ($i=0; $i -lt $loopFrames; $i++) {
    $newLeft[$i]  = [double]$loopSegment[$i * 2]
    $newRight[$i] = [double]$loopSegment[$i * 2 + 1]
  }

  Write-Host "  ✅ Seamless loop processing complete!" -ForegroundColor Green

  return @{
    Left = $newLeft
    Right = $newRight
  }
}

# -------------------- DSP helpers --------------------
$rand = New-Object System.Random


function Add-MixInto {
  param(
    [double[]]$Dest,
    [double[]]$Src,
    [int]$StartIndex,
    [double]$Gain = 1.0
  )

  # Calculate how many samples we can safely mix
  $n = [Math]::Min($Src.Length, [Math]::Max(0, $Dest.Length - $StartIndex))

  # Add source samples into destination buffer with gain applied
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

  # Calculate equal-power panning coefficients
  # Pan range: -1 (hard left) to 0 (center) to +1 (hard right)
  $pl = [Math]::Sqrt(0.5 * (1 - $Pan))  # Left channel gain
  $pr = [Math]::Sqrt(0.5 * (1 + $Pan))  # Right channel gain

  # Calculate safe mix length
  $n = [Math]::Min($Src.Length, [Math]::Max(0, $L.Length - $StartIndex))

  # Mix source into stereo channels with panning applied
  for ($i = 0; $i -lt $n; $i++) {
    $idx = $StartIndex + $i
    if ($idx -ge $L.Length) { break }
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

  # Convert delay time from milliseconds to samples
  $haas = [int]($HaasMs / 1000.0 * $SampleRate)

  for ($i = 0; $i -lt $Src.Length; $i++) {
    $idx = $StartIndex + $i
    if ($idx -ge $L.Length) { break }

    # Apply Haas effect: one channel on-time, other delayed
    # Creates stereo width through precedence effect
    if ($Pan -le 0) {
      # Pan left: left on-time, right delayed
      $L[$idx] += $Gain * $Src[$i]
      $rIdx = $idx + $haas
      if ($rIdx -lt $R.Length) { $R[$rIdx] += $Gain * $Src[$i] }
    }
    else {
      # Pan right: right on-time, left delayed
      $R[$idx] += $Gain * $Src[$i]
      $lIdx = $idx + $haas
      if ($lIdx -lt $L.Length) { $L[$lIdx] += $Gain * $Src[$i] }
    }
  }
}


# Stereo slapback send for space
function Add-SlapbackStereo {
  param([double[]]$L, [double[]]$R, [double[]]$Src, [int]$Start, [double]$Ms = 85, [double]$Gain = 0.18, [double]$Pan = 0.0)

  # Convert delay time from milliseconds to samples
  $d = [int]($Ms / 1000.0 * $SampleRate)

  # Calculate panning for slapback (mirror image of dry signal)
  $pl = [Math]::Sqrt(0.5 * (1 - $Pan))
  $pr = [Math]::Sqrt(0.5 * (1 + $Pan))

  # Add delayed signal with reversed pan for stereo width
  for ($i = 0; $i -lt $Src.Length; $i++) {
    $idx = $Start + $d + $i
    if ($idx -ge $L.Length) { break }

    # Send more to opposite side of dry signal for width
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

  # Random starting phase for natural variation
  $randomPhase = Get-Random -Minimum 0.0 -Maximum 6.28

  # Apply time-varying panning that wobbles around base position
  for ($i = 0; $i -lt $Src.Length; $i++) {
    $t = ($i / $SampleRate)

    # Calculate current pan position using sine wave modulation
    $pan = $BasePan + $Depth * [Math]::Sin(2 * [Math]::PI * $RateHz * $t + $randomPhase)

    # Equal-power panning calculated per sample for smooth movement
    $pl = [Math]::Sqrt(0.5 * (1 - $pan))
    $pr = [Math]::Sqrt(0.5 * (1 + $pan))

    $idx = $StartIndex + $i
    if ($idx -ge $L.Length) { break }

    # Apply wobbling pan position
    $L[$idx] += $Gain * $pl * $Src[$i]
    $R[$idx] += $Gain * $pr * $Src[$i]
  }
}

function Set-NormalizedLevel {
  param([double[]]$Samples, [double]$Target = 0.95)

  # Find peak absolute value in the signal
  $max = 0.0
  foreach ($s in $Samples) {
    $a = [Math]::Abs($s)
    if ($a -gt $max) { $max = $a }
  }

  # Apply normalization gain if signal has content
  if ($max -gt 0) {
    $g = $Target / $max
    for ($i = 0; $i -lt $Samples.Length; $i++) { $Samples[$i] *= $g }
  }
}


# Simple one-pole highpass (difference) for noise brightening
function Set-HighpassFilter {
  param([double[]]$x, [double]$alpha = 0.98)

  $y = New-Object double[] $x.Length
  $prev = 0.0

  # Apply first-order highpass filter (y[n] = alpha * y[n-1] + x[n] - x[n-1])
  for ($i = 0; $i -lt $x.Length; $i++) {
    $y[$i] = $alpha * ($y[[Math]::Max(0, $i - 1)]) + $x[$i] - $prev
    $prev = $x[$i]
  }

  return , $y
}


# Exponential decay envelope
function New-ExponentialEnvelope {
  param([int]$Len, [double]$tau) # tau in seconds

  $env = New-Object double[] $Len

  # Generate exponential decay curve: amplitude = e^(-t/tau)
  for ($i = 0; $i -lt $Len; $i++) {
    $t = $i / $SampleRate
    $env[$i] = [Math]::Exp(-$t / $tau)
  }

  return , $env
}


# Multiply arrays element-wise
function Invoke-ArrayMultiply {
  param([double[]]$a, [double[]]$b)

  $n = [Math]::Min($a.Length, $b.Length)
  $out = New-Object double[] $n

  # Multiply corresponding elements
  for ($i = 0; $i -lt $n; $i++) { $out[$i] = $a[$i] * $b[$i] }

  return , $out
}

# -------------------- Drum Synths --------------------
function New-SynthKick {
  param([double]$LengthSec = 0.25, [double]$f0 = 120, [double]$f1 = 40)

  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  # Generate kick with exponential frequency sweep from f0 to f1
  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Exponential freq sweep: f(t) = f1 + (f0 - f1)*exp(-t*k)
    $k = 8.0  # Decay rate for frequency sweep
    $f = $f1 + ($f0 - $f1) * [Math]::Exp(-$k * $t)

    # Accumulate phase and generate sine wave
    $phase += (2.0 * [Math]::PI * $f) / $SampleRate
    $out[$i] = [Math]::Sin($phase)
  }

  # Apply amplitude envelope for kick punch
  $env = New-ExponentialEnvelope -Len $len -tau 0.12
  $out = Invoke-ArrayMultiply $out $env

  # Apply subtle saturation for warmth and body
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(2.5 * $out[$i]) }

  return , $out
}


function New-SynthSnare {
  param([double]$LengthSec = 0.25)

  $len = [int]($LengthSec * $SampleRate)
  $tone = New-Object double[] $len
  $noise = New-Object double[] $len
  $phase = 0.0
  $f = 190.0  # Snare fundamental frequency

  # Generate tonal component (snare shell resonance)
  for ($i = 0; $i -lt $len; $i++) {
    $phase += (2.0 * [Math]::PI * $f) / $SampleRate
    $tone[$i] = [Math]::Sin($phase)

    # Generate white noise component (snare wire rattle)
    $noise[$i] = ($rand.NextDouble() * 2.0 - 1.0)
  }

  # Apply separate envelopes to tone and noise
  $toneEnv = New-ExponentialEnvelope -Len $len -tau 0.08   # Shorter tone decay
  $noiseEnv = New-ExponentialEnvelope -Len $len -tau 0.05  # Quick noise burst
  $tone = Invoke-ArrayMultiply $tone  $toneEnv
  $noise = Invoke-ArrayMultiply $noise $noiseEnv

  # Brighten noise with highpass filter
  $noise = Set-HighpassFilter $noise 0.995

  # Mix tone and noise components
  $out = New-Object double[] $len
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = 0.4 * $tone[$i] + 0.9 * $noise[$i] }

  # Apply saturation for snare crack
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(2.0 * $out[$i]) }

  return , $out
}


function New-SynthHat {
  param([double]$LengthSec = 0.12)

  $len = [int]($LengthSec * $SampleRate)
  $noise = New-Object double[] $len

  # Generate white noise as basis for hi-hat
  for ($i = 0; $i -lt $len; $i++) { $noise[$i] = ($rand.NextDouble() * 2.0 - 1.0) }

  # Apply aggressive highpass to create metallic character
  $noise = Set-HighpassFilter $noise 0.995

  # Apply quick decay envelope for closed hat
  $env = New-ExponentialEnvelope -Len $len -tau 0.03
  $out = Invoke-ArrayMultiply $noise $env

  # Subtle saturation for presence
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.6 * $out[$i]) }

  return , $out
}


function New-SynthOpenHat {
  param([double]$LengthSec = 0.30)

  $len = [int]($LengthSec * $SampleRate)
  $noise = New-Object double[] $len

  # Generate white noise as basis
  for ($i = 0; $i -lt $len; $i++) { $noise[$i] = ($rand.NextDouble() * 2.0 - 1.0) }

  # Apply even brighter filtering than closed hat
  $noise = Set-HighpassFilter $noise 0.997

  # Apply longer decay envelope for open hat sustain
  $env = New-ExponentialEnvelope -Len $len -tau 0.12
  $out = Invoke-ArrayMultiply $noise $env

  # Gentle saturation to maintain airy quality
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.4 * $out[$i]) }

  return , $out
}

function New-SynthClap {
  param([double]$LengthSec = 0.35)

  # Create classic handclap with 3 quick noise bursts spaced ~15ms
  $base = New-SynthSnare -LengthSec $LengthSec
  $len = $base.Length
  $burst = New-Object double[] $len
  $delSamp = [int](0.015 * $SampleRate)  # 15ms spacing between bursts

  # Generate bright noise burst
  $noiseBurst = New-Object double[] $len
  for ($i = 0; $i -lt $len; $i++) { $noiseBurst[$i] = ($rand.NextDouble() * 2 - 1.0) }
  $noiseBurst = Set-HighpassFilter $noiseBurst 0.997

  # Apply decay envelope to burst
  $env = New-ExponentialEnvelope -Len $len -tau 0.06
  $noiseBurst = Invoke-ArrayMultiply $noiseBurst $env

  # Layer three bursts at different delays with decreasing gain
  Add-MixInto -Dest $burst -Src $noiseBurst -StartIndex 0           -Gain 0.9
  Add-MixInto -Dest $burst -Src $noiseBurst -StartIndex $delSamp     -Gain 0.6
  Add-MixInto -Dest $burst -Src $noiseBurst -StartIndex (2 * $delSamp) -Gain 0.4

  # Mix and apply saturation for clap character
  $out = New-Object double[] $len
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = 0.6 * $burst[$i] }
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.8 * $out[$i]) }

  return , $out
}


function New-SynthShaker {
  param([double]$LenSec = 0.12)

  $len = [int]($LenSec * $SampleRate)
  $out = New-Object double[] $len
  $rand = New-Object System.Random

  for ($i = 0; $i -lt $len; $i++) {
    # Generate white noise burst
    $n = 2 * $rand.NextDouble() - 1

    # Apply simple band-pass effect (shakers live in 2–8kHz range)
    $bp = $n - 0.98 * $(if ($i -gt 0) { $out[$i - 1] } else { 0 })

    # Apply envelope: fast attack, medium decay
    $env = [Math]::Exp(-15.0 * ($i / $SampleRate))

    # Apply saturation for texture
    $out[$i] = [Math]::Tanh(1.6 * $bp * $env)
  }

  , $out
}

# -------------------- New Instruments --------------------
function New-SynthBass {
  param([double]$LengthSec = 0.5, [double]$frequency = 80)

  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Add slight vibrato for warmth and movement
    $vibrato = 1.0 + 0.02 * [Math]::Sin(6.0 * 2.0 * [Math]::PI * $t)
    $currentFreq = $frequency * $vibrato
    $phase += (2.0 * [Math]::PI * $currentFreq) / $SampleRate

    # Generate square wave for bass body
    $square = if ([Math]::Sin($phase) -gt 0) { 1.0 } else { -1.0 }

    # Add sub harmonic for depth
    $sub = 0.3 * [Math]::Sin($phase * 0.5)

    $out[$i] = 0.7 * $square + $sub
  }

  # Apply envelope for note shaping
  $env = New-ExponentialEnvelope -Len $len -tau 0.25
  $out = Invoke-ArrayMultiply $out $env

  # Apply soft saturation for analog warmth
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(1.5 * $out[$i]) }

  return , $out
}


function New-Synth808 {
  param([double]$LenSec = 0.6, [double]$f0 = 48, [double]$Drive = 1.3)

  $len = [int]($LenSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Quick down-chirp: initial punch then settle to fundamental
    $f = $f0 + 22.0 * [Math]::Exp(-20.0 * $t)
    $phase += (2.0 * [Math]::PI * $f) / $SampleRate

    # Long but decaying envelope for 808 boom
    $env = [Math]::Exp(-2.2 * $t)

    $out[$i] = $env * [Math]::Sin($phase)
  }

  # Apply heavy saturation for that classic 808 character
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh($Drive * $out[$i]) }

  return , $out
}


function New-SynthBrass {
  param([double]$LengthSec = 0.15, [double]$frequency = 220)

  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $phase += (2.0 * [Math]::PI * $frequency) / $SampleRate

    # Generate sawtooth wave using harmonic series for brass timbre
    $saw = 0.0
    for ($h = 1; $h -le 8; $h++) {
      $harmonic = [Math]::Sin($phase * $h) / $h
      $saw += $harmonic
    }

    $out[$i] = $saw * 0.3
  }

  # Apply sharp attack, quick decay envelope for brass stab
  $env = New-ExponentialEnvelope -Len $len -tau 0.08

  # Add extra punch to attack
  for ($i = 0; $i -lt [Math]::Min(100, $len); $i++) {
    $env[$i] *= (1.0 + 2.0 * [Math]::Exp(-$i * 0.05))
  }

  $out = Invoke-ArrayMultiply $out $env

  # Apply hard saturation for punch and presence
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(3.0 * $out[$i]) }

  return , $out
}

function New-SynthScratch {
  param([double]$LengthSec = 0.2)

  $len = [int]($LengthSec * $SampleRate)
  $out = New-Object double[] $len

  # Create scratch effect using noise modulated by frequency sweep
  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Generate white noise base
    $noise = ($rand.NextDouble() * 2.0 - 1.0)

    # Frequency modulation creates the "scratch" sweep effect
    $scratchFreq = 200.0 + 800.0 * [Math]::Sin(15.0 * 2.0 * [Math]::PI * $t)
    $phase = $scratchFreq * $t * 2.0 * [Math]::PI
    $carrier = [Math]::Sin($phase)

    # Modulate noise with carrier wave
    $out[$i] = $noise * $carrier * 0.8
  }

  # Apply highpass to enhance scratchy character
  $out = Set-HighpassFilter $out 0.97

  # Apply quick envelope for sharp attack
  $env = New-ExponentialEnvelope -Len $len -tau 0.04
  $out = Invoke-ArrayMultiply $out $env

  # Apply heavy saturation for gritty turntable sound
  for ($i = 0; $i -lt $len; $i++) { $out[$i] = [Math]::Tanh(4.0 * $out[$i]) }

  return , $out
}


# Additional scratch variation with crossfader gate effect
function New-SynthScratchWicky {
  param([double]$LenSec = 0.25)

  $len = [int]($LenSec * $SampleRate)
  $out = New-Object double[] $len
  $rand = New-Object System.Random
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Generate varispeed sweep effect (up then down)
    $f = (600 + 1800 * [Math]::Sin(2 * [Math]::PI * 3.0 * $t))
    $phase += (2 * [Math]::PI * $f) / $SampleRate

    # Mix tone and noise for texture
    $tone = 0.5 * [Math]::Sin($phase)
    $noi = 0.5 * (2 * $rand.NextDouble() - 1)
    $sig = $tone + $noi

    # Crossfader gate effect (square LFO ~ 12 Hz creates stuttering)
    $gate = if (([Math]::Sin(2 * [Math]::PI * 12.0 * $t) -ge 0)) { 1.0 } else { 0.0 }

    # Apply decay envelope
    $env = [Math]::Exp(-3.2 * $t)

    $out[$i] = [Math]::Tanh(1.6 * $sig * $gate * $env)
  }

  , $out
}


# Chirp scratch - quick high-to-low frequency sweep
function New-SynthScratchChirp {
  param([double]$LenSec = 0.18)

  $len = [int]($LenSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Exponential frequency sweep from high to low (chirp down)
    $f = 2000 * [Math]::Exp(-8.0 * $t) + 100
    $phase += (2 * [Math]::PI * $f) / $SampleRate

    # Mix tone with filtered noise for realism
    $tone = [Math]::Sin($phase)
    $noise = (2 * $rand.NextDouble() - 1) * 0.3
    $sig = $tone + $noise

    # Apply sharp attack, quick decay for chirp character
    $env = [Math]::Exp(-12.0 * $t)

    $out[$i] = [Math]::Tanh(2.0 * $sig * $env)
  }

  , $out
}


# Reverse scratch - low-to-high sweep with stutter
function New-SynthScratchReverse {
  param([double]$LenSec = 0.22)

  $len = [int]($LenSec * $SampleRate)
  $out = New-Object double[] $len
  $phase = 0.0

  for ($i = 0; $i -lt $len; $i++) {
    $t = $i / $SampleRate

    # Rising frequency sweep with wobble for movement
    $f = 150 + 1200 * $t + 300 * [Math]::Sin(2 * [Math]::PI * 8.0 * $t)
    $phase += (2 * [Math]::PI * $f) / $SampleRate

    # Apply stutter gate effect for rhythmic variation
    $stutter = if (([Math]::Sin(2 * [Math]::PI * 20.0 * $t) -gt -0.3)) { 1.0 } else { 0.2 }

    # Mix tone with noise
    $sig = [Math]::Sin($phase) + 0.2 * (2 * $rand.NextDouble() - 1)

    # Apply envelope
    $env = [Math]::Exp(-4.0 * $t)

    $out[$i] = [Math]::Tanh(1.8 * $sig * $stutter * $env)
  }

  , $out
}

# -------------------- Sequence pattern --------------------
# 16-step pattern (4/4, 16ths). 1 = hit, 0 = rest.
# Style-specific patterns for different hip-hop genres

switch ($Style) {
  'BoomBap' {
    # Classic 90s groove - moderate complexity
    $kick = @(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0)  # "1, e of 2, a of 3"
    $snare = @(0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0)  # on 2 and 4
    $hat = @(1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0)  # steady 8ths
    $hat[3] = 1; $hat[7] = 1; $hat[11] = 1; $hat[15] = 1  # extra 16th notes
    $openHat = @(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1)  # opens on "a of 2" and "a of 4"
    $bass = @(1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1)
    $brass = @(0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0)  # brass stab on 3
    $scratch = @(0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0)  # scratch on offbeats
    $shaker = @(1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0)  # steady 8ths for boom bap texture

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
    $kick = @(1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0)  # More kicks for breakbeat feel
    $snare = @(0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0)  # classic backbeat
    $hat = @(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)  # dense 16ths
    $openHat = @(0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0)  # minimal opens
    $bass = @(1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 0)  # busier bassline
    $brass = @(0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0)  # regular brass hits
    $scratch = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)  # no scratches in old school
    $shaker = @(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)  # steady 16ths for old school texture

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
    $kick = @(1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0)  # Simple, heavy kicks
    $snare = @(0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0)  # backbeat only
    $hat = @(1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0)  # base 8ths pattern
    # Dense 16ths with occasional 32nd rolls added later in rendering
    $hat[1] = 1; $hat[3] = 1; $hat[9] = 1; $hat[11] = 1
    $openHat = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0)  # rare opens
    $bass = @(1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0)  # heavy 808 pattern
    $brass = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)  # no brass in crunk
    $scratch = @(0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1)  # occasional scratches
    $shaker = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)  # no shaker in crunk - too minimal

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
      $bassVariations += , (New-Synth808 -LenSec 0.7 -f0 $freq -Drive 1.3)
    }
  }
  else {
    Write-Host "🎸 Laying down the bass foundation..." -ForegroundColor DarkGreen
    # Regular bass frequencies
    $bassFreqs = @(65, 73, 82, 98, 110)  # Roughly C2, D2, E2, G2, A2
    $bassVariations = @()
    foreach ($freq in $bassFreqs) {
      $bassVariations += , (New-SynthBass -LengthSec 0.45 -frequency $freq)
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
    $brassVariations += , (New-SynthBrass -LengthSec 0.12 -frequency $freq)
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

for ($bar = 0; $bar -lt $Bars; $bar++) {
  if ($bar -eq 0) {
    Write-Host "🎵 Bar 1: Dropping the beat..." -ForegroundColor DarkGreen
  }
  elseif ($bar -eq [Math]::Floor($Bars / 2)) {
    Write-Host "🔥 Halfway through - keeping that energy..." -ForegroundColor DarkYellow
  }
  elseif ($bar -eq ($Bars - 1)) {
    Write-Host "🏁 Final bar - bringing it home..." -ForegroundColor DarkRed
  }

  for ($step = 0; $step -lt 16; $step++) {
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
      }
      else {
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
        $clapPan = if ((($bar + $step) % 2 -eq 0)) { - $ClapAlt } else { $ClapAlt }
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
      }
      else {
        Add-MixIntoStereo -L $mixL -R $mixR -Src $hatBuf -StartIndex $start -Gain 0.35 -Pan $HatPan
      }

      # Crunk style: add occasional 32nd note hat rolls near bar end
      if ($Style -eq 'Crunk' -and $step -ge 12 -and (Get-Random) -lt 0.25) {
        # Add 32nd note roll after the main hat
        $stepSamp = $exactSamplesPerStep
        $maxJit = [int]($stepSamp * 0.02)  # Small timing jitter
        0..3 | ForEach-Object {
          $rollStart = $start + [int]($_ * ($stepSamp / 4))  # 32nd notes = quarter of 16th
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
        }
        else {
          # 50% chance for reverse scratches
          Get-Random -Minimum 7 -Maximum 9
        }
      }
      elseif (($step % 4) -eq 2) {
        # On the "e" of beats - prefer quick chirps
        $scratchChoice = Get-Random -Minimum 5 -Maximum 7
      }
      else {
        # General scratches - mix of everything with bias toward shorter ones
        $scratchChoice = if ((Get-Random -Maximum 4) -eq 0) {
          # 25% chance for any variation
          Get-Random -Maximum $scratchVariations.Length
        }
        else {
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
for ($i = 0; $i -lt $mixL.Length; $i++) {
  $mixL[$i] = [Math]::Tanh(1.2 * $mixL[$i])
  $mixR[$i] = [Math]::Tanh(1.2 * $mixR[$i])
}

Write-Host "📊 Analyzing peaks and normalizing stereo field..." -ForegroundColor DarkCyan

# Normalize stereo - find peak across both channels
$maxPeak = 0.0
for ($i = 0; $i -lt $mixL.Length; $i++) {
  $peakL = [Math]::Abs($mixL[$i])
  $peakR = [Math]::Abs($mixR[$i])
  $peak = [Math]::Max($peakL, $peakR)
  if ($peak -gt $maxPeak) { $maxPeak = $peak }
}

if ($maxPeak -gt 0) {
  $normGain = 0.95 / $maxPeak
  for ($i = 0; $i -lt $mixL.Length; $i++) {
    $mixL[$i] *= $normGain
    $mixR[$i] *= $normGain
  }
  Write-Host "✨ Normalized to 95% peak with gain of $([Math]::Round($normGain, 3))" -ForegroundColor Green
}

# Apply seamless loop processing (default behavior, unless disabled)
if (-not $DontMakeSeamless) {
  try {
    $loopResult = Invoke-SeamlessLoop `
      -LeftChannel $mixL `
      -RightChannel $mixR `
      -SampleRate $SampleRate `
      -Bpm $Bpm `
      -Bars $Bars `
      -BeatsPerBar $BeatsPerBar `
      -TailMs $TailMs `
      -SearchHeadMs $SearchHeadMs `
      -XfadeMs $XfadeMs `
      -GridSnapWindowMs $GridSnapWindowMs
    $mixL = $loopResult.Left
    $mixR = $loopResult.Right
  }
  catch {
    Write-Host "⚠️ Warning: Seamless loop processing failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "   Continuing with original audio..." -ForegroundColor Yellow
  }
}

# Output path - use automatic naming system
$loopSuffix = if (-not $DontMakeSeamless) { "_loop" } else { "" }
$name = "HipHopBeat_${Style}_${Bpm}bpm_${Bars}bars_stereo${loopSuffix}.wav"

if (-not $OutputFolder) {
  # Use temp folder if no output folder specified
  $OutPath = Join-Path $env:TEMP $name
}
else {
  # Use provided folder with auto-generated filename
  $OutPath = Join-Path $OutputFolder $name
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
if (-not $SkipPlayback) {
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
}
else {
  Write-Host "`n🔇 Playback skipped as requested." -ForegroundColor Yellow
  Write-Host "🔊 File saved: $OutPath" -ForegroundColor White
  Write-Host "✨ Beat generation completed successfully! ✨" -ForegroundColor Magenta
}
