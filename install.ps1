# Issue Tracker: https://github.com/ScoopInstaller/Install/issues
# Unlicense License:
#
# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <http://unlicense.org/>

<#
.SYNOPSIS
    Scoop installer.
.DESCRIPTION
    The installer of Scoop. For details please check the website and wiki.
.PARAMETER ScoopDir
    Specifies Scoop root path.
    If not specified, Scoop will be installed to '$env:USERPROFILE\scoop'.
.PARAMETER ScoopGlobalDir
    Specifies directory to store global apps.
    If not specified, global apps will be installed to '$env:ProgramData\scoop'.
.PARAMETER ScoopCacheDir
    Specifies cache directory.
    If not specified, caches will be downloaded to '$ScoopDir\cache'.
.PARAMETER NoProxy
    Bypass system proxy during the installation.
.PARAMETER Proxy
    Specifies proxy to use during the installation.
.PARAMETER ProxyCredential
    Specifies credential for the given proxy.
.PARAMETER ProxyUseDefaultCredentials
    Use the credentials of the current user for the proxy server that is specified by the -Proxy parameter.
.PARAMETER RunAsAdmin
    Force to run the installer as administrator.
.LINK
    https://scoop.sh
.LINK
    https://github.com/ScoopInstaller/Scoop/wiki
#>
param(
    [String] $ScoopDir,
    [String] $ScoopGlobalDir,
    [String] $ScoopCacheDir,
    [Switch] $NoProxy,
    [Uri] $Proxy,
    [System.Management.Automation.PSCredential] $ProxyCredential,
    [Switch] $ProxyUseDefaultCredentials,
    [Switch] $RunAsAdmin
)

# Disable StrictMode in this script
Set-StrictMode -Off

function Write-InstallInfo {
    param(
        [Parameter(Mandatory = $True, Position = 0)]
        [String] $String,
        [Parameter(Mandatory = $False, Position = 1)]
        [System.ConsoleColor] $ForegroundColor = $host.UI.RawUI.ForegroundColor
    )

    $backup = $host.UI.RawUI.ForegroundColor

    if ($ForegroundColor -ne $host.UI.RawUI.ForegroundColor) {
        $host.UI.RawUI.ForegroundColor = $ForegroundColor
    }

    Write-Output "$String"

    $host.UI.RawUI.ForegroundColor = $backup
}

function Deny-Install {
    param(
        [String] $message,
        [Int] $errorCode = 1
    )

    Write-InstallInfo -String $message -ForegroundColor DarkRed
    Write-InstallInfo 'Abort.'

    # Don't abort if invoked with iex that would close the PS session
    if ($IS_EXECUTED_FROM_IEX) {
        break
    } else {
        exit $errorCode
    }
}

function Test-LanguageMode {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-Output 'Scoop requires PowerShell FullLanguage mode to run, current PowerShell environment is restricted.'
        Write-Output 'Abort.'

        if ($IS_EXECUTED_FROM_IEX) {
            break
        } else {
            exit $errorCode
        }
    }
}

function Test-ValidateParameter {
    if ($null -eq $Proxy -and ($null -ne $ProxyCredential -or $ProxyUseDefaultCredentials)) {
        Deny-Install 'Provide a valid proxy URI for the -Proxy parameter when using the -ProxyCredential or -ProxyUseDefaultCredentials.'
    }

    if ($ProxyUseDefaultCredentials -and $null -ne $ProxyCredential) {
        Deny-Install "ProxyUseDefaultCredentials is conflict with ProxyCredential. Don't use the -ProxyCredential and -ProxyUseDefaultCredentials together."
    }
}

