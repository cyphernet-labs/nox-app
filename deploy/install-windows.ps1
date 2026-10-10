<#
.SYNOPSIS
Installs the NOX server on Windows, and tor beside it as a service of its own.

.DESCRIPTION
One run does everything: the server (built from this repository, or -Binary),
its folder readable by its own service account only, the Tor Expert Bundle
from the Tor Project with its signature checked, the NOX onion service, both
as Windows services that start with the machine, a firewall rule for the
server's port, the server's password, and at the end the link and QR code for
the first device. A run on a machine that already has a server updates it:
the database, the password and the onion address's key are left alone.

Run it from PowerShell started as administrator:

    powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1

Checking the script without changing the system:

    powershell -ExecutionPolicy Bypass -File deploy\install-windows.ps1 -Prefix C:\nox-check -NoService

puts every file under the prefix, creates no services, no firewall rule and
no permissions: tor and the server run as background processes of whoever ran
it.

.PARAMETER Port
The server's port (default 8443; on an update, the one in use).

.PARAMETER StatusPort
The service page's port, on this machine only (default 8081).

.PARAMETER PublicAddr
The address devices reach this machine at from the internet, as host:port.

.PARAMETER Binary
Install this noxd.exe instead of building one (needs no Go).

.PARAMETER NoTor
No tor: devices connect directly only.

.PARAMETER TorBin
Run this tor.exe (0.4.9 or newer, with proof of work) instead of the Tor
Project's, which the script otherwise downloads and checks. It is copied,
with the libraries beside it, into the install folder, where the tor
service's own account can run it.

.PARAMETER Prefix
Check the script without changing the system; goes together with -NoService.

.PARAMETER NoService
No services; goes together with -Prefix.
#>
[CmdletBinding()]
param(
    [int]$Port = 0,
    [int]$StatusPort = 0,
    [string]$PublicAddr = '',
    [string]$Binary = '',
    [switch]$NoTor,
    [string]$TorBin = '',
    [string]$Prefix = '',
    [switch]$NoService
)

# The script is plain ASCII on purpose: Windows PowerShell 5 reads a script
# without a byte order mark in the system's code page.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$DefaultPort = 8443
$DefaultStatusPort = 8081
# tor older than 0.4.9 is refused by the Tor network since 2026-09-01.
$TorMinVersion = [version]'0.4.9'
$HealthWaitSeconds = 60
$OnionWaitSeconds = 60

$ServerService = 'noxd'
$TorService = 'nox-tor'
$FirewallRule = 'NOX-server'

# The Tor Expert Bundle: where it is published, how its current version is
# found, and the key its checksums are signed with - Tor Browser Developers
# (signing key) <torbrowser@torproject.org>, by its primary fingerprint. Only
# this fingerprint is trusted, whatever the key download returns.
# NOX_TOR_DIST, NOX_TOR_VERSION and NOX_TOR_KEY_URL point at a mirror or a
# local copy (file://).
$TorSigningKey = 'EF6E286DDA85EA2A4BA7DE684E2C6E8793298290'
$TorDist = 'https://dist.torproject.org/torbrowser'
if ($env:NOX_TOR_DIST) { $TorDist = $env:NOX_TOR_DIST }
$TorVersionUrl = 'https://aus1.torproject.org/torbrowser/update_3/release/download-windows-x86_64.json'
$TorKeyUrl = 'https://openpgpkey.torproject.org/.well-known/openpgpkey/torproject.org/hu/kounek7zrdx745qydx6p59t9mqjpuhdf'
if ($env:NOX_TOR_KEY_URL) { $TorKeyUrl = $env:NOX_TOR_KEY_URL }

$DeployDir = $PSScriptRoot
$RepoDir = Split-Path -Parent $PSScriptRoot

# --- output ------------------------------------------------------------------

# Best effort: with the output going through a pipe whose reader is gone, a
# write throws, and a message lost must not cut a rollback short.
function Say([string]$Text) { try { Write-Host $Text } catch { } }
function Step([string]$Text) { try { Write-Host ''; Write-Host "==> $Text" } catch { } }
function Note([string]$Text) { try { Write-Host "    $Text" } catch { } }
function Warn([string]$Text) { try { Write-Host "warning: $Text" -ForegroundColor Yellow } catch { } }

# A failure the script means is an ApplicationException - nothing else here
# throws one - and its message is shown as it is.
function Fail([string]$Text) { throw (New-Object System.ApplicationException -ArgumentList $Text) }

# --- the record of changes ---------------------------------------------------
#
# Every change to the machine adds the action that takes it back. A run that
# fails before the server answers runs them, newest first, and the machine is
# as it was. The tor steps keep a record of their own: tor failing takes back
# only tor, and the server is installed without it. (Actions, not script
# blocks: a closure cannot call this script's functions.)
#
# The record is also kept on disk, in JournalDir, written whole before each
# step, with the copies of the files the run replaced. A run that ends with no
# chance to take back - its window closed, its SSH session dropped, killed by
# the PowerShell it was piped from, or the machine losing power - leaves it
# there, and the next run takes it back before it does anything else. It
# holds actions, paths and names, never the password, and only SYSTEM and the
# administrators may write it: what it holds is run.

$script:UndoMain = New-Object System.Collections.Generic.List[object]
$script:UndoTor = New-Object System.Collections.Generic.List[object]
$script:UndoInto = 'Main'
$script:Committed = $false
# UndoFailed is set when a step could not be taken back.
$script:UndoFailed = $false
# ServerLockedAgain is set when taking back started the server that ran before
# the run: it starts locked, as every start does.
$script:ServerLockedAgain = $false
# CtrlCGuard says whether the rollback can make the process ignore Ctrl+C.
$script:CtrlCGuard = $false
# UndoFailedSteps keeps the steps that could not be taken back: they stay in
# the record on disk, for the owner.
$script:UndoFailedSteps = New-Object System.Collections.Generic.List[object]
$script:JournalDir = ''
$script:JournalOpen = $false

function Add-Undo([string]$Action, [string]$A = '', [string]$B = '') {
    $entry = [pscustomobject]@{ Action = $Action; A = $A; B = $B }
    if ($script:UndoInto -eq 'Tor') { $script:UndoTor.Add($entry) } else { $script:UndoMain.Add($entry) }
    Write-Journal
}

function ConvertTo-JournalField([string]$S) { return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($S)) }
function ConvertFrom-JournalField([string]$S) { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($S)) }

