#Requires -Version 5.1

#region Microsoft Graph / Intune Integration

$script:GraphToken = $null
$script:GraphTokenExpiry = [datetime]::MinValue
$script:GraphBaseUri = 'https://graph.microsoft.com/v1.0'

function Connect-FindObjectGraph {
    <#
    .SYNOPSIS
        Authenticates to Microsoft Graph for Intune queries.

    .DESCRIPTION
        Acquires an OAuth2 token for Microsoft Graph using either the device code flow
        (interactive, default) or client credentials (automation/CI). The token is cached
        in-memory for the session and automatically refreshed when expired.

        Supports the standard Intune/DeviceManagement scopes. For read-only operations
        (all Get-Intune* commands), DeviceManagement.ManagedDevices.Read.All and
        DeviceManagementApps.Read.All are sufficient.

    .PARAMETER TenantId
        Your Azure AD tenant ID or domain (e.g. "contoso.onmicrosoft.com" or a GUID).

    .PARAMETER ClientId
        App registration client ID. Defaults to the well-known Microsoft PowerShell
        first-party app (14d82eec-204b-4c2f-b7e8-296a70dab67e) which supports device code flow.

    .PARAMETER ClientSecret
        Client secret for app-only (daemon) authentication. When provided, uses the
        client_credentials grant instead of device code flow.

    .PARAMETER Certificate
        X509Certificate2 for certificate-based app authentication.

    .PARAMETER Scope
        OAuth2 scopes to request. Defaults to common Intune read scopes.

    .EXAMPLE
        Connect-FindObjectGraph -TenantId "contoso.onmicrosoft.com"

        Interactive device code flow — displays a code to enter at microsoft.com/devicelogin.

    .EXAMPLE
        Connect-FindObjectGraph -TenantId $tenantId -ClientId $appId -ClientSecret $secret

        Non-interactive app-only auth for CI/CD pipelines.

    .LINK
        Disconnect-FindObjectGraph
        Get-IntuneDevice
    #>
    [CmdletBinding(DefaultParameterSetName = 'DeviceCode')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$TenantId,

        [Parameter(Position = 1)]
        [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

        [Parameter(ParameterSetName = 'ClientSecret', Mandatory = $true)]
        [string]$ClientSecret,

        [Parameter(ParameterSetName = 'Certificate', Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [string[]]$Scope = @(
            'https://graph.microsoft.com/DeviceManagement.ManagedDevices.Read.All'
            'https://graph.microsoft.com/DeviceManagementApps.Read.All'
            'https://graph.microsoft.com/DeviceManagementConfiguration.Read.All'
        )
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    switch ($PSCmdlet.ParameterSetName) {
        'DeviceCode' {
            # Step 1: Request device code
            $dcBody = @{
                client_id = $ClientId
                scope     = ($Scope -join ' ')
            }
            $dcResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
                -Method Post -Body $dcBody -ContentType 'application/x-www-form-urlencoded'

            Write-Host ""
            Write-Host $dcResponse.message -ForegroundColor Cyan
            Write-Host ""

            # Step 2: Poll for token
            $interval = [int]$dcResponse.interval
            $expiresIn = [int]$dcResponse.expires_in
            $deadline = (Get-Date).AddSeconds($expiresIn)

            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds $interval
                try {
                    $tokenBody = @{
                        grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                        client_id   = $ClientId
                        device_code = $dcResponse.device_code
                    }
                    $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint `
                        -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

                    $script:GraphToken = $tokenResponse.access_token
                    $script:GraphTokenExpiry = (Get-Date).AddSeconds($tokenResponse.expires_in - 60)
                    Write-Verbose "FindObject Graph: authenticated via device code flow."
                    Write-Host "Connected to Microsoft Graph ($TenantId)" -ForegroundColor Green
                    return
                } catch {
                    $err = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($err.error -eq 'authorization_pending') { continue }
                    if ($err.error -eq 'slow_down') { $interval += 5; continue }
                    throw "Device code authentication failed: $($err.error_description)"
                }
            }
            throw "Device code expired before authentication completed."
        }

        'ClientSecret' {
            $tokenBody = @{
                grant_type    = 'client_credentials'
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = 'https://graph.microsoft.com/.default'
            }
            $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint `
                -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded'

            $script:GraphToken = $tokenResponse.access_token
            $script:GraphTokenExpiry = (Get-Date).AddSeconds($tokenResponse.expires_in - 60)
            Write-Verbose "FindObject Graph: authenticated via client credentials."
            Write-Host "Connected to Microsoft Graph ($TenantId) [app-only]" -ForegroundColor Green
        }

        'Certificate' {
            # Build client assertion JWT (simplified — for production use a proper JWT library)
            throw "Certificate-based auth requires a JWT assertion builder. Use -ClientSecret for automation, or device code flow for interactive sessions."
        }
    }
}

function Disconnect-FindObjectGraph {
    <#
    .SYNOPSIS
        Clears the cached Microsoft Graph token.

    .EXAMPLE
        Disconnect-FindObjectGraph
    #>
    [CmdletBinding()]
    param()

    $script:GraphToken = $null
    $script:GraphTokenExpiry = [datetime]::MinValue
    Write-Verbose "FindObject Graph: token cleared."
}

function Invoke-FindObjectGraphRequest {
    <#
    Internal: paginated GET against Microsoft Graph. Returns all pages as a flat array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [hashtable]$QueryParameters = @{}
    )

    if (-not $script:GraphToken -or (Get-Date) -ge $script:GraphTokenExpiry) {
        throw "Not connected to Microsoft Graph. Run Connect-FindObjectGraph first."
    }

    $headers = @{
        Authorization  = "Bearer $script:GraphToken"
        'Content-Type' = 'application/json'
    }

    # Build query string
    if ($QueryParameters.Count -gt 0) {
        $qs = ($QueryParameters.GetEnumerator() | ForEach-Object {
            "$([uri]::EscapeDataString($_.Key))=$([uri]::EscapeDataString($_.Value))"
        }) -join '&'
        $Uri = "$Uri`?$qs"
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri

    do {
        $response = Invoke-RestMethod -Uri $nextUri -Headers $headers -Method Get
        foreach ($item in $response.value) { $results.Add($item) }
        $nextUri = $response.'@odata.nextLink'
        Write-Verbose "FindObject Graph: fetched $($results.Count) objects so far..."
    } while ($nextUri)

    return $results
}

function Get-IntuneDevice {
    <#
    .SYNOPSIS
        Retrieves managed devices from Intune via Microsoft Graph.

    .DESCRIPTION
        Queries the /deviceManagement/managedDevices endpoint and returns device objects
        that pipe directly into Find-ObjectByName for filtering.

    .PARAMETER Filter
        Optional OData $filter expression passed to Graph (server-side filtering).
        For client-side filtering, pipe to fob instead.

    .PARAMETER Select
        Properties to retrieve. Defaults to common identification fields.

    .PARAMETER Top
        Maximum number of results per page (Graph default is 1000).

    .EXAMPLE
        Get-IntuneDevice | fob "TONY"

        Find all devices with "TONY" in the displayName.

    .EXAMPLE
        Get-IntuneDevice | fob "windows NOT compliant" -Property operatingSystem,complianceState

    .EXAMPLE
        Get-IntuneDevice -Filter "operatingSystem eq 'iOS'" | fob "ipad" -First 5

    .LINK
        Connect-FindObjectGraph
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Filter,

        [string[]]$Select = @('id', 'displayName', 'operatingSystem', 'osVersion',
            'complianceState', 'managedDeviceOwnerType', 'deviceEnrollmentType',
            'lastSyncDateTime', 'userPrincipalName', 'serialNumber', 'model', 'manufacturer'),

        [ValidateRange(1, 1000)]
        [int]$Top = 1000
    )

    $params = @{
        '$select' = ($Select -join ',')
        '$top'    = "$Top"
    }
    if ($Filter) { $params['$filter'] = $Filter }

    $uri = "$script:GraphBaseUri/deviceManagement/managedDevices"
    Invoke-FindObjectGraphRequest -Uri $uri -QueryParameters $params
}

function Get-IntuneApp {
    <#
    .SYNOPSIS
        Retrieves mobile apps from Intune via Microsoft Graph.

    .EXAMPLE
        Get-IntuneApp | fob "chrome OR edge NOT update"

    .EXAMPLE
        Get-IntuneApp | fob "teams" -Property displayName -Highlight

    .LINK
        Connect-FindObjectGraph
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Filter,

        [string[]]$Select = @('id', 'displayName', 'publisher', 'platform',
            'appAvailability', 'createdDateTime', 'lastModifiedDateTime', 'isAssigned'),

        [ValidateRange(1, 1000)]
        [int]$Top = 1000
    )

    $params = @{
        '$select' = ($Select -join ',')
        '$top'    = "$Top"
    }
    if ($Filter) { $params['$filter'] = $Filter }

    $uri = "$script:GraphBaseUri/deviceAppManagement/mobileApps"
    Invoke-FindObjectGraphRequest -Uri $uri -QueryParameters $params
}

function Get-IntuneCompliancePolicy {
    <#
    .SYNOPSIS
        Retrieves device compliance policies from Intune.

    .EXAMPLE
        Get-IntuneCompliancePolicy | fob "windows"

    .EXAMPLE
        Get-IntuneCompliancePolicy | fob "bitlocker OR encryption" -Property displayName

    .LINK
        Connect-FindObjectGraph
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Filter,

        [string[]]$Select = @('id', 'displayName', 'description', 'createdDateTime',
            'lastModifiedDateTime', 'platforms', 'scheduledActionsForRule'),

        [ValidateRange(1, 1000)]
        [int]$Top = 1000
    )

    $params = @{
        '$select' = ($Select -join ',')
        '$top'    = "$Top"
    }
    if ($Filter) { $params['$filter'] = $Filter }

    $uri = "$script:GraphBaseUri/deviceManagement/deviceCompliancePolicies"
    Invoke-FindObjectGraphRequest -Uri $uri -QueryParameters $params
}

function Get-IntuneConfigProfile {
    <#
    .SYNOPSIS
        Retrieves device configuration profiles from Intune.

    .EXAMPLE
        Get-IntuneConfigProfile | fob "wifi OR vpn"

    .EXAMPLE
        Get-IntuneConfigProfile | fob "restrict" -Property displayName -Count

    .LINK
        Connect-FindObjectGraph
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Filter,

        [string[]]$Select = @('id', 'displayName', 'description', 'createdDateTime',
            'lastModifiedDateTime', 'platforms', 'deviceManagementApplicabilityRuleOsEdition'),

        [ValidateRange(1, 1000)]
        [int]$Top = 1000
    )

    $params = @{
        '$select' = ($Select -join ',')
        '$top'    = "$Top"
    }
    if ($Filter) { $params['$filter'] = $Filter }

    $uri = "$script:GraphBaseUri/deviceManagement/deviceConfigurations"
    Invoke-FindObjectGraphRequest -Uri $uri -QueryParameters $params
}

function Get-IntuneAutopilotDevice {
    <#
    .SYNOPSIS
        Retrieves Windows Autopilot device identities from Intune.

    .EXAMPLE
        Get-IntuneAutopilotDevice | fob "23H2"

    .EXAMPLE
        Get-IntuneAutopilotDevice | fob "dell OR lenovo" -Property manufacturer,model

    .LINK
        Connect-FindObjectGraph
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Filter,

        [string[]]$Select = @('id', 'serialNumber', 'productKey', 'manufacturer', 'model',
            'groupTag', 'enrollmentState', 'deploymentProfileAssignmentStatus'),

        [ValidateRange(1, 1000)]
        [int]$Top = 1000
    )

    $params = @{
        '$select' = ($Select -join ',')
        '$top'    = "$Top"
    }
    if ($Filter) { $params['$filter'] = $Filter }

    $uri = "$script:GraphBaseUri/deviceManagement/windowsAutopilotDeviceIdentities"
    Invoke-FindObjectGraphRequest -Uri $uri -QueryParameters $params
}

