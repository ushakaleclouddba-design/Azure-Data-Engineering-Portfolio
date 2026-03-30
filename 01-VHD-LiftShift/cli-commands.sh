#!/bin/bash
# ============================================================
# CLI COMMANDS — Node5 VHD Lift & Shift to Azure
# Project: Azure-Data-Engineering-Portfolio
# Author: Usha Kale | ushakaleclouddba-design
# Date: March 2026
# ============================================================

# ── PHASE 1: CREATE STORAGE ACCOUNT IN NORTH CENTRAL US ──────
az storage account create \
  --name <STORAGE_ACCOUNT_NCUS> \
  --resource-group <RESOURCE_GROUP> \
  --location northcentralus \
  --sku Standard_LRS

# Verify storage account
az storage account show \
  --name <STORAGE_ACCOUNT_NCUS> \
  --resource-group <RESOURCE_GROUP> \
  --query "{name:name, location:primaryLocation, status:statusOfPrimary}" \
  --output table

# ── PHASE 2: CREATE BLOB CONTAINER ───────────────────────────
az storage container create \
  --name vhds \
  --account-name <STORAGE_ACCOUNT_NCUS>

# ── PHASE 3: GENERATE SAS TOKEN FOR SOURCE VHD ───────────────
az storage blob generate-sas \
  --account-name <STORAGE_ACCOUNT_SOURCE> \
  --container-name vhds \
  --name Node5_Fixed_Final.vhd \
  --permissions r \
  --expiry <EXPIRY_DATETIME> \
  --output tsv

# ── PHASE 4: COPY VHD CROSS-REGION ───────────────────────────
az storage blob copy start \
  --account-name <STORAGE_ACCOUNT_NCUS> \
  --destination-container vhds \
  --destination-blob Node5_Fixed_Final.vhd \
  --source-uri 'https://<STORAGE_ACCOUNT_SOURCE>.blob.core.windows.net/vhds/Node5_Fixed_Final.vhd?<SAS_TOKEN>'

# Monitor copy progress
az storage blob show \
  --account-name <STORAGE_ACCOUNT_NCUS> \
  --container-name vhds \
  --name Node5_Fixed_Final.vhd \
  --query "{status:properties.copy.status, progress:properties.copy.progress}" \
  --output table

# ── PHASE 5: CREATE MANAGED DISK ─────────────────────────────
az disk create \
  --name disk-node5-os-ncus \
  --resource-group <RESOURCE_GROUP> \
  --location northcentralus \
  --source 'https://<STORAGE_ACCOUNT_NCUS>.blob.core.windows.net/vhds/Node5_Fixed_Final.vhd' \
  --os-type Windows \
  --hyper-v-generation V1 \
  --sku StandardSSD_LRS

# ── PHASE 6: CREATE NSG IN NORTH CENTRAL US ──────────────────
az network nsg create \
  --name nsg-sqlnode5-ncus \
  --resource-group <RESOURCE_GROUP> \
  --location northcentralus

# Allow RDP
az network nsg rule create \
  --nsg-name nsg-sqlnode5-ncus \
  --resource-group <RESOURCE_GROUP> \
  --name Allow-RDP \
  --priority 1000 \
  --protocol Tcp \
  --destination-port-ranges 3389 \
  --access Allow

# Allow SQL Server
az network nsg rule create \
  --nsg-name nsg-sqlnode5-ncus \
  --resource-group <RESOURCE_GROUP> \
  --name Allow-SQL \
  --priority 1010 \
  --protocol Tcp \
  --destination-port-ranges 1433 \
  --access Allow

# ── PHASE 7: CHECK AVAILABLE VM SIZES ────────────────────────
az vm list-skus \
  --location northcentralus \
  --size Standard_B \
  --output table \
  --query "[?restrictions[0].reasonCode!='NotAvailableForSubscription'].{Name:name}"

# ── PHASE 8: CREATE AZURE VM ─────────────────────────────────
az vm create \
  --name vm-sqlnode5-azure \
  --resource-group <RESOURCE_GROUP> \
  --location northcentralus \
  --attach-os-disk disk-node5-os-ncus \
  --os-type Windows \
  --size Standard_B2as_v2 \
  --public-ip-address pip-sqlnode5 \
  --nsg nsg-sqlnode5-ncus

# ── CLEANUP: DELETE ALL RESOURCES ────────────────────────────
# Deallocate VM only (stops compute charges)
az vm deallocate \
  --name vm-sqlnode5-azure \
  --resource-group <RESOURCE_GROUP>

# Delete entire resource group (full cleanup)
az group
