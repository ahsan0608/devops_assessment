## Steps and Commands

### Set Up Azure Environment

#### Resource Group
```bash
az group create --name devops-assessment-rg --location southeastasia
```

#### Virtual Network
```bash
az network vnet create \
  --resource-group devops-assessment-rg \
  --name aks-vnet \
  --address-prefix 10.0.0.0/16 \
  --subnet-name aks-subnet \
  --subnet-prefix 10.0.0.0/24
```

#### Create the AKS Cluster
```bash
az aks create \
  --resource-group devops-assessment-rg \
  --name selise-aks-cluster \
  --node-count 2 \
  --network-plugin azure \
  --vnet-subnet-id /subscriptions/572e96d6-b3ce-48e3-a756-d35519f2b47d/resourceGroups/devops-assessment-rg/providers/Microsoft.Network/virtualNetworks/aks-vnet/subnets/aks-subnet \
  --enable-private-cluster \
  --generate-ssh-keys \
  --location southeastasia
```

<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/cf86971f-b21a-41aa-8edf-6036954c3f8c">

#### Create a VM for Accessing AKS
```bash
az vm create \
  --resource-group devops-assessment-rg \
  --name aks-bastion-vm \
  --image Ubuntu2204 \
  --vnet-name aks-vnet \
  --subnet aks-subnet \
  --admin-username azureuser \
  --generate-ssh-keys \
  --size Standard_B2ms \
  --location southeastasia
```

#### Open SSH Port on Network Security Group 
```bash
az network nsg rule create \
  --resource-group devops-assessment-rg \
  --nsg-name aks-bastion-vmNSG \
  --name AllowSSH \
  --priority 1000 \
  --source-address-prefixes '*' \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/f7b2c819-bad3-4e63-b270-67a71d292bd4">


#### SSH into the Bastion VM
```bash
az vm show -d -g devops-assessment-rg -n aks-bastion-vm --query publicIps -o tsv
ssh azureuser@40.65.179.144
```

#### Verify AKS Nodes
```bash
az aks get-credentials --resource-group devops-assessment-rg --name selise-aks-cluster
kubectl get nodes
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/f8f3ec7a-0193-4301-8f8c-62100d1d5bd4">

### Deploy the Sample Application Manually

##### Added a Docker file in the application directory. [Link](https://github.com/ahsan0608/devops_assessment/blob/main/Dockerfile):
```yaml
FROM node:18-alpine
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install --only=production
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
```

##### Build the Docker image.
```bash
docker build -t seliseacr.azurecr.io/selise-rest-api:v1 .
```

##### Create ACR
```bash
az acr create --resource-group devops-assessment-rg --name seliseacr --sku Basic --location southeastasia
```

##### Log in to ACR
```bash
az acr login --name seliseacr
```

##### Push Docker Image
```bash
docker push seliseacr.azurecr.io/selise-rest-api:v1
```

<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/fff5e31d-ce9f-4b42-b69c-3f3f570b380a">

### Create Kubernetes Deployment and Service
#### Attach ACR to AKS
```bash
az aks update \
  --resource-group devops-assessment-rg \
  --name selise-aks-cluster \
  --attach-acr seliseacr

```
#### Create the Deployment
```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: selise-rest-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: selise-rest-api
  template:
    metadata:
      labels:
        app: selise-rest-api
    spec:
      containers:
      - name: selise-rest-api
        image: seliseacr.azurecr.io/selise-rest-api:v1
        ports:
        - containerPort: 3000
```
#### Create the Service
```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: selise-rest-api-service
spec:
  type: LoadBalancer
  selector:
    app: selise-rest-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/6f472396-acfd-48cc-9d25-196161465df5">

### Set Up Azure Application Gateway

#### Create Application Gateway

```bash
az network application-gateway create \
  --name selise-app-gateway \
  --resource-group devops-assessment-rg \
  --vnet-name aks-vnet \
  --subnet aks-subnet \
  --sku Standard_v2 \
  --public-ip-address selise-app-gateway-pip \
  --frontend-port 80 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --location southeastasia
```
#### Create Backend Pool
```bash
az network application-gateway address-pool create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name selise-backend-pool \
  --backend-ip-addresses 10.0.190.3
```
#### Create HTTP Settings
```bash
az network application-gateway http-settings create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name selise-backend-settings \
  --port 80 \
  --protocol Http \
  --cookie-based-affinity Disabled \
  --timeout 20
```
#### Create Frontend IP Configuration
``` bash
az network application-gateway frontend-ip-config create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name appGwPublicFrontendIpIPv4 \
  --public-ip-address selise-app-gateway-pip
```
#### Create Frontend Port
```bash
az network application-gateway frontend-port create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name port_80 \
  --port 80
```
#### Create HTTP Listener
```bash
az network application-gateway http-listener create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name selise-http-listener \
  --frontend-ip-configuration appGwPublicFrontendIpIPv4 \
  --frontend-port port_80 \
  --protocol Http
```
#### Create Request Routing Rule
```bash
az network application-gateway rule create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name selise-routing-rule \
  --http-listener selise-http-listener \
  --backend-address-pool selise-backend-pool \
  --backend-http-settings selise-backend-settings
```
#### Create Health Probe
```bash
az network application-gateway probe create \
  --resource-group devops-assessment-rg \
  --gateway-name selise-app-gateway \
  --name selise-health-probe \
  --protocol Http \
  --path /api \
  --interval 30 \
  --timeout 30 \
  --unhealthy-threshold 3
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/8dcb5f39-d8a0-4e27-8c89-3036f38c6118">