# Open-Journal makes the folder of the record on disk the first time the run
# records a step - SYSTEM's and the administrators' alone, made so even when
# it was there already, before anything is written into it.
function Open-Journal {
    if ($script:JournalOpen) { return }
    if (-not $script:JournalDir.EndsWith('NOX-install')) { Fail "no folder for the record of changes: $($script:JournalDir)" }
    New-Item -ItemType Directory -Path $script:JournalDir -Force | Out-Null
    if (-not $Prefix) {
        $out = Invoke-Native "$env:SystemRoot\System32\icacls.exe" @($script:JournalDir, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
        if ($out.ExitCode -ne 0) { Fail "could not set who may open $($script:JournalDir)`: $($out.Output.Trim())" }
    }
    $script:JournalOpen = $true
}

function Add-JournalLines($Lines, [string]$Name, $Record) {
    foreach ($u in $Record) { $Lines.Add($Name + "`t" + $u.Action + "`t" + (ConvertTo-JournalField $u.A) + "`t" + (ConvertTo-JournalField $u.B)) }
}

# Write-Journal writes the record as it stands to disk - whole, through a
# replace, so the file is always one complete record. Its first line names
# the run's process: a run that finds the record knows whether the one that
# wrote it still goes.
function Write-Journal {
    Open-Journal
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("nox-install-journal 1 $PID")
    Add-JournalLines $lines 'Tor' $script:UndoTor
    Add-JournalLines $lines 'Main' $script:UndoMain
    Add-JournalLines $lines 'Failed' $script:UndoFailedSteps
    $file = Join-Path $script:JournalDir 'journal'
    $tmp = "$file.new"
    [System.IO.File]::WriteAllLines($tmp, $lines, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $file) { [System.IO.File]::Replace($tmp, $file, $null) } else { [System.IO.File]::Move($tmp, $file) }
}

# Close-Journal removes the record and the copies from disk: the run is taken
# back, or it stands.
function Close-Journal {
    if ($script:JournalDir.EndsWith('NOX-install') -and (Test-Path -LiteralPath $script:JournalDir)) {
        Remove-Item -LiteralPath $script:JournalDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:JournalOpen = $false
}

# Save-FailedJournal sets aside, readably, what could not be taken back, with
# the copies of the replaced files beside it, for the owner to look at.
function Save-FailedJournal {
    $failed = Join-Path $script:JournalDir 'journal.failed'
    try {
        [System.IO.File]::WriteAllLines($failed, [string[]]@($script:UndoFailedSteps | ForEach-Object { "$($_.Action)`t$($_.A)`t$($_.B)" }), (New-Object System.Text.UTF8Encoding($false)))
        Remove-Item -LiteralPath (Join-Path $script:JournalDir 'journal') -Force -ErrorAction SilentlyContinue
    } catch { }
    $script:JournalOpen = $false
    Warn "what was not taken back is listed in $failed, the copies of the files the run replaced beside it; put it right, remove $($script:JournalDir), and run the script again"
}

# Set-Committed marks the installation as standing: the record on disk goes
# first, so a run that ends after this point is never taken back by the next
# one, then the copies with it.
function Set-Committed {
    Remove-Item -LiteralPath (Join-Path $script:JournalDir 'journal') -Force -ErrorAction SilentlyContinue
    $script:Committed = $true
    Close-Journal
}

# Test-JournalTrusted says whether the record on disk can only have been
# written by SYSTEM, the administrators or this account: they own its folder
# and its file, and nobody else may write to them. (A check under -Prefix is
# the account's own.)
function Test-JournalTrusted {
    if ($Prefix) { return $true }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trusted = @('S-1-5-18', 'S-1-5-32-544', $me)
    $writes = [Security.AccessControl.FileSystemRights]'WriteData, AppendData, Delete, ChangePermissions, TakeOwnership'
    foreach ($p in @($script:JournalDir, (Join-Path $script:JournalDir 'journal'))) {
        $acl = Get-Acl -LiteralPath $p
        if ($trusted -notcontains $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writes) -and ($trusted -notcontains $rule.IdentityReference.Value)) { return $false }
        }
    }
    return $true
}

# Test-JournalOwnerAlive says whether the run that wrote the record still
# goes: that process lives and is this script.
function Test-JournalOwnerAlive([int]$Id) {
    if ($Id -eq $PID) { return $false }
    try { $p = Get-CimInstance Win32_Process -Filter "ProcessId = $Id" -ErrorAction Stop } catch { return $false }
    return ($null -ne $p -and [string]$p.CommandLine -match 'install-windows\.ps1')
}

# Resume-Interrupted takes back what a run before this one changed and left
# recorded on disk - it ended with no chance to take it back - before this
# run looks at the machine. Ctrl+C does not cut it short. When all of it is
# back this run goes on; when not, it stops, with the record set aside.
function Resume-Interrupted {
    $file = Join-Path $script:JournalDir 'journal'
    $failed = Join-Path $script:JournalDir 'journal.failed'
    if (Test-Path -LiteralPath $failed) { Fail "a run before this one could not take back everything it changed: what is left is listed in $failed, the copies of the files it replaced beside it; put it right, remove $($script:JournalDir), and run the script again" }
    if (-not (Test-Path -LiteralPath $file)) { return }
    if (-not (Test-JournalTrusted)) { Fail "$($script:JournalDir) holds a record of changes that others could have written; look at it, remove it, and run the script again" }
    $lines = [System.IO.File]::ReadAllLines($file)
    if ($lines.Count -lt 1 -or $lines[0] -notmatch '^nox-install-journal 1 (\d+)$') { Fail "$file is not a record this script wrote; look at it, remove $($script:JournalDir), and run the script again" }
    $owner = [int]$Matches[1]
    if (Test-JournalOwnerAlive $owner) { Fail "another run of this script is under way (process $owner): let it finish, and run the script again" }
    try {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $f = $lines[$i] -split "`t"
            if ($f.Count -ne 4) { continue }
            $entry = [pscustomobject]@{ Action = $f[1]; A = (ConvertFrom-JournalField $f[2]); B = (ConvertFrom-JournalField $f[3]) }
            switch ($f[0]) {
                'Tor' { $script:UndoTor.Add($entry) }
                'Main' { $script:UndoMain.Add($entry) }
                # A step that failed before is reported, not tried again unseen.
                'Failed' { $script:UndoFailedSteps.Add($entry); $script:UndoFailed = $true }
            }
        }
    } catch {
        Fail "$file is not a record this script wrote; look at it, remove $($script:JournalDir), and run the script again"
    }
    Step 'Taking back an interrupted run'
    Say 'A run before this one ended before it finished - its window was closed, it was stopped, or the machine'
    Say 'went down - and what it changed is still in place. That is taken back first.'
    $script:JournalOpen = $true
    Set-CtrlCIgnored $true
    try {
        Invoke-Undo $script:UndoTor
        Invoke-Undo $script:UndoMain
    } finally {
        Set-CtrlCIgnored $false
    }
    if ($script:UndoFailed) {
        Save-FailedJournal
        Fail 'not everything the interrupted run changed could be taken back: see the lines above'
    }
    Close-Journal
    Say 'What the interrupted run changed is taken back.'
}

# Write-ServerLockedAgain is what to say when taking back started the server
# that ran before: it starts locked, as every start does, and how it opens.
function Write-ServerLockedAgain {
    if (-not $script:ServerLockedAgain) { return }
    $cmd = '& ' + (ConvertTo-Argument $script:Noxd).Replace('"', "'")
    Say 'The server that ran before was started again and, as after every start, it is locked until its'
    Say "password is entered - on the service page, http://127.0.0.1:$($script:PreviousStatusPort) on this machine, or with:"
    Say "    $cmd unlock$(Get-StatusFlagFor $script:PreviousStatusPort)"
}

function Invoke-UndoAction($U) {
    switch ($U.Action) {
        'remove' { Remove-Item -LiteralPath $U.A -Recurse -Force -ErrorAction SilentlyContinue }
        'restore' { Copy-Item -LiteralPath $U.A -Destination $U.B -Force }
        'stop-background' { Stop-Background $U.A $U.B }
        'service-command' { [void](Invoke-Native "$env:SystemRoot\System32\sc.exe" @('config', $U.A, 'binPath=', $U.B)) }
        'service-delete' { [void](Invoke-Native "$env:SystemRoot\System32\sc.exe" @('delete', $U.A)) }
        'service-start' { Start-ServiceAgain $U.A }
        'service-stop' { Stop-Service -Name $U.A -Force -ErrorAction SilentlyContinue }
        'firewall-port' { Get-NetFirewallRule -Name $U.A | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $U.B }
        'firewall-remove' { Remove-NetFirewallRule -Name $U.A -ErrorAction SilentlyContinue }
        default { Warn "no way to undo '$($U.Action)'" }
    }
}

