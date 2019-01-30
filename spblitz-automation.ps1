#######################################################################################################################
## 
## name:        
##      spblitz-automation.ps1
##
##      powershell script to run sp_Blitz scripts remotely, mostly via sqlcmd, and report back to a linked server repo.
##
## syntax:
##      .\spblitz-automation.ps1
##
## dependencies:
##      windows task to run this every day 
##
## updated:
##      -- Thursday, July 26, 2018 3:44 PM       -- initial commit
##      -- Wednesday, September 5, 2018 4:25 PM  -- finished functions, a refacatoring round to reduce the nlines
##      -- Friday, September 28, 2018 3:38 PM    -- added another server, really time to refactor again
##      -- Tuesday, January 8, 2019 4:21 PM      -- refactoring to use a hashtable for values from Settings.xml
##      -- Wednesday, January 30, 2019 8:33 AM   -- added @BringThePain = 1 to accomodate growth
##
## todo:
##

## Functions ##########################################################################################################

##########################################################################################################
##
## LogWrite - write messages to log file 
##
Function LogWrite
{
   Param ([string]$logstring)
   Add-content $Logfile -value $logstring 
}


##########################################################################################################
##
## ExtractPassword - Get a password from the encrypted credentials file 
##
Function ExtractPassword
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]   [string] $tryCredentialsFile,
         [Parameter(Mandatory=$true, Position=1)]   [string] $tryServerUsername,
         [Parameter(Mandatory=$true, Position=2)] [AllowEmptyString()]  [string] $tryServerPassword
    )

##
## Get the destination password from the encrypted credentials file 
## 
## https://blogs.technet.microsoft.com/robcost/2008/05/01/powershell-tip-storing-and-using-password-credentials/
## note the pre-requisite (as explained in the blog)
##     credentials.txt   
## which comes from:  
##     read-host -assecurestring | convertfrom-securestring | out-file credentials-xyz.txt
##

if(![System.IO.File]::Exists($tryCredentialsFile))
    {
    Write-Output ("Error. Halted. Missing encrypted credentials file.")
    LogWrite ("Error. Halted. Missing encrypted credentials file.")
    throw ("Error. Halted. Missing encrypted credentials file.")
    }

$passwordSecureString = get-content $tryCredentialsFile | convertto-securestring
$credentialsObject = new-object -typename System.Management.Automation.PSCredential -argumentlist $tryServerUsername,$passwordSecureString
LogWrite ("credentials            :  " + $credentialsObject)
LogWrite ("decrypted username     :  " + $credentialsObject.GetNetworkCredential().UserName)
LogWrite ("decrypted password     :  " + "<redacted>")          ## redact this asap  + $credentialsObject.GetNetworkCredential().password
$tryServerPassword = $credentialsObject.GetNetworkCredential().password

return $tryServerPassword
}


##########################################################################################################
##
## BuildTempLink - build a temporary link back to instance with a central table with the sp_Blitz results
##
Function BuildTempLink
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]   [string] $serverUsername,
         [Parameter(Mandatory=$true, Position=1)]   [string] $serverPassword,
         [Parameter(Mandatory=$true, Position=2)]   [string] $serverInstance,
         [Parameter(Mandatory=$true, Position=3)]   [string] $serverBlitzInDb,
         [Parameter(Mandatory=$true, Position=4)]   [string] $OutputServerName,
         [Parameter(Mandatory=$true, Position=5)]   [string] $OutputServerServer,
         [Parameter(Mandatory=$true, Position=6)]   [string] $OutputDatabaseName,
         [Parameter(Mandatory=$true, Position=7)]   [string] $OutputServerUser,
         [Parameter(Mandatory=$true, Position=8)]   [string] $OutputServerPass
    )

