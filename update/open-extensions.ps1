$ErrorActionPreference = 'Stop'
$exe = foreach ($base in $env:LOCALAPPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)}) {
    if ($base) {
        $candidate = Join-Path $base 'Google/Chrome/Application/chrome.exe'
        if (Test-Path -LiteralPath $candidate) { $candidate; break }
    }
}
if (!$exe) { throw 'Google Chrome was not found.' }
$data = Join-Path $env:LOCALAPPDATA 'Google/Chrome/User Data'
$state = Join-Path $data 'Local State'
$profile = 'Default'
if (Test-Path -LiteralPath $state) {
    $cache = (Get-Content -Raw -Encoding UTF8 -LiteralPath $state | ConvertFrom-Json).profile.info_cache
    $profiles = @($cache.PSObject.Properties | Where-Object {
        $_.MemberType -eq 'NoteProperty' -and $_.Name -notin '.','..','Guest Profile','System Profile' -and
        $_.Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0 -and
        (Test-Path -LiteralPath (Join-Path $data $_.Name) -PathType Container)
    } | Sort-Object Name)
    if ($profiles.Count -eq 1) { $profile = $profiles[0].Name }
    if ($profiles.Count -gt 1) {
        Write-Host 'Choose a Chrome profile:'
        for ($i=0; $i -lt $profiles.Count; $i++) {
            Write-Host ('{0}. {1} ({2})' -f ($i+1),$profiles[$i].Value.name,$profiles[$i].Name)
        }
        do {
            $answer = Read-Host 'Profile number (Enter to skip)'
            if (!$answer) { return }
            $index = 0
        } until ([int]::TryParse($answer,[ref]$index) -and $index -ge 1 -and $index -le $profiles.Count)
        $profile = $profiles[$index-1].Name
    }
}

# A local guide identifies this particular window and supplies manual steps if focus changes.
$title = 'FXT Team New Tab ' + [guid]::NewGuid().ToString('N')
$guide = Join-Path $PSScriptRoot 'install-help.html'
$folder = [Net.WebUtility]::HtmlEncode((Join-Path (Split-Path $PSScriptRoot) 'extension'))
[IO.File]::WriteAllText($guide,"<!doctype html><meta charset=utf-8><title>$title</title><h1>FXT Team New Tab</h1><p>Open <code>chrome://extensions/</code> in the address bar. Enable Developer mode and click Load unpacked.</p><p><code>$folder</code></p>")
$url = ([uri]$guide).AbsoluteUri
Start-Process -FilePath $exe -ArgumentList ('--profile-directory="'+$profile+'" --new-window "'+$url+'"')
Add-Type -Namespace FXT -Name ChromeWindow -MemberDefinition @"
private delegate bool EnumCallback(System.IntPtr hwnd, System.IntPtr unused);
[System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool EnumWindows(EnumCallback callback, System.IntPtr data);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
private static extern int GetWindowText(System.IntPtr hwnd, System.Text.StringBuilder text, int length);
[System.Runtime.InteropServices.DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
[System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool PostMessage(System.IntPtr hwnd, uint message, System.IntPtr command, System.IntPtr data);
public static bool OpenExtensions(string title) {
    bool sent = false;
    EnumWindows(delegate(System.IntPtr hwnd, System.IntPtr unused) {
        var text = new System.Text.StringBuilder(512);
        GetWindowText(hwnd, text, text.Capacity);
        if (!text.ToString().StartsWith(title, System.StringComparison.Ordinal)) return true;
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        using (var process = System.Diagnostics.Process.GetProcessById((int)pid)) {
            if (process.ProcessName != "chrome") return true;
        }
        // WM_COMMAND: Chromium's IDC_MANAGE_EXTENSIONS menu action.
        sent = PostMessage(hwnd, 0x0111, new System.IntPtr(40022), System.IntPtr.Zero);
        return !sent;
    }, System.IntPtr.Zero);
    return sent;
}
"@
$deadline = [DateTime]::UtcNow.AddSeconds(12)
do {
    if ([FXT.ChromeWindow]::OpenExtensions($title)) { return }
    Start-Sleep -Milliseconds 150
} while ([DateTime]::UtcNow -lt $deadline)
Write-Host 'Open chrome://extensions/ in the selected Chrome window.'
