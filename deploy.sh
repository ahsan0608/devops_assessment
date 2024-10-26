#!/bin/bash

RESOURCE_GROUP="devops-assessment-rg"
LOCATION="southeastasia"
VNET_NAME="aks-vnet"
SUBNET_NAME="aks-subnet"
AKS_CLUSTER_NAME="selise-aks-cluster"
BASTION_VM_NAME="aks-bastion-vm"
ACR_NAME="seliseacr"
STORAGE_ACCOUNT="ahsanselisestorage"
CONTAINER_NAME="ahsanselisecontainer"
MONGODB_VM_NAME="mongodb-vm"

# Fetch subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Virtual Network and Subnet
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $SUBNET_NAME \
  --subnet-prefix 10.0.0.0/24

# Create AKS Cluster
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER_NAME \
  --node-count 2 \
  --network-plugin azure \
  --vnet-subnet-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/$SUBNET_NAME \
  --enable-private-cluster \
  --generate-ssh-keys \
  --location $LOCATION

# Wait for the AKS cluster to be provisioned
az aks wait --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --created

# Create Bastion VM
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $BASTION_VM_NAME \
  --image Ubuntu2204 \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --admin-username azureuser \
  --generate-ssh-keys \
  --size Standard_B2ms \
  --location $LOCATION

# Wait for Bastion VM to be provisioned
az vm wait --resource-group $RESOURCE_GROUP --name $BASTION_VM_NAME --created

# Open SSH Port on NSG
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name aks-bastion-vmNSG \
  --name AllowSSH \
  --priority 1000 \
  --source-address-prefixes '*' \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound

# Create ACR
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --location $LOCATION

# Wait for ACR to be created
az acr wait --resource-group $RESOURCE_GROUP --name $ACR_NAME --created

# Set up Azure Blob Storage
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --allow-blob-public-access true

# Create Blob Container
az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT --public-access blob

# Create MongoDB VM
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $MONGODB_VM_NAME \
  --image Ubuntu2204 \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --admin-username mongouser \
  --generate-ssh-keys \
  --size Standard_B2ms \
  --location $LOCATION

# Wait for MongoDB VM to be provisioned
az vm wait --resource-group $RESOURCE_GROUP --name $MONGODB_VM_NAME --created

# Allow Traffic from AKS to MongoDB
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name mongodb-vmNSG \
  --name AllowAKSTraffic \
  --priority 150 \
  --source-address-prefixes 10.0.0.0/24 \
  --destination-port-ranges 27017 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound
