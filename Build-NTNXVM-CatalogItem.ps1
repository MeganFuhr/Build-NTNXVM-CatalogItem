begin{
	$VMName = ""
    
#Certificate information to call Nutanix Prism API
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
    ServicePoint srvPoint, X509Certificate certificate,
    WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Forcing PoSH to use TLS1.2 as it defaults to 1.0 and Prism requires 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cred = Get-Cred
$Header = @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($cred.username+":"+$cred.password ))}
$PrismCentral = "PrismCentral.YourCompany.com"
$BuildCluster = "Cluster.YourCompany.com"
$NutanixHostingConnection = Get-Content -Path "\\path\to\your\cluster\list.txt"
$allNutanixVMs = @()

#get all nutanix VMS across all the clusters. Create a custom object to include the cluster name
foreach ($connection in $NutanixHostingConnection) {

	$NTNXVMsUri = "https://$($connection):9440/PrismGateway/services/rest/v2.0/vms"

	$NTNXVMs = (Invoke-RestMethod -Method Get -Uri $NTNXVMsUri -Headers $Header).entities

		foreach ($item in $NTNXVMs) {
			$temp = New-Object psobject -Property @{
				VMName = $item.name
				VMUUID = $item.uuid
				HostingConnection = $connection
			   }
			 $allNutanixVMs += $temp
		} 
}

if ($allNutanixVMs.vmname -contains $VMName) {
    Write-Host "$VMName Nutanix object already exists on another cluster."
    $LastExitCode = 1
    exit $LASTEXITCODE
}


$VMCreatePayload = @"
{
  "metadata": {
    "project_reference": {
      "uuid": "{{UUID for Project}}",
      "kind": "project"
    },
    "categories_mapping": {},
    "kind": "vm",
    "use_categories_mapping": true
  },
  "spec": {
    "name": "$VMname",
    "resources": {
      "memory_size_mib": 8192,
      "boot_config": {
        "boot_type": "LEGACY",
        "boot_device_order_list": [
          "CDROM",
          "DISK",
          "NETWORK"
        ]
      },
      "disk_list": [
        {
          "device_properties": {
            "device_type": "CDROM",
            "disk_address": {
              "adapter_type": "IDE",
              "device_index": 0
            }
          },
          "disk_size_mib": 560
        },
        {
          "device_properties": {
            "device_type": "DISK",
            "disk_address": {
              "adapter_type": "SCSI",
              "device_index": 0
            }
          },
          "disk_size_mib": 61440
        }
      ],
      "power_state": "ON",
      "num_vcpus_per_socket": 2,
      "num_sockets": 2,
      "hardware_clock_timezone": "America/Denver",
      "power_state_mechanism": {
        "mechanism": "HARD"
      },
      "nic_list": [
        {
          "subnet_reference": {
            "uuid": "{{UUID of Subnet}}",
            "kind": "subnet"
          },
          "ip_endpoint_list": [],
          "is_connected": true,
          "uuid": "{{UUID}}"
        }
      ],
      "parent_reference": {
        "kind": "vm_recovery_point",
        "uuid": "{{UUID}}"
      }
    }
  },
  "api_version": "3.1.0"
}
"@


}
Process {
	#Create VM via Prism Central v3 API
    $PrismCentralURI = "https://$($PrismCentral):9440/api/nutanix/v3/vms"
	$Response = Invoke-RestMethod -Method POST -Uri $PrismCentralURI -Headers $Header -ContentType 'application/json' -Body $VMCreatePayload
}

end {
	#Create new URI for tasks
	$taskURI = "https://$($PrismCentral):9440/api/nutanix/v3/tasks"
	
	#Get the status of the task
	$responseStatus = Invoke-RestMethod -Method GET -URI "$taskURI/$($response.status.execution_context.task_uuid)" -Headers $header -ContentType 'application/json'

	#wait while the VM finishes building
	While (($reponseStatus.status -eq "PENDING") -or ($responseStatus.Status -eq "RUNNING")){
		$responseStatus = Invoke-RestMethod -Method GET -URI "$taskURI/$($response.status.execution_context.task_uuid)" -Headers $header -ContentType 'application/json'
	}

#Pull info about the VM once completed building
$VMSPec = Invoke-RestMethod -Method GET -Uri "$PrismCentralURI/$($response.metadata.uuid)" -Headers $Header -ContentType 'application/json'

#Update the timezone and remove Status from the response
$VMSPec.spec.resources.hardware_clock_timezone = "America/Denver"
$VMSpec = $VMSPec | Select-Object * -ExcludeProperty status

#Convert to json with a depth of 6
$VMSpec = $VMSPec | convertto-Json -Depth 6

#Update the VM with the correct timezone
$UpdateResponse = Invoke-RestMethod -Method PUT -Uri "$PrismCentralURI/$($response.metadata.uuid)" -Headers $Header -ContentType 'application/json' -Body $VMSpec

}