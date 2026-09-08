# Structural audit of a memory-wiki. PowerShell twin of wiki-lint.sh.
#
# Output MUST stay byte-identical to the bash original — test/run-tests.sh asserts it
# against every fixture. The bash script's stdout is the specification; this exists so
# the agent side can invoke the linter without going through an unreliable Bash layer
# on Windows.
param(
  [Parameter(Mandatory)][string]$WikiDir,
  [string]$Sources,
  [string]$Atlas
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $WikiDir)) { Write-Error "not a directory: $WikiDir"; exit 0 }

# Sort ordinally to match the bash side's LC_ALL=C byte ordering.
function Sort-Ordinal([string[]]$a) {
  # An empty pipeline binds $a to $null, not an empty array.
  if ($null -eq $a -or $a.Count -eq 0) { return @() }
  $copy = [string[]]$a.Clone()
  [Array]::Sort($copy, [StringComparer]::Ordinal)
  # Plain return, not `return ,$copy` — the comma wraps the array in an outer array, so
  # callers see Count 1 and string interpolation space-joins the members. Call sites
  # wrap with @() where they need a guaranteed array.
  return $copy
}

# Index and log files link to nearly every page by design; MEMORY.md is the index in a
# pre-wiki memory dir. See the matching comment in wiki-lint.sh.
$structural = @('index','log','MEMORY')
$linkRx  = [regex]'\[\[([^\]\|#]*)'
$required = @('description','last_accessed','name','status','type')

$pages = @(); $links = @(); $nofm = @(); $inbound = @(); $linkCount = 0

foreach ($f in Get-ChildItem $WikiDir -Filter *.md -File | Sort-Object Name) {
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $body = ((Get-Content $f.FullName -Raw) -replace "`r", '')
  $lines = $body -split "`n"

  if ($base -notin $structural) {
    $pages += $base
    if ($lines[0] -ne '---') {
      $nofm += "$base (no frontmatter)"
    } else {
      $fm = @()
      for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*$') { break }
        $fm += $lines[$i]
      }
      # $required is already alphabetical, so the reported list comes out sorted.
      $missing = @($required | Where-Object { $fld = $_; -not ($fm | Where-Object { $_ -match "^$fld`:" }) })
      if ($missing.Count) { $nofm += "$base (missing: $($missing -join ', '))" }
    }
  }

  foreach ($m in $linkRx.Matches($body)) {
    $t = $m.Groups[1].Value -replace '\s+$', ''
    if ($t) { $linkCount++; $links += ,@($base, $t) }
  }
}
$pages = @(Sort-Ordinal ($pages | Select-Object -Unique))

# --- resolvable-name sets ---
$known = [System.Collections.Generic.HashSet[string]]::new([string[]]$pages)
if ($Sources -and (Test-Path $Sources)) {
  Get-ChildItem $Sources -Filter *.md -File | ForEach-Object { [void]$known.Add([IO.Path]::GetFileNameWithoutExtension($_.Name)) }
}
foreach ($s in $structural) { if (Test-Path (Join-Path $WikiDir "$s.md")) { [void]$known.Add($s) } }
$knownAtlas = [System.Collections.Generic.HashSet[string]]::new()
if ($Atlas -and (Test-Path $Atlas)) {
  Get-ChildItem $Atlas -Filter *.md -File | ForEach-Object { [void]$knownAtlas.Add([IO.Path]::GetFileNameWithoutExtension($_.Name)) }
}

# --- classify every link ---
$broken = @()
foreach ($l in $links) {
  $from = $l[0]; $to = $l[1]
  if ($to -like 'atlas/*') {
    if ($knownAtlas.Contains($to.Substring(6))) { continue }
  } elseif ($known.Contains($to)) {
    if ($from -notin $structural) { $inbound += $to }
    continue
  }
  $broken += "$from -> [[$to]]"
}
$orphans = @($pages | Where-Object { $_ -notin $inbound })
$nofm = @(Sort-Ordinal ($nofm | Select-Object -Unique))

# --- report ---
"## Structural"
"  {0,-20} : {1}" -f 'pages', $pages.Count
"  {0,-20} : {1}" -f 'wikilinks', $linkCount
"  {0,-20} : {1}" -f 'broken links', $broken.Count
"  {0,-20} : {1}" -f 'orphans', $orphans.Count
"  {0,-20} : {1}" -f 'missing frontmatter', $nofm.Count

if ($broken.Count)  { ""; "  BROKEN:";         Sort-Ordinal $broken | ForEach-Object { "    $_" } }
if ($orphans.Count) { ""; "  ORPHANS:";        $orphans             | ForEach-Object { "    $_" } }
if ($nofm.Count)    { ""; "  NO FRONTMATTER:"; $nofm                | ForEach-Object { "    $_" } }

""
"## Injection budget"
$regionBytes = 0
$idx = Join-Path $WikiDir 'index.md'
if (Test-Path $idx) {
  $raw = ((Get-Content $idx -Raw) -replace "`r", '')
  $m = [regex]::Match($raw, '(?s)<!-- BEGIN memory-wiki[^>]*-->\n(.*?)<!-- END memory-wiki')
  if ($m.Success) { $regionBytes = [Text.Encoding]::UTF8.GetByteCount($m.Groups[1].Value) }
}
"  {0,-20} : {1} B (~{2} tokens)" -f 'index region', $regionBytes, [math]::Floor($regionBytes * 10 / 36)
