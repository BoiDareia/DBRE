<#
.SYNOPSIS
    A collection of PowerShell functions to generate and publish SQL Server database deployments using Data-Tier Application Packages (DACPACs).

.DESCRIPTION
    This script provides two main functions for automating database deployments with DACPACs and the SQLPackage tool.
    It is intended to be used as a module or library within a larger Octopus Deploy process.

    Functions:
    - GetConnectionString: Constructs a standard SQL Server connection string from a data source, credentials, and database name.
    - GenerateDeployScript: Uses `sqlpackage.exe` to generate a differential SQL deployment script by comparing a DACPAC file against a target database. It also cleans the script of SQLCMD variables to make it compatible with tools like Flyway.
    - Publish-DatabaseDeployment: Uses the older DACFx .NET libraries to directly publish a DACPAC to a target database.

.NOTES
    Author:      Sergio Goncalves
    Date:        25/08/2025
    Requires:    - For `GenerateDeployScript`: `sqlpackage.exe` (part of SQL Server Data Tools) must be in the system's PATH or at a known location.
                 - For `Publish-DatabaseDeployment`: The DACFx .NET libraries (`Microsoft.SqlServer.Dac.dll`) must be available at the specified path.
#>

$ErrorActionPreference = 'Stop'

#================================================================================
# HELPER FUNCTIONS
#================================================================================

Function GetConnectionString {
<#
.SYNOPSIS
    Builds a standard SQL Server connection string.
#>
    Param(
        [Parameter(Mandatory=$True)]
        [string]$dataSource,
        [Parameter(Mandatory=$True)]
        [System.Management.Automation.PSCredential]$credentials,
        [Parameter(Mandatory=$True)]
        [string]$database
    )
    
    try {
        Write-Host "--- Building Connection String for database '$database' on '$dataSource' ---"
        if ($credentials -eq [System.Management.Automation.PSCredential]::Empty) {
            throw "Credentials cannot be empty."
        }
        
        $plainPassword = $credentials.GetNetworkCredential().Password
        $userName = $credentials.UserName
        
        # Standard connection string with settings for reliability in automation.
        return "server=$dataSource;Initial Catalog=$database;Persist Security Info=True;user id=$userName;password=$plainPassword;Pooling=False;MultipleActiveResultSets=False;Connect Timeout=60;Encrypt=False;TrustServerCertificate=True"
    }
    catch {
        $errorMessage = "Failed to construct connection string. Reason: '$($_.Exception.Message)'"
        Write-Error $errorMessage
        throw $errorMessage
    }
}

Function GenerateDeployScript {
<#
.SYNOPSIS
    Generates a SQL deployment script from a DACPAC using sqlpackage.exe.
#>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)]
        [string]$dacpac,
        [Parameter(Mandatory=$True)]
        [string]$publishXml,
        [Parameter(Mandatory=$True)]
        [string]$targetConnectionString,
        [Parameter(Mandatory=$True)]
        [string]$filepath,
        [Parameter(Mandatory=$True)]
        [string]$database,
        [Parameter(Mandatory=$True)]
        [string]$logfile
    )

    try {
        Write-Host "--- Generating Deploy Script ---" | Tee-Object -FilePath $logfile -Append
        
        # --- Validate Input Paths ---
        if (-not (Test-Path $dacpac)) { throw "DACPAC file not found at: $dacpac" }
        if (-not (Test-Path $publishXml)) { throw "Publish profile XML not found at: $publishXml" }

        # --- Use sqlpackage.exe to generate the script ---
        $sqlPackageArgs = @(
            "/Action:Script",
            "/SourceFile:`"$dacpac`"",
            "/TargetConnectionString:`"$targetConnectionString`"",
            "/Profile:`"$publishXml`"",
            "/OutputPath:`"$filepath`""
        )
        
        Write-Host "Executing sqlpackage.exe with arguments: $sqlPackageArgs" | Tee-Object -FilePath $logfile -Append
        & sqlpackage $sqlPackageArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "sqlpackage.exe failed with exit code $LASTEXITCODE."
        }
        
        Write-Host "Successfully generated raw SQL script at '$filepath'." | Tee-Object -FilePath $logfile -Append

        # --- Clean up SQLCMD variables for Flyway compatibility ---
        Write-Host "Cleaning SQLCMD variables from the generated script..." | Tee-Object -FilePath $logfile -Append
        $scriptContent = Get-Content -Path $filepath -Raw
        $scriptContent = $scriptContent -replace ':setvar', '--:setvar' `
                                         -replace ':on error exit', '--:on error exit' `
                                         -replace '\$\(DatabaseName\)', $database `
                                         -replace '\$\(__IsSqlCmdEnabled\)', 'True' `
                                         -replace 'SET NOEXEC ON;', ''
        
        Set-Content -Path $filepath -Value $scriptContent -Encoding UTF8
        
        Write-Host "Generate DeployScript successful!" | Tee-Object -FilePath $logfile -Append
    }
    catch {
        $errorMessage = "Generate DeployScript failed. Reason: '$($_.Exception.Message)'"
        $errorMessage | Tee-Object -FilePath $logfile -Append
        throw $errorMessage
    }
}

Function Publish-DatabaseDeployment {
<#
.SYNOPSIS
    Publishes a DACPAC directly to a database using the DACFx .NET library.
#>
    param(
        [string]$dacfxPath,
        [string]$dacpac,
        [string]$publishXml,
        [string]$targetConnectionString
    )
    
    try {
        Write-Host "--- Publishing Database Deployment using DACFx Library ---"
        
        # --- Load DACFx Assembly ---
        if (-not (Test-Path $dacfxPath)) { throw "DACFx DLL not found at '$dacfxPath'." }
        Add-Type -Path $dacfxPath
        Write-Host "Loaded DAC assembly from '$dacfxPath'."
        
        # --- Load DACPAC and Profile ---
        if (-not (Test-Path $dacpac)) { throw "DACPAC file not found at '$dacpac'." }
        $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($dacpac)
        
        if (-not (Test-Path $publishXml)) { throw "Publish profile XML not found at '$publishXml'." }
        $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($publishXml)
        
        # --- Deploy ---
        $dacServices = New-Object Microsoft.SqlServer.Dac.DacServices($targetConnectionString)
        Register-ObjectEvent -InputObject $dacServices -EventName "Message" -SourceIdentifier "DacFxMessage" -Action { Write-Host "DACFx: $($EventArgs.Message.Message)" } | Out-Null
        
        Write-Host "Executing deployment..."
        $dacServices.Deploy($dacPackage, $dacProfile.TargetDatabaseName, $true, $dacProfile.DeployOptions, $null)
        
        Write-Host "Deployment successful!" -ForegroundColor Green
    }
    catch {
        $errorMessage = "Deployment failed. Reason: '$($_.Exception.Message)'. Inner Exception: '$($_.Exception.InnerException.Message)'"
        Write-Error $errorMessage
        throw $errorMessage
    }
    finally {
        Unregister-Event -SourceIdentifier "DacFxMessage" -ErrorAction SilentlyContinue
    }
}
