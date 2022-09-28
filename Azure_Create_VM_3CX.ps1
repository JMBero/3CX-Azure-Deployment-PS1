# NOTES: 
# ! If using existing virtual network and/or subnet, make sure the name and address space match.  Make sure existing vNet is in the same location as the VM.
# ! If the script fails to create the VM, re-run the script after changing failing parameters and choose [Yes] to overwriting any resources that were previously created.
#
# Define Parameters:
#___________________________________________________________________________________________________________________________________________________________________
$rgName 		= "3cx-rg"		# Azure Resource Group for housing the VM and related resources (will create new or use existing)
$vmComputerName 	= "cust-az-pbx"		# Computername
$vNetName		= "3cx-vnet"		# Virtual Network Name (will create new or use existing if already created)
$vNetPrefix		= '10.10.0.0/16'	# This should be larger than the subnetPrefix in order to contain future subnets
$subnetName		= "3cx-subnet"		# Subnet name for housing the VM (will create new or use existing if already created)
$subnetPrefix		= '10.10.199.0/24'  	# Subnet attached to the VM NIC
$adminUser		= "3cxroot"		# Admin user - may have error using 'root'
$securePassword 	= ConvertTo-SecureString "ChangeMe!" -AsPlainText -Force	# Admin password
#___________________________________________________________________________________________________________________________________________________________________|

Clear-Host

# Suppress Change Warnings (https://aka.ms/azps-changewarnings):
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

# Check that Required Azure Modules Exist / Install if not:
Write-Host "Checking Installed AZ Modules..."
if (Get-Module -ListAvailable -Name Az.compute) {
    Write-Host "Az.Compute Module exists" -ForegroundColor Green
} 
else {
    Write-Host "Az.Compute Module does not exist" -ForegroundColor Red
	Write-Host "Installing Az Module..." -ForegroundColor Cyan
	Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
}
if (Get-Module -ListAvailable -Name Az.MarketplaceOrdering) {
    Write-Host "Az.MarketplaceOrdering Module exists" -ForegroundColor Green
} 
else {
    Write-Host "Az.MarketplaceOrdering Module does not exist" -ForegroundColor Red
	Write-Host "Installing Az Module..." -ForegroundColor Cyan
	Install-Module -Name Az.MarketplaceOrdering -Scope CurrentUser -Repository PSGallery -Force
}
if (Get-Module -ListAvailable -Name Az.Network) {
    Write-Host "Az.Network Module exists" -ForegroundColor Green
} 
else {
    Write-Host "Az.Network Module does not exist" -ForegroundColor Red
	Write-Host "Installing Az Module..." -ForegroundColor Cyan
	Install-Module -Name Az.Network -Scope CurrentUser -Repository PSGallery -Force
}
if (Get-Module -ListAvailable -Name Az.Resources) {
    Write-Host "Az.Resources Module exists" -ForegroundColor Green
} 
else {
    Write-Host "Az.Resources Module does not exist" -ForegroundColor Red
	Write-Host "Installing Az Module..." -ForegroundColor Cyan
	Install-Module -Name Az.Resources -Scope CurrentUser -Repository PSGallery -Force
}


# Create Login and TestLogin Functions:
Function AzureLogin()
{
 Write-Host ""
 Write-Host "Please Sign-in"
 $connectFailed = $false
 Clear-AzContext -Scope CurrentUser -Force
 Login-AzAccount -ErrorVariable connectFailed -ErrorAction SilentlyContinue
 
 TestLogin
}

Function TestLogin()
{
if ( $connectFailed )
    {
        Write-Host "Login-AzAccount failed." -ForegroundColor Red
        $promptYes = "yes"
        $promptText = "Try Again? [${promptYes}/no]"

        Write-Host ""
        Write-Host "${promptText}" -NoNewline
        $answer = (Read-Host " ")
        if ( $answer )
        {
            $answer = $answer.ToLower()
        }
        if ( "${answer}" -ne "${promptYes}" -and "${answer}" -ne "y" )
        {
            Write-Host ""
            Write-Host "Operation canceled." -ForegroundColor Red
            exit
        }
        else
        {
            AzureLogin
        }
    }
    else
    {
        Write-Host "Connected..." -ForegroundColor Green
        Write-Host ""
    }
}

# Call Login Function:
AzureLogin

# Promt user for required information:
Write-Host "Prompting for input...  (Check out-grid window and title bar for examples / notes)" -ForegroundColor Gray
Write-Host ""

write-host "Subscription: " -NoNewline
$SubscriptionName = (
	Get-AzSubscription | 
	Out-Gridview -OutputMode Single -Title 'Choose Subscription'
	).id
if (!$SubscriptionName) {write-host "Subscription not selected" -ForegroundColor Red; Read-Host -Prompt "Press Enter to exit"; exit}
Write-host "$SubscriptionName" -ForegroundColor Green
Set-AzContext -SubscriptionName $SubscriptionName

Write-host "Location: " -NoNewline
$locName = (
	Get-AzLocation | 
	Out-Gridview -OutputMode Single -Title 'Choose Location (Example: SouthCentralUS)'
	).location
