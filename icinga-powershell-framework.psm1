<#
.Synopsis
   Icinga PowerShell Module - Powerful PowerShell Framework for monitoring Windows Systems
.DESCRIPTION
   More Information on https://github.com/Icinga/icinga-powershell-framework
.EXAMPLE
   Install-Icinga
 .NOTES
#>

function Use-Icinga()
{
    param (
        [switch]$LibOnly   = $FALSE,
        [switch]$Daemon    = $FALSE,
        [switch]$DebugMode = $FALSE,
        [switch]$Minimal   = $FALSE
    );

    if ($null -ne $Global:Icinga -And $Global:Icinga.ContainsKey('RebuildCache') -And $Global:Icinga.RebuildCache) {
        # On some systems, this call will re-build the cache
        Import-Module (Join-Path -Path (Get-IcingaForWindowsRootPath) -ChildPath 'icinga-powershell-framework') -Global -Force;
        # The second run would then actually import the new module. Only happens on some systems, but with this we fix
        # possible exceptions
        Import-Module (Join-Path -Path (Get-IcingaForWindowsRootPath) -ChildPath 'icinga-powershell-framework') -Global -Force;
    }

    # Only apply migrations if we directly call "Use-Icinga" without any other argument
    if ($LibOnly -eq $FALSE -And $Daemon -eq $FALSE -and $Minimal -eq $FALSE) {
        Invoke-IcingaForWindowsMigration;
    }

    Disable-IcingaProgressPreference;

    if ($Minimal) {
        if ($null -eq $global:Icinga) {
            $global:Icinga = @{ };
        }

        if ($global:Icinga.ContainsKey('Minimal') -eq $FALSE) {
            $global:Icinga.Add('Minimal', $TRUE);
        }
    }

    # Ensure we autoload the Icinga Plugin collection, provided by the external
    # module 'icinga-powershell-plugins'
    if (Get-Command 'Use-IcingaPlugins' -ErrorAction SilentlyContinue) {
        Use-IcingaPlugins;
    }

    if ($LibOnly -eq $FALSE) {
        $global:IcingaThreads       = [hashtable]::Synchronized(@{ });
        $global:IcingaThreadContent = [hashtable]::Synchronized(@{ });
        $global:IcingaThreadPool    = [hashtable]::Synchronized(@{ });
        $global:IcingaTimers        = [hashtable]::Synchronized(@{ });
        $global:IcingaDaemonData    = [hashtable]::Synchronized(
            @{
                'IcingaThreads'            = $global:IcingaThreads;
                'IcingaThreadContent'      = $global:IcingaThreadContent;
                'IcingaThreadPool'         = $global:IcingaThreadPool;
                'IcingaTimers'             = $global:IcingaTimers;
                'FrameworkRunningAsDaemon' = $Daemon;
                'JEAContext'               = $FALSE;
                'DebugMode'                = $DebugMode;
            }
        );
    } else {
        # This will fix the debug mode in case we are only using Libs
        # without any other variable content and daemon handling
        if ($null -eq $global:IcingaDaemonData) {
            $global:IcingaDaemonData = [hashtable]::Synchronized(@{ });
        }
        if ($global:IcingaDaemonData.ContainsKey('DebugMode') -eq $FALSE) {
            $global:IcingaDaemonData.DebugMode = $DebugMode;
        }
        if ($global:IcingaDaemonData.ContainsKey('JEAContext') -eq $FALSE) {
            $global:IcingaDaemonData.JEAContext = $FALSE;
        }
        if ($global:IcingaDaemonData.ContainsKey('FrameworkRunningAsDaemon') -eq $FALSE) {
            $global:IcingaDaemonData.FrameworkRunningAsDaemon = $Daemon;
        }
    }
    New-IcingaPerformanceCounterCache;

    # Enable DebugMode in case it is enabled in our config
    if (Get-IcingaFrameworkDebugMode) {
        Enable-IcingaFrameworkDebugMode;
        $DebugMode = $TRUE;
    }

    $EventLogMessages = Invoke-IcingaNamespaceCmdlets -Command 'Register-IcingaEventLogMessages*';
    foreach ($entry in $EventLogMessages.Values) {
        foreach ($event in $entry.Keys) {
            if ($LibOnly -eq $FALSE) {
                Register-IcingaEventLog -LogName $event;
            }
            Add-IcingaHashtableItem -Hashtable $global:IcingaEventLogEnums `
                -Key $event `
                -Value $entry[$event] | Out-Null;
        }
    }

    if ($LibOnly -eq $FALSE) {
        Register-IcingaEventLog;
    }
}

function Get-IcingaFrameworkCodeCacheFile()
{
    return (Join-Path -Path (Get-IcingaCacheDir) -ChildPath 'framework_cache.psm1');
}

function Import-IcingaLib()
{
    # Do nothing, just leave it here as compatibility layer until we
    # cleaned every other repository
}

function Write-IcingaFrameworkCodeCache()
{
    [string]$CacheFile    = Get-IcingaFrameworkCodeCacheFile;
    [string]$directory    = Join-Path -Path $PSScriptRoot -ChildPath 'lib\';
    [string]$CacheContent = '';

    # Load modules from directory
    Get-ChildItem -Path $directory -Recurse -Filter '*.psm1' |
        ForEach-Object {
            $CacheContent += (Get-Content -Path $_.FullName -Raw);
            $CacheContent += "`r`n";
        }

    $CacheContent += "Export-ModuleMember -Function @( '*' ) -Alias @( '*' ) -Variable @( '*' )";
    Set-Content -Path $CacheFile -Value $CacheContent;

    Remove-IcingaFrameworkDependencyFile;
}

