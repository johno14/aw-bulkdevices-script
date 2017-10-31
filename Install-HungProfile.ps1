<#
.SYNOPSIS
  Checks install status of selected profile on a list of devices and if pending or errored sends an install command
.DESCRIPTION
  To do: provide better feedback/more options, choose platform first to eliminate errors selecting profiles with the exact same name.
  .INPUTS
  AirWatchConfig.json
  Serials.csv
.OUTPUTS
  NO OUTPUT CURRENTLY:Outputs a CSV log of actions
.NOTES
  Version:        1.2
  Author:         Joshua Clark @audioeng
  Creation Date:  10/27/2017
  Site:           https://github.com/audioeng/aw-bulkdevices-script
.EXAMPLE
  Install-HungProfile.ps1
#>



Function Read-Config {
    try {
        if (Test-Path "AirWatchConfig.json") {
            $h = (Get-Content "AirWatchConfig.json") -join "`n" | ConvertFrom-Json
            Write-Verbose "Config file loaded."
        } else {
            Write-Verbose "No config file exists, please complete the sample config and name the file AirWatchConfig.json "
            Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor Black -BackgroundColor Red
            Write-Host "No config file exists, please complete the sample config and name the file AirWatchConfig.json " -ForegroundColor Black -BackgroundColor Red
            Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor Black -BackgroundColor Red
        }
        if ($h.groupid -and $h.awtenantcode -and $h.host) {
            Write-Verbose "Config file formatted correctly."
            return $h
        } else {
            Write-Verbose "ConfigFile not correct, please complete the sample config and name the file AirWatchConfig.json"
            Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor Black -BackgroundColor Red
            Write-Host "ConfigFile not correct, please complete the sample config and name the file AirWatchConfig.json" -ForegroundColor Black -BackgroundColor Red
            Write-Host "-----------------------------------------------------------------------------------------------" -ForegroundColor Black -BackgroundColor Red
        }
    }
    catch {
        Write-Verbose "No config file exists, please complete the sample config and name the file AirWatchConfig.json"
        Write-Host "No config file exists, please complete the sample config and name the file AirWatchConfig.json"
    }
}

<#  This implementation uses Basic authentication. #>
Function Get-BasicUserForAuth {
    $Credential = Get-Credential
    $EncodedUsernamePassword = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($('{0}:{1}' -f $Credential.UserName,$Credential.GetNetworkCredential().Password)))
    
    Return "Basic " + $EncodedUsernamePassword
}

Function Read-Serials {
    if (Test-Path "Serials.csv") {
        Write-Verbose "Serials.csv exists, importing list."
        $data = Import-Csv -Path Serials.csv
        $s = @()
        foreach ($device in $data) {
            $s += $device.SerialNumber
            Write-Verbose $device.SerialNumber
        }
        return $s
    } else {
        Write-Verbose "Serials.csv does not exist."
        Write-Host "--------------------------------------------------------------------------------------" -ForegroundColor Black -BackgroundColor Red
        Write-Host "      No Serials.csv file exists, please place file in same directory as script.      " -ForegroundColor Black -BackgroundColor Red
        Write-Host "--------------------------------------------------------------------------------------" -ForegroundColor Black -BackgroundColor Red
    }
    
}

Function Build-Headers {

    Param([string]$authoriztionString, [string]$tenantCode, [string]$acceptType, [string]$contentType)

    $authString = $authoriztionString
    $tcode = $tenantCode
    $accept = $acceptType
    $content = $contentType

    Write-Verbose("---------- Headers ----------")
    Write-Verbose("Authorization: " + $authString)
    Write-Verbose("aw-tenant-code:" + $tcode)
    Write-Verbose("Accept: " + $accept)
    Write-Verbose("Content-Type: " + $content)
    Write-Verbose("------------------------------")
    Write-Verbose("")
    $header = @{"Authorization" = $authString; "aw-tenant-code" = $tcode; "Accept" = $useJSON; "Content-Type" = $useJSON}
     
    Return $header
}