if (!$locName) {write-host "Location not selected" -ForegroundColor Red; Read-Host -Prompt "Press Enter to exit"; exit}
write-host "$locName" -ForegroundColor Green

Write-Host "Publisher: " -NoNewline
$pubName = (
	Get-AzVMImagePublisher -Location $locName | 
	Select-Object PublisherName |
	Out-Gridview -OutputMode Single -Title 'Choose Publisher (Example: 3cx-pbx)'
	).PublisherName
if (!$pubName) {write-host "Publisher not selected" -ForegroundColor Red; Read-Host -Prompt "Press Enter to exit"; exit}
write-host "$pubName" -ForegroundColor Green

Write-host "Offer: " -NoNewline
$offerName = (
	Get-AzVMImageOffer -Location $locName -PublisherName $pubName | 
	Select-Object Offer |
	Out-Gridview -OutputMode Single -Title 'Choose Offer (Example: 3cx-pbx)'
	).Offer
if (!$offerName) {write-host "Offer not selected" -ForegroundColor Red; Read-Host -Prompt "Press Enter to exit"; exit}
write-host "$offerName" -ForegroundColor Green

Write-host "SKU: " -NoNewline
$skuName = (
	Get-AzVMImageSku -Location $locName -PublisherName $pubName -Offer $offerName | 
	Select-Object Skus |
	Out-Gridview -OutputMode Single -Title 'Choose SKU (Example: 16 - [this is actually v18])'
	).Skus
if (!$skuName) {write-host "SKU not selected" -ForegroundColor Red; Read-Host -Prompt "Press Enter to exit"; exit}
write-host "$skuName" -ForegroundColor Green

Write-host "VM Size: " -NoNewline
$vmSizeName = (
	Get-AzVMSize -Location $locName |
	Out-Gridview -OutputMode Single -Title 'Choose VM Size'
	).Name
if (!$vmSizeName) {write-host "VM Size not selected" -ForegroundColor Red; Read-Host -Prompt "Press Enter to exit"; exit}
write-host "$vmSizeName" -ForegroundColor Green

# Choose Disk StorageAccountType:
write-host "Querying VM Size SKU for Premium Disk Support..." -ForegroundColor Gray
$CheckVMSize = Get-AzComputeResourceSku  | where{$_.ResourceType.Equals('virtualMachines') -and $_.Locations.Contains($locName).Equals($true) -and $_.Name.Equals($vmSizeName)}
if ($CheckVMSize.Capabilities.where({($_.Value -eq 'True') -and ($_.Name -eq 'PremiumIO')}))
    {
        write-host ""
        write-host "1. Standard_LRS" -ForegroundColor Magenta
        write-host "2. StandardSSD_LRS" -ForegroundColor Magenta
        write-host "3. Premium_LRS" -ForegroundColor Magenta
        $DiskSelection = Read-Host "Select Disk Storage Account Type:"
        switch ($DiskSelection)
        {
            '1' {$StorageAccountType = "Standard_LRS"}
            '2' {$StorageAccountType = "StandardSSD_LRS"}
            '3' {$StorageAccountType = "Premium_LRS"}
        }
        write-host "$StorageAccountType" -ForegroundColor Green
    }
else
    {
        write-host ""
        write-host "VM Size: " -NoNewLine -ForegroundColor Yellow; write-host "$vmSizeName " -NoNewLine -ForegroundColor Blue; write-host "does not support premium disks." -NoNewLine -ForegroundColor Yellow
        write-host ""
        write-host "1. Standard_LRS" -ForegroundColor Magenta
        write-host "2. StandardSSD_LRS" -ForegroundColor Magenta
        $DiskSelection = Read-Host "Select Disk Storage Account Type:"
        switch ($DiskSelection)
        {
            '1' {$StorageAccountType = "Standard_LRS"}
            '2' {$StorageAccountType = "StandardSSD_LRS"}
        }
        write-host "$StorageAccountType" -ForegroundColor Green
    }


# Accept Marketplace Terms:
Get-AzMarketplaceTerms -publisher $pubname -product $offername -Name $skuname | Set-AzMarketplaceTerms -Accept

# Check for existing Resource Group / Create Resource Group:
Write-Host "Creating Resource Group '$rgName'..." -ForegroundColor Gray
Get-AzResourceGroup -Name $rgName -ErrorVariable notPresent -ErrorAction SilentlyContinue
if ($notPresent)
	{
		New-AzResourceGroup -Name $rgName -Location $locName
	}
else
	{
		write-host "Resource Group already exists" -ForegroundColor Green
	}

# Setup additional variables based on computername naming convention:
$nicName = $vmComputerName + "-nic"
$nsgName = $nicName + "-nsg"
$publicIpName = $vmComputerName + "-ip"
$vmOSDiskName = $vmComputerName + "-disk_os"
$cred = New-Object System.Management.Automation.PSCredential ($adminUser, $securePassword)

# Get existing vNet info / create vNet, subnet, IP, NIC:
Write-Host "Creating virtual network '$vNetName'..." -ForegroundColor Gray
$subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPrefix
$checkVnet = (Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $rgName -ErrorVariable vNetNotPresent -ErrorAction SilentlyContinue)
if ($vNetNotPresent)
	{
		$vnet = New-AzVirtualNetwork -ResourceGroupName $rgName -Location $locName -Name $vNetName -AddressPrefix $vNetPrefix -Subnet $subnetConfig
	}
