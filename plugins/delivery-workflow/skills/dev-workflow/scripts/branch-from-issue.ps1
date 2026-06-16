#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Create and check out a GitHub issue-linked branch BEFORE coding.
  Windows-native (PowerShell) mirror of branch-from-issue.sh.
.DESCRIPTION
  Runs the explicit-flag form, branching from the repo's default branch:
    gh issue develop <issue-number> --base <main-branch> --name <branch-name> --checkout
  Resolves <main-branch> = the repo's default branch (unless -Base is given).
  Derives <branch-name> = "<issue>-<kebab-slug-of-title>" (unless -Name is given).
  Prints the created branch name; exits non-zero with a clear message on any failure.
  Requires: gh (authenticated) and git, run inside the target repository.
.PARAMETER Issue
  The GitHub issue number.
.PARAMETER Base
  Override the base branch (default: the repo's default branch).
.PARAMETER Name
  Override the new branch name (default: <issue>-<kebab-slug-of-title>).
.EXAMPLE
  ./branch-from-issue.ps1 142
.EXAMPLE
  ./branch-from-issue.ps1 142 -Base main -Name 142-fix-login
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)] [string] $Issue,
  [string] $Base,
  [string] $Name
)

function Die([string]$msg) { [Console]::Error.WriteLine("branch-from-issue: $msg"); exit 1 }

if ($Issue -notmatch '^[0-9]+$') { Die "issue number must be numeric, got: '$Issue'" }

# Preconditions.
if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { Die "gh CLI not installed (https://cli.github.com)" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die "git not installed" }
gh auth status *> $null; if ($LASTEXITCODE -ne 0) { Die "gh not authenticated — run: gh auth login" }
git rev-parse --is-inside-work-tree *> $null; if ($LASTEXITCODE -ne 0) { Die "not inside a git repository" }

# Warn (don't fail) on a dirty tree — gh ... --checkout may refuse to switch branches.
if (git status --porcelain) { Write-Warning "branch-from-issue: uncommitted changes present; --checkout may fail" }

# Resolve <main-branch> (unless -Base given): GitHub API, then local origin/HEAD fallback.
$Main = $Base
if (-not $Main) {
  $Main = (gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>$null)
  if (-not $Main) {
    $ref = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($ref) { $Main = $ref -replace '^origin/', '' }
  }
  if (-not $Main) {
    git remote set-head origin --auto *> $null
    $ref = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
    if ($ref) { $Main = $ref -replace '^origin/', '' }
  }
}
if (-not $Main) { Die "could not resolve the default branch (pass -Base <branch>)" }

# Guard: base must be a real remote branch (gh may silently fall back otherwise).
git show-ref --verify --quiet "refs/remotes/origin/$Main"
if ($LASTEXITCODE -ne 0) {
  git ls-remote --exit-code --heads origin $Main *> $null
  if ($LASTEXITCODE -ne 0) { Die "base branch '$Main' not found on origin" }
}

# Derive <branch-name> (unless -Name given) as "<issue>-<kebab-slug-of-title>".
$Branch = $Name
if (-not $Branch) {
  $Title = (gh issue view $Issue --json title -q .title 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not $Title) { Die "issue #$Issue not found (check the number, or run from the right repo)" }
  $slug = [regex]::Replace($Title.ToLower(), '[^a-z0-9]+', '-').Trim('-')
  if ($slug.Length -gt 50) { $slug = $slug.Substring(0, 50).TrimEnd('-') }
  if (-not $slug) { $slug = 'issue' }
  $Branch = "$Issue-$slug"
}

[Console]::Error.WriteLine("branch-from-issue: issue #$Issue -> '$Branch' (base '$Main')")

# Create the issue-linked branch, based on the default branch, and check it out locally.
gh issue develop $Issue --base $Main --name $Branch --checkout
if ($LASTEXITCODE -ne 0) { Die "gh issue develop failed (branch may already exist or be linked; see: gh issue develop $Issue --list)" }

# Confirm the local checkout actually happened.
$current = (git rev-parse --abbrev-ref HEAD 2>$null)
if ($current -ne $Branch) { Die "branch created but HEAD is '$current' (expected '$Branch')" }

Write-Host "OK created and checked out '$Branch' (base '$Main', issue #$Issue)"
