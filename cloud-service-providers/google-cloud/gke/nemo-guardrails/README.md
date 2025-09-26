# Deploy NeMo Guardrails on Google Kubernetes Engine

## Introduction
This tutorial will guide you through deploying NVIDIA NeMo Guardrails on Google Kubernetes Engine (GKE). NeMo Guardrails provides a framework for building safe, secure, and trustworthy AI applications by implementing guardrails that control and monitor AI model behavior.

## Prerequisites
- **GCloud SDK:** Ensure you have the Google Cloud SDK installed and configured.
- **Project:** A Google Cloud project with billing enabled.
- **Permissions:** Sufficient permissions to create GKE clusters and other related resources.
- **kubectl:** kubectl command-line tool installed and configured.
- **Helm:** Helm package manager for Kubernetes installed.
- **NVIDIA API key:** Required to download NeMo microservices: [NGC API key](https://org.ngc.nvidia.com/setup/api-key).
- **NVIDIA GPUs:** One of the below GPUs should work
  - [NVIDIA L4 GPU (1)](https://cloud.google.com/compute/docs/gpus#l4-gpus)
  - [NVIDIA A100 40GB GPU (1)](https://cloud.google.com/compute/docs/gpus#a100-gpus)
  - [NVIDIA H100 80GB GPU (1)](https://cloud.google.com/compute/docs/gpus#a3-series)

## Option 1: Quick Deployment Using Script

### Step 1: Set Environment Variables
```bash
export PROJECT_ID=<YOUR PROJECT ID>
export REGION=<YOUR REGION>
export ZONE=<YOUR ZONE>
export CLUSTER_NAME=nemo-guardrails-demo
export NODE_POOL_MACHINE_TYPE=g2-standard-16
export CLUSTER_MACHINE_TYPE=e2-standard-4
export GPU_TYPE=nvidia-l4
export GPU_COUNT=1
export NGC_API_KEY=<YOUR NGC API KEY>
```

### Step 2: Create GKE Cluster
```bash
gcloud container clusters create ${CLUSTER_NAME} \
    --project=${PROJECT_ID} \
    --location=${ZONE} \
    --release-channel=rapid \
    --machine-type=${CLUSTER_MACHINE_TYPE} \
    --num-nodes=1
```

### Step 3: Create GPU Node Pool
```bash
gcloud container node-pools create gpupool \
    --accelerator type=${GPU_TYPE},count=${GPU_COUNT},gpu-driver-version=latest \
    --project=${PROJECT_ID} \
    --location=${ZONE} \
    --cluster=${CLUSTER_NAME} \
    --machine-type=${NODE_POOL_MACHINE_TYPE} \
    --num-nodes=1
```

### Step 4: Deploy NeMo Guardrails
```bash
# Make the script executable
chmod +x deploy-guardrails.sh

# Deploy with NGC API key
./deploy-guardrails.sh -k $NGC_API_KEY -n nemo-guardrails
```

### Step 5: Verify Deployment
```bash
# Check pods status
kubectl get pods -n nemo-guardrails

# Check services
kubectl get services -n nemo-guardrails
```

### Step 6: Access Services
```bash
# NeMo Guardrails service
kubectl port-forward -n nemo-guardrails svc/nemo-guardrails 7331:7331

# NIM LLM service (in another terminal)
kubectl port-forward -n nemo-guardrails svc/nemo-guardrails-nim 8000:8000
```

## Option 2: Manual Step-by-Step Deployment

### Step 1: Infrastructure Setup

1. **Set Environment Variables:**
   ```bash
   export PROJECT_ID=<YOUR PROJECT ID>
   export REGION=<YOUR REGION>
   export ZONE=<YOUR ZONE>
   export CLUSTER_NAME=nemo-guardrails-demo
   export NODE_POOL_MACHINE_TYPE=g2-standard-16
   export CLUSTER_MACHINE_TYPE=e2-standard-4
   export GPU_TYPE=nvidia-l4
   export GPU_COUNT=1
   export NGC_API_KEY=<YOUR NGC API KEY>
   ```

2. **Create GKE Cluster:**
   ```bash
   gcloud container clusters create ${CLUSTER_NAME} \
       --project=${PROJECT_ID} \
       --location=${ZONE} \
       --release-channel=rapid \
       --machine-type=${CLUSTER_MACHINE_TYPE} \
       --num-nodes=1
   ```

3. **Create GPU Node Pool:**
   ```bash
   gcloud container node-pools create gpupool \
       --accelerator type=${GPU_TYPE},count=${GPU_COUNT},gpu-driver-version=latest \
       --project=${PROJECT_ID} \
       --location=${ZONE} \
       --cluster=${CLUSTER_NAME} \
       --machine-type=${NODE_POOL_MACHINE_TYPE} \
       --num-nodes=1
   ```

### Step 2: Configure NGC Authentication

1. **Create Namespace:**
   ```bash
   kubectl create namespace nemo-guardrails
   ```

2. **Create NGC Registry Secret:**
   ```bash
   kubectl create secret docker-registry nvcrimagepullsecret \
       --docker-server=nvcr.io \
       --docker-username='$oauthtoken' \
       --docker-password="$NGC_API_KEY" \
       --docker-email='nemo-guardrails@nvidia.com' \
       --namespace=nemo-guardrails
   ```

3. **Create NGC API Secret:**
   ```bash
   kubectl create secret generic ngc-api \
       --from-literal=NGC_API_KEY="$NGC_API_KEY" \
       --namespace=nemo-guardrails
   ```

### Step 3: Configure Helm Repositories

1. **Add NGC Helm Repositories:**
   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo add nvidia-nemo-microservices https://helm.ngc.nvidia.com/nvidia/nemo-microservices/ \
       --username '$oauthtoken' \
       --password "$NGC_API_KEY"
   ```

2. **Update Repositories:**
   ```bash
   helm repo update
   ```

### Step 4: Create Guardrails Configuration

1. **Create Values File:**
   ```bash
   cat <<EOF > guardrails-values.yaml
   # NeMo Guardrails Configuration
   guardrails:
     enabled: true
     image:
       repository: nvcr.io/nvidia/nemo/guardrails
       tag: latest
     resources:
       requests:
         memory: "4Gi"
         cpu: "2"
         nvidia.com/gpu: "1"
       limits:
         memory: "8Gi"
         cpu: "4"
         nvidia.com/gpu: "1"
   
   # NIM LLM Configuration
   nim:
     enabled: true
     image:
       repository: nvcr.io/nim/meta/llama3-8b-instruct
       tag: 1.0.0
     resources:
       requests:
         memory: "8Gi"
         cpu: "2"
         nvidia.com/gpu: "1"
       limits:
         memory: "16Gi"
         cpu: "4"
         nvidia.com/gpu: "1"
   
   # Image Pull Secrets
   imagePullSecrets:
     - name: nvcrimagepullsecret
   
   # NGC API Configuration
   ngcAPISecret: ngc-api
   EOF
   ```

### Step 5: Deploy NeMo Guardrails

1. **Search for Available Charts:**
   ```bash
   helm search repo nvidia --output table | grep nemo
   ```

2. **Install NeMo Microservices:**
   ```bash
   helm install nemo-guardrails nvidia/nemo-microservices-helm-chart \
       --namespace nemo-guardrails \
       --values guardrails-values.yaml \
       --timeout 15m
   ```

### Step 6: Verify Deployment

1. **Check Pod Status:**
   ```bash
   kubectl get pods -n nemo-guardrails
   ```

2. **Check Services:**
   ```bash
   kubectl get services -n nemo-guardrails
   ```

3. **Check Logs:**
   ```bash
   kubectl logs -n nemo-guardrails -l app=nemo-guardrails
   ```

## Testing the Deployment

### Test NeMo Guardrails Service
```bash
# Port forward to access the service
kubectl port-forward -n nemo-guardrails svc/nemo-guardrails 7331:7331

# Test the guardrails service
curl -X POST http://localhost:7331/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Hello, how are you?"
      }
    ],
    "model": "nemo-guardrails"
  }'
```

### Test NIM LLM Service
```bash
# Port forward to access the NIM service
kubectl port-forward -n nemo-guardrails svc/nemo-guardrails-nim 8000:8000

# Test the NIM service
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful assistant."
      },
      {
        "role": "user",
        "content": "What is artificial intelligence?"
      }
    ],
    "model": "meta/llama3-8b-instruct",
    "max_tokens": 128
  }'
