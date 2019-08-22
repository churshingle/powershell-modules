$Registry = "https://registry.npm.taobao.org"
$CheckVersion = {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Registry, 
        [Parameter(Mandatory = $true, Position = 1)][System.Object]$Dependency
    )
    $Name = $Dependency.name
    $Version = $Dependency.Value -Replace "^\^"
    $oldVersion = $Version.Split('.')
    $uri = "$Registry/$Name/latest"
    $response = Invoke-WebRequest -Method GET -Uri $uri
    if (!$response.StatusCode -eq 200) {
        return;
    }
    $body = $response.Content | ConvertFrom-Json
    $latestVersionStr = $body.version
    $latestVersion = $latestVersionStr.split('.')
    $hasNewVersion = {
        Param(
            [Parameter(Mandatory = $true, Position = 0)][string[]]$oldVersion, 
            [Parameter(Mandatory = $true, Position = 1)][string[]]$latestVersion
        )
        $minLength = [math]::Min($oldVersion.Length, $latestVersion.Length)
        for ($i = 0; $i -lt $minLength; $i++) {
            if ($oldVersion[$i] -eq $latestVersion[$i]) {
                continue;
            }
            $old = [convert]::ToInt32($oldVersion[$i], 10)
            $new = [convert]::ToInt32($latestVersion[$i], 10)
            if ($old -lt $new) {
                return $true
            }
        }
        return $false
    }
    if (Invoke-Command -scriptBlock $hasNewVersion -ArgumentList $oldVersion, $latestVersion) {
        $Dependency.Value = "^$latestVersionStr"
        return New-Object psobject -Property @{
            Name      = $Name
            Latest    = $latestVersionStr
            Current   = $Version
            Updatable = $true
        }
    }
    return New-Object psobject -Property @{
        Name      = $Name
        Latest    = $latestVersionStr
        Current   = $Version
        Updatable = $false
    }
}
function Script:Check-NodeVersions ([Parameter(Mandatory = $false, Position = 0)][System.Object]$node) {
    if ($null -eq $node) {
        return @();
    }
    $dependencies = $node.psobject.Properties
    $threads = @()
    $jobs = $dependencies | ForEach-Object {
        $thread = [PowerShell]::Create().Addscript($CheckVersion).AddArgument($Registry).AddArgument($_)
        $threads += $thread
        return $thread.BeginInvoke()
    }
    $Updatables = @()
    for ($i = 0; $i -lt $jobs.Count; $i++) {
        if ($jobs[$i].AsyncWaitHandle.WaitOne()) {
            $thread = $threads[$i]
            $result = $thread.EndInvoke($jobs[$i])
            if ($result.Updatable -eq $true) {
                $Updatables += $result
            }
            $thread.Runspace.Dispose()
            $thread.Dispose()
        }
    }
    return $Updatables
}
function Script:obtainJson {
    param (
        [string] $dir = "."
    )
    return (Get-Content "$dir/package.json") | ConvertFrom-Json
}
function Script:Check-For-Update {
    param (
        [string] $dir = "."
    )
    $package = obtainJson $dir
    $runtime = Check-NodeVersions $package.dependencies
    $dev = Check-NodeVersions $package.devDependencies
    if ($runtime.Length -gt 0) {
        Write-Host "dependencies 可更新项:" -ForegroundColor Green
        Format-Table -InputObject $runtime -AutoSize -Property Name, Current, Latest
    }
    if ($dev.Length -gt 0) {
        Write-Host "devDependencies 可更新项:" -ForegroundColor Green
        Format-Table -InputObject $dev -AutoSize -Property Name, Current, Latest
    }
    $total = $runtime.Length + $dev.Length
    if ($total -gt 0) {
        Write-Host "总共有$($total)个可更新项" -ForegroundColor Green
    }
    else {
        Write-Host "没有可用的更新项" -ForegroundColor Green
    }
}
function Script:Upgrade {
    param (
        [string] $dir = "."
    )
    Write-Host $dir
    Write-Host ($dir -eq $null)
    $package = obtainJson $dir
    $runtime = Check-NodeVersions $package.dependencies
    $dev = Check-NodeVersions $package.devDependencies
    $total = $runtime.Length + $dev.Length
    $json = ConvertTo-Json -InputObject $package
    Out-File -InputObject $json -FilePath ./package.json
    $package = obtainJson
    $runtime = Check-NodeVersions $package.dependencies
    $dev = Check-NodeVersions $package.devDependencies
    $updatableTotal = $runtime.Length + $dev.Length
    Write-Host "更新完成,总共更新了 $($total-$updatableTotal) 项" -ForegroundColor Green
    if ($updatableTotal -gt 0) {
        Write-Host "还有 $($updatableTotal) 个可更新项, 具体可通过check命令查看" -ForegroundColor Green
    }
}
function Script:Clean {
    param (
        [string] $dir = "."
    )
    $modules = "$dir/node_modules"
    $yarnLock = "$dir/yarn.lock"
    $npmLock = "$dir/package.lock"
    if (Test-Path $modules) {
        Write-Host "删除$modules..."
        Remove-Item $modules -Recurse -Force
    }
    if (Test-Path $yarnLock) {
        Remove-Item $yarnLock -Force
    }
    if (Test-Path $npmLock) {
        Remove-Item $npmLock -Force
    }
}
function Script:Refresh {
    param (
        [string] $dir = "."
    )
    Clean $dir
    Write-Host "安装依赖..."
    Check-Yarn $dir
    yarn --registry=$Registry
}
function Script:Clean-And-Boot {
    param (
        [string] $dir = "."
    )
    Refresh $dir
    Write-Host "启动项目..."
    Check-Yarn $dir
    Set-Location $dir
    yarn start
}
function Script:Check-Yarn {
    param (
        [string] $dir = "."
    )
    try {
        Get-Command yarn | Out-Null
    }
    catch {
        Set-Location $dir
        npm install yarn --registry=$Registry
    }
}
function Node-Package {
    param (
        [parameter (mandatory = $true, Position = 0)]
        [ValidateSet("update", "upgrade", "clean", "refresh", "cleanBoot")]
        [string] $command,

        [parameter (mandatory = $false, Position = 1)]
        [string] $dir = (Get-Location).Path
    )
    switch ($command) {
        "update" {
            return Check-For-Update $dir
        }
        "upgrade" {
            return Upgrade $dir
        }
        "clean" {
            return Clean $dir
        }
        "refresh" {
            return Refresh $dir
        }
        "cleanBoot" {
            return Clean-And-Boot $dir
        }
    }
}