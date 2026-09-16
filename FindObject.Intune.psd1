@{
RootModule = 'FindObject.Intune.psm1'
ModuleVersion = '2.0.0'
CompatiblePSEditions = @('Desktop', 'Core')
GUID = 'd5e1f8a2-9b3c-4e5f-8a1d-7c2e3f4a5b6c'
Author = 'Matthew Bubb'
CompanyName = 'Personal'
Copyright = '(c) 2025 Matthew Bubb. All rights reserved.'
Description = 'Optional Microsoft Graph and Intune integration cmdlets for FindObject.'
PowerShellVersion = '5.1'
FunctionsToExport = @(
    'Connect-FindObjectGraph'
    'Disconnect-FindObjectGraph'
    'Get-IntuneDevice'
    'Get-IntuneApp'
    'Get-IntuneCompliancePolicy'
    'Get-IntuneConfigProfile'
    'Get-IntuneAutopilotDevice'
    'Get-IntuneEnrollment'
)
CmdletsToExport = @()
VariablesToExport = @()
AliasesToExport = @('gid')
FileList = @('FindObject.Intune.psm1', 'FindObject.Intune.psd1')
PrivateData = @{
    PSData = @{
        Tags = @('Intune', 'Graph', 'DeviceManagement', 'MDM', 'FindObject', 'PowerShell')
        LicenseUri = 'https://github.com/thebubbsy/FindObject/blob/main/LICENSE'
        ProjectUri = 'https://github.com/thebubbsy/FindObject'
        ReleaseNotes = 'v2.0.0 - Extracted into optional submodule decoupled from core FindObject'
    }
}
}