### Configure DNS

#### Create a DNS Zone:
```bash
az network dns zone create \
  --resource-group devops-assessment-rg \
  --name seliseassessment.com
```
#### Create an A Record:
```bash
az network dns record-set a create \
  --resource-group devops-assessment-rg \
  --zone-name seliseassessment.com \
  --name ahsan \
  --ttl 3600
```
#### Set the A Record's IP Address:
```bash
PUBLIC_IP=$(az network public-ip show \
  --resource-group devops-assessment-rg \
  --name selise-app-gateway-pip \
  --query ipAddress -o tsv)

az network dns record-set a add-record \
  --resource-group devops-assessment-rg \
  --zone-name seliseassessment.com \
  --record-set-name ahsan \
  --ipv4-address $PUBLIC_IP
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/859a4c0e-55a1-4300-b48a-b88f8e268387">

### Access the application 
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/6f77fdc0-345e-4439-a664-c4a48caf601b">
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/bacdfa62-660b-4628-9bf5-3715afedb03e">

### Set Up Azure Blob Storage

#### Create Storage Account
```bash
az storage account create \
  --name ahsanselisestorage \
  --resource-group devops-assessment-rg \
  --location southeastasia \
  --sku Standard_LRS \
  --allow-blob-public-access true
```

#### Create Container and Upload Blob
```bash
az storage container create --name ahsanselisecontainer --account-name ahsanselisestorage --public-access blob
az storage blob upload --container-name ahsanselisecontainer --file ./dummyfile.txt --name dummyfile.txt --account-name ahsanselisestorage
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/8233e53d-6f0b-4385-97e6-57cd0bd6273e">

#### Update Application Code
After uploading the blob, i updated the application's index.js file to access the uploaded file [Link](https://github.com/ahsan0608/devops_assessment/blob/main/index.js):

```javascript
Copy code
const express = require('express');
const app = express();
const axios = require('axios');

app.get('/api', (req, res) => {
    res.json({ message: 'Hello, World!' });
});

app.get('/pub/dummyfile', async (req, res) => {
    try {
        const response = await axios.get('https://ahsanselisecontainer.blob.core.windows.net/ahsanselisecontainer/dummyfile.txt');
        res.send(response.data);
    } catch (error) {
        res.status(500).send('Error fetching the file.');
    }
});

app.listen(3000, () => {
    console.log('Server running on port 3000');
});
```
### Rebuild, push the new image and the dummy file is accessed through the URL
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/98ec8884-8467-48cb-ad23-9a13f013bfb4">
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/5edaa362-9fb7-4e02-a653-da28bf8e9ac3">

### Create MongoDB VM

#### Create VM for MongoDB
```bash
az vm create \
  --resource-group devops-assessment-rg \
  --name mongodb-vm \
  --image Ubuntu2204 \
  --vnet-name aks-vnet \
  --subnet aks-subnet \
  --admin-username mongouser \
  --generate-ssh-keys \
  --size Standard_B2ms \
  --location southeastasia
```

#### Allow Traffic from AKS to MongoDB
```bash
az network nsg rule create \
  --resource-group devops-assessment-rg \
  --nsg-name mongodb-vmNSG \
  --name AllowAKSTraffic \
  --priority 150 \
  --source-address-prefixes 10.0.0.0/24 \
  --destination-port-ranges 27017 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound
```
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/2a47caf1-6a70-44a4-9965-8791a32fda07">

### Implement CI/CD Pipeline

#### Configure Self-Hosted Runner
In the Bastion VM, i configured a GitHub Actions self-hosted runner to have access to the AKS cluster for deployment updates
<img width="795" alt="Screenshot 2024-09-20 at 11 49 57 PM" src="https://github.com/user-attachments/assets/a658913c-58ae-43fe-b243-f16d95ac4a6f">

#### GitHub Actions Workflow [Link](https://github.com/ahsan0608/devops_assessment/blob/main/.github/workflows/deploy.yml)
```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main

jobs:
  build-and-deploy:
    runs-on: self-hosted
    steps:
      - name: Checkout code
        uses: actions/checkout@v2

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v1

      - name: Log in to Azure Container Registry
        uses: docker/login-action@v1
        with:
          registry: seliseacr.azurecr.io
          username: ${{ secrets.AZURE_REGISTRY_USERNAME }}
          password: ${{ secrets.AZURE_REGISTRY_PASSWORD }}

      - name: Build and Push Docker image
        run: |
          docker buildx build --platform linux/amd64 -t seliseacr.azurecr.io/selise-rest-api:v1 --push .

      - name: Set up AKS context
        uses: azure/aks-set-context@v1
        with:
          resource-group: devops-assessment-rg
          cluster-name: selise-aks-cluster
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Update deployment
        run: |
          kubectl set image deployment/selise-rest-api selise-rest-api=seliseacr.azurecr.io/selise-rest-api:v1
```

#### Workflow Status
The workflow runs successfully, and all steps completed without errors. The application is deployed, and you can view the successful run here -
[Action Link](https://github.com/ahsan0608/devops_assessment/actions/runs/11529184113/job/32097310800)

## Deployment Script

Script for automating the process of setting up all the resources and configurations required for the assessment - [here](https://github.com/ahsan0608/devops_assessment/blob/main/deploy-script.sh).