else
	{
		write-host "vNet already exists" -ForegroundColor Green
        write-host "Verifying existing vNet is in the same location as new VM..." -ForegroundColor Gray
            if ($checkVnet.Location -eq $locName)
                {
                write-host "vNet exists in '$locName'" -ForegroundColor Green
                }
            else
                {
                write-host ""
                write-host "Existing vNet is not in the chosen VM location.  Either create a new vNet for " -NoNewline -ForegroundColor Red
                write-host "$locName " -NoNewline -ForegroundColor Yellow
                write-host "or change the VM location to " -NoNewline -ForegroundColor Red
                write-host "$($checkVnet.Location).  " -ForegroundColor Yellow
                Read-Host -Prompt "Press Enter to exit"; exit
                }
        write-host "Creating subnet '$subnetname'..." -ForegroundColor Gray
		$vnetq=Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $rgName
		$checksubnet = ($vnetq.subnets | Where-Object { $_.name -in $subnetname }).name
			if ($checksubnet -eq $subnetname) 
				{
                    write-host "Subnet already exists" -ForegroundColor Green
				}
			else
				{
					Add-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnetq -AddressPrefix $subnetPrefix
				}
	}

# Create NSG, 3CX Rules:
Write-Host "Creating rules for 3CX required ports..." -ForegroundColor Gray
$rule1 = New-AzNetworkSecurityRuleConfig -Name HTTPS -Description "HTTPS" `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet `
	-SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

$rule2 = New-AzNetworkSecurityRuleConfig -Name 3CX-Tunnel -Description "3CX Tunnel" `
    -Access Allow -Protocol * -Direction Inbound -Priority 102 -SourceAddressPrefix Internet `
	-SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5090

$rule3 = New-AzNetworkSecurityRuleConfig -Name SIP -Description "SIP" `
    -Access Allow -Protocol * -Direction Inbound -Priority 103 -SourceAddressPrefix Internet `
	-SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5060
	
$rule4 = New-AzNetworkSecurityRuleConfig -Name 3CX-RTP -Description "3CX RTP" `
    -Access Allow -Protocol UDP -Direction Inbound -Priority 104 -SourceAddressPrefix Internet `
	-SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 9000-10999

$rule5 = New-AzNetworkSecurityRuleConfig -Name 3CX-Wizard -Description "3CX Wizard" `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 105 -SourceAddressPrefix Internet `
	-SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5015
	
$rule6 = New-AzNetworkSecurityRuleConfig -Name HTTP -Description "HTTP" `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 106 -SourceAddressPrefix Internet `
	-SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80

Write-Host "Creating Network Security Group '$nsgName'..." -ForegroundColor Gray
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $rgName -Location $locName -Name $nsgName `
	-SecurityRules $rule1,$rule2,$rule3,$rule4,$rule5,$rule6

Write-Host "Creating Public IP '$publicIpName'..." -ForegroundColor Gray
$vnetq2=Get-AzVirtualNetwork -Name $vNetName -ResourceGroupName $rgName
$pip = New-AzPublicIpAddress -ResourceGroupName $rgName -Location $locName -Name $PublicIpName -AllocationMethod Static
Write-Host "Creating Network Interface '$nicName'..." -ForegroundColor Gray
$nic = New-AzNetworkInterface -ResourceGroupName $rgName -Location $locName -Name $nicName `
 -SubnetId ($vnetq2.subnets | Where-Object { $_.name -in $subnetname }).id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id

# Build VM

Write-Host "Creating virtual machine configuration..." -ForegroundColor Gray
$vmConfig = New-AzVMConfig -VMName $vmComputerName -VMSize $vmSizeName
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $vmComputerName -Credential $cred
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $pubName -Offer $offerName -Skus $skuName -Version "latest"
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
$vmConfig = Set-AzVMPlan -VM $vmConfig -Publisher $pubName -Product $offerName -Name $skuName
$vmConfig = Set-AzVMOSDisk -VM $vmConfig -StorageAccountType $StorageAccountType -Caching ReadWrite -Name $VmOSDiskName -CreateOption FromImage

Write-Host "Creating VM..." -ForegroundColor Gray
New-AzVM -ResourceGroupName $rgName -Location $locName -VM $vmConfig

# Query VM Info:
$VMq=Get-AzVM -name $vmComputerName
    If ($VMq)
	    {
            Write-Host ""
	       	Write-Host "VM Created Successfully." -ForegroundColor Green
            If ($offerName -eq "3cx-pbx")
                {
                    Write-Host ""
                    Write-Host -NoNewline "Continue 3CX Configuration: --> " -ForegroundColor Green
                    Write-Host -NoNewline "http://$($pip.IpAddress):5015" -ForegroundColor Cyan
                }
            Write-Host ""
            $VMq
        }
    Else
    	{
            Write-Host ""
		    Write-Host "VM Creation Failed." -ForegroundColor Red
	    }
