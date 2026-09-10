# Structural audit of a memory-wiki. PowerShell twin of wiki-lint.sh.
#
# Output MUST stay byte-identical to the bash original — test/run-tests.sh asserts it
# against every fixture. The bash script's stdout is the specification; this exists so
# the agent side can invoke the linter without going through an unreliable Bash layer
# on Windows.
param(
  [Parameter(Mandatory)][string]$WikiDir,
  [string]$Sources,
  [string]$Atlas,
  [string]$Concepts
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
# pre-wiki memory dir; README.md is the scaffolded page schema, not a page written against it.
# See the matching comments in wiki-lint.sh.
$structural = @('index','log','MEMORY','README')
$linkRx  = [regex]'\[\[([^\]\|#]*)'
$requiredBase = @('description','last_accessed','name','status','type')
$validTypes   = @('project','component','tech','failure','concept')
$validStatus  = @('active','dormant','superseded')

# Reads one top-level frontmatter key out of the frontmatter lines, stripping the key, any
# surrounding quotes and any trailing whitespace. Mirrors fm_value() in wiki-lint.sh.
# Every comparison here is case-sensitive (-cmatch, -cnotin, switch -CaseSensitive): bash's
# `case`, `grep` and `sed` are, and a key or value differing only in case must be judged the
# same way on both sides.
function Get-FmValue([string[]]$fm, [string]$key) {
  $rx = '^' + [regex]::Escape($key) + ':\s*(.*)$'
  foreach ($line in $fm) {
    if ($line -cmatch $rx) {
      $v = $Matches[1] -replace '\s+$', ''
      if ($v -cmatch '^"(.*)"$') { return $Matches[1] }
      if ($v -cmatch "^'(.*)'$")  { return $Matches[1] }
      return $v
    }
  }
  return ''
}

$pages = @(); $links = @(); $nofm = @(); $schema = @(); $inbound = @(); $linkCount = 0

foreach ($f in Get-ChildItem $WikiDir -Filter *.md -File | Sort-Object Name) {
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $body = ((Get-Content $f.FullName -Raw) -replace "`r", '')
  $lines = $body -split "`n"

  # -cnotin, not -notin: the exemption is exactly the four filenames the scaffolder writes, and
  # bash matches them case-sensitively. Anything else — Readme.md included — is user-authored
  # content and must be audited as a page rather than silently hidden from the audit.
  if ($base -cnotin $structural) {
    $pages += $base
    if ($lines[0] -ne '---') {
      $nofm += "$base (no frontmatter)"
    } else {
      $fm = @()
      for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^---\s*$') { break }
        $fm += $lines[$i]
      }
      # Only top-level keys are read — an indented key under a nested `metadata:` block matches
      # nothing here, so such a page has no parseable type and is exempt from the type-specific
      # and value checks. See the matching comment in wiki-lint.sh.
      $typeV   = Get-FmValue $fm 'type'
      $statusV = Get-FmValue $fm 'status'

      # Each list is written in ordinal order, so the reported fields come out alphabetical.
      $req = @(switch -CaseSensitive ($typeV) {
        'failure'   { 'description','last_accessed','name','sources','status','symptom','type' }
        'component' { 'description','last_accessed','name','part_of','sources','status','type' }
        'project'   { 'description','last_accessed','name','sources','status','type' }
        'tech'      { 'description','last_accessed','name','sources','status','type' }
        default     { $requiredBase }
      })
      # A key with nothing after it is absent, not present — see the matching comment in
      # wiki-lint.sh. `[ \t]`, not `\s`: .NET's `\s` matches Unicode separators that bash's
      # C-locale `[[:blank:]]` does not, and the two reports must stay byte-identical.
      $missing = @($req | Where-Object { $fld = $_; -not ($fm | Where-Object { $_ -cmatch "^$fld`:[ \t]*[^ \t]" }) })
      if ($missing.Count) { $nofm += "$base (missing: $($missing -join ', '))" }

      # Out of range is a different finding from absent, and absent is already reported above,
      # so each value is judged only where it is actually present.
      if ($typeV) {
        $invalid = @()
        if ($typeV -cnotin $validTypes) { $invalid += "type=$typeV" }
        if ($statusV -and $statusV -cnotin $validStatus) { $invalid += "status=$statusV" }
        if ($invalid.Count) { $schema += "$base (invalid: $($invalid -join ', '))" }
      }
    }
  }

  # README is not a participant in the link graph — neither counted nor classified. index and
  # log are: their links are real edges. See the matching comment in wiki-lint.sh.
  if ($base -ceq 'README') { continue }

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
# claude-memory's root concept_*.md files are link targets, never pages of this wiki: they go
# into $known and never into $pages. See the matching comment in wiki-lint.sh.
if ($Concepts -and (Test-Path $Concepts)) {
  Get-ChildItem $Concepts -Filter *.md -File | ForEach-Object { [void]$known.Add([IO.Path]::GetFileNameWithoutExtension($_.Name)) }
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
  # -clike / -cnotin for the same reason as everywhere else here: bash's `== atlas/*` and
  # is_structural() are case-sensitive, so `[[Atlas/x]]` is an ordinary name on both sides.
  if ($to -clike 'atlas/*') {
    if ($knownAtlas.Contains($to.Substring(6))) { continue }
  } elseif ($known.Contains($to)) {
    if ($from -cnotin $structural) { $inbound += $to }
    continue
  }
  $broken += "$from -> [[$to]]"
}
$orphans = @($pages | Where-Object { $_ -cnotin $inbound })
$nofm = @(Sort-Ordinal ($nofm | Select-Object -Unique))
$schema = @(Sort-Ordinal ($schema | Select-Object -Unique))

# --- report ---
"## Structural"
"  {0,-20} : {1}" -f 'pages', $pages.Count
"  {0,-20} : {1}" -f 'wikilinks', $linkCount
"  {0,-20} : {1}" -f 'broken links', $broken.Count
"  {0,-20} : {1}" -f 'orphans', $orphans.Count
"  {0,-20} : {1}" -f 'missing frontmatter', $nofm.Count
"  {0,-20} : {1}" -f 'schema errors', $schema.Count

if ($broken.Count)  { ""; "  BROKEN:";         Sort-Ordinal $broken | ForEach-Object { "    $_" } }
if ($orphans.Count) { ""; "  ORPHANS:";        $orphans             | ForEach-Object { "    $_" } }
if ($nofm.Count)    { ""; "  NO FRONTMATTER:"; $nofm                | ForEach-Object { "    $_" } }
if ($schema.Count)  { ""; "  SCHEMA:";         $schema              | ForEach-Object { "    $_" } }

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