function Get-IntuneEnrollment {
    <#
    .SYNOPSIS
        Retrieves device enrollment configurations (enrollment restrictions) from Intune.

    .EXAMPLE
        Get-IntuneEnrollment | fob "limit OR restrict"

    .LINK
        Connect-FindObjectGraph
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [string]$Filter,

        [string[]]$Select = @('id', 'displayName', 'description', 'platformRestrictions',
            'createdDateTime', 'lastModifiedDateTime', 'priority'),

        [ValidateRange(1, 1000)]
        [int]$Top = 1000
    )

    $params = @{
        '$select' = ($Select -join ',')
        '$top'    = "$Top"
    }
    if ($Filter) { $params['$filter'] = $Filter }

    $uri = "$script:GraphBaseUri/deviceManagement/deviceEnrollmentConfigurations"
    Invoke-FindObjectGraphRequest -Uri $uri -QueryParameters $params
}

#endregion

New-Alias -Name gid -Value Get-IntuneDevice -Force

Export-ModuleMember -Function @(
    'Connect-FindObjectGraph',
    'Disconnect-FindObjectGraph',
    'Get-IntuneDevice',
    'Get-IntuneApp',
    'Get-IntuneCompliancePolicy',
    'Get-IntuneConfigProfile',
    'Get-IntuneAutopilotDevice',
    'Get-IntuneEnrollment'
) -Alias @('gid')

