param([ValidateSet('Check','Enable','Disable','Status','Register','Native','Ask')][string]$Action = 'Status')
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
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    # Windows PowerShell initializes redirected stdin with the console encoding.
    # Its StreamWriter must not prepend a BOM to the signed binary payload.
    $encoding = [Console]::InputEncoding
    if ($encoding.GetPreamble().Length) {
        try {
            [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
            $proc = [Diagnostics.Process]::Start($info)
        } finally { [Console]::InputEncoding = $encoding }
    } else {
        $proc = [Diagnostics.Process]::Start($info)
    }
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    $file = [IO.File]::OpenRead($archive)
    try {
        $pipeError = $null
        try { $file.CopyTo($proc.StandardInput.BaseStream) }
        catch [IO.IOException] { $pipeError = $_ }
        finally { $proc.StandardInput.Close() }
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) {
            $detail = ($stderr.Result.Trim() + ' ' + $stdout.Result.Trim()).Trim()
            if ($detail -match '(?i)(unknown|illegal|invalid|unrecognized) option[^\r\n]*\bY\b|unsupported operation for -Y') {
                throw "Клиент OpenSSH '$keygen' не поддерживает проверку подписи (-Y verify). Обновите «Клиент OpenSSH» и повторите запуск."
            }
            throw "Не удалось подтвердить подпись с помощью '$keygen' (код $($proc.ExitCode)). $detail"
        }
        if ($pipeError) { throw $pipeError }
    } finally { $file.Dispose(); $proc.Dispose() }
}

function Update-Extension([switch]$Preview) {
    $repo = Get-Repository
    $signers = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'allowed_signers')).FullName
    $keygen = (Get-Command ssh-keygen.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (!$keygen) { throw 'Не найден ssh-keygen.exe. Для обновлений добавьте «Клиент OpenSSH» в дополнительных компонентах Windows и снова запустите установщик.' }
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
        foreach ($suffix in '', '.sig') {
            try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri "$url$suffix" -OutFile "$zip$suffix" }
            catch { throw "Не удалось скачать $url$suffix. Проверьте доступ к ссылке на GitHub. $($_.Exception.Message)" }
        }
        Assert-Signature $zip "$zip.sig" $signers $keygen
        $candidate = Join-Path $stage 'candidate'
        Expand-Archive -LiteralPath $zip -DestinationPath $candidate
        $next = Get-ReleaseVersion $candidate
        if ($Preview) {
            $folder = if ($next -gt $installed) { $candidate } else { $live }
            return (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $folder 'manifest.json') | ConvertFrom-Json).version
        }
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
    'Ask' {
        if ([Console]::IsInputRedirected) { [Console]::InputEncoding = New-Object Text.UTF8Encoding($false) }
        while ($true) {
            Write-Host 'Включить ежедневные обновления? 1 — Да, 2 — Нет (Enter — пропустить): ' -NoNewline
            $answer = ([string][Console]::ReadLine()).Trim().ToLowerInvariant()
            if ($answer -in '1','да','д','y','yes','нуы','lf') { exit 0 }
            if ($answer -in '','2','нет','n','no','т','тщ','ytn') { exit 2 }
            Write-Host 'Введите 1 или 2 и нажмите Enter.'
        }
    }
    'Register' {
        $path = [IO.Path]::GetFullPath($live)
        $path = $path.Substring(0,1).ToUpperInvariant() + $path.Substring(1)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = $sha.ComputeHash([Text.Encoding]::Unicode.GetBytes($path)) }
        finally { $sha.Dispose() }
        $id = -join ($hash[0..15] | ForEach-Object {
            [char](97 + ($_ -shr 4)); [char](97 + ($_ -band 15))
        })
        $hostName = 'ru.fxtteam.newtab_update'
        $hostFile = Join-Path $PSScriptRoot 'native.json'
        $config = @{name=$hostName; description='FXT Team signed release updater'; type='stdio';
                    path=(Join-Path $PSScriptRoot 'native.cmd'); allowed_origins=@("chrome-extension://$id/")}
        [IO.File]::WriteAllText($hostFile, ($config | ConvertTo-Json))
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Software\Google\Chrome\NativeMessagingHosts\$hostName")
        try { $key.SetValue('', $hostFile) } finally { $key.Dispose() }
    }
    'Native' {
        $reader = New-Object IO.BinaryReader ([Console]::OpenStandardInput())
        $writer = New-Object IO.BinaryWriter ([Console]::OpenStandardOutput())
        try {
            $length = $reader.ReadUInt32()
            if ($length -gt 1024 -or !$length) { return }
            $message = [Text.Encoding]::UTF8.GetString($reader.ReadBytes($length)) | ConvertFrom-Json
            switch -CaseSensitive ($message.action) {
                'inspect' { $number = Update-Extension -Preview }
                'apply' {
                    $null = Update-Extension
                    $number = (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $live 'manifest.json') | ConvertFrom-Json).version
                }
                default { throw 'Unknown action.' }
            }
            $reply = @{version=$number}
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            $reply = @{error='update'}
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($reply | ConvertTo-Json -Compress))
        $writer.Write([uint32]$bytes.Length)
        $writer.Write($bytes)
        $writer.Flush()
    }
    'Check' { Update-Extension }
    'Enable' {
        foreach ($cmd in 'Register-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskSettingsSet','New-ScheduledTaskPrincipal') {
            if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Для расписания требуется модуль Windows ScheduledTasks. Недоступна команда $cmd. Можно обновлять расширение вручную." }
        }
        if ((Get-Service -Name Schedule -ErrorAction SilentlyContinue).Status -ne 'Running') {
            throw 'Служба «Планировщик заданий» (Schedule) недоступна или остановлена. Для расписания обратитесь к администратору Windows.'
        }
        Update-Extension
        $run = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument (
            '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + $PSCommandPath + '" -Action Check')
        $when = New-ScheduledTaskTrigger -Daily -At '12:00'
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
        try { Register-ScheduledTask -TaskName $taskName -Action $run -Trigger $when -Settings $settings -Principal $principal -Force | Out-Null }
        catch { throw "Планировщик не смог сохранить задание для текущего пользователя. Проверьте разрешение на создание заданий. $($_.Exception.Message)" }
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