Function Get-Profiles {
    Param([string]$GroupID)
    $endpointURL = "https://${airwatchServer}/api/mdm/profiles/search?organizationgroupid=${GroupID}"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $headers
    $Array = New-Object System.Collections.Hashtable
    foreach ($profile in $webReturn.Profiles) {
        $Array.Add($profile.ProfileName, $profile.Id.Value)
    }
    return $Array
}

Function Get-OrgGroups {
    $endpointURL = "https://${airwatchServer}/api/system/groups/search?orderby=name"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $headers
    $OrgArray = New-Object System.Collections.Hashtable
    foreach ($org in $webReturn.LocationGroups) {
        $OrgArray.Add($org.Name, $org.Id.Value)
    }
    return $OrgArray
}

Function Select-Tag {
    Param([object]$TagList)

    $selection = $null
    
    Do
    {
        $mhead
        Write-Host # empty line
        $TagArr = @()
        $i=0
        foreach($tag in $TagList.keys)
        {
            Write-Host -ForegroundColor Cyan "  $($i+1)." $tag
            $TagArr += $tag
            $i++
        }
        Write-Host # empty line
        $ans = (Read-Host 'Please enter selection') -as [int]
    
    } While ((-not $ans) -or (0 -gt $ans) -or ($TagList.Count -lt $ans))
    
    $selection = $ans-1
    $selectedTag = $TagArr[$selection]
    return $TagList.$selectedTag
}

Function Get-Device {
    Param([string]$lastseen, [string]$lgid)


    $endpointURL = "https://${airwatchServer}/api/mdm/devices/search?lastseen=${lastseen}&lgid=${lgid}&orderby=lastseen&sortorder=DESC"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $headers
    return $webReturn.Devices
}

<#  This function builds the JSON to add the tag to all of the devices. #>
Function Set-AddTagJSON {

    Param([Array]$deviceList)
    
    Write-Verbose("------------------------------")
    Write-Verbose("Building JSON to Post")
    
    $arrayLength = $deviceList.Count
    $counter = 0
    $quoteCharacter = [char]34

    $addTagJSON = "{ " + $quoteCharacter + "BulkValues" + $quoteCharacter + " : { " + $quoteCharacter + "Value" + $quoteCharacter + " : [ "
    foreach ($currentDeviceID in $deviceList) {
        $deviceIDString = Out-String -InputObject $currentDeviceID
        $deviceIDString = $deviceIDString.Trim()
    
        $counter = $counter + 1
        if ($counter -lt $arrayLength) {
            $addTagJSON = $addTagJSON + $quoteCharacter + $deviceIDString + $quoteCharacter + ", "
        } else {
            $addTagJSON = $addTagJSON + $quoteCharacter + $deviceIDString + $quoteCharacter
        }
    }
    $addTagJSON = $addTagJSON + " ] } }"
    
    Write-Verbose($addTagJSON)
    Write-Verbose("------------------------------")
    Write-Verbose("")
        
    Return $addTagJSON
}

Function Get-DeviceDetails {
    Param([string]$addTagJSON)
    try {
        $endpointURL = "https://${airwatchServer}/api/mdm/devices/id"
        $webReturn = Invoke-RestMethod -Method Post -Uri $endpointURL -Headers $headers -Body $addTagJSON
       
        return $webReturn.Devices
    }
    catch {
        Write-Host "Error retrieving device details. May not be any devices with the selected tag."
    }

}

Function Set-DeviceIdList {
    Param([object]$Devices)
    $s = @()
    foreach ($device in $Devices) {
        $s += $device.Id.Value
        Write-Verbose $device.Id.Value
    }
    return $s
}

Function Remove-DevicesFromManagement { # Enterprise Wipes List of devices by device id
    Param([string]$addTagJSON)
    try {
        $endpointURL = "https://${airwatchServer}/api/mdm/devices/commands/bulk?command=enterprisewipe&searchby=deviceid"
        $webReturn = Invoke-RestMethod -Method Post -Uri $endpointURL -Headers $headers -Body $addTagJSON
       
        return $webReturn
    }
    catch {
        Write-Host "Error retrieving device details. May not be any devices with that device id."
    }

}

