param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$bundle = (Get-Item -LiteralPath $PSScriptRoot).Parent.FullName
if (![IO.Directory]::Exists($Destination)) {
    [IO.Directory]::Move($bundle, $Destination)
} else {
    function In-Folder($folder,$name) { Join-Path (Join-Path $folder 'update') $name }
    if ((Get-FileHash -LiteralPath (In-Folder $bundle 'allowed_signers')).Hash -ne
        (Get-FileHash -LiteralPath (In-Folder $Destination 'allowed_signers')).Hash) {
        throw 'Ключ подписи отличается от установленного. Проверьте, что файл скачан из официального релиза FXT Team.'
    }
    $lock = [IO.File]::Open((Join-Path $Destination '.fxt-lock'),'OpenOrCreate','Write','None')
    try {
        $live = Join-Path $Destination 'extension'
        $backup = Join-Path $Destination '.fxt-previous'
        if (!(Test-Path -LiteralPath $live) -and (Test-Path -LiteralPath $backup)) {
            [IO.Directory]::Move($backup,$live)
        }
        $installed = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $live 'manifest.json') | ConvertFrom-Json
        $candidate = Join-Path $bundle 'extension'
        $next = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $candidate 'manifest.json') | ConvertFrom-Json
        if ($installed.name -cne $next.name -or [version]$installed.version -gt [version]$next.version) {
            throw 'В папке другое расширение или более новая версия. Скачайте последний установщик FXT Team из GitHub Releases.'
        }
        foreach ($name in 'native.cmd','windows.ps1','open-extensions.ps1') {
            $from = In-Folder $bundle $name
            $to = In-Folder $Destination $name
            if ([IO.File]::Exists($to)) { [IO.File]::Replace($from,$to,(Join-Path $bundle ($name+'.old'))) }
            else { [IO.File]::Move($from,$to) }
        }
        if ([version]$installed.version -lt [version]$next.version) {
            [IO.Directory]::Move($live,$backup)
            try { [IO.Directory]::Move($candidate,$live) }
            catch { [IO.Directory]::Move($backup,$live); throw }
            [IO.Directory]::Move($backup,(Join-Path $bundle 'old-extension'))
        }
    } finally { $lock.Dispose() }
}
try { & (Join-Path $Destination 'update/windows.ps1') -Action Register }
catch { Write-Warning "Файлы установлены, но кнопка обновления в Chrome пока недоступна. Проверьте права записи в папку установки и в реестр текущего пользователя. $($_.Exception.Message)" }
if (!(Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
    Write-Warning 'Для обновлений нужен «Клиент OpenSSH». Его можно добавить в дополнительных компонентах Windows. Стартовая страница доступна без него.'
}
