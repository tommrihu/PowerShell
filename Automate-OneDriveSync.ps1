$Steps = 11
$Step = 1
Write-Progress -Activity "Start Logging" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Start logging
$LogPath = $($env:localappdata) + "\Temp\OneDrive.log"
Start-Transcript $LogPath
#endregion

Write-Progress -Activity "Getting UPN" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region UPN
#Getting UPN for logon user for SPO document library
$User = $(whoami /upn)
#endregion

Write-Progress -Activity "Defining settings" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Defining SPO library, OD name, OD Tenant
$ODTenant = "" #OneDrive tenant name of SPO

$AllToStop = "","" #Nameparts of the current synced SPO document library where the sync should be stopped

$AllToSync = @{
    SPOODName = "" #Name of SPO document library
    SPOODLink = "" #Copied from SPO-Sync popup "Copy this Library-ID"
    GroupMatch = "" #Part of the groupmembership name - If the user is part of the group the sync will start
},@{
    SPOODName = "" #Name of SPO document library
    SPOODLink = "" #Copied from SPO-Sync popup "Copy this Library-ID"
    GroupMatch = "" #Part of the groupmembership name - If the user is part of the group the sync will start
},@{
    SPOODName = "" #Name of SPO document library
    SPOODLink = "" #Copied from SPO-Sync popup "Copy this Library-ID"
    GroupMatch = "" #Part of the groupmembership name - If the user is part of the group the sync will start
}
#endregion

Write-Progress -Activity "Check if an update is running" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Waiting for update to complete
While(Get-Process *OneDrive*Update*){
    Write-Host "Update is running - waiting"
    Start-Sleep 1
}
Start-Sleep 10
#endregion

Write-Progress -Activity "Loading function Stop-OD" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Function for stopping OneDrive process
Function Stop-OD {
    $ODProc = Get-Process OneDrive -ErrorAction SilentlyContinue
    If($ODProc){
        Stop-Process -Id $ODProc.Id
    }Else{
        Write-Output "No OneDrive process found"
    }
}
#endregion

