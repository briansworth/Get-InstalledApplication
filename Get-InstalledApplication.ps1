<#
.SYNOPSIS
Get installed applications on local and / or remote computer(s).

.DESCRIPTION
Get installed applications on local and / or remote computer(s). 

.PARAMETER ComputerName
The computer name(s) to query for installed applications.

.PARAMETER Properties
The properties to include when querying the registry keys for installed applications.

.PARAMETER IdentifyingNumber
The application Id for a given application. Generally in the form of a GUID. 

.PARAMETER Name
The name of the application to search for.  Wildcards are accepted.

.PARAMETER Publisher
Search for applications from a specific publisher. Wildcards are accepted.

.EXAMPLE
Get-InstalledApplication

Description
-----------
Get full list of installed applications on the local system.

.EXAMPLE
Get-InstalledApplication -ComputerName Workstation01 -Name "Google Chrome"

Description
-----------
Search for applications named Google Chrome on Workstation01

.EXAMPLE
Get-InstalledApplication -ComputerName Server1, Server2 -Publisher 'Microsoft*'

Description
-----------
Search for all applications on Server1 & Server2 where the publisher name begins with 'Microsoft'.

.EXAMPLE
Get-InstalledApplication -ComputerName Server1, Server2 -Name '7-zip*' -Properties DisplayVersion, UninstallString, InstallDate

Description
-----------
Search for applications on Server1 & Server2, where the name starts with 7-zip. 
Also include the properties DisplayVersion, UninstallString, & InstallDate if they exist.

.EXAMPLE
Get-InstalledApplication -ComputerName server1,server2,server3 -IdentifyingNumber {5FCE6D76-F5DC-37AB-B2B8-22AB8CEDB1D4} -Properties *

Description
-----------
Search for an application with an ID of 5FCE6D76-F5DC-37AB-B2B8-22AB8CEDB1D4 on Server1, Server2, & Server3. 
Include all available properties.
#>
Function Get-InstalledApplication {
  [CmdletBinding()]
  Param(
    [Parameter(
      Position=0,
      ValueFromPipeline=$true,
      ValueFromPipelineByPropertyName=$true
    )]
    [String[]]$ComputerName=$ENV:COMPUTERNAME,

    [Parameter(Position=1)]
    [String[]]$Properties,

    [Parameter(Position=2)]
    [String]$IdentifyingNumber,

    [Parameter(Position=3)]
    [String]$Name,

    [Parameter(Position=4)]
    [String]$Publisher
  )
  Begin{
    Function IsCpuX86 ([Microsoft.Win32.RegistryKey]$hklmHive){
      $regPath='SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
      $key=$hklmHive.OpenSubKey($regPath)

      $cpuArch=$key.GetValue('PROCESSOR_ARCHITECTURE')

      if($cpuArch -eq 'x86'){
        return $true
      }else{
        return $false
      }
    }
  }
  Process{
    foreach($computer in $computerName){
      $regPath = @(
        'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
      )

      Try{
        $hive=[Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey(
          [Microsoft.Win32.RegistryHive]::LocalMachine, 
          $computer
        )
        if(!$hive){
          continue
        }
        
        # if CPU is x86 do not query for Wow6432Node
        if($IsCpuX86){
          $regPath=$regPath[0]
        }

        foreach($path in $regPath){
          $key=$hive.OpenSubKey($path)
          if(!$key){
            continue
          }
          foreach($subKey in $key.GetSubKeyNames()){
            $subKeyObj=$null
            if($PSBoundParameters.ContainsKey('IdentifyingNumber')){
              if($subKey -ne $IdentifyingNumber -and 
                $subkey.TrimStart('{').TrimEnd('}') -ne $IdentifyingNumber){
                continue
              }
            }
            $subKeyObj=$key.OpenSubKey($subKey)
            if(!$subKeyObj){
              continue
            }
            $outHash=New-Object -TypeName Collections.Hashtable
            $appName=[String]::Empty
            $appName=($subKeyObj.GetValue('DisplayName'))
            if($PSBoundParameters.ContainsKey('Name')){
              if($appName -notlike $name){
                continue
              }
            }
            if($appName){
              if($PSBoundParameters.ContainsKey('Properties')){
                if($Properties -eq '*'){
                  foreach($keyName in ($hive.OpenSubKey("$path\$subKey")).GetValueNames()){
                    Try{
                      $value=$subKeyObj.GetValue($keyName)
                      if($value){
                        $outHash.$keyName=$value
                      }
                    }Catch{
                      Write-Warning "Subkey: [$subkey]: $($_.Exception.Message)"
                      continue
                    }
                  }
                }else{
                  foreach ($prop in $Properties){
                    $outHash.$prop=($hive.OpenSubKey("$path\$subKey")).GetValue($prop)
                  }
                }
              }
              $outHash.Name=$appName
              $outHash.IdentifyingNumber=$subKey
              $outHash.Publisher=$subKeyObj.GetValue('Publisher')
              if($PSBoundParameters.ContainsKey('Publisher')){
                if($outHash.Publisher -notlike $Publisher){
                  continue
                }
              }
              $outHash.ComputerName=$computer
              $outHash.Path=$subKeyObj.ToString()
              New-Object -TypeName PSObject -Property $outHash
            }
          }
        }
      }Catch{
        Write-Error $_
      }
    }
  }
  End{}
}
