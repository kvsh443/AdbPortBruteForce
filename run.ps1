
param(
    [string]$AndroidIP = "192.168.0.1"
)

$MaxThreads = 2000
$StartTime = [System.Diagnostics.Stopwatch]::StartNew()

$PortList = [System.Collections.Generic.List[int]]::new()
$Sec1 = [System.Collections.Generic.List[int]]::new(); for ($p = 49999; $p -ge 45000; $p--) { $Sec1.Add($p) }
$Sec2 = [System.Collections.Generic.List[int]]::new(); for ($p = 30000; $p -le 34999; $p++) { $Sec2.Add($p) }
$Sec3 = [System.Collections.Generic.List[int]]::new(); for ($p = 44999; $p -ge 40000; $p--) { $Sec3.Add($p) }
$Sec4 = [System.Collections.Generic.List[int]]::new(); for ($p = 35000; $p -le 39999; $p++) { $Sec4.Add($p) }

for ($i = 0; $i -lt 5000; $i++) {
    $PortList.Add($Sec1[$i])
    $PortList.Add($Sec2[$i])
    $PortList.Add($Sec3[$i])
    $PortList.Add($Sec4[$i])
}

$SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxThreads, $SessionState, $Host)
$RunspacePool.Open()

$SharedState = [hashtable]::Synchronized(@{ Found = $false; Port = 0 })

$ScriptBlock = {
    param($IP, $Port, $State)
    if ($State.Found) { return }

    $Socket = New-Object System.Net.Sockets.TcpClient
    try {
        $Connect = $Socket.BeginConnect($IP, $Port, $null, $null)
        $Wait = $Connect.AsyncWaitHandle.WaitOne(110, $false)

        if ($Wait -and $Socket.Connected -and !$State.Found) {
            $State.Found = $true
            $State.Port = $Port
        }
    }
    catch {} finally {
        $Socket.Close(); $Socket.Dispose()
    }
}

$Jobs = New-Object System.Collections.Generic.List[Object]
foreach ($Port in $PortList) {
    if ($SharedState.Found) { break }
    
    $Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($AndroidIP).AddArgument($Port).AddArgument($SharedState)
    $Powershell.RunspacePool = $RunspacePool
    $Handle = $Powershell.BeginInvoke()
    $Jobs.Add([PSCustomObject]@{ Pipe = $Powershell; Handle = $Handle })
}

while (!$SharedState.Found -and ($Jobs.Count -gt 0)) {
    Start-Sleep -Milliseconds 15
    if ($SharedState.Found) { break }
}

foreach ($Job in $Jobs) {
    try { $Job.Pipe.EndInvoke($Job.Handle) } catch {}
    $Job.Pipe.Dispose()
}
$RunspacePool.Close(); $RunspacePool.Dispose()
$StartTime.Stop()

if ($SharedState.Found) {
    $MatchedPort = $SharedState.Port
    Write-Host "Success: Found port $MatchedPort on $AndroidIP" -ForegroundColor Green
    adb connect "$($AndroidIP):$MatchedPort"

    Start-Sleep -Seconds 1
    
    adb -s "$($AndroidIP):$MatchedPort" shell sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.sh
}
else {
    Write-Host "Failed: Target port not discovered on $AndroidIP." -ForegroundColor Red
}