```

## Configuration Options

### Custom Guardrails Configuration
You can customize the guardrails behavior by modifying the `guardrails-values.yaml` file:

```yaml
guardrails:
  config:
    # Enable specific guardrails
    topics:
      - "unwanted_topics"
      - "sensitive_information"
    # Configure response policies
    response_policies:
      - "response_quality"
      - "response_safety"
```

### Resource Scaling
Adjust resource requirements based on your workload:

```yaml
guardrails:
  resources:
    requests:
      memory: "8Gi"
      cpu: "4"
      nvidia.com/gpu: "2"
    limits:
      memory: "16Gi"
      cpu: "8"
      nvidia.com/gpu: "2"
```

## Troubleshooting

### Common Issues

1. **Pod Stuck in Pending State:**
   ```bash
   kubectl describe pod <pod-name> -n nemo-guardrails
   ```
   Check for GPU resource availability and node capacity.

2. **Image Pull Errors:**
   ```bash
   kubectl get events -n nemo-guardrails
   ```
   Verify NGC API key and registry secret configuration.

3. **Service Not Accessible:**
   ```bash
   kubectl get endpoints -n nemo-guardrails
   kubectl logs -n nemo-guardrails -l app=nemo-guardrails
   ```

### Debug Commands
```bash
# Check cluster status
kubectl cluster-info

# Check node resources
kubectl describe nodes

# Check GPU availability
kubectl get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu")'

# Check pod logs
kubectl logs -n nemo-guardrails -l app=nemo-guardrails --tail=100
```

## Cleanup

To avoid incurring further costs, delete the GKE cluster and all associated resources:

```bash
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE
```

## Learn More

Be sure to check out the following resources for more information:
- [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode#why-standard)
- [NVIDIA GPUs](https://cloud.google.com/compute/docs/gpus)
- [NVIDIA NeMo Guardrails](https://docs.nvidia.com/nemo/microservices/latest/set-up/index.html)
- [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
- [NeMo Guardrails Documentation](https://docs.nvidia.com/nemo/microservices/latest/guardrails/index.html)