Function Set-DaysPrior {
    do {
        try {
            $numOk = $true
            [int]$days = Read-Host -Prompt "Input how many days since the devices were last seen"
            } # end try
        catch {$numOK = $false}
        } # end do 
    until (($days -ge 1 -and $days -lt 100) -and $numOK)
    return 0-$days
}

Function Set-LastSeenDate {
    Param([int]$days)
    $date = Get-Date
    $lastseendate = $date.AddDays($days)
    $ls = Get-Date -Date $lastseendate -Format "yyyy-MM-dd"
    return $ls
}

Function Check-Devices {
    Param([array]$devices, $profile)
    $body = ""
    $quoteCharacter = [char]34
    foreach ($deviceid in $devices) {
        try {
            $endpointURL = "https://${airwatchServer}/api/mdm/devices/profiles?searchBy=Serialnumber&id=$deviceid"
            $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $headers 
            if ($webReturn) {
                $r = $webReturn.DeviceProfiles | where { $_.Id.Value -eq $profile}
                if ($r.Status -eq 1) {
                    $devid = $webReturn.DeviceId.Id.Value
                    $endpointURL2 = "https://${airwatchServer}/api/mdm/profiles/$profile/install"
                    $body = "{ " + $quoteCharacter + "SerialNumber" + $quoteCharacter + " : " + $quoteCharacter + $deviceid + $quoteCharacter +" }"
                    $webReturn2 = Invoke-RestMethod -Method Post -Uri $endpointURL2 -Headers $headers -Body $body
                    Write-Host $devid  "  install queued   " + $webReturn2
                } elseif ($r.Status -eq 3) {
                    Write-Host $webReturn.DeviceId.Id.Value profile already installed.
                } elseif ($r.Status -eq 6) {
                    $endpointURL2 = "https://${airwatchServer}/api/mdm/profiles/$profile/install"
                    $body = "{ " + $quoteCharacter + "SerialNumber" + $quoteCharacter + " : " + $quoteCharacter + $deviceid + $quoteCharacter +" }"
                    $webReturn2 = Invoke-RestMethod -Method Post -Uri $endpointURL2 -Headers $headers -Body $body
                    Write-Host $devid  "  Previous Error, install queued   " + $webReturn2
                }
            }
        }
        catch {
            $e = [int]$Error[0].Exception.Response.StatusCode
            Write-Host "Error with device $deviceid. Status code $e. May not be any devices with that serial."
        }
    }
}
<#
Start of Script
#>

<# Set configurations #>
$devicelist = Read-Serials
$restUserName = Get-BasicUserForAuth
$Config = Read-Config
$tenantAPIKey = $Config.awtenantcode
$organizationGroupID = $Config.groupid
$airwatchServer = $Config.host

<# Build the headers and send the request to the server. #>
$useJSON = "application/json"
$headers = Build-Headers $restUserName $tenantAPIKey $useJSON $useJSON
$OrgGroups = Get-OrgGroups
$GroupID = Select-Tag $OrgGroups
$ProfileList = Get-Profiles $GroupID[1]
$ProfileSelected = Select-Tag $ProfileList

$results = Check-Devices $devicelist $ProfileSelected[1]



#$DeviceList = Set-DeviceIdList $Devices
#$DeviceJSON = Set-AddTagJSON $DeviceList
#$DeviceDetails = Get-DeviceDetails $DeviceJSON
#$DeviceDetails | Export-Csv -Path "DevicesLastSeen${LastSeenDate}.csv"
<# Start API calls 

$Devices = Get-Device $SelectedTag
$DeviceJSON = Set-AddTagJSON $Devices
$DeviceDetails = Get-DeviceDetails $DeviceJSON
$DeviceDetails | Export-Csv -Path "${TagName}.csv"
Write-Host "All Devices with ${TagName} saved to ${TagName}.csv"
#>