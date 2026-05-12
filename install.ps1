<#
.SYNOPSIS
    ns-skills installer for Windows (PowerShell 5.1+).

.DESCRIPTION
    Installs ns-skills into ~\.claude\skills (global, default) or .\.claude\skills (local).

.EXAMPLE
    irm https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.ps1 | iex

.EXAMPLE
    # Local install when piping (set env var first)
    $env:SCOPE='local'; irm https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.ps1 | iex

.EXAMPLE
    # When running the file directly
    .\install.ps1 -Scope local
#>
[CmdletBinding()]
param(
    [ValidateSet('global', 'local')]
    [string]$Scope  = $(if ($env:SCOPE)            { $env:SCOPE }            else { 'global' }),
    [string]$Repo   = $(if ($env:NS_SKILLS_REPO)   { $env:NS_SKILLS_REPO }   else { 'kaushik-cognizant/ns-skills' }),
    [string]$Branch = $(if ($env:NS_SKILLS_BRANCH) { $env:NS_SKILLS_BRANCH } else { 'main' })
)

$ErrorActionPreference = 'Stop'

$target = if ($Scope -eq 'global') {
    Join-Path $HOME '.claude\skills'
} else {
    Join-Path (Get-Location) '.claude\skills'
}

Write-Host "Installing ns-skills"
Write-Host "  Source: github.com/$Repo@$Branch"
Write-Host "  Scope:  $Scope"
Write-Host "  Target: $target"

New-Item -ItemType Directory -Force -Path $target | Out-Null

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ns-skills-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $zipUrl  = "https://codeload.github.com/$Repo/zip/refs/heads/$Branch"
    $zipPath = Join-Path $tmp 'repo.zip'

    Write-Host "  Downloading archive..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $tmp -Force

    $rootDir = Get-ChildItem -Path $tmp -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'skills') } |
        Select-Object -First 1

    if (-not $rootDir) {
        throw "Could not find skills/ directory in archive"
    }

    $skillsDir = Join-Path $rootDir.FullName 'skills'
    $installed = 0

    Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
        Write-Host "  Installing skill: $($_.Name)"
        $dest = Join-Path $target $_.Name
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Copy-Item -Path $_.FullName -Destination $dest -Recurse
        $installed++
    }

    if ($installed -eq 0) {
        throw "No skills found to install."
    }

    Write-Host ""
    Write-Host "Installed $installed skill(s) to $target"
    Write-Host "Restart Claude Code and run /help to verify."
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