function Test-IsAdministrator {
    return ([Security.Principal.WindowsPrincipal]`
            [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Prerequisite {
    # Scoop requires PowerShell 5 at least
    if (($PSVersionTable.PSVersion.Major) -lt 5) {
        Deny-Install 'PowerShell 5 or later is required to run Scoop. Go to https://microsoft.com/powershell to get the latest version of PowerShell.'
    }

    # Scoop requires TLS 1.2 SecurityProtocol, which exists in .NET Framework 4.5+
    if ([System.Enum]::GetNames([System.Net.SecurityProtocolType]) -notcontains 'Tls12') {
        Deny-Install 'Scoop requires .NET Framework 4.5+ to work. Go to https://microsoft.com/net/download to get the latest version of .NET Framework.'
    }

    # Ensure Robocopy.exe is accessible
    if (!(Test-CommandAvailable('robocopy'))) {
        Deny-Install "Scoop requires 'C:\Windows\System32\Robocopy.exe' to work. Please make sure 'C:\Windows\System32' is in your PATH."
    }

    # Detect if RunAsAdministrator, there is no need to run as administrator when installing Scoop
    if (!$RunAsAdmin -and (Test-IsAdministrator)) {
        # Exception: Windows Sandbox, GitHub Actions CI
        $exception = ($env:USERNAME -eq 'WDAGUtilityAccount') -or ($env:GITHUB_ACTIONS -eq 'true' -and $env:CI -eq 'true')
        if (!$exception) {
            Deny-Install 'Running the installer as administrator is disabled by default, see https://github.com/ScoopInstaller/Install#for-admin for details.'
        }
    }

    # Show notification to change execution policy
    $allowedExecutionPolicy = @('Unrestricted', 'RemoteSigned', 'ByPass')
    if ((Get-ExecutionPolicy).ToString() -notin $allowedExecutionPolicy) {
        Deny-Install "PowerShell requires an execution policy in [$($allowedExecutionPolicy -join ', ')] to run Scoop. For example, to set the execution policy to 'RemoteSigned' please run 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'."
    }
    
    # Assuming $SCOOP_DIR is set to your local scoop path
    $localScoopExe = Join-Path $SCOOP_SHIMS_DIR 'scoop.ps1'

    if (Test-Path $localScoopExe) {
	Write-Output "Local Scoop installation found at $localScoopExe"
	# Allow install or update local scoop here
    } else {
	# No local scoop detected, but system-wide scoop might exist
	$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
	if ($scoopCmd) {
            Write-Output "System-wide Scoop detected at $($scoopCmd.Path), ignoring for local install"
            # Do NOT deny install, since local scoop isn't present
	} else {
            Write-Output "No Scoop detected at all"
            # Proceed with install
	}
    }

}

function Optimize-SecurityProtocol {
    # .NET Framework 4.7+ has a default security protocol called 'SystemDefault',
    # which allows the operating system to choose the best protocol to use.
    # If SecurityProtocolType contains 'SystemDefault' (means .NET4.7+ detected)
    # and the value of SecurityProtocol is 'SystemDefault', just do nothing on SecurityProtocol,
    # 'SystemDefault' will use TLS 1.2 if the webrequest requires.
    $isNewerNetFramework = ([System.Enum]::GetNames([System.Net.SecurityProtocolType]) -contains 'SystemDefault')
    $isSystemDefault = ([System.Net.ServicePointManager]::SecurityProtocol.Equals([System.Net.SecurityProtocolType]::SystemDefault))

    # If not, change it to support TLS 1.2
    if (!($isNewerNetFramework -and $isSystemDefault)) {
        # Set to TLS 1.2 (3072), then TLS 1.1 (768), and TLS 1.0 (192). Ssl3 has been superseded,
        # https://docs.microsoft.com/en-us/dotnet/api/system.net.securityprotocoltype?view=netframework-4.5
        [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
        Write-Verbose 'SecurityProtocol has been updated to support TLS 1.2'
    }
}

function Get-Downloader {
    $downloadSession = New-Object System.Net.WebClient

    # Set proxy to null if NoProxy is specificed
    if ($NoProxy) {
        $downloadSession.Proxy = $null
    } elseif ($Proxy) {
        # Prepend protocol if not provided
        if (!$Proxy.IsAbsoluteUri) {
            $Proxy = New-Object System.Uri('http://' + $Proxy.OriginalString)
        }

        $Proxy = New-Object System.Net.WebProxy($Proxy)

        if ($null -ne $ProxyCredential) {
            $Proxy.Credentials = $ProxyCredential.GetNetworkCredential()
        } elseif ($ProxyUseDefaultCredentials) {
            $Proxy.UseDefaultCredentials = $true
        }

        $downloadSession.Proxy = $Proxy
    }

    return $downloadSession
}

function Test-isFileLocked {
    param(
        [String] $path
    )

    $file = New-Object System.IO.FileInfo $path

    if (!(Test-Path $path)) {
        return $false
    }

    try {
        $stream = $file.Open(
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        if ($stream) {
            $stream.Close()
        }
        return $false
    } catch {
        # The file is locked by a process.
        return $true
    }
}

function Expand-ZipArchive {
    param(
        [String] $path,
        [String] $to
    )

    if (!(Test-Path $path)) {
        Deny-Install "Unzip failed: can't find $path to unzip."
    }

    # Check if the zip file is locked, by antivirus software for example
    $retries = 0
    while ($retries -le 10) {
        if ($retries -eq 10) {
            Deny-Install "Unzip failed: can't unzip because a process is locking the file."
        }
        if (Test-isFileLocked $path) {
            Write-InstallInfo "Waiting for $path to be unlocked by another process... ($retries/10)"
            $retries++
            Start-Sleep -Seconds 2
        } else {
            break
        }
    }

    # Workaround to suspend Expand-Archive verbose output,
    # upstream issue: https://github.com/PowerShell/Microsoft.PowerShell.Archive/issues/98
    $oldVerbosePreference = $VerbosePreference
    $global:VerbosePreference = 'SilentlyContinue'

    # Disable progress bar to gain performance
    $oldProgressPreference = $ProgressPreference
    $global:ProgressPreference = 'SilentlyContinue'

    # PowerShell 5+: use Expand-Archive to extract zip files
    Microsoft.PowerShell.Archive\Expand-Archive -Path $path -DestinationPath $to -Force
    $global:VerbosePreference = $oldVerbosePreference
    $global:ProgressPreference = $oldProgressPreference
}

function Out-UTF8File {
    param(
        [Parameter(Mandatory = $True, Position = 0)]
        [Alias('Path')]
        [String] $FilePath,
        [Switch] $Append,
        [Switch] $NoNewLine,
        [Parameter(ValueFromPipeline = $True)]
        [PSObject] $InputObject
    )
    process {
        if ($Append) {
            [System.IO.File]::AppendAllText($FilePath, $InputObject)
        } else {
            if (!$NoNewLine) {
                # Ref: https://stackoverflow.com/questions/5596982
                # Performance Note: `WriteAllLines` throttles memory usage while
                # `WriteAllText` needs to keep the complete string in memory.
                [System.IO.File]::WriteAllLines($FilePath, $InputObject)
            } else {
                # However `WriteAllText` does not add ending newline.
                [System.IO.File]::WriteAllText($FilePath, $InputObject)
            }
        }
    }
}

function Import-ScoopShim {
    Write-InstallInfo 'Creating shim...'
    # The scoop executable
    $path = "$SCOOP_APP_DIR\bin\scoop.ps1"

    if (!(Test-Path $SCOOP_SHIMS_DIR)) {
        New-Item -Type Directory $SCOOP_SHIMS_DIR | Out-Null
    }

    # The scoop shim
    $shim = "$SCOOP_SHIMS_DIR\scoop"

    # Convert to relative path
    Push-Location $SCOOP_SHIMS_DIR
    $relativePath = Resolve-Path -Relative $path
    Pop-Location
    $absolutePath = Resolve-Path $path

    # if $path points to another drive resolve-path prepends .\ which could break shims
    $ps1text = if ($relativePath -match '^(\.\\)?\w:.*$') {
        @(
            "# $absolutePath",
            "`$path = `"$path`"",
            "if (`$MyInvocation.ExpectingInput) { `$input | & `$path $arg @args } else { & `$path $arg @args }",
            "exit `$LASTEXITCODE"
        )
    } else {
        @(
            "# $absolutePath",
            "`$path = Join-Path `$PSScriptRoot `"$relativePath`"",
            "if (`$MyInvocation.ExpectingInput) { `$input | & `$path $arg @args } else { & `$path $arg @args }",
            "exit `$LASTEXITCODE"
        )
    }
    $ps1text -join "`r`n" | Out-UTF8File "$shim.ps1"

    # make ps1 accessible from cmd.exe
    @(
        "@rem $absolutePath",
        '@echo off',
        'setlocal enabledelayedexpansion',
        'set args=%*',
        ':: replace problem characters in arguments',
        "set args=%args:`"='%",
        "set args=%args:(=``(%",
        "set args=%args:)=``)%",
        "set invalid=`"='",
        'if !args! == !invalid! ( set args= )',
        'where /q pwsh.exe',
        'if %errorlevel% equ 0 (',
        "    pwsh -noprofile -ex unrestricted -file `"$absolutePath`" $arg %args%",
        ') else (',
        "    powershell -noprofile -ex unrestricted -file `"$absolutePath`" $arg %args%",
        ')'
    ) -join "`r`n" | Out-UTF8File "$shim.cmd"

    @(
        '#!/bin/sh',
        "# $absolutePath",
        'if command -v pwsh.exe > /dev/null 2>&1; then',
        "    pwsh.exe -noprofile -ex unrestricted -file `"$absolutePath`" $arg `"$@`"",
        'else',
        "    powershell.exe -noprofile -ex unrestricted -file `"$absolutePath`" $arg `"$@`"",
        'fi'
    ) -join "`n" | Out-UTF8File $shim -NoNewLine
}

