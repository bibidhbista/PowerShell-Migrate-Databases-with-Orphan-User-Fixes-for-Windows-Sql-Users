
<#

AUTHOR: BIBIDH BISTA

REQUIRES DBATOOLS FROM DBATOOLS.IO FOR COPYING THE DATABASE
THE FOLDER MUST CONTAIN TWO SQL SCRIPTS THAT WORK ON FIXING ORPHAN USERS FOR SQL USERS AND WINDOWS USERS RESPECTIVELY.

PARAMS:

REQUIRED:
SOURCESERVER             : SOURCE SERVERNAME WHERE THE DATABASE TO BE MOVE RESIDES                                  
DESTINATIONSERVER        : DESTINATION SERVERNAME WHERE THE DATABASE IS TO BE MOVED       
DATABASENAME             : NAME OF THE DATABASE TO BE MOVED FROM SOURCE SERVER TO DESTINATION SERVER

#>



param( 
   [Parameter(Mandatory=$True, HelpMessage='ENTER A VALID SQL SERVER ENVIRONMENT FOR CONNECTION - NO ALIASES')]
   [ValidateNotNullorEmpty()]  
   #[ValidateSet()]                             ########## Validate against a list of servers
   [string] $SourceServer,
   
   [Parameter(Mandatory=$True, HelpMessage='ENTER A VALID SQL SERVER ENVIRONMENT FOR CONNECTION - NO ALIASES')]
   [ValidateNotNullorEmpty()]  
   #[ValidateSet()]                             ########## Validate against a list of servers
   [string] $DestinationServer,

   
   [Parameter(Mandatory=$true, HelpMessage='ENTER A VALID SQL SERVER DATABASE FOR MIGRATION')]
   [ValidateNotNullorEmpty()] 
   [string] $DatabaseName
)


############################################################################################
############################## Script out permissions ######################################
############################################################################################
Write-Host "#################################################      Sripting out permissions from $DatabaseName : $SourceServer #################################################" 
$timestamp = get-date -f MMddyyyy_HHmm
$logfile = "$PSScriptRoot\Permission_Scripts\$DatabaseName`_$SourceServer`_Permissions_$timestamp.sql"
try{
    Invoke-Sqlcmd -InputFile "$PSScriptRoot\Permission Extract.sql"  -serverinstance $SourceServer -database $DatabaseName -Verbose 4> $logfile #routes verbose outputs to file
    Write-Host "Successfully extracted all permissions from $SourceServer : $DatabaseName and saved the query file to $logfile" -BackgroundColor Green
}catch{
    Write-Error "Couldn't extract permissions from $SourceServer : $DatabaseName . Check if you have sufficient permissions to run the permissions extract script on $PSScriptRoot!" -ErrorAction Stop
}


############################################################################################
###################################### Migrate DB ##########################################
############################################################################################
Write-Host "#################################################   Migrating $DatabaseName from $SourceServer to $DestinationServer #################################################"
try{
    #$DatabaseName = (Get-DbaDatabase -SqlInstance $SourceServer|Out-GridView -PassThru)
    #$DatabaseName = $DatabaseName.name
    #Copy-dbadatabase -Source $SourceServer -Destination $DestinationServer -Database $DatabaseName -BackupRestore -NetworkShare "\\pfs02\sqlbackup\dbaTools_Staging" -force
    
    #Copy dbadatbase acting weird and fails to restore
    Backup-DbaDatabase -SqlInstance $SourceServer -Database $DatabaseName -BackupDirectory "\\pfs02\sqlbackup\dbatools_staging\" -CopyOnly|Restore-DbaDatabase -SqlInstance $DestinationServer
    Write-Host "Migration of $SourceServer : $DatabaseName to $DestinationServer : $DatabaseName completed successfully" -BackgroundColor Green

}catch{
    Write-Error "Error: Migration of $DatabaseName from $SourceServer to $DestinationServer failed. Make sure you have installed dbatools before trying again. Check if you have sufficient permissions to run the permissions extract script on $PSScriptRoot!" -ErrorAction Stop    
}


############################################################################################
############################# Apply permissions on destination server ######################
############################################################################################
Write-Host "################################################# Applying permissions to $DestinationServer : $DatabaseName #################################################" 
try{
    Invoke-Sqlcmd -InputFile $logfile -serverinstance $DestinationServer -database $DatabaseName -Verbose 
    Write-Host "Successfully applied all permissions from $SourceServer : $DatabaseName to $DestinationServer : $DatabaseName and saved the query file to $logfile" -BackgroundColor Green
}catch{
    Write-Error "Couldn't apply permissions to $DestinationServer : $DatabaseName . Check if you have sufficient permissions to run the permissions extract script on $PSScriptRoot!" -ErrorAction Stop
}



############################################################################################
###################### Take care of orphan users/Migrate Logins ############################
############################################################################################
Write-Host "###################################    Migrating logins and fixing of orphan users  #################################################" 
try{
    # For SQL Orphan Users
    $object = Repair-DbaOrphanUser -SqlInstance $DestinationServer -Database $DatabaseName
    $users = $object.user
    $count = $users.count
    # If there are SQL Orphan Users
    if($count -gt 0){
        Write-Host "Following SQL Orphan User(s) were fixed: " -BackgroundColor Green
        foreach($user in $users){
                Copy-DbaLogin -Source $SourceServer -Destination $DestinationServer -Login $user # Migrates Logins with password so they don't have to be reentered for SQL Logins
        }
        Repair-DbaOrphanUser -SqlInstance $DestinationServer -Database $DatabaseName|ft -AutoSize
    }
    # For Windows Orphan Users
    try{
        Invoke-Sqlcmd -InputFile "$PSScriptRoot\Windows Orphan Fix.sql" -serverinstance $DestinationServer -database $DatabaseName -Verbose 
    }catch{
        Write-Error "Couldn't fix Windows Orphaned Users. Check if you have sufficient permissions to run the permissions extract script on $PSScriptRoot!" -ErrorAction Stop
    }

    Write-Host "Fixed both SQL and Windows Orphan Users!" -BackgroundColor Green
    Write-Host "End of Migration: Successfully copied $DatabaseName from $SourceServer to $DestinationServer and reapplied required permissions."
}catch{
    Write-Error "Error: Couldn't repair orphan users. Make sure you have installed dbatools before trying again. Check if you have sufficient permissions to run the permissions extract script on $PSScriptRoot!" -ErrorAction Stop            
}




#specific database
#copy-dbadatabase -source tfhlbdmsql12 -Destination ufhlbdmsql15 -Database teadvantage -BackupRestore -NetworkShare "\\pfs02\sqlbackup\dbaTools_Staging" -force