##
## use a "here string" aka "splat operator", insert the parameters into the sqlcmd command string
##
## sqlcmd -U BATMAN      -P opensesame -S SRCSERVER  -d MASTER -Q "EXEC master.dbo.sp_addlinkedserver @server = N'LINKED.SERVER.NAME', @srvproduct=N'SQLOLEDB', @provider=N'SQLOLEDB', @datasrc=N'LINKSRV',  @provstr=N'Data Source=LINKSRV;Initial Catalog=MASTER;Provider=SQLOLEDB;User ID=ADMIN;Password=OPENUPSAYI ;Auto Translate=false;', @catalog=N'MASTER'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                                    ^^^^^^^^^^^^^^^^^                                                               ^^^^^^                            ^^^^^^                  ^^^^^^                          ^^^^^^       ^^^^^^                                         ^^^^^^ 
##           $sun           $spw          $sin          $sbd                                                      $osn                                                                            $oss                              $oss                    $osd                            $osu         $osp                                           $osd   
##
## sqlcmd -U {0}        -P {1}           -S {2}      -d {3}    -Q "EXEC master.dbo.sp_addlinkedserver @server = N'{4}', @srvproduct=N'SQLOLEDB', @provider=N'SQLOLEDB', @datasrc=N'{5}', @provstr=N'Data Source={5};Initial Catalog={6};Provider=SQLOLEDB;User ID={7};Password={8};Auto Translate=false;', @catalog=N'{6}'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                                    ^^^^^^^^^^^^^^^^^                                                ^^^^^^                       ^^^^^^              ^^^^^^                      ^^^^^^         ^^^^^^                                  ^^^^^^ 
##           $sun           $spw          $sin          $sbd                                                      $osn                                                             $oss                         $oss                $odn                        $osu           $osp                                    $odn   

##
##  $sun  $serverUsername     0  
##  $spw  $serverPassword     1  
##  $sin  $serverInstance     2  
##  $sbd  $serverBlitzInDb    3  
##  $osn  $OutputServerName   4  
##  $oss  $OutputServerServer 5  
##  $odn  $OutputDatabaseName 6  
##  $osu  $OutputServerUser   7  
##  $osp  $OutputServerPass   8  

$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC master.dbo.sp_addlinkedserver @server = N'{4}', @srvproduct=N'SQLOLEDB', @provider=N'SQLOLEDB', @datasrc=N'{5}', @provstr=N'Data Source={5};Initial Catalog={6};Provider=SQLOLEDB;User ID={7};Password={8};Auto Translate=false;', @catalog=N'{6}'"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName, $OutputServerServer, $OutputDatabaseName, $OutputServerUser, $OutputServerPass
Write-Output "--------------------------------------"
$command
Write-Output "--------------------------------------"
LogWrite ("command               :  " + "EXEC master.dbo.sp_addlinkedserver <redacted>")   ## to troubleshoot temporarily replace this with $command

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)

##
## sqlcmd -U BATMAN      -P opensesame  -S SRCSERVER -d MASTER -Q "EXEC master.dbo.sp_addlinkedsrvlogin  @rmtsrvname=N'LINKED.SERVER.NAME', @useself=N'False', @locallogin=NULL, @rmtuser=N'ADMIN', @rmtpassword='secretsauce'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                                         ^^^^^^^^^^^^^^^^^                                                  ^^^^^^^                 ^^^^^^                  
##           $sun           $spw          $sin          $sbd                                                           $osn                                                               $osu                    $osp                    
##
## sqlcmd -U {0}        -P {1}           -S {2}      -d {3}    -Q "EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'{4}', @useself=N'False', @locallogin=NULL, @rmtuser=N'{5}', @rmtpassword='{6}'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                                        ^^^^^                                               ^^^^^^^              ^^^^^^                  
##           $sun           $spw          $sin          $sbd                                                          $osn                                                $osu                 $osp                    

$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname=N'{4}', @useself=N'False', @locallogin=NULL, @rmtuser=N'{5}', @rmtpassword='{6}'"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName, $OutputServerUser, $OutputServerPass

Write-Output "--------------------------------------"
$command
Write-Output "--------------------------------------"
LogWrite ("command               :  " + "EXEC master.dbo.sp_addlinkedsrvlogin <redacted>")  ## to troubleshoot temporarily replace this with $command

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)

