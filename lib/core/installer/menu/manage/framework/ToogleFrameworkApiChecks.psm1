function Invoke-IcingaForWindowsManagementConsoleToggleFrameworkApiChecks()
{
    if (Get-IcingaFrameworkApiChecks) {
        Disable-IcingaFrameworkApiChecks;
    } else {
        if ((Get-IcingaBackgroundDaemons).ContainsKey('Start-IcingaWindowsRESTApi') -eq $FALSE) {
            Register-IcingaBackgroundDaemon -Command 'Start-IcingaWindowsRESTApi';
            Add-IcingaRESTApiCommand -Command 'Invoke-IcingaCheck*' -Endpoint 'apichecks';
        }
        if ([string]::IsNullOrEmpty((Get-IcingaJEAContext)) -eq $FALSE) {
            Install-IcingaForWindowsCertificate;
        }

        Enable-IcingaFrameworkApiChecks;
    }

    Restart-IcingaWindowsService;
}
