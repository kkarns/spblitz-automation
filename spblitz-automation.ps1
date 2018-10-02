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
##      -- Tuesday, October 2, 2018 12:52 PM     -- ok, this is no bueno, after this server i'll refactor
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
    echo ("Error. Halted. Missing encrypted credentials file.")
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
echo "--------------------------------------"
$command
echo "--------------------------------------"
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

echo "--------------------------------------"
$command
echo "--------------------------------------"
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

echo "--------------------------------------"
$command
echo "--------------------------------------"
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

echo "--------------------------------------"
$command
echo "--------------------------------------"
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
sqlcmd -U {0} -P {1} -S {2} -d {3} -Q "EXEC [dbo].[sp_Blitz] @CheckUserDatabaseObjects = 1, @CheckProcedureCache = 0, @OutputType = 'COUNT', @OutputProcedureCache = 0, @CheckProcedureCacheFilter = NULL, @CheckServerInfo = 1, @OutputServerName = '{4}', @OutputDatabaseName = '{5}', @OutputSchemaName = 'dbo', @OutputTableName = '{6}', @OutputXMLasNVARCHAR = 1"
"@ -f $serverUsername, $serverPassword, $serverInstance, $serverBlitzInDb, $OutputServerName, $OutputDatabaseName, $OutputTableName   

echo "--------------------------------------"
$command
echo "--------------------------------------"
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

echo "--------------------------------------"
$command
echo "--------------------------------------"
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
echo "results are logged to:  "$Logfile 
LogWrite ("Started at:  " + $(get-date -f yyyy-MM-dd-HHmmss))
$date1 = Get-Date

##
## Get variables from the settings.xml file 
##
$serverUsername01    = $ConfigFile.spblitz_automation.serverUsername01   
$serverUsername02    = $ConfigFile.spblitz_automation.serverUsername02   
$serverUsername03    = $ConfigFile.spblitz_automation.serverUsername03   
$serverUsername04    = $ConfigFile.spblitz_automation.serverUsername04   
$serverUsername05    = $ConfigFile.spblitz_automation.serverUsername05   
$serverUsername06    = $ConfigFile.spblitz_automation.serverUsername06   
$serverUsername07    = $ConfigFile.spblitz_automation.serverUsername07   
$serverUsername08    = $ConfigFile.spblitz_automation.serverUsername08   
$serverUsername09    = $ConfigFile.spblitz_automation.serverUsername09   
$serverUsername10    = $ConfigFile.spblitz_automation.serverUsername10   
$serverUsername11    = $ConfigFile.spblitz_automation.serverUsername11   
$serverUsername12    = $ConfigFile.spblitz_automation.serverUsername12   
$serverUsername13    = $ConfigFile.spblitz_automation.serverUsername13   
$serverUsername14    = $ConfigFile.spblitz_automation.serverUsername14   

$serverPassword01    = ""
$serverPassword02    = ""
$serverPassword03    = ""
$serverPassword04    = ""
$serverPassword05    = ""
$serverPassword06    = ""
$serverPassword07    = ""
$serverPassword08    = ""
$serverPassword09    = ""
$serverPassword10    = ""
$serverPassword11    = ""
$serverPassword12    = ""
$serverPassword13    = ""
$serverPassword14    = ""

$credentialsFile01   = $ConfigFile.spblitz_automation.credentialsFile01  
$credentialsFile02   = $ConfigFile.spblitz_automation.credentialsFile02  
$credentialsFile03   = $ConfigFile.spblitz_automation.credentialsFile03  
$credentialsFile04   = $ConfigFile.spblitz_automation.credentialsFile04  
$credentialsFile05   = $ConfigFile.spblitz_automation.credentialsFile05  
$credentialsFile06   = $ConfigFile.spblitz_automation.credentialsFile06  
$credentialsFile07   = $ConfigFile.spblitz_automation.credentialsFile07  
$credentialsFile08   = $ConfigFile.spblitz_automation.credentialsFile08  
$credentialsFile09   = $ConfigFile.spblitz_automation.credentialsFile09  
$credentialsFile10   = $ConfigFile.spblitz_automation.credentialsFile10  
$credentialsFile11   = $ConfigFile.spblitz_automation.credentialsFile11  
$credentialsFile12   = $ConfigFile.spblitz_automation.credentialsFile12  
$credentialsFile13   = $ConfigFile.spblitz_automation.credentialsFile13  
$credentialsFile14   = $ConfigFile.spblitz_automation.credentialsFile14  