##
## sqlcmd -U BATMAN      -P opensesame  -S SRCSERVER  -d MASTER -Q "EXEC master.dbo.sp_serveroption @server=N'LINKED.SERVER.NAME', @optname=N'rpc', @optvalue=N'true'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                               ^^^^^^^^^^^^^^^^^                                                  
##           $sun           $spw          $sin          $sbd                                                 $osn                                                               
##
## sqlcmd -U {0}        -P {1}           -S {2}      -d {3}    -Q "EXEC master.dbo.sp_serveroption @server=N'{4}', @optname=N'rpc', @optvalue=N'true'"
##           ^^^^^          ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                               ^^^^                                                  
##           $sun           $spw          $sin          $sbd                                                 $osn                                                               

$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC master.dbo.sp_serveroption @server=N'{4}', @optname=N'rpc', @optvalue=N'true'"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName

Write-Output "--------------------------------------"
$command
Write-Output "--------------------------------------"
LogWrite ("command               :  " + "EXEC master.dbo.sp_serveroption <redacted>")  ## to troubleshoot temporarily replace this with $command

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)

##
## sqlcmd -U BATMAN      -P opensesame  -S SRCSERVER  -d MASTER -Q "EXEC master.dbo.sp_serveroption @server=N'LINKED.SERVER.NAME', @optname=N'rpc out', @optvalue=N'true'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                               ^^^^^^^^^^^^^^^^^                                                  
##           $sun           $spw          $sin          $sbd                                                 $osn                                                               
##
## sqlcmd -U {0}        -P {1}           -S {2}      -d {3}    -Q "EXEC master.dbo.sp_serveroption @server=N'{4}', @optname=N'rpc out', @optvalue=N'true'"
##           ^^^^^          ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                               ^^^^                                                  
##           $sun           $spw          $sin          $sbd                                                 $osn                                                               

$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC master.dbo.sp_serveroption @server=N'{4}', @optname=N'rpc out', @optvalue=N'true'"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName

Write-Output "--------------------------------------"
$command
Write-Output "--------------------------------------"
LogWrite ("command               :  " + "EXEC master.dbo.sp_serveroption <redacted>")  ## to troubleshoot temporarily replace this with $command

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)
}


##########################################################################################################
##
## RunSpBlitz - run sp_blitz with @outputsername = 'LINKED.SERVER.NAME' and tablename = BlitzResults
##
Function RunSpBlitz
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]       [string] $serverUsername,
         [Parameter(Mandatory=$true, Position=1)]       [string] $serverPassword,
         [Parameter(Mandatory=$true, Position=2)]       [string] $serverInstance,
         [Parameter(Mandatory=$true, Position=3)]       [string] $serverBlitzInDb,
         [Parameter(Mandatory=$true, Position=4)]       [string] $OutputServerName,
         [Parameter(Mandatory=$true, Position=5)]       [string] $OutputDatabaseName,
         [Parameter(Mandatory=$true, Position=6)]       [string] $OutputTableName
    )

##
## use a "here string" aka "splat operator", insert the parameters into the sqlcmd command string
##
## sqlcmd -U BATMAN -P opensesame -S SRCSERVER   -d MASTER     -Q "EXEC [dbo].[sp_Blitz] @CheckUserDatabaseObjects = 1, @CheckProcedureCache = 0, @OutputType = 'COUNT', @OutputProcedureCache = 0, @CheckProcedureCacheFilter = NULL, @CheckServerInfo = 1, @OutputServerName = 'LINKED.SERVER.NAME', @OutputDatabaseName = 'master', @OutputSchemaName = 'dbo', @OutputTableName = 'BlitzResults', @OutputXMLasNVARCHAR = 1"
##           ^^^^^^    ^^^^^^^^^^    ^^^^^^^^^^^    ^^^^^^^^^^                                                                                                                                                                                                                    ^^^^^^^^^^^^^^^^^                          ^^^^^^                                                  ^^^^^^^^^^^^   
##           $sun      $spw          $sin           $sbd                                                                                                                                                                                                                          $osn                                       $odn                                                    $otn   
##
##  $sun  $serverUsername      0  
##  $spw  $serverPassword      1  
##  $sin  $serverInstance      2  
##  $sbd  $serverBlitzInDb     3  
##  $osn  $OutputServerName    4  
##  $odn  $OutputDatabaseName  5  
##  $otn  $OutputTableName     6  

