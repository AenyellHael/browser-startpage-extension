@echo off
setlocal DisableDelayedExpansion
echo First remove FXT Team New Tab from chrome://extensions in each Chrome profile.
echo Remove its local installation and daily update task for this Windows user?
choice /C YN /N /M "[Y/N] "
if errorlevel 2 exit /b 0
if not errorlevel 1 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command ^
  "$ErrorActionPreference='Stop'; $root=Join-Path $env:LOCALAPPDATA 'FXTTeam/NewTab';" ^
  "if (!(Test-Path -LiteralPath $root)) { Write-Output 'Installation folder not found.'; exit 0 };" ^
  "$dir=Get-Item -LiteralPath $root; if ($dir.FullName -ne [IO.Path]::GetFullPath($root) -or (($dir.Attributes -bor $dir.Parent.Attributes) -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unexpected installation path.' };" ^
  "function CheckItem($p) { if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('Unexpected link: '+$p) } };" ^
  "$dirs='extension','update','extension/icons'; foreach ($n in $dirs) { CheckItem (Join-Path $root $n) };" ^
  "$manifest=Join-Path $root 'extension/manifest.json'; CheckItem $manifest; if ((Get-Content -Raw -Encoding UTF8 -LiteralPath $manifest | ConvertFrom-Json).name -cne 'FXT Team New Tab') { throw 'Unexpected extension.' };" ^
  "$taskName='FXT Chrome Update '+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $task=Get-ScheduledTask -TaskPath '\' | Where-Object TaskName -eq $taskName;" ^
  "if ($task) { $script=Join-Path $root 'update/windows.ps1'; if ($task.Actions.Count -ne 1 -or $task.Actions[0].Arguments.IndexOf([char]34+$script+[char]34,[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'Update task points to another installation.' } };" ^
  "$lp=Join-Path $root '.fxt-lock'; if (Test-Path -LiteralPath $lp) { CheckItem $lp }; $lock=[IO.File]::Open($lp,'OpenOrCreate','Write','None');" ^
  "try { $reg='HKCU:\Software\Google\Chrome\NativeMessagingHosts\ru.fxtteam.newtab_update'; if ((Test-Path -LiteralPath $reg) -and ((Get-Item -LiteralPath $reg).GetValue('') -eq (Join-Path $root 'update/native.json'))) { Remove-Item -LiteralPath $reg }; if ($task) { Unregister-ScheduledTask -InputObject $task -Confirm:$false }; $files='extension/popup.html','extension/popup.js','extension/manual-update.js','extension/installed.js','update/native.json','update/native.cmd','update/setup.ps1','update/install-help.html','update/open-extensions.ps1','extension/newtab.html','extension/newtab.js','extension/icons/icon16.png','extension/icons/icon32.png','extension/icons/icon48.png','extension/icons/icon128.png','update/windows.ps1','update/linux.py','update/allowed_signers','update/repository.txt','README.md','extension/manifest.json'; foreach ($n in $files) { $p=Join-Path $root $n; if (Test-Path -LiteralPath $p) { CheckItem $p; [IO.File]::Delete($p) } } } finally { $lock.Dispose() };" ^
  "[IO.File]::Delete($lp); foreach ($p in @((Join-Path $root 'extension/icons'),(Join-Path $root 'extension'),(Join-Path $root 'update'),$root,$dir.Parent.FullName)) { if ([IO.Directory]::Exists($p) -and ![IO.Directory]::GetFileSystemEntries($p).Length) { [IO.Directory]::Delete($p) } }; Write-Output 'FXT Team New Tab removed. Other files, if any, were kept.'"
if errorlevel 1 (
  echo Removal could not finish. See the message above.
  pause
  exit /b 1
)
pause
