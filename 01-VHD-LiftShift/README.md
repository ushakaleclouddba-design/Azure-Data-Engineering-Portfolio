 # Project 1: SQL Server VHD Lift & Shift to Azure

## Overview
Complete migration of SQL Server 2019 (Node5) from on-premises 
VirtualBox to Azure VM using VHD Lift & Shift approach.

## Architecture
```
On-Premises Node5 (VirtualBox)
        ↓ Disk2VHD
Node5_Fixed_Final.vhd (64 GiB)
        ↓ AzCopy
Azure Blob Storage (West US 2)
        ↓ Cross-region copy with SAS token
Azure Blob Storage (North Central US)
        ↓ az disk create
Managed Disk (Standard SSD LRS)
        ↓ az vm create
Azure VM (Standard_B2as_v2)
        ↓ RDP
SQL Server 2019 Verified Online ✅
```

## Challenges Resolved
| # | Challenge | Resolution |
|---|-----------|-----------|
| 1 | West US 2 quota exceeded | Pivoted to North Central US |
| 2 | Region mismatch error | Copied VHD cross-region |
| 3 | SAS token auth failure | Generated time-limited SAS token |
| 4 | Premium SSD v2 incompatible | Changed to Standard SSD LRS |
| 5 | Standard_B2ms unavailable | Used Standard_B2as_v2 |
| 6 | NSG region mismatch | Created new NSG in NCUS |

## Key Commands
```bash
# Generate SAS token
az storage blob generate-sas \
  --account-name ushacloudmigrationpoc \
  --container-name vhds \
  --name Node5_Fixed_Final.vhd \
  --permissions r \
  --expiry 2026-03-28T05:00:00Z \
  --output tsv

# Copy VHD cross-region
az storage blob copy start \
  --account-name ushacloudmigrationncus \
  --destination-container vhds \
  --destination-blob Node5_Fixed_Final.vhd \
  --source-uri 'https://ushacloudmigrationpoc.blob.core.windows.net/vhds/Node5_Fixed_Final.vhd?<SAS_TOKEN>'

# Create Managed Disk
az disk create \
  --name disk-node5-os-ncus \
  --resource-group UshacloudMigration1 \
  --location northcentralus \
  --source 'https://ushacloudmigrationncus.blob.core.windows.net/vhds/Node5_Fixed_Final.vhd' \
  --os-type Windows \
  --hyper-v-generation V1 \
  --sku StandardSSD_LRS

# Create Azure VM
az vm create \
  --name vm-sqlnode5-azure \
  --resource-group UshacloudMigration1 \
  --location northcentralus \
  --attach-os-disk disk-node5-os-ncus \
  --os-type Windows \
  --size Standard_B2as_v2 \
  --public-ip-address pip-sqlnode5 \
  --nsg nsg-sqlnode5-ncus
```
 
## Results
| Resource | Value |
|----------|-------|
| VM Name | vm-sqlnode5-azure |
| Location | North Central US |
| VM Size | Standard_B2as_v2 |
| Public IP | <PUBLIC_IP> |
| Private IP | <PRIVATE_IP> |
| SQL Version | 15.0.4430.1 (SQL 2019) |
| Databases | CoreBank_OnPrem_POC ✅ AcquiredBanks_OnPrem_POC ✅ |
| SSRS | ReportServer ✅ ReportServerTempDB ✅ |

## Cost Analysis
| Item | Cost |
|------|------|
| VHD Blob Storage | $79.07 |
| Managed Disk | $3.84 |
| Public IP | $0.73 |
| Other | $0.29 |
| **Total** | **$83.93** |

## Lesson Learned
Delete storage accounts immediately after disk creation to avoid ongoing blob storage charges.

## Files
- `cli-commands.sh` — All Azure CLI commands used
- `Post_Migration_Config_Node5.sql` — Post-migration hardening script