function Publish-IcingaEventLogDocumentation()
{
    param(
        [string]$Namespace,
        [string]$OutFile
    );

    [string]$DocContent = [string]::Format(
        '# {0} EventLog Documentation',
        $Namespace
    );
    $DocContent += New-IcingaNewLine;
    $DocContent += New-IcingaNewLine;
    $DocContent += "Below you will find a list of EventId's which are exported by this module. The short and detailed message are both written directly into the EventLog. This documentation shall simply provide a summary of available EventId's";

    $SortedArray = $IcingaEventLogEnums[$Namespace].Keys.GetEnumerator() | Sort-Object;

    foreach ($entry in $SortedArray) {
        $entry = $IcingaEventLogEnums[$Namespace][$entry];

        $DocContent = [string]::Format(
            '{0}{2}{2}## Event Id {1}{2}{2}| Category | Short Message | Detailed Message |{2}| --- | --- | --- |{2}| {3} | {4} | {5} |',
            $DocContent,
            $entry.EventId,
            (New-IcingaNewLine),
            $entry.EntryType,
            $entry.Message,
            $entry.Details
        );
    }

    if ([string]::IsNullOrEmpty($OutFile)) {
        Write-Output $DocContent;
    } else {
        Write-IcingaFileSecure -File $OutFile -Value $DocContent;
    }
}

function Get-IcingaPluginDir()
{
    return (Join-Path -Path $PSScriptRoot -ChildPath 'lib\plugins\');
}

function Get-IcingaCustomPluginDir()
{
    return (Join-Path -Path $PSScriptRoot -ChildPath 'custom\plugins\');
}

function Get-IcingaCacheDir()
{
    return (Join-Path -Path $PSScriptRoot -ChildPath 'cache');
}

function Get-IcingaPowerShellConfigDir()
{
    return (Join-Path -Path $PSScriptRoot -ChildPath 'config');
}

function Get-IcingaFrameworkRootPath()
{
    [string]$Path = $PSScriptRoot;

    return $PSScriptRoot;
}

function Get-IcingaForWindowsRootPath()
{
    [string]$Path = $PSScriptRoot;
    [int]$Index   = $Path.LastIndexOf('icinga-powershell-framework');
    $Path         = $Path.Substring(0, $Index);

    return $Path;
}

function Get-IcingaPowerShellModuleFile()
{
    return (Join-Path -Path $PSScriptRoot -ChildPath 'icinga-powershell-framework.psd1');
}

function Invoke-IcingaCommand()
{
    [CmdletBinding()]
    param (
        $ScriptBlock,
        [switch]$SkipHeader   = $FALSE,
        [switch]$Manage       = $FALSE,
        [switch]$RebuildCache = $FALSE,
        [array]$ArgumentList  = @()
    );

    Import-LocalizedData `
        -BaseDirectory (Get-IcingaFrameworkRootPath) `
        -FileName 'icinga-powershell-framework.psd1' `
        -BindingVariable IcingaFrameworkData;

    # Print a header informing our user that loaded the Icinga Framework with a specific
    # version. We can also skip the header by using $SKipHeader
    if ([string]::IsNullOrEmpty($ScriptBlock) -And $SkipHeader -eq $FALSE -And $Manage -eq $FALSE) {
        [array]$Headers = @(
            'Icinga for Windows $FrameworkVersion',
            'Copyright $Copyright',
            'User environment $UserDomain\$Username'
        );

        if ($null -eq (Get-Command -Name 'Write-IcingaConsoleHeader' -ErrorAction SilentlyContinue)) {
            Use-Icinga;
        }

        Write-IcingaConsoleHeader -HeaderLines $Headers;
    }

    if ($RebuildCache) {
        Write-IcingaFrameworkCodeCache;
    }

    powershell.exe -NoExit -Command {
        $Script          = $args[0];
        $RootPath        = $args[1];
        $Version         = $args[2];
        $Manage          = $args[3];
        $IcingaShellArgs = $args[4];

        # Load our Icinga Framework
        Use-Icinga;

        $Host.UI.RawUI.WindowTitle = ([string]::Format('Icinga for Windows {0}', $Version));

        # Set the location to the Icinga Framework module folder
        Set-Location $RootPath;

        if ($Manage) {
            Install-Icinga;
            exit $LASTEXITCODE;
        }

        # If we added a block to execute, do it right here and exit the shell
        # with the last exit code of the command
        if ([string]::IsNullOrEmpty($Script) -eq $FALSE) {
            Invoke-Command -ScriptBlock ([Scriptblock]::Create($Script));
            exit $LASTEXITCODE;
        }

        # Set our "path" to something different so we know that we loaded the Framework
        function prompt {
            Write-Host -Object "icinga" -NoNewline;
            return "> "
        }

    } -Args $ScriptBlock, $PSScriptRoot, $IcingaFrameworkData.PrivateData.Version, ([bool]$Manage), $ArgumentList;
}

function Start-IcingaShellAsUser()
{
    param (
        [string]$User = ''
    );

    Start-Process `
        -WorkingDirectory $PSHOME `
        -FilePath 'powershell.exe' `
        -Verb RunAs `
        -ArgumentList (
            [string]::Format(
                "-Command `"Start-Process -FilePath `"powershell.exe`" -WorkingDirectory `"{0}`" -Credential (Get-Credential -UserName '{1}' -Message 'Please enter your credentials to open an Icinga Shell with') -ArgumentList icinga`"",
                $PSHOME,
                $User
            )
        );
}

Set-Alias icinga Invoke-IcingaCommand -Description "Execute Icinga Framework commands in a new PowerShell instance for testing or quick access to data";
Export-ModuleMember -Alias * -Function * -Variable *;
