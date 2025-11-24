<#
    Texty.ps1 — Windows port
    Rituals:
      - Null-check wards on all inputs
      - Canonical errors with exit codes
      - Editor handoff with fallback
      - Idempotent creation: won’t overwrite unless -Force
#>

param(
    [string] $FileName,
    [string] $TargetDir,
    [string] $InitialContent,
    [switch] $Force,
    [string] $Editor      # e.g. "code", "notepad", full path, etc.
)

function Fail {
    param([int]$Code, [string]$Msg)
    Write-Error $Msg
    exit $Code
}

# --- Wards: Resolve editor ---
if (-not $Editor -or [string]::IsNullOrWhiteSpace($Editor)) {
    # Prefer VS Code if available; else Notepad
    $Editor = (Get-Command code -ErrorAction SilentlyContinue) ? "code" : "notepad"
}

# --- Wards: Interactive prompts if missing ---
if (-not $FileName -or [string]::IsNullOrWhiteSpace($FileName)) {
    $FileName = Read-Host "Enter file name (e.g., notes.txt)"
}
if (-not $TargetDir -or [string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = Read-Host "Enter target directory (e.g., C:\Users\$env:USERNAME\Documents)"
}
if ($InitialContent -eq $null) {
    $InitialContent = Read-Host "Initial content (blank allowed)"
}

# --- Wards: Validate inputs ---
if ([string]::IsNullOrWhiteSpace($FileName)) { Fail 10 "Filename is required." }
if ([string]::IsNullOrWhiteSpace($TargetDir)) { Fail 11 "Target directory is required." }

# Normalize and validate path
try {
    $TargetDir = [System.IO.Path]::GetFullPath($TargetDir)
} catch {
    Fail 12 "Invalid directory path: $TargetDir"
}

# Create directory if missing
if (-not (Test-Path -LiteralPath $TargetDir)) {
    try {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    } catch {
        Fail 13 "Failed to create directory: $TargetDir"
    }
}

# Compose full path
$FullPath = Join-Path -Path $TargetDir -ChildPath $FileName

# Check overwrite behavior
if ((Test-Path -LiteralPath $FullPath) -and -not $Force) {
    Write-Warning "File exists: $FullPath"
    $choice = Read-Host "Overwrite? (y/N)"
    if ($choice -notin @("y","Y")) {
        Write-Host "Aborted without changes."
        exit 0
    }
}

# Create or overwrite file atomically
try {
    # Use Set-Content to avoid BOM issues; create empty if no content
    if ([string]::IsNullOrEmpty($InitialContent)) {
        # Ensure file exists
        New-Item -ItemType File -Path $FullPath -Force | Out-Null
        Clear-Content -Path $FullPath -ErrorAction SilentlyContinue
    } else {
        Set-Content -Path $FullPath -Value $InitialContent -NoNewline -Encoding UTF8
    }
} catch {
    Fail 20 "Failed to write file: $FullPath"
}

# Echo canonical success
Write-Host "Texty: created $FullPath" -ForegroundColor Green

# Editor handoff
try {
    if ($Editor -eq "code") {
        & code --reuse-window --goto "$FullPath:1"
    } else {
        & $Editor "$FullPath"
    }
} catch {
    Write-Warning "Editor handoff failed for '$Editor'. Opening with Notepad."
    try { & notepad "$FullPath" } catch { Fail 30 "Fallback editor failed." }
}

exit 0

