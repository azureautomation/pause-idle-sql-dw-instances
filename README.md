Pause Idle SQL DW Instances
===========================

            

Pause Idle SQL DW Instances


  *      .SYNOPSIS
This script queries all SQL DW instances, using a SQL connection, to get the last time a query execution completed, and pause if Threshold time exceeded.


  *  .DESCRIPTION
Running this script across a subscription will

  *  Get all SQL Servers 
  *  Get all online SQL DW instances assigned to the SQL Servers 
  *  Connect to the SQL DW instance and query the list of executions 
  *  If the last completed execution is over a threshold, pause the instance



  *  .PARAMETERS

  *  $LastExecEndThreshold
The number of minutes that need to have elapsed since the last completed execution to trigger a pause of the SQL DW Instance


  *  $KeyVaultName
The KeyVault that holds the Username(s) and Password(s) of the SQL Instances that have access to query
The KeyVault Secret Name is in the format

  *  UserName: '{SQL Server Name}{SQL DW Instance Name}UserName' 
  *  Password: '{SQL Server Name}{SQL DW Instance Name}Password'




  *  .MODULES
AzureRM > 4.0.0 

 


 

 

 


        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