$serverInstance01    = $ConfigFile.spblitz_automation.serverInstance01   
$serverInstance02    = $ConfigFile.spblitz_automation.serverInstance02   
$serverInstance03    = $ConfigFile.spblitz_automation.serverInstance03   
$serverInstance04    = $ConfigFile.spblitz_automation.serverInstance04   
$serverInstance05    = $ConfigFile.spblitz_automation.serverInstance05   
$serverInstance06    = $ConfigFile.spblitz_automation.serverInstance06   
$serverInstance07    = $ConfigFile.spblitz_automation.serverInstance07   
$serverInstance08    = $ConfigFile.spblitz_automation.serverInstance08   
$serverInstance09    = $ConfigFile.spblitz_automation.serverInstance09   
$serverInstance10    = $ConfigFile.spblitz_automation.serverInstance10   
$serverInstance11    = $ConfigFile.spblitz_automation.serverInstance11   
$serverInstance12    = $ConfigFile.spblitz_automation.serverInstance12   
$serverInstance13    = $ConfigFile.spblitz_automation.serverInstance13   
$serverInstance14    = $ConfigFile.spblitz_automation.serverInstance14   

$serverBlitzInDb01   = $ConfigFile.spblitz_automation.serverBlitzInDb01  
$serverBlitzInDb02   = $ConfigFile.spblitz_automation.serverBlitzInDb02  
$serverBlitzInDb03   = $ConfigFile.spblitz_automation.serverBlitzInDb03  
$serverBlitzInDb04   = $ConfigFile.spblitz_automation.serverBlitzInDb04  
$serverBlitzInDb05   = $ConfigFile.spblitz_automation.serverBlitzInDb05  
$serverBlitzInDb06   = $ConfigFile.spblitz_automation.serverBlitzInDb06  
$serverBlitzInDb07   = $ConfigFile.spblitz_automation.serverBlitzInDb07  
$serverBlitzInDb08   = $ConfigFile.spblitz_automation.serverBlitzInDb08  
$serverBlitzInDb09   = $ConfigFile.spblitz_automation.serverBlitzInDb09  
$serverBlitzInDb10   = $ConfigFile.spblitz_automation.serverBlitzInDb10  
$serverBlitzInDb11   = $ConfigFile.spblitz_automation.serverBlitzInDb11  
$serverBlitzInDb12   = $ConfigFile.spblitz_automation.serverBlitzInDb12  
$serverBlitzInDb13   = $ConfigFile.spblitz_automation.serverBlitzInDb13  
$serverBlitzInDb14   = $ConfigFile.spblitz_automation.serverBlitzInDb14  

$outputServerName    = $ConfigFile.spblitz_automation.outputServerName   
$outputServerServer  = $ConfigFile.spblitz_automation.outputServerServer 
$outputDatabaseName  = $ConfigFile.spblitz_automation.outputDatabaseName 
$outputServerUser    = $ConfigFile.spblitz_automation.outputServerUser   
$credentialsFileDest = $ConfigFile.spblitz_automation.credentialsFileDest
$outputTableName     = $ConfigFile.spblitz_automation.outputTableName    

$outputServerPass    = ""



LogWrite ("serverUsername01    :  " + $serverUsername01   )
LogWrite ("serverUsername02    :  " + $serverUsername02   )
LogWrite ("serverUsername03    :  " + $serverUsername03   )
LogWrite ("serverUsername04    :  " + $serverUsername04   )
LogWrite ("serverUsername05    :  " + $serverUsername05   )
LogWrite ("serverUsername06    :  " + $serverUsername06   )
LogWrite ("serverUsername07    :  " + $serverUsername07   )
LogWrite ("serverUsername08    :  " + $serverUsername08   )
LogWrite ("serverUsername09    :  " + $serverUsername09   )
LogWrite ("serverUsername10    :  " + $serverUsername10   )
LogWrite ("serverUsername11    :  " + $serverUsername11   )
LogWrite ("serverUsername12    :  " + $serverUsername12   )
LogWrite ("serverUsername13    :  " + $serverUsername13   )
LogWrite ("serverUsername14    :  " + $serverUsername14   )