Write-Progress -Activity "Loading function Get-RegPropValue" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Function for building mountpoint information
Function Get-RegPropValue {
    Param([Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
        $RegPath
    )
    $MPObjects = @()
    $MountPoints = (Get-Item $RegPath).property

    ForEach($MountPoint in $MountPoints){
        $Prop = @{
            MPID = $($MountPoint)
            MPPath = $((Get-ItemProperty -Path $RegPath -Name $MountPoint).$MountPoint)
        }
        $MPObjects += New-Object -TypeName psobject -Property $Prop
    }
    return $MPObjects
}
#endregion

Write-Progress -Activity "Stop syncing of old libraries" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Stop syncing of old SPO document libraries
$MPRegPath = "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1\ScopeIdToMountPointPathCache"
$MPPathReg = "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1\Tenants\$ODTenant"
$MPPathSync = "HKCU:\Software\SyncEngines\Providers\OneDrive\"
$ODUserID = (Get-Item "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1").GetValue("cid")
$ConfigPath = $($env:localappdata) + "\Microsoft\OneDrive\settings\Business1\"
$INIPath = $ConfigPath + $ODUserID + ".ini"
$sum = $AllToStop.Count
$i = 1
ForEach($ToStop in $AllToStop){
    Write-Progress -Activity "Stop syncing of > $ToStop < library" -Status "Progress:" -PercentComplete ($i/$sum*100) -Id 2 -ParentId 1
    $i++
    Start-Sleep 1
    If(((Get-Item "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1\Tenants\$ODTenant").property) -like "*$ToStop*"){
        Write-Output "Old SPO document library found - $ToStop found - stop sync"
        $MPID = (Get-RegPropValue -RegPath $MPRegPath | Where-Object {$_.MPPath -like "*$ToStop*"}).MPID
        $MPPath = (Get-RegPropValue -RegPath $MPRegPath | Where-Object {$_.MPPath -like "*$ToStop*"}).MPPath
        If($MPID){
            Write-Output "Mount point found for $ToStop"
            Stop-OD
            $INIData = Get-Content $INIPath -Encoding Unicode
            $INIData | Where-Object {$_ -notlike "*$MPID*"} | Set-Content $INIPath -Encoding Unicode
            Remove-ItemProperty -Path $MPRegPath -Name $MPID
            Remove-ItemProperty -Path $MPPathReg -Name $MPPath
            $PolicyFileMatch = (Get-RegPropValue -RegPath "HKCU:\Software\SyncEngines\Providers\OneDrive\$MPID" | Where-Object {$_.MPID -like "*UrlNamespace*"}).MPPath
            $PolicyFiles = Get-ChildItem $ConfigPath | Where-Object {$_.Name -like "*ClientPolicy_*.ini"}
            ForEach($PolicyFile in $PolicyFiles){
                If(Get-Content $PolicyFile.FullName -Encoding Unicode | Where-Object {$_ -like "*$PolicyFileMatch*"}){
                   Remove-Item $PolicyFile.FullName
                }
            }
            Remove-Item -Path "$MPPathSync$MPID"
            #region Remove a stopped sync folder on filesystem
            $ACL = Get-Acl $MPPath
            ForEach($Access in $ACL.Access){
                If($Access.IdentityReference -like "*Jeder*"#Everyone for English){
                    $ACL.RemoveAccessRule($Access) | Out-Null
                }
            }
            Set-Acl -Path $MPPath -AclObject $ACL
            $AllItems = Get-ChildItem $MPPath -Recurse
            $sum2 = $AllItems.Count + 1
            $i2 = 1
            ForEach($DelItem in $AllItems){
                Write-Progress -Activity "Setting ACL to files of sync-stopped > $ToStop < library" -Status "Progress:" -PercentComplete ($i2/$sum2*100) -Id 3 -ParentId 2
                Set-Acl $DelItem.FullName -AclObject $ACL
                $i2++
            }
            Write-Progress -Activity "Removing files of sync-stopped > $ToStop < library" -Status "Progress:" -PercentComplete ($i2/$sum2*100) -Id 3 -ParentId 2
            Remove-Item $MPPath -Recurse -Force
            #endregion
        }Else{
            Write-Output "No mount point found for $ToStop"
        }
    }Else{
        Write-Output "old SPO document library $ToStop not found"
    }
}
#endregion

Write-Progress -Activity "Start OneDrive" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Start OneDrive
$ODStartExe = $($env:localappdata) + "\Microsoft\OneDrive\OneDrive.exe"
$Arguments = "/background"
Start-Process $ODStartExe -ArgumentList $Arguments
Start-Sleep 10
#endregion

Write-Progress -Activity "Start syncing of new libraries" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Start syncing
#Check if OneDrive Personal was set up
Write-Progress -Activity "Checking OD user config" -Status "Progress:" -PercentComplete (1/2*100) -Id 2 -ParentId 1
Start-Sleep 1
If(Test-Path "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1\Tenants\OneDrive - $ODTenant") {
    Write-Output "user config found"
    #Check after OneDrive Personal was set up if at least one SPO document library was synced for the specified tenant
    Write-Progress -Activity "Checking OD company config" -Status "Progress:" -PercentComplete (2/2*100) -Id 2 -ParentId 1
    Start-Sleep 1
    If(Test-Path "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1\Tenants\$ODTenant"){
        #Check after OneDrive for Business has already synced SPO document libraries if there are at least the required ones are synced
        Write-Output "user config found - company config found"
        #Check what is already synced
        $sum3 = $AllToSync.Count
        $i3 = 1
        ForEach($ToSync in $AllToSync){
            Write-Progress -Activity "Starting sync of > $ToSync.SPOODName <" -Status "Progress:" -PercentComplete ($i3/$sum3*100) -Id 3 -ParentId 2
            $i3++
            Start-Sleep 1
            $FinalCommand = "odopen://sync/?" + $($ToSync.SPOODLink) + "&userEmail=" + $User + "&webTitle=" + $($ToSync.SPOODName) + "&listTitle=Dokumente"
            If(!(((Get-Item "HKCU:\Software\Microsoft\OneDrive\Accounts\Business1\Tenants\$ODTenant").property) -like "*$($ToSync.SPOODName)*")){
                Write-Output "user config found - company config found - $($ToSync.SPOODName) not found - checking group match"
                If(whoami /groups | Where-Object {$_ -like "*$($ToSync.GroupMatch)*"}){
                    Write-Output "user config found - company config found - $($ToSync.SPOODName) not found - group match - start sync"
                    Start-Process $FinalCommand -Wait
                    Start-Sleep 5
                }Else{
                    Write-Output "User it not part of the $($ToSync.GroupMatch) security group - not syncing $($ToSync.SPOODName)"
                }
            }Else{
                Write-Output "user config found - company config found - $($ToSync.SPOODName) found"
            }
        }
    }Else{
    #As its nothing synced all synces will triggered
        Write-Output "user config found - company config not found - connect all"
        $sum3 = $AllToSync.Count
        $i3 = 1
        ForEach($ToSync in $AllToSync){
            Write-Progress -Activity "Starting sync of > $ToSync.SPOODName <" -Status "Progress:" -PercentComplete ($i3/$sum3*100) -Id 3 -ParentId 2
            $i3++
            Start-Sleep 1
            $FinalCommand = "odopen://sync/?" + $($ToSync.SPOODLink) + "&userEmail=" + $User + "&webTitle=" + $($ToSync.SPOODName) + "&listTitle=Dokumente"
            If(whoami /groups | Where-Object {$_ -like "*$($ToSync.GroupMatch)*"}){
                Start-Process $FinalCommand -Wait
                Start-Sleep 5
            }Else{
                Write-Output "User it not part of the $($ToSync.GroupMatch) security group"
            }
        }
    }
}Else{
    Write-Output "user config not found - waiting for silent setup"
}
#endregion

Write-Progress -Activity "Stop Logging" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
#region Stop logging
Stop-Transcript
#endregion

Write-Progress -Activity "Done" -Status "Progress:" -PercentComplete ($Step/$Steps*100) -Id 1
$Step++
Start-Sleep 1
