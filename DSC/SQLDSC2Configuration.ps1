Configuration Main
{

Param ( [string] $nodeName )

Import-DscResource -ModuleName PSDesiredStateConfiguration

Node $nodeName
  {
    Script ConfigureSql
    {
        TestScript = {
            return $false
        }
        SetScript ={
		$disks = Get-Disk | Where partitionstyle -eq 'raw' 
		if($disks -ne $null)
		{
		# Create a new storage pool using all available disks 
		New-StoragePool –FriendlyName "VMStoragePool" `
				–StorageSubsystemFriendlyName "Windows Storage*" `
				–PhysicalDisks (Get-PhysicalDisk –CanPool $True)

		# Return all disks in the new pool
		$disks = Get-StoragePool –FriendlyName "VMStoragePool" `
					-IsPrimordial $false | 
					Get-PhysicalDisk

		# Create a new virtual disk 
		New-VirtualDisk –FriendlyName "DataDisk" `
				-ResiliencySettingName Simple `
						–NumberOfColumns $disks.Count `
						–UseMaximumSize –Interleave 256KB `
						-StoragePoolFriendlyName "VMStoragePool" 

		# Format the disk using NTFS and mount it as the F: drive
		Get-Disk | 
			Where partitionstyle -eq 'raw' |
			Initialize-Disk -PartitionStyle MBR -PassThru |
			New-Partition -DriveLetter "F" -UseMaximumSize |
	Format-Volume -FileSystem NTFS -NewFileSystemLabel "DataDisk" -Confirm:$false

		Start-Sleep -Seconds 60

		$logs = "F:\Logs"
		$data = "F:\Data"
		$backups = "F:\Backup" 
		[system.io.directory]::CreateDirectory($logs)
		[system.io.directory]::CreateDirectory($data)
		[system.io.directory]::CreateDirectory($backups)
		[system.io.directory]::CreateDirectory("C:\SQDATA")

	# Setup the data, backup and log directories as well as mixed mode authentication
	Import-Module "sqlps" -DisableNameChecking
	[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
	$sqlesq = new-object ('Microsoft.SqlServer.Management.Smo.Server') Localhost
	$sqlesq.Settings.LoginMode = [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed
	$sqlesq.Settings.DefaultFile = $data
	$sqlesq.Settings.DefaultLog = $logs
	$sqlesq.Settings.BackupDirectory = $backups
	$sqlesq.Alter() 

	# Enable TCP Server Network Protocol
	$smo = 'Microsoft.SqlServer.Management.Smo.'  
	$wmi = new-object ($smo + 'Wmi.ManagedComputer').  
	$uri = "ManagedComputer[@Name='" + (get-item env:\computername).Value + "']/ServerInstance[@Name='MSSQLSERVER']/ServerProtocol[@Name='Tcp']"  
	$Tcp = $wmi.GetSmoObject($uri)  
	$Tcp.IsEnabled = $true  
	$Tcp.Alter() 

	# Restart the SQL Server service
	Restart-Service -Name "MSSQLSERVER" -Force
	# Re-enable the sa account and set a new password to enable login
	Invoke-Sqlcmd -ServerInstance Localhost -Database "master" -Query "ALTER LOGIN sa ENABLE"
	Invoke-Sqlcmd -ServerInstance Localhost -Database "master" -Query "ALTER LOGIN sa WITH PASSWORD = 'demo@pass123'"

	New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound –Protocol TCP –LocalPort 1433 -Action allow 
	New-NetFirewallRule -DisplayName "SQL AG Endpoint" -Direction Inbound –Protocol TCP –LocalPort 5022 -Action allow 
	New-NetFirewallRule -DisplayName "SQL AG Load Balancer Probe Port" -Direction Inbound –Protocol TCP –LocalPort 59999 -Action allow 

	#Add local administrators group as sysadmin
	Invoke-Sqlcmd -ServerInstance Localhost -Database "master" -Query "CREATE LOGIN [BUILTIN\Administrators] FROM WINDOWS"
	Invoke-Sqlcmd -ServerInstance Localhost -Database "master" -Query "ALTER SERVER ROLE sysadmin ADD MEMBER [BUILTIN\Administrators]"

	}
  }
        GetScript = {@{Result = "ConfigureSql"}}
}



  }
}