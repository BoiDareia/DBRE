<# PowerShell script file to be executed as a AWS Lambda function. 
# 
# When executing in Lambda the following variables will be predefined.
#   $LambdaInput - A PSObject that contains the Lambda function input data.
#   $LambdaContext - An Amazon.Lambda.Core.ILambdaContext object that contains information about the currently running Lambda environment.
#
# The last item in the PowerShell pipeline will be returned as the result of the Lambda function.
#
# To include PowerShell modules with your Lambda function, like the AWS.Tools.S3 module, add a "#Requires" statement
# indicating the module and version. If using an AWS.Tools.* module the AWS.Tools.Common module is also required.#>

#Requires -Modules @{ModuleName='AWS.Tools.Common';ModuleVersion='4.1.2.0'}
#Requires -Modules @{ModuleName='AWS.Tools.SecretsManager';ModuleVersion='4.1.2.0'}

[string] $secretid = $env:RDS_SECRET_ID
[string] $region = $env:SOURCE_REGION
[string] $dataSource = $env:RDS_INSTANCE 
[string] $procedurename = $env:SP_NAME 
[string] $namespace = $env:CLOUDWATCH_CUSTOM_NAMESPACE 
[string] $metricvalue = $env:METRIC_VALUE


try {
    Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
    Write-Host "Region = $region  Data Source = $dataSource  Stored Procedure = $procedureName" -ForegroundColor Cyan
    Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan

    $secretvalue = (Get-SECSecretValue -SecretId $secretid -Region $region).SecretString  | ConvertFrom-Json 
    [string] $username = $secretvalue.username
    [securestring] $securepassword = ConvertTo-SecureString $secretvalue.password -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential($username,$securepassword)

    if($credentials -eq [System.Management.Automation.PSCredential]::Empty){
        throw "Credential not provided"
    }
    else {
        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        Write-Host "Credentials Received" -ForegroundColor Cyan
        Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        
        $PlainPassword = $credentials.GetNetworkCredential().Password
        $username = $credentials.UserName

        [string]$targetConnectionString ="server=$datasource;Initial Catalog=companyMonitor;Persist Security Info=True;user id=$userName;password=$PlainPassword;Pooling=False;MultipleActiveResultSets=False;Connect Timeout=60;Encrypt=False;TrustServerCertificate=True"
        Write-Host "Built connection string" -ForegroundColor Cyan
    
        <#Set and open connection#>
        $Connection = New-Object System.Data.SqlClient.SqlConnection
        $Connection.ConnectionString = $targetConnectionString
        $Connection.Open()
        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
        Write-Host "Database Connection Established" -ForegroundColor Cyan
        Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan

        <#Set and execute sql command#>
        $SQLCmd = New-Object System.Data.SqlClient.SqlCommand
        $SQLCmd.Connection = $Connection
        $SQLCmd.CommandType = [System.Data.CommandType]'StoredProcedure'
        $SQLCmd.CommandText = $procedurename
        $SQLCmd.CommandTimeout = 0

        $result = $SQLCmd.ExecuteReader()

        <#Process results for cloudwatch#>
        $table = New-Object "System.Data.DataTable"
        $table.Load($result)
        $passon = $table | Select-Object $table.Columns.ColumnName | ConvertTo-Json

        $Connection.Close()

        Write-Host "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
		Write-Host "Building Json Output" -ForegroundColor Cyan
		Write-Host "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -ForegroundColor Cyan
		
        $formatOutput = $passon | ConvertFrom-Json

        $moreOutput = '{"Identifier":"'+$dataSource+'", "NameSpace":"'+$namespace+'", "MetricValue":"'+$metricvalue+'" , "MetricList": ['

        for ($i=0; $i -lt $formatOutput.Length; $i++)
		{
			if($i -eq ($formatOutput.Length -1))
			{
				$moreOutput = $moreOutput + '{"Key": {"Metric": "Records_Created_'+$formatOutput.table[$i]+'"}, "DataPoints": ['
				$moreOutput = $moreOutput + '{"RecordsCreated":'+$formatOutput.row_count[$i]+', "PollDate":"'+$formatOutput.poll_date[$i]+'"}]}'
			}
			else {
				$moreOutput = $moreOutput + '{"Key": {"Metric": "Records_Created_'+$formatOutput.table[$i]+'"}, "DataPoints": ['
				$moreOutput = $moreOutput + '{"RecordsCreated":'+$formatOutput.row_count[$i]+', "PollDate":"'+$formatOutput.poll_date[$i]+'"}]},'
			}
		}

		$moreOutput = $moreOutput +']}'

		$parseMoreOutput = $moreOutput.replace("\","") 
					
		return $parseMoreOutput
    }     
}
catch{
    $toThrow = ("Execution Failed: ''{0}'' Reason: ''{1}''" -f $_.Exception, $_.Exception.InnerException.Message)
    $LastExitCode = 1
}
finally{
    if ($toThrow){
        Write-Error $toThrow
    }
    exit $LastExitCode
}