$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC [dbo].[sp_Blitz] @CheckUserDatabaseObjects = 1, @CheckProcedureCache = 0, @OutputType = 'COUNT', @OutputProcedureCache = 0, @CheckProcedureCacheFilter = NULL, @CheckServerInfo = 1, @OutputServerName = '{4}', @OutputDatabaseName = '{5}', @OutputSchemaName = 'dbo', @OutputTableName = '{6}', @OutputXMLasNVARCHAR = 1, @BringThePain = 1"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName, $OutputDatabaseName, $OutputTableName   

Write-Output "--------------------------------------"
$command
Write-Output "--------------------------------------"
LogWrite ("command               :  " + "<redacted>")  ## to troubleshoot temporarily replace this with $command

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)
}


############################################################################################################
##
## RemoveTempLink - remove the temporary link back to the linked server connection that we just built
##
Function RemoveTempLink
{
    Param
    (
         [Parameter(Mandatory=$true, Position=0)]   [string] $serverUsername,
         [Parameter(Mandatory=$true, Position=1)]   [string] $serverPassword,
         [Parameter(Mandatory=$true, Position=2)]   [string] $serverInstance,
         [Parameter(Mandatory=$true, Position=3)]   [string] $serverBlitzInDb,
         [Parameter(Mandatory=$true, Position=4)]   [string] $OutputServerName
    )

##
## use a "here string" aka "splat operator", insert the parameters into the sqlcmd command string
##
## sqlcmd -U BATMAN      -P opensesame  -S SOURCESRV  -d MASTER -Q "EXEC master.dbo.sp_dropserver @server=N'LINKED.SERVER.NAME', @droplogins='droplogins'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                              ^^^^^^^^^^^^^^^^^    
##           $sun           $spw          $sin          $sbd                                                $osn                 
##
## sqlcmd -U {0}        -P {1}           -S {2}      -d {3}    -Q "EXEC master.dbo.sp_dropserver @server=N'{4}', @droplogins='droplogins'"
##           ^^^^^^         ^^^^^^^^^^    ^^^^^^^^^^    ^^^^^^                                             ^^^^
##           $sun           $spw          $sin          $sbd                                               $osn                                         

##
$command = @"
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC master.dbo.sp_dropserver @server=N'{4}', @droplogins='droplogins'"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName

Write-Output "--------------------------------------"
$command
Write-Output "--------------------------------------"
##LogWrite ("command               :  " + $command)
LogWrite ("command               :  " + "<redacted>")

Invoke-Expression -Command:$command -OutVariable out | Tee-Object -Variable out
LogWrite ("output                :  " + $out)
}


## Main Code ##########################################################################################################