# Invoke-Undo runs a record newest first and empties it. Each step leaves the
# record - and the record on disk - once it ran, so taking back that is
# interrupted goes on from that step, not from the start.
function Invoke-Undo([System.Collections.Generic.List[object]]$Record) {
    while ($Record.Count -gt 0) {
        $u = $Record[$Record.Count - 1]
        try { $null = Invoke-UndoAction $u } catch {
            Warn "could not undo a step: $($_.Exception.Message)"
            $script:UndoFailed = $true
            $script:UndoFailedSteps.Add($u)
        }
        $Record.RemoveAt($Record.Count - 1)
        try { Write-Journal } catch { }
    }
}

function Save-TorRecord {
    foreach ($b in $script:UndoTor) { $script:UndoMain.Add($b) }
    $script:UndoTor.Clear()
    $script:UndoInto = 'Main'
    Write-Journal
}

# --- running programs --------------------------------------------------------

# ConvertTo-Argument quotes one argument the way a Windows program reads its
# command line back.
function ConvertTo-Argument([string]$Arg) {
    if ($Arg -ne '' -and $Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Arg.ToCharArray()) {
        if ($ch -eq [char]'\') { $slashes++; continue }
        if ($ch -eq [char]'"') {
            [void]$sb.Append('\' * ($slashes * 2 + 1))
            [void]$sb.Append('"')
        } else {
            [void]$sb.Append('\' * $slashes)
            [void]$sb.Append($ch)
        }
        $slashes = 0
    }
    [void]$sb.Append('\' * ($slashes * 2))
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Join-Arguments([string[]]$Arguments) {
    return (($Arguments | ForEach-Object { ConvertTo-Argument $_ }) -join ' ')
}

# Invoke-Native runs a program to its end and returns its exit code and what it
# printed. Standard input, when given, is written as UTF-8 bytes and closed -
# how the password reaches `noxd unlock`, never on a command line.
# (InputText is untyped: a [string] parameter turns $null into '', and an empty
# standard input is not none.)
function Invoke-Native([string]$File, [string[]]$Arguments, $InputText = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = Join-Arguments $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = ($null -ne $InputText)
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEndAsync()
    $stderr = $p.StandardError.ReadToEndAsync()
    if ($null -ne $InputText) {
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($InputText)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.Close()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Output = ($stdout.Result + $stderr.Result) }
}

# --- checks ------------------------------------------------------------------

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PublicAddr([string]$Addr) {
    if ($Addr -match '\.onion(:\d+)?$') { return $false }
    if ($Addr -notmatch '^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\]):([0-9]{1,5})$') { return $false }
    $p = [int]$Matches[3]
    return ($p -ge 1 -and $p -le 65535)
}

# Get-PortHolder names the program listening on a TCP port, or returns ''.
function Get-PortHolder([int]$P) {
    $c = Get-NetTCPConnection -State Listen -LocalPort $P -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $c) { return '' }
    $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
    if ($proc) { return $proc.ProcessName }
    return 'another program'
}

function Test-OwnServerRunning {
    if ($Prefix) { return (Test-Background 'noxd' $script:ServerPidFile) }
    $s = Get-Service -Name $ServerService -ErrorAction SilentlyContinue
    return ($null -ne $s -and $s.Status -eq 'Running')
}

function Assert-Ports {
    if ($script:Port -eq $script:StatusPort) { Fail "-Port and -StatusPort are the same port, $($script:Port)" }
    foreach ($what in @('server', 'page')) {
        $p = if ($what -eq 'server') { $script:Port } else { $script:StatusPort }
        $holder = Get-PortHolder $p
        if (-not $holder) { continue }
        if ($script:Update -and ($holder -eq 'noxd' -or ($holder -eq 'another program' -and (Test-OwnServerRunning)))) { continue }
        if ($what -eq 'server') { Fail "port $p is in use by $holder; pick another with -Port" }
        Fail "port $p, for the service page, is in use by $holder; pick another with -StatusPort"
    }
}

# --- files -------------------------------------------------------------------

# New-Directory creates a directory and records how to take it back - the
# top-most part of it that did not exist. One that existed is left alone.
function New-Directory([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return }
    $top = $Path
    $parent = Split-Path -Parent $top
    while ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $top = $parent
        $parent = Split-Path -Parent $top
    }
    # Recorded before the step, as every change is; removing what was never
    # made is nothing.
    Add-Undo 'remove' $top
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

# Install-File copies one file into place and records how to take it back:
# the previous file is kept in the scratch directory until the run ends.
function Install-File([string]$Source, [string]$Dest) {
    if (Test-Path -LiteralPath $Dest) {
        # Beside the record on disk: a run taken back by the next one finds
        # the copy there.
        Open-Journal
        $keep = Join-Path $script:JournalDir ('previous-' + [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $Dest -Destination $keep -Force
        Add-Undo 'restore' $keep $Dest
    } else {
        Add-Undo 'remove' $Dest
    }
    Copy-Item -LiteralPath $Source -Destination "$Dest.nox-new" -Force
    Move-Item -LiteralPath "$Dest.nox-new" -Destination $Dest -Force
}

function Write-TextFile([string]$Path, [string]$Text) {
    $tmp = Join-Path $script:Work ('text-' + [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($false)))
    Install-File $tmp $Path
}

# Expand-Template returns a template with every @NAME@ replaced by its value,
# taken literally; a placeholder left without a value is an error.
function Expand-Template([string]$Name, [hashtable]$Values) {
    $text = [System.IO.File]::ReadAllText((Join-Path $DeployDir $Name))
    foreach ($m in [regex]::Matches($text, '@[A-Z][A-Z_]*@')) {
        if (-not $Values.ContainsKey($m.Value.Trim('@'))) { Fail "unfilled placeholder $($m.Value) in $Name" }
    }
    foreach ($k in $Values.Keys) { $text = $text.Replace("@$k@", [string]$Values[$k]) }
    return $text.Replace("`r`n", "`n")
}

# ConvertTo-TorString escapes a value for a quoted torrc string.
function ConvertTo-TorString([string]$V) { return $V.Replace('\', '\\').Replace('"', '\"') }

# Set-PrivateAcl gives a folder to SYSTEM, the administrators and one service
# account, and to nobody else: inheritance from ProgramData, which lets every
# user read, is cut. Well-known SIDs, so it reads the same in every language.
function Set-PrivateAcl([string]$Path, [string]$Account) {
    $out = Invoke-Native "$env:SystemRoot\System32\icacls.exe" @($Path, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', "${Account}:(OI)(CI)M")
    if ($out.ExitCode -ne 0) { Fail "could not set who may open $Path`: $($out.Output.Trim())" }
}

# --- the background processes of a check -------------------------------------

function Test-Background([string]$Name, [string]$PidFile) {
    if (-not (Test-Path -LiteralPath $PidFile)) { return $false }
    $id = [int](Get-Content -LiteralPath $PidFile -Raw)
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    return ($null -ne $p -and $p.ProcessName -eq $Name)
}

function Start-Background([string]$Name, [string]$PidFile, [string]$Log, [string]$File, [string[]]$Arguments) {
    $p = Start-Process -FilePath $File -ArgumentList (Join-Arguments $Arguments) -NoNewWindow -PassThru `
        -RedirectStandardError $Log -RedirectStandardOutput "$Log.out"
    Set-Content -LiteralPath $PidFile -Value $p.Id
    Add-Undo 'stop-background' $Name $PidFile
}

function Stop-Background([string]$Name, [string]$PidFile) {
    if (Test-Background $Name $PidFile) {
        $id = [int](Get-Content -LiteralPath $PidFile -Raw)
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $id -Timeout 30 -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

# --- services ----------------------------------------------------------------

function Invoke-Sc([string[]]$Arguments) {
    $out = Invoke-Native "$env:SystemRoot\System32\sc.exe" $Arguments
    if ($out.ExitCode -ne 0) { Fail "sc.exe $($Arguments -join ' ') failed: $($out.Output.Trim())" }
}

# Install-Service creates a service that starts with the machine and runs as
# its own virtual account, NT SERVICE\<name>, or points the existing one at a
# new command line. It is left stopped; the old one's configuration comes back
# if the run fails.
function Install-Service([string]$Name, [string]$Display, [string]$Description, [string]$CommandLine) {
    $existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        $oldPath = (Get-ItemProperty -LiteralPath $key -Name ImagePath).ImagePath
        Add-Undo 'service-command' $Name $oldPath
        Invoke-Sc @('config', $Name, 'binPath=', $CommandLine, 'start=', 'auto')
    } else {
        # Deleting a service that was never created is harmless.
        Add-Undo 'service-delete' $Name
        New-Service -Name $Name -BinaryPathName $CommandLine -DisplayName $Display -Description $Description -StartupType Automatic | Out-Null
    }
    Invoke-Sc @('sidtype', $Name, 'unrestricted')
    Invoke-Sc @('config', $Name, 'obj=', "NT SERVICE\$Name")
    Invoke-Sc @('failure', $Name, 'reset=', '86400', 'actions=', 'restart/5000/restart/5000/restart/5000')
    Invoke-Sc @('failureflag', $Name, '1')
}

# Each undo below is recorded before its step, so a step interrupted half way
# - Ctrl+C while Stop-Service waits for noxd, which closes its connections
# first - is taken back too.
function Stop-ServiceForUpdate([string]$Name) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne 'Stopped') {
        Add-Undo 'service-start' $Name
        Stop-Service -Name $Name -Force
    }
}

function Start-InstalledService([string]$Name) {
    Add-Undo 'service-stop' $Name
    Start-Service -Name $Name
}

# Start-ServiceAgain starts a service this run stopped, once a stop still under
# way - an interrupted Stop-Service leaves it so - has ended. A service that
# does not start is an error the rollback reports.
function Start-ServiceAgain([string]$Name) {
    $s = Get-Service -Name $Name
    if ($s.Status -eq 'StopPending') { $s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60)) }
    $s.Refresh()
    if ($s.Status -ne 'Running' -and $s.Status -ne 'StartPending') { Start-Service -Name $Name }
    if ($Name -eq $ServerService) { $script:ServerLockedAgain = $true }
}

# Initialize-CtrlCGuard prepares what keeps Ctrl+C from cutting a rollback
# short: SetConsoleCtrlHandler(NULL, TRUE) makes the process ignore Ctrl+C
# whatever its standard input is. [Console]::TreatControlCAsInput, the other
# way, needs the console as standard input - and a password given from a
# file, as deploy/README.md describes, takes it away. Without the guard (a
# system that refuses Add-Type) the rollback falls back to the other way.
function Initialize-CtrlCGuard {
    if ($script:CtrlCGuard) { return }
    try {
        Add-Type -Namespace NoxInstall -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(System.IntPtr handler, bool add);'
        $script:CtrlCGuard = $true
    } catch {
        $script:CtrlCGuard = $false
    }
}

# Set-CtrlCIgnored turns ignoring Ctrl+C on or off, where the guard exists.
function Set-CtrlCIgnored([bool]$Ignored) {
    if ($script:CtrlCGuard) { try { [void][NoxInstall.Native]::SetConsoleCtrlHandler([IntPtr]::Zero, $Ignored) } catch { } }
}

# --- the server binary -------------------------------------------------------

function Find-Go {
    $g = Get-Command go -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    foreach ($c in @("$env:ProgramFiles\Go\bin\go.exe", "$env:SystemDrive\Go\bin\go.exe")) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return ''
}

function Get-NewBinary {
    if ($Binary) {
        if (-not (Test-Path -LiteralPath $Binary)) { Fail "-Binary: no file at $Binary" }
        $b = (Resolve-Path -LiteralPath $Binary).Path
    } else {
        $src = Join-Path $RepoDir 'client_backend'
        if (-not (Test-Path -LiteralPath (Join-Path $src 'go.mod'))) { Fail "no server source at $src`: run the script from the NOX repository, or pass -Binary" }
        $go = Find-Go
        if (-not $go) { Fail 'no Go toolchain to build the server with: install Go (see client_backend\go.mod for the version), or pass -Binary <a noxd.exe built for Windows>' }
        Step 'Building the server'
        $b = Join-Path $script:Work 'noxd.exe'
        $env:CGO_ENABLED = '0'
        if ($Prefix) { $env:GOCACHE = Join-Path $script:Work 'gocache' }
        $out = Invoke-Native $go @('-C', $src, 'build', '-trimpath', '-ldflags=-s', '-o', $b, '.')
        if ($out.ExitCode -ne 0) {
            Say $out.Output
            Fail 'the server did not build (see above); fix that, or pass -Binary'
        }
    }
    # It runs here, and it is a server of this generation: the locked start
    # and the commands this script talks to.
    $help = (Invoke-Native $b @('unlock', '-h')).Output
    if ($help -notmatch '-status-addr') { Fail "$b does not run here as a NOX server with 'noxd unlock'; build it for Windows" }
    $help = (Invoke-Native $b @('link', '-h')).Output
    if ($help -notmatch '-qr') { Fail "$b has no 'noxd link -qr'; build it from this repository" }
    return $b
}

# --- the password and the public address -------------------------------------

function Get-CharCount([string]$S) {
    $n = 0
    foreach ($c in $S.ToCharArray()) { if (-not [char]::IsLowSurrogate($c)) { $n++ } }
    return $n
}

# Get-PasswordRefusal is the server's rule for a first password, in its words:
# at least twelve characters - characters, not bytes - and not whitespace
# alone. The server checks again; this only spares a round trip.
function Get-PasswordRefusal([string]$Pw) {
    if ([string]::IsNullOrWhiteSpace($Pw) -or (Get-CharCount $Pw) -lt 12) { return 'Use at least 12 characters.' }
    return ''
}

function ConvertFrom-Secure([Security.SecureString]$S) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($S)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# Read-Password returns the first password: asked twice at the console until
# both match and the server would take it; or two lines on standard input when
# that is redirected - the password and its repeat.
function Read-Password {
    if ([Console]::IsInputRedirected) {
        # The bytes as they came, read as UTF-8 and refused when they are not:
        # [Console]::In decodes with the console's code page, and a password
        # changed on its way in is one nobody can type again. A byte order
        # mark - UTF-8, or UTF-16 as Windows PowerShell writes files - is
        # honoured.
        $stdin = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding($false, $true)), $true)
        try {
            $pw = $stdin.ReadLine()
            $repeat = $stdin.ReadLine()
        } catch {
            Fail 'standard input is redirected, so the password is read from it, and it is not UTF-8 text: give the password and its repeat as two lines of UTF-8'
        }
        if ($null -eq $pw -or $null -eq $repeat) { Fail 'standard input is redirected, so the password is read from it: two lines, the password and its repeat' }
        $refusal = Get-PasswordRefusal $pw
        if ($refusal) { Fail $refusal }
        if ($pw -cne $repeat) { Fail "The passwords don't match." }
        return $pw
    }
    Say ''
    Say "Set a password for this server. It opens the server's data after every start, and it is stored nowhere."
    Say "If you forget this password, the server's data can't be opened by anyone, including you."
    while ($true) {
        $pw = ConvertFrom-Secure (Read-Host -Prompt 'Password' -AsSecureString)
        $refusal = Get-PasswordRefusal $pw
        if ($refusal) { Say $refusal; continue }
        $repeat = ConvertFrom-Secure (Read-Host -Prompt 'Repeat password' -AsSecureString)
        if ($pw -cne $repeat) { Say "The passwords don't match."; continue }
        return $pw
    }
}

function Read-PublicAddr {
    if ([Console]::IsInputRedirected) { return '' }
    Say ''
    Say "If this machine is reachable from the internet (a public name or address forwarded to port $($script:Port)),"
    Say 'enter it as host:port - devices will use it away from home. Otherwise press Enter.'
    while ($true) {
        $a = (Read-Host -Prompt 'Public address').Trim()
        if (-not $a) { return '' }
        if (Test-PublicAddr $a) { return $a }
        Say 'That is not host:port (for example nox.example.org:8443). Try again, or press Enter for none.'
    }
}

# --- tor ---------------------------------------------------------------------

function Get-TorVersion([string]$Exe) {
    try { $out = (Invoke-Native $Exe @('--version')).Output } catch { return $null }
    if ($out -match 'Tor version (\d+\.\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
    return $null
}

# Get-TorUnsuitable says why a tor cannot carry the NOX onion service, or ''.
function Get-TorUnsuitable([string]$Exe) {
    $v = Get-TorVersion $Exe
    if (-not $v) { return 'it does not run' }
    if ($v -lt $TorMinVersion) { return "it is version $v, and the Tor network takes $TorMinVersion or newer" }
    $modules = (Invoke-Native $Exe @('--list-modules')).Output
    if ($modules -notmatch 'pow: yes') { return 'it was built without proof-of-work support (the "pow" module)' }
    return ''
}

function Find-GpgVerifier {
    foreach ($name in @('gpgv', 'gpg')) {
        $g = Get-Command $name -ErrorAction SilentlyContinue
        if ($g) { return $g.Source }
        foreach ($dir in @("${env:ProgramFiles(x86)}\GnuPG\bin", "$env:ProgramFiles\GnuPG\bin", "$env:ProgramFiles\Git\usr\bin")) {
            $c = Join-Path $dir "$name.exe"
            if (Test-Path -LiteralPath $c) { return $c }
        }
    }
    return ''
}

function Get-Url([string]$Url, [string]$OutFile) {
    if ($Url.StartsWith('file://')) {
        Copy-Item -LiteralPath ([Uri]$Url).LocalPath -Destination $OutFile -Force
        return
    }
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 900
}

# Test-TorProjectSignature passes only for a valid signature over Data by a key
# whose PRIMARY fingerprint is the pinned one. The verdict comes from the
# status lines, not the exit code.
function Test-TorProjectSignature([string]$Sig, [string]$Data, [string]$Keyring) {
    $checker = Find-GpgVerifier
    if ((Split-Path -Leaf $checker) -like 'gpgv*') {
        $out = Invoke-Native $checker @('--keyring', $Keyring.Replace('\', '/'), '--status-fd', '1', $Sig, $Data)
    } else {
        # Not $home: that is PowerShell's own, and read-only.
        $gnupgHome = Join-Path $script:Work ('gnupg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $gnupgHome | Out-Null
        $out = Invoke-Native $checker @('--homedir', $gnupgHome, '--batch', '--no-autostart', '--no-default-keyring', '--keyring', $Keyring.Replace('\', '/'),
            '--trust-model', 'always', '--status-fd', '1', '--verify', $Sig, $Data)
    }
    $ok = $false
    foreach ($line in ($out.Output -split "`r?`n")) {
        $f = $line -split ' '
        if ($f.Count -ge 2 -and $f[0] -eq '[GNUPG:]') {
            if ($f[1] -eq 'VALIDSIG' -and $f[$f.Count - 1] -eq $TorSigningKey) { $ok = $true }
            if ($f[1] -in @('BADSIG', 'ERRSIG', 'REVKEYSIG')) { return $false }
        }
    }
    return $ok
}

# Get-TorBundle fetches the Tor Expert Bundle for Windows and checks it: the
# checksum list must carry a valid signature by the Tor Browser signing key -
# its primary fingerprint, not just any key that answers to the name - and the
# bundle must match its line in the list. It returns the unpacked tor.exe.
function Get-TorBundle {
    if (-not (Find-GpgVerifier)) { Fail 'there is no gpg to check the Tor Project''s signature with (install Gpg4win), and tor is never installed unchecked' }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { 'i686' } else { 'x86_64' }
    $version = $env:NOX_TOR_VERSION
    if (-not $version) {
        try { $version = (Invoke-RestMethod -Uri $TorVersionUrl -UseBasicParsing -TimeoutSec 60).version } catch { $version = '' }
    }
    if ($version -notmatch '^\d+(\.\d+)+$') { Fail 'could not learn the current Tor Expert Bundle version from the Tor Project (no network?)' }
    $tarball = "tor-expert-bundle-windows-$arch-$version.tar.gz"
    $dir = Join-Path $script:Work 'tor'
    New-Item -ItemType Directory -Path (Join-Path $dir 'bundle') -Force | Out-Null
    Note "downloading $tarball"
    try {
        Get-Url "$TorDist/$version/$tarball" (Join-Path $dir $tarball)
        Get-Url "$TorDist/$version/sha256sums-signed-build.txt" (Join-Path $dir 'sums.txt')
        Get-Url "$TorDist/$version/sha256sums-signed-build.txt.asc" (Join-Path $dir 'sums.txt.asc')
        Get-Url $TorKeyUrl (Join-Path $dir 'signing-key')
    } catch {
        Fail "could not download the Tor Expert Bundle $version (no network?): $($_.Exception.Message)"
    }
    Note 'checking the Tor Project''s signature'
    if (-not (Test-TorProjectSignature (Join-Path $dir 'sums.txt.asc') (Join-Path $dir 'sums.txt') (Join-Path $dir 'signing-key'))) {
        Fail "the checksum list is not signed by the Tor Project's key ($TorSigningKey); tor was not installed"
    }
    $expected = ''
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $dir 'sums.txt'))) {
        $f = $line -split '\s+'
        if ($f.Count -ge 2 -and $f[1] -eq $tarball) { $expected = $f[0].ToLower(); break }
    }
    $actual = (Get-FileHash -LiteralPath (Join-Path $dir $tarball) -Algorithm SHA256).Hash.ToLower()
    if (-not $expected -or $expected -ne $actual) { Fail "the downloaded $tarball does not match its signed checksum; tor was not installed" }
    Note 'signature and checksum match'
    $out = Invoke-Native "$env:SystemRoot\System32\tar.exe" @('-xzf', (Join-Path $dir $tarball), '-C', (Join-Path $dir 'bundle'))
    if ($out.ExitCode -ne 0) { Fail "could not unpack $tarball`: $($out.Output.Trim())" }
    $exe = Join-Path $dir 'bundle\tor\tor.exe'
    if (-not (Test-Path -LiteralPath $exe)) { Fail "$tarball holds no tor\tor.exe" }
    return $exe
}

# Install-TorFiles puts a tor.exe into the install folder, under that name,
# with the libraries that sit beside it: the folder the tor service's account
# may read and run from.
function Install-TorFiles([string]$Exe) {
    $dir = Split-Path -Parent $script:TorExeInstalled
    New-Directory $dir
    Install-File $Exe $script:TorExeInstalled
    foreach ($lib in (Get-ChildItem -LiteralPath (Split-Path -Parent $Exe) -Filter '*.dll' -File -ErrorAction SilentlyContinue)) {
        Install-File $lib.FullName (Join-Path $dir $lib.Name)
    }
}

# Install-Tor puts tor and the NOX onion service in place and returns the
# onion address. Every change goes on the tor record.
function Install-Tor {
    Step 'tor'
    $fresh = ''
    if ($TorBin) {
        $given = (Resolve-Path -LiteralPath $TorBin).Path
        $why = Get-TorUnsuitable $given
        if ($why) { Fail "the tor at $TorBin cannot be used: $why" }
        # Run from the install folder, like a downloaded tor: the service runs
        # as NT SERVICE\nox-tor, which may read Program Files but not the
        # owner's own folders - where a tor.exe usually is (Tor Browser on the
        # Desktop, a bundle unpacked in Downloads).
        if ($given -ne $script:TorExeInstalled) { $fresh = $given }
        $script:TorExe = $script:TorExeInstalled
        Note "using the tor at $given ($(Get-TorVersion $given)), run from $(Split-Path -Parent $script:TorExeInstalled)"
    } elseif ((Test-Path -LiteralPath $script:TorExeInstalled) -and -not (Get-TorUnsuitable $script:TorExeInstalled)) {
        $script:TorExe = $script:TorExeInstalled
        Note "using the tor installed before ($(Get-TorVersion $script:TorExe))"
    } else {
        $fresh = Get-TorBundle
        $why = Get-TorUnsuitable $fresh
        if ($why) { Fail "the downloaded tor cannot be used: $why" }
        $script:TorExe = $script:TorExeInstalled
        Note "Tor Expert Bundle ready ($(Get-TorVersion $fresh))"
    }

    # Stopped before its files are replaced: Windows does not let a running
    # program's file be written over.
    if ($Prefix) { Stop-Background 'tor' $script:TorPidFile } else { Stop-ServiceForUpdate $TorService }
    if ($fresh) { Install-TorFiles $fresh }
    New-Directory $script:TorDir
    New-Directory $script:TorData

    # tor's own settings are written once and then belong to the owner; the
    # NOX onion service is written on every run. A check's tor logs to its
    # standard error, which goes to the log file; a service has none, and tor
    # reads no quotes in a Log line, so its log path must not hold a space.
    if (-not (Test-Path -LiteralPath $script:Torrc)) {
        $logTarget = 'stderr'
        if (-not $NoService) {
            if ($script:TorLog -match '\s') { Warn "tor's log path holds a space, so tor logs nowhere: $($script:TorLog)" }
            else { $logTarget = "file $($script:TorLog)" }
        }
        Write-TextFile $script:Torrc (Expand-Template 'torrc.tmpl' @{
                DATA_DIR = (ConvertTo-TorString $script:TorData); LOG_TARGET = $logTarget; NOX_CONF = (ConvertTo-TorString $script:NoxTorConf) })
    }
    if (-not (Test-Path -LiteralPath $script:TorDefaults)) { Write-TextFile $script:TorDefaults '' }
    Write-TextFile $script:NoxTorConf (Expand-Template 'nox-tor.conf.tmpl' @{ HS_DIR = (ConvertTo-TorString $script:HsDir); PORT = $script:Port })

    $check = Invoke-Native $script:TorExe @('--defaults-torrc', $script:TorDefaults, '-f', $script:Torrc, '--verify-config')
    if ($check.ExitCode -ne 0) {
        $why = (($check.Output -split "`r?`n") | Where-Object { $_ -match '\[(warn|err)\]' } | Select-Object -Last 2) -join ' '
        Fail "tor does not accept its settings: $why"
    }
    # tor writes the address from the key on every start; without the old
    # file, the wait below proves this start. The key itself stays.
    Remove-Item -LiteralPath (Join-Path $script:HsDir 'hostname') -Force -ErrorAction SilentlyContinue

    $torArgs = @('--defaults-torrc', $script:TorDefaults, '-f', $script:Torrc)
    if ($Prefix) {
        Stop-Background 'tor' $script:TorPidFile
        Start-Background 'tor' $script:TorPidFile $script:TorLog $script:TorExe $torArgs
        Write-TextFile (Join-Path $script:RunDir "$TorService.service.txt") ((ConvertTo-Argument $script:TorExe) + ' --nt-service ' + (Join-Arguments $torArgs))
    } else {
        Install-Service $TorService 'tor for NOX' 'Publishes the onion service of the NOX server on this machine.' `
            ((ConvertTo-Argument $script:TorExe) + ' --nt-service ' + (Join-Arguments $torArgs))
        Set-PrivateAcl $script:TorDir "NT SERVICE\$TorService"
        Start-InstalledService $TorService
    }

    $hostFile = Join-Path $script:HsDir 'hostname'
    $deadline = (Get-Date).AddSeconds($OnionWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $hostFile) {
            $h = ([System.IO.File]::ReadAllText($hostFile)).Trim()
            if ($h -match '^[a-z2-7]{56}\.onion$') { Note 'the onion service is ready'; return $h }
        }
        Start-Sleep -Seconds 1
    }
    if (Test-Path -LiteralPath $script:TorLog) {
        Say "The end of tor's log:"
        Get-Content -LiteralPath $script:TorLog -Tail 8 | ForEach-Object { Say $_ }
    }
    Fail "tor did not write its onion address within $OnionWaitSeconds seconds"
}

# --- the server --------------------------------------------------------------

function Get-Health {
    try {
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$($script:StatusPort)/health")
        $req.Proxy = $null
        $req.Timeout = 3000
        $resp = $req.GetResponse()
        try {
            $body = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd()
        } finally { $resp.Close() }
        if ($body -match '"status":"([a-z]+)"') { return $Matches[1] }
    } catch {}
    return ''
}

function Wait-Health {
    $deadline = (Get-Date).AddSeconds($HealthWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $s = Get-Health
        if ($s) { return $s }
        if ($Prefix -and -not (Test-Background 'noxd' $script:ServerPidFile)) { return '' }
        Start-Sleep -Seconds 1
    }
    return ''
}

# Get-PreviousArg reads a flag's value from the installed server's command
# line - the service's, or a check's record of it.
function Get-PreviousArg([string]$Flag) {
    $line = ''
    if ($Prefix) {
        $f = Join-Path $script:RunDir "$ServerService.service.txt"
        if (Test-Path -LiteralPath $f) { $line = [System.IO.File]::ReadAllText($f) }
    } else {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServerService"
        if (Test-Path -LiteralPath $key) { $line = (Get-ItemProperty -LiteralPath $key -Name ImagePath).ImagePath }
    }
    if ($line -match ('(^|\s)' + [regex]::Escape($Flag) + '\s+"?([^"\s]+)"?')) { return $Matches[2] }
    return ''
}

function Get-ServerArguments {
    $a = @('-addr', "0.0.0.0:$($script:Port)", '-db', $script:Db, '-status-addr', "127.0.0.1:$($script:StatusPort)")
    if ($script:Onion) { $a += @('-onion-addr', $script:Onion) }
    if ($script:PublicAddress) { $a += @('-public-addr', $script:PublicAddress) }
    return $a
}

function Start-Server {
    Step 'Starting the server'
    $serverArgs = Get-ServerArguments
    $commandLine = (ConvertTo-Argument $script:Noxd) + ' ' + (Join-Arguments $serverArgs)
    if ($Prefix) {
        Stop-Background 'noxd' $script:ServerPidFile
        Write-TextFile (Join-Path $script:RunDir "$ServerService.service.txt") $commandLine
        Start-Background 'noxd' $script:ServerPidFile $script:ServerLog $script:Noxd $serverArgs
        return
    }
    Install-Service $ServerService 'NOX server' "The NOX server. It starts locked: enter its password on its service page, http://127.0.0.1:$($script:StatusPort), or with noxd unlock." $commandLine
    Set-PrivateAcl $script:DataDir "NT SERVICE\$ServerService"
    # The backups folder was made before the data folder's permissions were
    # set: it gets them explicitly rather than through inheritance.
    Set-PrivateAcl $script:BackupDir "NT SERVICE\$ServerService"
    # The tor folder inside keeps its own permissions, which the data
    # folder's do not reach: its inheritance is cut.
    if ((Test-Path -LiteralPath $script:TorDir) -and (Get-Service -Name $TorService -ErrorAction SilentlyContinue)) {
        Set-PrivateAcl $script:TorDir "NT SERVICE\$TorService"
    }
    $rule = Get-NetFirewallRule -Name $FirewallRule -ErrorAction SilentlyContinue
    if ($rule) {
        $old = [string](($rule | Get-NetFirewallPortFilter).LocalPort)
        Add-Undo 'firewall-port' $FirewallRule $old
        $rule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort $script:Port
    } else {
        Add-Undo 'firewall-remove' $FirewallRule
        New-NetFirewallRule -Name $FirewallRule -DisplayName 'NOX server' -Direction Inbound -Action Allow -Protocol TCP `
            -LocalPort $script:Port -Program $script:Noxd -Profile Any | Out-Null
    }
    Start-InstalledService $ServerService
}

# --- the end -----------------------------------------------------------------

# ConvertTo-PsLiteral quotes a value for a PowerShell command shown to the
# owner.
function ConvertTo-PsLiteral([string]$S) { return "'" + $S.Replace("'", "''") + "'" }

function Get-StatusFlag { return (Get-StatusFlagFor $script:StatusPort) }

# Get-StatusFlagFor is Get-StatusFlag for the service page on another port.
function Get-StatusFlagFor([int]$P) {
    if ($P -ne $DefaultStatusPort) { return " -status-addr 127.0.0.1:$P" }
    return ''
}

function Complete-NewServer {
    $cmd = '& ' + (ConvertTo-Argument $script:Noxd).Replace('"', "'")
    Step "Setting the server's password"
    while ($true) {
        $out = Invoke-Native $script:Noxd @('unlock', '-status-addr', "127.0.0.1:$($script:StatusPort)") ($script:Password + "`n" + $script:Password + "`n")
        if ($out.ExitCode -eq 0) { break }
        if ($out.Output -match 'Use at least 12 characters' -and -not [Console]::IsInputRedirected) {
            Say $out.Output.Trim()
            $script:Password = Read-Password
            continue
        }
        $script:Password = $null
        Warn "the password was not set: $($out.Output.Trim())"
        Say "The server is installed and running, but has no password yet. Set it on the service page,"
        Say "http://127.0.0.1:$($script:StatusPort) on this machine, or with: $cmd unlock$(Get-StatusFlag)"
        return
    }
    $script:Password = $null
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and (Get-Health) -ne 'ok') { Start-Sleep -Seconds 1 }
    Say 'Password set. The server is open.'
    Step 'The link for your first device'
    Say 'Scan the code with the NOX app on your phone, or paste the link into the app:'
    Say ''
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $script:Noxd link -qr -status-addr "127.0.0.1:$($script:StatusPort)"
    $code = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($code -ne 0) { Warn "the server did not give a link; get one on the service page or with: $cmd link -qr$(Get-StatusFlag)" }
}

function Write-Summary {
    $cmd = '& ' + (ConvertTo-Argument $script:Noxd).Replace('"', "'")
    Step 'Done'
    if ($Prefix) {
        Say "A check under $Prefix`: nothing outside it was changed, and nothing starts with the machine."
        Say 'The server (and tor, when there is one) run as background processes; stop them with'
        Say "    Stop-Process -Id (Get-Content '$($script:ServerPidFile)')"
        if (Test-Path -LiteralPath $script:TorPidFile) { Say "    Stop-Process -Id (Get-Content '$($script:TorPidFile)')" }
    } else {
        Say "The NOX server is installed and starts with this machine (service: $ServerService)."
    }
    Note "service page:  http://127.0.0.1:$($script:StatusPort) (on this machine only)"
    Note "server port:   $($script:Port) - devices connect here directly"
    if ($script:Onion) {
        Note 'tor:           running; devices reach the server through it away from home'
    } elseif ($NoTor) {
        Note 'tor:           not set up (-NoTor); devices connect directly only'
    } else {
        Note "tor:           not installed - $($script:TorProblem)"
        Note '               devices connect directly only; see deploy\README.md to set tor up by hand'
    }
    Note "server log:    $($script:ServerLog)"
    Say ''
    Say 'After every restart of this machine the server starts locked, and devices cannot connect'
    Say 'until its password is entered - on the service page, or in PowerShell:'
    Say "    $cmd unlock$(Get-StatusFlag)"
    Say 'A link lasts 10 minutes. For a new one: Add a device or New link on the service page, or'
    Say "    $cmd link -qr$(Get-StatusFlag)"
    $backup = Join-Path $script:BackupDir ('nox-' + (Get-Date -Format 'yyyy-MM-dd') + '.tar')
    Say ''
    Say 'A backup is written by the running server, as its own account, which can write only in its own'
    Say "folder - $($script:BackupDir) is there for backups:"
    Say "    $cmd backup$(Get-StatusFlag) $(ConvertTo-PsLiteral $backup)"
    Say 'Then copy it off this machine from PowerShell run as administrator; there, only administrators can read it:'
    Say ('    Copy-Item ' + (ConvertTo-PsLiteral $backup) + ' $HOME\Documents')
}

# --- main --------------------------------------------------------------------

function Initialize-Paths {
    if ($Prefix) {
        New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
        $root = (Resolve-Path -LiteralPath $Prefix).Path
        $script:ProgramDir = Join-Path $root 'Program Files\NOX'
        $script:DataDir = Join-Path $root 'ProgramData\NOX'
    } else {
        $script:ProgramDir = Join-Path $env:ProgramFiles 'NOX'
        $script:DataDir = Join-Path $env:ProgramData 'NOX'
    }
    $script:Noxd = Join-Path $script:ProgramDir 'noxd.exe'
    $script:Db = Join-Path $script:DataDir 'nox.db'
    $script:ServerLog = Join-Path $script:DataDir 'noxd.log'
    $script:BackupDir = Join-Path $script:DataDir 'backups'
    $script:TorExeInstalled = Join-Path $script:ProgramDir 'tor\tor.exe'
    $script:TorDir = Join-Path $script:DataDir 'tor'
    $script:Torrc = Join-Path $script:TorDir 'torrc'
    $script:TorDefaults = Join-Path $script:TorDir 'torrc-defaults'
    $script:NoxTorConf = Join-Path $script:TorDir 'nox-tor.conf'
    $script:TorData = Join-Path $script:TorDir 'data'
    $script:HsDir = Join-Path $script:TorDir 'nox'
    $script:TorLog = Join-Path $script:TorDir 'tor.log'
    $script:RunDir = Join-Path $script:DataDir 'run'
    $script:ServerPidFile = Join-Path $script:RunDir 'noxd.pid'
    $script:TorPidFile = Join-Path $script:RunDir 'nox-tor.pid'
    # The record of changes on disk: SYSTEM's and the administrators' alone,
    # beside nothing the server's account may write.
    if ($Prefix) { $script:JournalDir = Join-Path $root 'ProgramData\NOX-install' } else { $script:JournalDir = Join-Path $env:ProgramData 'NOX-install' }
}

function Invoke-Install {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { Fail 'this script is for Windows; on macOS use install-macos.sh, on Linux install-linux.sh' }
    if ($Prefix -and -not $NoService) { Fail '-Prefix goes together with -NoService: services must not run from a scratch directory' }
    if ($NoService -and -not $Prefix) { Fail '-NoService goes together with -Prefix: it is for checking the script without changing the system' }
    if ($TorBin -and $NoTor) { Fail '-TorBin and -NoTor contradict each other' }
    if (-not $Prefix -and -not (Test-Administrator)) { Fail 'installing needs administrator rights: start PowerShell with "Run as administrator" and run the script again' }
    foreach ($p in @($Port, $StatusPort)) { if ($p -lt 0 -or $p -gt 65535) { Fail "a port is a number from 1 to 65535: $p" } }
    if ($PublicAddr -and -not (Test-PublicAddr $PublicAddr)) { Fail "-PublicAddr takes host:port, such as nox.example.org:8443: $PublicAddr" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    Initialize-Paths
    Initialize-CtrlCGuard
    Resume-Interrupted
    $script:FreshData = -not ((Test-Path -LiteralPath $script:Db) -or (Test-Path -LiteralPath "$($script:Db).key"))
    $script:Update = (-not $script:FreshData) -or [bool](Get-PreviousArg '-addr')
    $script:Port = $Port
    if (-not $script:Port) { $prev = Get-PreviousArg '-addr'; if ($prev -match ':(\d+)$') { $script:Port = [int]$Matches[1] } else { $script:Port = $DefaultPort } }
    $prev = Get-PreviousArg '-status-addr'
    if ($prev -match ':(\d+)$') { $script:PreviousStatusPort = [int]$Matches[1] } else { $script:PreviousStatusPort = $DefaultStatusPort }
    $script:StatusPort = $StatusPort
    if (-not $script:StatusPort) { $script:StatusPort = $script:PreviousStatusPort }
    Write-ServerLockedAgain
    $script:ServerLockedAgain = $false
    $script:PublicAddress = $PublicAddr
    if (-not $script:PublicAddress) { $script:PublicAddress = Get-PreviousArg '-public-addr' }
    $script:Onion = ''
    $script:TorProblem = ''

    $base = if ($Prefix) { (Resolve-Path -LiteralPath $Prefix).Path } else { [System.IO.Path]::GetTempPath() }
    $script:Work = Join-Path $base ('nox-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Work | Out-Null

    Step 'Checking this machine'
    Assert-Ports
    if ($script:Update) { Note 'a NOX server is installed here: this run updates it, and leaves its data, password and onion address alone' }
    $newBinary = Get-NewBinary
    if ($script:FreshData) {
        $script:Password = Read-Password
        if (-not $script:PublicAddress) { $script:PublicAddress = Read-PublicAddr }
    }

    # From here on the machine changes; a failure takes every change back,
    # and nothing - not Ctrl+C either - cuts the taking back short.
    Step "Installing the server at $($script:Noxd)"
    if ($Prefix) { Stop-Background 'noxd' $script:ServerPidFile } else { Stop-ServiceForUpdate $ServerService }
    New-Directory $script:ProgramDir
    New-Directory $script:DataDir
    # noxd backup has the server write the file, and its account can write in
    # its own folder only.
    New-Directory $script:BackupDir
    if ($Prefix) { New-Directory $script:RunDir }
    Install-File $newBinary $script:Noxd

    if (-not $NoTor) {
        $script:UndoInto = 'Tor'
        try {
            $script:Onion = Install-Tor
            Save-TorRecord
        } catch {
            # Whatever stopped tor stops tor alone: the server goes on without it.
            $script:UndoInto = 'Main'
            $script:TorProblem = $_.Exception.Message
            Warn "tor: $($script:TorProblem)"
            Invoke-Undo $script:UndoTor
            $script:Onion = ''
            Say 'The server is installed without tor: devices connect directly.'
        }
    }
    Start-Server
    $state = Wait-Health
    if (-not $state) {
        if (Test-Path -LiteralPath $script:ServerLog) {
            Say "The end of the server's log:"
            Get-Content -LiteralPath $script:ServerLog -Tail 12 | ForEach-Object { Say $_ }
        }
        Fail "the server did not start, or did not answer on its service page within $HealthWaitSeconds seconds"
    }
    Set-Committed
    Note "the server answers: $state"

    if ($script:FreshData) {
        Complete-NewServer
    } else {
        $cmd = '& ' + (ConvertTo-Argument $script:Noxd).Replace('"', "'")
        Say ''
        Say 'The server was updated and restarted. It is locked until its password is entered:'
        Say "on the service page, http://127.0.0.1:$($script:StatusPort), or with: $cmd unlock$(Get-StatusFlag)"
    }
    Write-Summary
}

$script:Work = ''
$script:Password = $null
$exitCode = 1
$completed = $false
try {
    Invoke-Install
    $completed = $true
    $exitCode = 0
} catch {
    $message = $_.Exception.Message
    if (-not ($_.Exception -is [System.ApplicationException])) { $message = "$message ($($_.InvocationInfo.PositionMessage))" }
    try { Write-Host "error: $message" -ForegroundColor Red } catch { }
} finally {
    # The taking back is here and not in the catch: Ctrl+C stops the script
    # past every catch, and only finally blocks run. It comes before the
    # scratch directory goes, which holds the copies it restores from. A
    # Ctrl+C during it is ignored: one that started it is no threat - the
    # pipeline is already stopping - but one during a rollback a failure
    # started would stop it half way, with standard input redirected too.
    $script:Password = $null
    if (-not $completed -and -not $script:Committed -and ($script:UndoTor.Count -gt 0 -or $script:UndoMain.Count -gt 0)) {
        Set-CtrlCIgnored $true
        $ctrlC = $null
        try { $ctrlC = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true } catch { $ctrlC = $null }
        try {
            Warn 'the installation did not finish; taking back what this run changed'
            Invoke-Undo $script:UndoTor
            Invoke-Undo $script:UndoMain
            if ($script:UndoFailed) { Warn 'not everything could be taken back: see the lines above'; Save-FailedJournal }
            elseif ($script:ServerLockedAgain) { Say 'Everything this run changed was taken back.'; Close-Journal }
            else { Say 'This machine is as it was before the run.'; Close-Journal }
            Write-ServerLockedAgain
        } finally {
            if ($null -ne $ctrlC) { try { [Console]::TreatControlCAsInput = $ctrlC } catch { } }
            Set-CtrlCIgnored $false
        }
    } elseif (-not $script:Committed -and $script:JournalOpen) {
        Close-Journal
    }
    if ($script:Work -and (Test-Path -LiteralPath $script:Work)) { Remove-Item -LiteralPath $script:Work -Recurse -Force -ErrorAction SilentlyContinue }
}
exit $exitCode
