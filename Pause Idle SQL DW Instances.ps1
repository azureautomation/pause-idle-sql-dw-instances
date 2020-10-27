<#
    .SYNOPSIS
        This script queries all SQL DW instances, using a SQL connection, to get the last time a query execution completed, and pause if Threshold time exceeded.

    .DESCRIPTION
        Running this script across a subscription will
            Get all SQL Servers
            Get all online SQL DW instances assigned to the SQL Servers
            Connect to the SQL DW instance and query the list of executions
            If the last completed execution is over a threshold, pause the instance

    .PARAMETERS
        $LastExecEndThreshold
            The number of minutes that need to have elapsed since the last completed execution to trigger a pause of the SQL DW Instance
        $KeyVaultName
            The KeyVault that holds the Username(s) and Password(s) of the SQL Instances that have access to query
            The KeyVault Secret Name is in the format 
                UserName: '{SQL Server Name}{SQL DW Instance Name}UserName'
                Password: '{SQL Server Name}{SQL DW Instance Name}Password'

    .MODULES
        AzureRM > 4.0.0

#>

Param
    (
        #Set the minutes since the last recorded execution ended to trigger suspend of SQL DW Instrance		
        [parameter(Mandatory=$true)]
        [int] $LastExecEndThreshold,

        #Name of the KeyVault to lookup SQL UserName and Password
        [parameter(Mandatory=$true)]
        [string] $KeyVaultName	
    )

#Get all SQL Servers
$SQLServers = Get-AzureRmSqlServer

#ForEach SQLServer
foreach ($SQLServer in $SQLServers) {
    
    #Get all SQL DW Instances that are Online
    $SQLDWs = Get-AzureRmSqlDatabase -ServerName $SQLServer.ServerName -ResourceGroupName $SQLServer.ResourceGroupName | Where-Object {$_.Edition -eq "DataWarehouse" -and $_.Status -eq "Online"}
    
    #ForEach Online SQL DW instance
    foreach ($SQLDW in $SQLDWs) {

        #Set Prefix for SQL UserName and Password in KeyVault
        $SecretName = "$($SQLDW.ServerName)$($SQLDW.DatabaseName)"

        #Set variables related to SQL DW details
        $DBServerName = $SQLDW.ServerName
        $DBServer = "$($SQLDW.ServerName).database.windows.net"
        $DBName = $SQLDW.DatabaseName
        $DBSubscriptionID = $SQLDW.ResourceId.Substring(15,$SQLDW.ResourceId.IndexOf("/",16)-15)
        $DBResourceGroup = $SQLDW.ResourceGroupName

        #Get UserName and Password from KeyVault
        $DBUserName = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name "$($SecretName)UserName").SecretValueText
        $DBPassword =(Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name "$($SecretName)Password").SecretValueText

        #Connect to SQL DW Instance
        $cn = new-object System.Data.SqlClient.SqlConnection("Server=tcp:$($DBServer),1433;Initial Catalog=$($DBName);Persist Security Info=False;User ID=$($DBUserName);Password=$($DBPassword);MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;");
        $cn.Open()

        #Query all executions that are not instances of this query, using 'SQLDWQueryChkSess' as flag
        $Command = New-Object System.Data.SQLClient.SQLCommand
        $Command.Connection = $cn
        $SQL = "SELECT *, SESSION_ID() as [SQLDWQueryChkSess]`r`n"
        $SQL = "$($SQL)`tFROM	sys.dm_pdw_exec_requests`r`n"
        $SQL = "$($SQL)`tWHERE session_id != SESSION_ID()`r`n" 
        $SQL = "$($SQL)`t`tAND ([session_id] not in`r`n"
        $SQL = "$($SQL)`t`t`t(select [session_id] from sys.dm_pdw_exec_requests where [command] like '%SQLDWQueryChkSess%')`r`n"
        $SQL = "$($SQL)`t`t)`r`n"
        $SQL = "$($SQL)`tORDER BY submit_time"
        
        #If DB connection is closed, open it
        if ($cn.State -eq "Closed") {$cn.Open()}
        $Command.CommandText = $SQL
        try {
            $DataReader = $Command.ExecuteReader()
            $RecCount=0
            $LastEnd = $null
            $LastStart = $null

            #Loop through Records
            while ($DataReader.Read()) {
                $RecCount += 1
                $Status = $DataReader['status']
                $SubmitT = $DataReader['submit_time']
                $StartT = $DataReader['start_time']
                $EndCompT = $DataReader['end_compile_time']
                $EndT = $DataReader['end_time']
                $SessID = $DataReader['SessionID']

                #If Start_time > latest recorded start_time, update latest recorded start_time
                if ($StartT.ToString() -ne [String]::Empty) {
                    if ($StartT -gt $LastStart) {
                        $LastStart = $StartT
                    }
                }

                #If end_time > latest recorded end_time, update latest recorded end_time
                if ($EndT.ToString() -ne [String]::Empty) {
                    if ($EndT -gt $LastEnd) {
                        $LastEnd = $EndT
                    }
                }

                #If the query is still running, send end_time WAY into the future
                if ($Status -eq "Running") {
                    $LastEnd = Get-Date "1 Jan 2099"
                }
            }
            #End 
            $DataReader.Dispose()
        } catch {
            Write-Output $_.Exception.Message
            $DataReader.Dispose()
        }
        #END Try

        #Calculate times
        $Now = [System.DateTime]::UtcNow
        $TimeSinceLastEnd = ($Now - $LastEnd).TotalMinutes
        $TimeSinceLastStart = ($Now - $LastStart).TotalMinutes

        Write-Output "LastEnd: $($LastEnd) - $($TimeSinceLastEnd) Minutes"
        #Write-Output "LastStart: $($LastStart) - $($TimeSinceLastStart) Minutes"

        $command.Dispose()

        #If last recorded execution end_time is longer ago than the threshold minutes
        if ($TimeSinceLastEnd -gt $LastExecEndThreshold) {

            #Pause SQL DW Instance
            Write-Output "Suspending DB Server: $($DBServerName) Database: $($DBName) ResourceGroup: $($DBResourceGroup)"
            Suspend-AzureRmSqlDatabase -ServerName $DBServerName -DatabaseName $DBName -ResourceGroupName $DBResourceGroup
        }
        #END if ($TimeSinceLastEnd -gt $LastExecEndThreshold) {
    }
    #END foreach ($SQLDW in $SQLDWs) {
}
#END foreach ($SQLServer in $SQLServers) {