function Get-Env {
    param(
        [String] $name,
        [Switch] $global
    )

    $RegisterKey = if ($global) {
        Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    } else {
        Get-Item -Path 'HKCU:'
    }

    $EnvRegisterKey = $RegisterKey.OpenSubKey('Environment')
    $RegistryValueOption = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    $EnvRegisterKey.GetValue($name, $null, $RegistryValueOption)
}

function Publish-Env {
    if (-not ('Win32.NativeMethods' -as [Type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }

    $HWND_BROADCAST = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero

    [Win32.Nativemethods]::SendMessageTimeout($HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [UIntPtr]::Zero,
        'Environment',
        2,
        5000,
        [ref] $result
    ) | Out-Null
}

function Write-Env {
    param(
        [String] $name,
        [String] $val,
        [Switch] $global
    )

    $RegisterKey = if ($global) {
        Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    } else {
        Get-Item -Path 'HKCU:'
    }

    $EnvRegisterKey = $RegisterKey.OpenSubKey('Environment', $true)
    if ($val -eq $null) {
        $EnvRegisterKey.DeleteValue($name)
    } else {
        $RegistryValueKind = if ($val.Contains('%')) {
            [Microsoft.Win32.RegistryValueKind]::ExpandString
        } elseif ($EnvRegisterKey.GetValue($name)) {
            $EnvRegisterKey.GetValueKind($name)
        } else {
            [Microsoft.Win32.RegistryValueKind]::String
        }
        $EnvRegisterKey.SetValue($name, $val, $RegistryValueKind)
    }
    Publish-Env
}

function Add-ShimsDirToPath {
    # Get $env:PATH of current user
    $userEnvPath = Get-Env 'PATH'

    if ($userEnvPath -notmatch [Regex]::Escape($SCOOP_SHIMS_DIR)) {
        $h = (Get-PSProvider 'FileSystem').Home
        if (!$h.EndsWith('\')) {
            $h += '\'
        }

        if (!($h -eq '\')) {
            $friendlyPath = "$SCOOP_SHIMS_DIR" -Replace ([Regex]::Escape($h)), '~\'
            Write-InstallInfo "Adding $friendlyPath to your path."
        } else {
            Write-InstallInfo "Adding $SCOOP_SHIMS_DIR to your path."
        }

        # For future sessions
        Write-Env 'PATH' "$SCOOP_SHIMS_DIR;$userEnvPath"
        # For current session
        $env:PATH = "$SCOOP_SHIMS_DIR;$env:PATH"
    }
}

function Use-Config {
    if (!(Test-Path $SCOOP_CONFIG_FILE)) {
        return $null
    }

    try {
        return (Get-Content $SCOOP_CONFIG_FILE -Raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Deny-Install "ERROR loading $SCOOP_CONFIG_FILE`: $($_.Exception.Message)"
    }
}

function Add-Config {
    param (
        [Parameter(Mandatory = $True, Position = 0)]
        [String] $Name,
        [Parameter(Mandatory = $True, Position = 1)]
        [String] $Value
    )

    $scoopConfig = Use-Config

    if ($scoopConfig -is [System.Management.Automation.PSObject]) {
        if ($Value -eq [bool]::TrueString -or $Value -eq [bool]::FalseString) {
            $Value = [System.Convert]::ToBoolean($Value)
        }
        if ($null -eq $scoopConfig.$Name) {
            $scoopConfig | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
        } else {
            $scoopConfig.$Name = $Value
        }
    } else {
        $baseDir = Split-Path -Path $SCOOP_CONFIG_FILE
        if (!(Test-Path $baseDir)) {
            New-Item -Type Directory $baseDir | Out-Null
        }

        $scoopConfig = New-Object PSObject
        $scoopConfig | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }

    if ($null -eq $Value) {
        $scoopConfig.PSObject.Properties.Remove($Name)
    }

    ConvertTo-Json $scoopConfig | Set-Content $SCOOP_CONFIG_FILE -Encoding ASCII
    return $scoopConfig
}

function Add-DefaultConfig {
    # Always write to local scoop config — no env or userprofile checks

    # Set root path explicitly
    if ($SCOOP_DIR) {
        Write-Verbose "Setting config root_path: $SCOOP_DIR"
        Add-Config -Name 'root_path' -Value $SCOOP_DIR | Out-Null
    }

    # Set global path explicitly
    if ($SCOOP_GLOBAL_DIR) {
        Write-Verbose "Setting config global_path: $SCOOP_GLOBAL_DIR"
        Add-Config -Name 'global_path' -Value $SCOOP_GLOBAL_DIR | Out-Null
    }

    # Set cache path explicitly
    if ($SCOOP_CACHE_DIR) {
        Write-Verbose "Setting config cache_path: $SCOOP_CACHE_DIR"
        Add-Config -Name 'cache_path' -Value $SCOOP_CACHE_DIR | Out-Null
    }

    # save current datatime to last_update
    Add-Config -Name 'last_update' -Value ([System.DateTime]::Now.ToString('o')) | Out-Null
}

function Test-CommandAvailable {
    param (
        [Parameter(Mandatory = $True, Position = 0)]
        [String] $Command
    )
    return [Boolean](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Install-Scoop {
    Write-InstallInfo 'Initializing...'
    # Validate install parameters
    Test-ValidateParameter
    # Check prerequisites
    Test-Prerequisite
    # Enable TLS 1.2
    Optimize-SecurityProtocol

    # Download scoop from GitHub
    Write-InstallInfo 'Downloading...'
    $downloader = Get-Downloader
    [bool]$downloadZipsRequired = $True

    if (Test-CommandAvailable('git')) {
        $old_https = $env:HTTPS_PROXY
        $old_http = $env:HTTP_PROXY
        try {
            if ($downloader.Proxy) {
                #define env vars for git when behind a proxy
                $Env:HTTP_PROXY = $downloader.Proxy.Address
                $Env:HTTPS_PROXY = $downloader.Proxy.Address
            }
            Write-Verbose "Cloning $SCOOP_PACKAGE_GIT_REPO to $SCOOP_APP_DIR"
            git clone -q $SCOOP_PACKAGE_GIT_REPO $SCOOP_APP_DIR
            if (-Not $?) {
                throw 'Cloning failed. Falling back to downloading zip files.'
            }
            Write-Verbose "Cloning $SCOOP_MAIN_BUCKET_GIT_REPO to $SCOOP_MAIN_BUCKET_DIR"
            git clone -q $SCOOP_MAIN_BUCKET_GIT_REPO $SCOOP_MAIN_BUCKET_DIR
            if (-Not $?) {
                throw 'Cloning failed. Falling back to downloading zip files.'
            }
            $downloadZipsRequired = $False
        } catch {
            Write-Warning "$($_.Exception.Message)"
            $Global:LastExitCode = 0
        } finally {
            $env:HTTPS_PROXY = $old_https
            $env:HTTP_PROXY = $old_http
        }
    }

    if ($downloadZipsRequired) {
        # 1. download scoop
        $scoopZipfile = "$SCOOP_APP_DIR\scoop.zip"
        if (!(Test-Path $SCOOP_APP_DIR)) {
            New-Item -Type Directory $SCOOP_APP_DIR | Out-Null
        }
        Write-Verbose "Downloading $SCOOP_PACKAGE_REPO to $scoopZipfile"
        $downloader.downloadFile($SCOOP_PACKAGE_REPO, $scoopZipfile)
        # 2. download scoop main bucket
        $scoopMainZipfile = "$SCOOP_MAIN_BUCKET_DIR\scoop-main.zip"
        if (!(Test-Path $SCOOP_MAIN_BUCKET_DIR)) {
            New-Item -Type Directory $SCOOP_MAIN_BUCKET_DIR | Out-Null
        }
        Write-Verbose "Downloading $SCOOP_MAIN_BUCKET_REPO to $scoopMainZipfile"
        $downloader.downloadFile($SCOOP_MAIN_BUCKET_REPO, $scoopMainZipfile)

        # Extract files from downloaded zip
        Write-InstallInfo 'Extracting...'
        # 1. extract scoop
        $scoopUnzipTempDir = "$SCOOP_APP_DIR\_tmp"
        Write-Verbose "Extracting $scoopZipfile to $scoopUnzipTempDir"
        Expand-ZipArchive $scoopZipfile $scoopUnzipTempDir
        Copy-Item "$scoopUnzipTempDir\scoop-*\*" $SCOOP_APP_DIR -Recurse -Force
        # 2. extract scoop main bucket
        $scoopMainUnzipTempDir = "$SCOOP_MAIN_BUCKET_DIR\_tmp"
        Write-Verbose "Extracting $scoopMainZipfile to $scoopMainUnzipTempDir"
        Expand-ZipArchive $scoopMainZipfile $scoopMainUnzipTempDir
        Copy-Item "$scoopMainUnzipTempDir\Main-*\*" $SCOOP_MAIN_BUCKET_DIR -Recurse -Force

        # Cleanup
        Remove-Item $scoopUnzipTempDir -Recurse -Force
        Remove-Item $scoopZipfile
        Remove-Item $scoopMainUnzipTempDir -Recurse -Force
        Remove-Item $scoopMainZipfile
    }
    # Create the scoop shim
    Import-ScoopShim
    # Finially ensure scoop shims is in the PATH
    Add-ShimsDirToPath
    # Setup initial configuration of Scoop
    Add-DefaultConfig

    Write-InstallInfo 'Scoop was installed successfully!' -ForegroundColor DarkGreen
    Write-InstallInfo "Type 'scoop help' for instructions."
}

function Ensure-NTFS($path) {
    if (-not (Test-Path $path)) {
        Write-Host "`n[!] ERROR: Path '$path' does not exist." -ForegroundColor Red
        exit 1
    }

    $drive = (Get-Item -Path $path).PSDrive.Root.TrimEnd('\')
    $fsinfo = & fsutil fsinfo volumeinfo $drive 2>$null

    $fs = $null
    if ($fsinfo) {
        foreach ($line in $fsinfo) {
            if ($line -match 'File System Name\s+:\s+(\S+)') {
                $fs = $matches[1]
                break
            }
        }
    }

    if ($fs -ne 'NTFS') {
        Write-Host "`n[!] Scoop must be installed on an NTFS drive." -ForegroundColor Red
        Write-Host "    Detected file system on drive '$drive': $fs. `n" -ForegroundColor Yellow
        Write-Host "    Please choose an NTFS-formatted drive and try again.`n" -ForegroundColor Yellow
        exit 1
    }
}


function Write-DebugInfo {
    param($BoundArgs)

    Write-Verbose '-------- PSBoundParameters --------'
    $BoundArgs.GetEnumerator() | ForEach-Object { Write-Verbose $_ }
    Write-Verbose '-------- Environment Variables --------'
    Write-Verbose "`$env:USERPROFILE: $env:USERPROFILE"
    Write-Verbose "`$env:ProgramData: $env:ProgramData"
    Write-Verbose "`$env:SCOOP: $env:SCOOP"
    Write-Verbose "`$env:SCOOP_CACHE: $SCOOP_CACHE"
    Write-Verbose "`$env:SCOOP_GLOBAL: $env:SCOOP_GLOBAL"
    Write-Verbose '-------- Selected Variables --------'
    Write-Verbose "SCOOP_DIR: $SCOOP_DIR"
    Write-Verbose "SCOOP_CACHE_DIR: $SCOOP_CACHE_DIR"
    Write-Verbose "SCOOP_GLOBAL_DIR: $SCOOP_GLOBAL_DIR"
    Write-Verbose "SCOOP_CONFIG_HOME: $SCOOP_CONFIG_HOME"
}

# Prepare variables
$IS_EXECUTED_FROM_IEX = ($null -eq $MyInvocation.MyCommand.Path)

# Abort when the language mode is restricted
Test-LanguageMode

# Determine script directory
$scriptDir = if ($IS_EXECUTED_FROM_IEX) {
    Get-Location
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Define all Scoop-related directories relative to script directory
# Scoop root directory
$SCOOP_DIR = Join-Path $scriptDir 'scoop'
# Scoop global apps directory
$SCOOP_GLOBAL_DIR = Join-Path $scriptDir 'scoop-global'
# Scoop cache directory
$SCOOP_CACHE_DIR = Join-Path $SCOOP_DIR '.cache'
# Scoop shims directory
$SCOOP_SHIMS_DIR = Join-Path $SCOOP_DIR 'shims'
# Scoop itself directory
$SCOOP_APP_DIR = Join-Path $SCOOP_DIR 'apps\scoop\current'
# Scoop main bucket directory
$SCOOP_MAIN_BUCKET_DIR = Join-Path $SCOOP_DIR 'buckets\main'
# Scoop config file location
$SCOOP_CONFIG_HOME = Join-Path $SCOOP_DIR 'config'
$SCOOP_CONFIG_FILE = Join-Path $SCOOP_CONFIG_HOME 'config.json'

# TODO: Use a specific version of Scoop and the main bucket
$SCOOP_PACKAGE_REPO = 'https://github.com/nitincodery/Scoop-Portable/archive/master.zip'
$SCOOP_MAIN_BUCKET_REPO = 'https://github.com/ScoopInstaller/Main/archive/master.zip'

$SCOOP_PACKAGE_GIT_REPO = 'https://github.com/nitincodery/Scoop-Portable.git'
$SCOOP_MAIN_BUCKET_GIT_REPO = 'https://github.com/ScoopInstaller/Main.git'

# Write scoob.cmd file to initialize local scoop via cmd
$scoobCmd = @'
@echo off
REM Get the directory of this script
set SCRIPT_DIR=%~dp0

REM Set SCOOP environment variable to local scoop folder inside script directory
set "SCOOP=%SCRIPT_DIR%\scoop"
set "SCOOP_GLOBAL=%SCRIPT_DIR%\scoop-global"

REM Update PATH to use local scoop shims ONLY (prepend so it takes priority)
set "PATH=%SCOOP%\shims;%PATH%"
echo Local Scoop Enabled.

scoop config
'@

Set-Content -Path (Join-Path $scriptDir 'scoob.cmd') -Value $scoobCmd -Encoding ASCII

# Write scoob.ps1 file to initialize local scoop via powershell
$scoobPs1 = @"
# Get the directory of this script
`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path

# Set SCOOP environment variables to local scoop folders inside the script directory
`$env:SCOOP = Join-Path `$ScriptDir 'scoop'
`$env:SCOOP_GLOBAL = Join-Path `$ScriptDir 'scoop-global'

# Prepend local scoop shims to PATH so it takes priority
`$env:PATH = "`$(`$env:SCOOP)\shims;`$env:PATH"

Write-Output "Local Scoop Enabled."

# Show current scoop config
scoop config
"@

Set-Content -Path (Join-Path $scriptDir 'scoob.ps1') -Value $scoobPs1 -Encoding UTF8

# Ensure first drive is NTFS or not
Ensure-NTFS $scriptDir

# Define default config to avoid any problems with system scoop
$CONFIG = @{
    root_path     = $SCOOP_DIR
    global_path   = $SCOOP_GLOBAL_DIR
    cache_path    = $SCOOP_CACHE_DIR
    scoop_repo    = 'https://github.com/nitincodery/Scoop-Portable'
    scoop_branch  = 'master'
}

# Ensure config directory exists
New-Item -ItemType Directory -Path $SCOOP_CONFIG_HOME -Force | Out-Null

# Write config file
$CONFIG | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 -Path $SCOOP_CONFIG_FILE

# Quit if anything goes wrong
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'

# Logging debug info
Write-DebugInfo $PSBoundParameters
# Bootstrap function
Install-Scoop

# Reset $ErrorActionPreference to original value
$ErrorActionPreference = $oldErrorActionPreference
