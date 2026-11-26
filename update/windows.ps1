param([ValidateSet('Check','Enable','Disable','Status')][string]$Action = 'Status')
$ErrorActionPreference = 'Stop'
$root = (Get-Item -LiteralPath $PSScriptRoot).Parent.FullName
$live = Join-Path $root 'extension'
$backup = Join-Path $root '.fxt-previous'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$taskName = 'FXT Chrome Update ' + $identity.User.Value

function Get-ReleaseVersion($directory) {
    $m = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $directory 'manifest.json') | ConvertFrom-Json
    if ($m.name -cne 'FXT Team New Tab' -or $m.manifest_version -ne 3 -or
        $m.version -notmatch '^\d+(\.\d+){1,3}$' -or $m.chrome_url_overrides.newtab -ne 'newtab.html') {
        throw 'Unexpected extension manifest.'
    }
    return [version](($m.version.Split('.') + @('0','0') | Select-Object -First 4) -join '.')
}

function Get-Repository {
    $repo = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'repository.txt')).Trim()
    if ($repo -notmatch '^[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9_-][A-Za-z0-9._-]*$') { throw 'Invalid repository.txt' }
    return $repo
}

function Remove-WorkDirectory($path) {
    $item = Get-Item -Force -LiteralPath $path
    if ($item.Parent.FullName -ne $root -or $item.Name -notin '.fxt-previous','.fxt-stage' -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unexpected work path: $path" }
    Remove-Item -Recurse -Force -LiteralPath $item.FullName
}

function Assert-Signature($archive, $signature, $signers, $keygen) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $keygen
    $info.Arguments = '-Y verify -I fxt-release -n fxtteam-chrome -f "' + $signers + '" -s "' + $signature + '"'
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.CreateNoWindow = $true
    $proc = [Diagnostics.Process]::Start($info)
    $file = [IO.File]::OpenRead($archive)
    try {
        try { $file.CopyTo($proc.StandardInput.BaseStream) }
        catch [IO.IOException] { if (!$proc.HasExited) { throw } }
        finally { $proc.StandardInput.Close() }
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) { throw 'Invalid release signature.' }
    } finally { $file.Dispose(); $proc.Dispose() }
}

function Update-Extension {
    $repo = Get-Repository
    $signers = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'allowed_signers')).FullName
    $keygen = (Get-Command ssh-keygen.exe -CommandType Application | Select-Object -First 1).Source
    $stage = Join-Path $root '.fxt-stage'
    $lock = [IO.File]::Open((Join-Path $root '.fxt-lock'), 'OpenOrCreate','Write','None')
    try {
        if ((Test-Path -LiteralPath $backup) -and !(Test-Path -LiteralPath $live)) {
            [IO.Directory]::Move($backup,$live)
        }
        $installed = Get-ReleaseVersion $live
        if (Test-Path -LiteralPath $stage) { Remove-WorkDirectory $stage }
        if (Test-Path -LiteralPath $backup) { Remove-WorkDirectory $backup }
        [void][IO.Directory]::CreateDirectory($stage)
        $zip = Join-Path $stage 'chrome-extension.zip'
        $url = "https://github.com/$repo/releases/latest/download/chrome-extension.zip"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri $url -OutFile $zip
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri "$url.sig" -OutFile "$zip.sig"
        Assert-Signature $zip "$zip.sig" $signers $keygen
        $candidate = Join-Path $stage 'candidate'
        Expand-Archive -LiteralPath $zip -DestinationPath $candidate
        $next = Get-ReleaseVersion $candidate
        if ($next -le $installed) { Write-Output "Up to date ($installed)."; return }
        [IO.Directory]::Move($live,$backup)
        try { [IO.Directory]::Move($candidate,$live) }
        catch { [IO.Directory]::Move($backup,$live); throw }
        Remove-WorkDirectory $backup
        Write-Output "Updated $installed -> $next. Reload the extension in Chrome."
    } finally {
        try { if (Test-Path -LiteralPath $stage) { Remove-WorkDirectory $stage } }
        finally { $lock.Dispose() }
    }
}

switch ($Action) {
    'Check' { Update-Extension }
    'Enable' {
        Update-Extension
        $run = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument (
            '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + $PSCommandPath + '" -Action Check')
        $when = New-ScheduledTaskTrigger -Daily -At '12:00'
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $run -Trigger $when -Settings $settings -Principal $principal -Force | Out-Null
        Write-Output "Enabled: $taskName"
    }
    'Disable' {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        Write-Output 'Automatic updates disabled.'
    }
    'Status' {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) { Get-ScheduledTaskInfo -TaskName $taskName | Select-Object LastRunTime,LastTaskResult,NextRunTime }
        else { Write-Output 'No update task registered.' }
    }
}