try {

##                      
## set local code path and initialize settings file 
##
$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path
[xml]$ConfigFile = Get-Content "$myDir\Settings.xml"

## setup the logfile
$LogDir = $myDir + "\logs"
if(-not ([IO.Directory]::Exists($LogDir))) {New-Item -ItemType directory -Path $LogDir}
$Logfile = ($LogDir + "\spblitz-automation-" + $(get-date -f yyyy-MM-dd-HHmmss) + ".log")
Write-Output "results are logged to:  "$Logfile 
LogWrite ("Started at:  " + $(get-date -f yyyy-MM-dd-HHmmss))

##
## Get linked server name variables from the settings.xml file, and read into hashtable
##

$serverUsernameHash = @{}
$i = 0
foreach ($setting in $ConfigFile.SelectNodes("/spblitz_automation/*") ) {
    if($setting.Name -Match 'serverUsername*')
    {
        $serverUsernameHash[$i] = $setting.InnerText
        LogWrite ("($i):  " + $setting.InnerText )
        $i++
    }
}

$nServers = $i 

$credentialsFileHash = @{}
$i = 0
foreach ($setting in $ConfigFile.SelectNodes("/spblitz_automation/*") ) {
    if($setting.Name -Match 'credentialsFile*')
    {
        $credentialsFileHash[$i] = $setting.InnerText
        LogWrite ("($i):  " + $setting.InnerText )
        $i++
    }
}

$serverPasswordHash = @{}
for ($i=0; $i -lt $nServers; $i++) {
    $tryCredentialsFile = $MyDir+ "\" + $credentialsFileHash[$i]
    $tryServerUsername  = $serverUsernameHash[$i]
    $tryServerPassword  = ""
    $serverPasswordHash[$i] = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword
    LogWrite ("($i):  " + "<redacted>")
    }

$serverInstanceHash = @{}
$i = 0
foreach ($setting in $ConfigFile.SelectNodes("/spblitz_automation/*") ) {
    if($setting.Name -Match 'serverInstance*')
    {
        $serverInstanceHash[$i] = $setting.InnerText
        LogWrite ("($i):  " + $setting.InnerText )
        $i++
    }
}

$serverBlitzInDbHash = @{}
$i = 0
foreach ($setting in $ConfigFile.SelectNodes("/spblitz_automation/*") ) {
    if($setting.Name -Match 'serverBlitzInDb*')
    {
        $serverBlitzInDbHash[$i] = $setting.InnerText
        LogWrite ("($i):  " + $setting.InnerText )
        $i++
    }
}

$outputServerName    = $ConfigFile.spblitz_automation.outputServerName   
$outputServerServer  = $ConfigFile.spblitz_automation.outputServerServer 
$outputDatabaseName  = $ConfigFile.spblitz_automation.outputDatabaseName 
$outputServerUser    = $ConfigFile.spblitz_automation.outputServerUser   
$credentialsDest     = $ConfigFile.spblitz_automation.credentialsDest
$outputTableName     = $ConfigFile.spblitz_automation.outputTableName    
$outputServerPass    = ""

LogWrite ("outputServerName    :  " + $outputServerName   )
LogWrite ("outputServerServer  :  " + $outputServerServer )
LogWrite ("outputDatabaseName  :  " + $outputDatabaseName )
LogWrite ("outputServerUser    :  " + $outputServerUser   )
LogWrite ("credentialsDest     :  " + $credentialsDest)
LogWrite ("outputTableName     :  " + $outputTableName    )

##
##  extract password for destination linked server  
##

$tryCredentialsFile = $MyDir+ "\" + $credentialsDest
$tryServerUsername  = $outputServerUser
$tryServerPassword  = $OutputServerPass
$OutputServerPass = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

##
## for each server in the hashtable, extract password, build temp linked server, run sp_Blitz, drop linked server
##

for($i = 0; $i -lt $nServers; $i++) 
{    
    ## other parameters from .XML file
    $serverUsername      =  $serverUsernameHash[$i]
    $serverPassword      =  $serverPasswordHash[$i] 
    $serverInstance      =  $serverInstanceHash[$i]
    $serverBlitzInDb     =  $serverBlitzInDbHash[$i]

    ## build a temporary link back to outputServer
    BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
    Logwrite ("BuildTempLink -serverUsername " + $serverUsername + " -serverPassword + <redacted> -serverInstance " + $serverInstance + " -serverBlitzInDb + " + $serverBlitzInDb + " -OutputServerName + " + $OutputServerName + " -OutputServerServer " + $OutputServerServer + " -OutputDatabaseName " + $OutputDatabaseName + " -OutputServerUser " + $OutputServerUser + " -OutputServerPass + <redacted> ")
        
    ## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
    RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    
    Logwrite ("RunSpBlitz -serverUsername " + $serverUsername + " -serverPassword + <redacted> -serverInstance " + $serverInstance + " -serverBlitzInDb " + $serverBlitzInDb + " -OutputServerName " + $OutputServerName + " -OutputDatabaseName " + $OutputDatabaseName + " -OutputTableName " + $OutputTableName)   

    ## remove the temporary link to outputServer
    RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 
    Logwrite ("RemoveTempLink -serverUsername " + $serverUsername + " -serverPassword <redacted> -serverInstance + " + $serverInstance + " -serverBlitzInDb " + $serverBlitzInDb + " -OutputServerName " + $OutputServerName)
} 

throw ("Halted.  This is the end.  Who knew.")

##
## future stuff below ?
##

##
## run net group /domain "PplWhollGetMeFired"
##

##
## run setacl  (ISACA 4.1.15)
##


}
Catch {
    ##
    ## log any error
    ##    
    LogWrite $Error[0]
}
Finally {

    ##
    ## go back to the software directory where we started
    ##
    set-location $myDir

    LogWrite ("finished at:  " + $(get-date -f yyyy-MM-dd-HHmmss))
}