LogWrite ("credentialsFile01   :  " + $credentialsFile01  )
LogWrite ("credentialsFile02   :  " + $credentialsFile02  )
LogWrite ("credentialsFile03   :  " + $credentialsFile03  )
LogWrite ("credentialsFile04   :  " + $credentialsFile04  )
LogWrite ("credentialsFile05   :  " + $credentialsFile05  )
LogWrite ("credentialsFile06   :  " + $credentialsFile06  )
LogWrite ("credentialsFile07   :  " + $credentialsFile07  )
LogWrite ("credentialsFile08   :  " + $credentialsFile08  )
LogWrite ("credentialsFile09   :  " + $credentialsFile09  )
LogWrite ("credentialsFile10   :  " + $credentialsFile10  )
LogWrite ("credentialsFile11   :  " + $credentialsFile11  )
LogWrite ("credentialsFile12   :  " + $credentialsFile12  )
LogWrite ("credentialsFile13   :  " + $credentialsFile13  )
LogWrite ("credentialsFile14   :  " + $credentialsFile14  )

LogWrite ("serverInstance01    :  " + $serverInstance01   )
LogWrite ("serverInstance02    :  " + $serverInstance02   )
LogWrite ("serverInstance03    :  " + $serverInstance03   )
LogWrite ("serverInstance04    :  " + $serverInstance04   )
LogWrite ("serverInstance05    :  " + $serverInstance05   )
LogWrite ("serverInstance06    :  " + $serverInstance06   )
LogWrite ("serverInstance07    :  " + $serverInstance07   )
LogWrite ("serverInstance08    :  " + $serverInstance08   )
LogWrite ("serverInstance09    :  " + $serverInstance09   )
LogWrite ("serverInstance10    :  " + $serverInstance10   )
LogWrite ("serverInstance11    :  " + $serverInstance11   )
LogWrite ("serverInstance12    :  " + $serverInstance12   )
LogWrite ("serverInstance13    :  " + $serverInstance13   )
LogWrite ("serverInstance14    :  " + $serverInstance14   )

LogWrite ("serverBlitzInDb01   :  " + $serverBlitzInDb01  )
LogWrite ("serverBlitzInDb02   :  " + $serverBlitzInDb02  )
LogWrite ("serverBlitzInDb03   :  " + $serverBlitzInDb03  )
LogWrite ("serverBlitzInDb04   :  " + $serverBlitzInDb04  )
LogWrite ("serverBlitzInDb05   :  " + $serverBlitzInDb05  )
LogWrite ("serverBlitzInDb06   :  " + $serverBlitzInDb06  )
LogWrite ("serverBlitzInDb07   :  " + $serverBlitzInDb07  )
LogWrite ("serverBlitzInDb08   :  " + $serverBlitzInDb08  )
LogWrite ("serverBlitzInDb09   :  " + $serverBlitzInDb09  )
LogWrite ("serverBlitzInDb10   :  " + $serverBlitzInDb10  )
LogWrite ("serverBlitzInDb11   :  " + $serverBlitzInDb11  )
LogWrite ("serverBlitzInDb12   :  " + $serverBlitzInDb12  )
LogWrite ("serverBlitzInDb13   :  " + $serverBlitzInDb13  )
LogWrite ("serverBlitzInDb14   :  " + $serverBlitzInDb14  )

LogWrite ("outputServerName    :  " + $outputServerName   )
LogWrite ("outputServerServer  :  " + $outputServerServer )
LogWrite ("outputDatabaseName  :  " + $outputDatabaseName )
LogWrite ("outputServerUser    :  " + $outputServerUser   )
LogWrite ("credentialsFileDest :  " + $credentialsFileDest)
LogWrite ("outputTableName     :  " + $outputTableName    )


##
## for all connections -- extract password for destination linked server  
##

$tryCredentialsFile = $MyDir+ "\" + $credentialsFileDest
$tryServerUsername  = $outputServerUser
$tryServerPassword  = $OutputServerPass
$OutputServerPass = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword


##
## serverinstance: 01  ##########################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile01
$tryServerUsername  = $serverUsername01
$tryServerPassword  = $serverPassword01
$serverPassword01 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername01
$serverPassword      =  $serverPassword01       
$serverInstance      =  $serverInstance01
$serverBlitzInDb     =  $serverBlitzInDb01

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 02  ##########################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile02
$tryServerUsername  = $serverUsername02
$tryServerPassword  = $serverPassword02
$serverPassword02 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername02
$serverPassword      =  $serverPassword02       
$serverInstance      =  $serverInstance02
$serverBlitzInDb     =  $serverBlitzInDb02

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 03 ####################################################################################################### 
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile03
$tryServerUsername  = $serverUsername03
$tryServerPassword  = $serverPassword03
$serverPassword03 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername03
$serverPassword      =  $serverPassword03       
$serverInstance      =  $serverInstance03
$serverBlitzInDb     =  $serverBlitzInDb03

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 04 #####################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile04
$tryServerUsername  = $serverUsername04
$tryServerPassword  = $serverPassword04
$serverPassword04 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername04
$serverPassword      =  $serverPassword04       
$serverInstance      =  $serverInstance04
$serverBlitzInDb     =  $serverBlitzInDb04

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 05  ##################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile05
$tryServerUsername  = $serverUsername05
$tryServerPassword  = $serverPassword05
$serverPassword05 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername05
$serverPassword      =  $serverPassword05       
$serverInstance      =  $serverInstance05
$serverBlitzInDb     =  $serverBlitzInDb05

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 06 ################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile06
$tryServerUsername  = $serverUsername06
$tryServerPassword  = $serverPassword06
$serverPassword06 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername06
$serverPassword      =  $serverPassword06       
$serverInstance      =  $serverInstance06
$serverBlitzInDb     =  $serverBlitzInDb06

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 07 ################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile07
$tryServerUsername  = $serverUsername07
$tryServerPassword  = $serverPassword07
$serverPassword07 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername07
$serverPassword      =  $serverPassword07       
$serverInstance      =  $serverInstance07
$serverBlitzInDb     =  $serverBlitzInDb07

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 08  #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile08
$tryServerUsername  = $serverUsername08
$tryServerPassword  = $serverPassword08
$serverPassword08 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername08
$serverPassword      =  $serverPassword08       
$serverInstance      =  $serverInstance08
$serverBlitzInDb     =  $serverBlitzInDb08

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 09 #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile09
$tryServerUsername  = $serverUsername09
$tryServerPassword  = $serverPassword09
$serverPassword09 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername09
$serverPassword      =  $serverPassword09       
$serverInstance      =  $serverInstance09
$serverBlitzInDb     =  $serverBlitzInDb09

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 

     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 10 #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile10
$tryServerUsername  = $serverUsername10
$tryServerPassword  = $serverPassword10
$serverPassword10 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername10
$serverPassword      =  $serverPassword10       
$serverInstance      =  $serverInstance10
$serverBlitzInDb     =  $serverBlitzInDb10

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 11 #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile11
$tryServerUsername  = $serverUsername11
$tryServerPassword  = $serverPassword11
$serverPassword11 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername11
$serverPassword      =  $serverPassword11       
$serverInstance      =  $serverInstance11
$serverBlitzInDb     =  $serverBlitzInDb11

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 12 #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile12
$tryServerUsername  = $serverUsername12
$tryServerPassword  = $serverPassword12
$serverPassword12 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername12
$serverPassword      =  $serverPassword12       
$serverInstance      =  $serverInstance12
$serverBlitzInDb     =  $serverBlitzInDb12

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 13 #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile13
$tryServerUsername  = $serverUsername13
$tryServerPassword  = $serverPassword13
$serverPassword13 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername13
$serverPassword      =  $serverPassword13       
$serverInstance      =  $serverInstance13
$serverBlitzInDb     =  $serverBlitzInDb13

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


##
## serverinstance: 14 #####################################################################################################################################
##

## extract password for this server instance
$tryCredentialsFile = $MyDir+ "\" + $credentialsFile14
$tryServerUsername  = $serverUsername14
$tryServerPassword  = $serverPassword14
$serverPassword14 = ExtractPassword -tryCredentialsFile $tryCredentialsFile -tryServerUsername $tryServerUsername -tryServerPassword $tryServerPassword

## other parameters form .XML file
$serverUsername      =  $serverUsername14
$serverPassword      =  $serverPassword14       
$serverInstance      =  $serverInstance14
$serverBlitzInDb     =  $serverBlitzInDb14

## build a temporary link back to outputServer
BuildTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputServerServer $OutputServerServer -OutputDatabaseName $OutputDatabaseName -OutputServerUser $OutputServerUser -OutputServerPass $OutputServerPass 
     
## run sp_blitz with @outputsername = $outputServerName and @tablename = $outputTableName == 'BlitzResults'
RunSpBlitz -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName -OutputDatabaseName $OutputDatabaseName -OutputTableName $OutputTableName    

## remove the temporary link to outputServer
RemoveTempLink -serverUsername $serverUsername -serverPassword $serverPassword -serverInstance $serverInstance -serverBlitzInDb $serverBlitzInDb -OutputServerName $OutputServerName 


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