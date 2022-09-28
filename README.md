# 3CX-Azure-Deployment-PS1

Easiest way to execute this script is from PowerShell ISE.
Open in ISE and define parameters:

#______________________________________________________________________________________________________________________________________
$rgName 	    	= "3cx-rg"		  # Azure Resource Group for housing the VM and related resources (will create new or use existing)
$vmComputerName 	= "cust-az-pbx"	  # Computername
$vNetName	      = "3cx-vnet"	  # Virtual Network Name (will create new or use existing if already created)
$vNetPrefix	  	= '10.10.0.0/16'	  # This should be larger than the subnetPrefix in order to contain future subnets
$subnetName	  	= "3cx-subnet"      # Subnet name for housing the VM (will create new or use existing if already created)
$subnetPrefix  	= '10.10.199.0/24'  # Subnet attached to the VM NIC
$adminUser	  	= "3cxroot"		  # Admin user - may have error using 'root'
$securePassword 	= ConvertTo-SecureString "ChangeMe!" -AsPlainText -Force	# Admin password
#_____________________________________________________________________________________________________________________________________/

Script will prompt for credentials to Azure portal (Modern Auth), query subscriptions and then ask you for other needed information:
1. Subscription
2. Location (data center)
3. Publisher (marketplace)
4. Offer (marketplace)
5. SKU (marketplace)
6. VM Size

Test if Premium Disks are supported for VM size and then ask for disk storage type:
7. Storage Account Type (Standard_LRS / StandardSSD_LRS / Premium_LRS)

Create Network Security Group with firewall rules for 3CX (80, 443, 5015, 5060, 9000-10999) 
      - You can modify script ports or modify the NSG after deployement if using different ports
      
Create Public IP

Create VM config and deploy VM

Give output with 3CX Web Configuration Tool URL if VM deployment completed successfully
 
