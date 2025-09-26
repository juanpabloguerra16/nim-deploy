#!/bin/bash

# NeMo Guardrails Deployment Script
# This script deploys the NeMo Guardrails microservice using Helm

set -e

# Default values
NAMESPACE="nemo-guardrails"
NGC_API_KEY=""
CREATE_SECRET=false

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -k, --ngc-api-key KEY    NGC API key for pulling images and charts"
    echo "  -n, --namespace NAME     Kubernetes namespace (default: nemo-guardrails)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -k YOUR_NGC_API_KEY"
    echo "  $0 --ngc-api-key YOUR_NGC_API_KEY --namespace my-namespace"
    echo ""
    echo "Note: If no NGC API key is provided, the script will attempt to use"
    echo "      existing NGC CLI configuration or prompt for the key."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--ngc-api-key)
            NGC_API_KEY="$2"
            CREATE_SECRET=true
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

echo "🚀 Deploying NeMo Guardrails..."

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not available. Please ensure you have access to a Kubernetes cluster."
    exit 1
fi

# Check if we're connected to a cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

# Create namespace if it doesn't exist
echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Handle NGC API key and create secret if needed
if [[ "$CREATE_SECRET" == true ]]; then
    echo "🔑 Creating NGC registry secret..."
    
               # Delete existing secrets if they exist
           kubectl delete secret nvcrimagepullsecret -n $NAMESPACE --ignore-not-found=true
           kubectl delete secret ngc-api -n $NAMESPACE --ignore-not-found=true

           # Create new secrets
           kubectl create secret docker-registry nvcrimagepullsecret \
               --docker-server=nvcr.io \
               --docker-username='$oauthtoken' \
               --docker-password="$NGC_API_KEY" \
               --docker-email='nemo-guardrails@nvidia.com' \
               --namespace=$NAMESPACE
    
               echo "✅ NGC registry secret created successfully"
           
           # Create NGC API secret for NIM model access
           echo "🔑 Creating NGC API secret for NIM..."
           kubectl create secret generic ngc-api \
               --from-literal=NGC_API_KEY="$NGC_API_KEY" \
               --namespace=$NAMESPACE \
               --dry-run=client -o yaml | kubectl apply -f -
           echo "✅ NGC API secret created successfully"
       else
           echo "🔍 Checking for existing NGC configuration..."
    
    # Check if NGC CLI is configured
    if command -v ngc &> /dev/null; then
        if ngc config current &> /dev/null; then
            echo "✅ Using existing NGC CLI configuration"
        else
            echo "⚠️  NGC CLI not configured. Please provide API key with -k flag or run 'ngc config set apikey YOUR_KEY'"
            exit 1
        fi
    else
        echo "⚠️  NGC CLI not found. Please provide API key with -k flag"
        exit 1
    fi
fi

# Add NGC Helm repositories with authentication
echo "🔗 Adding NGC Helm repositories..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia

# Try to add the nvidia-nemo-microservices repository with authentication
echo "🔗 Adding nvidia-nemo-microservices repository..."
helm repo add nvidia-nemo-microservices https://helm.ngc.nvidia.com/nvidia/nemo-microservices/ \
    --username '$oauthtoken' \
    --password "$NGC_API_KEY"

# Update repositories
echo "🔄 Updating Helm repositories..."
helm repo update

# Check available Helm charts and provide better debugging
echo "🔍 Checking available Helm charts..."

# First, let's see what's in the nvidia repository
echo "📋 All charts in nvidia repository:"
helm search repo nvidia --output table | head -20

echo ""
echo "🔍 Looking specifically for NeMo charts..."

# Try to find NeMo charts in both repositories
echo "🔍 Searching for NeMo charts in nvidia repository..."
NEMO_CHARTS_NVIDIA=$(helm search repo nvidia --output json 2>/dev/null | jq -r '.[] | select(.name | contains("nemo")) | .name' 2>/dev/null || echo "")

echo "🔍 Searching for NeMo charts in nvidia-nemo-microservices repository..."
NEMO_CHARTS_NEMO=$(helm search repo nvidia-nemo-microservices --output json 2>/dev/null | jq -r '.[] | select(.name | contains("nemo")) | .name' 2>/dev/null || echo "")

# Combine results
NEMO_CHARTS=$(echo -e "${NEMO_CHARTS_NVIDIA}\n${NEMO_CHARTS_NEMO}" | grep -v '^$' | sort -u)

if [ -n "$NEMO_CHARTS" ]; then
    echo "✅ Found NeMo charts:"
    echo "$NEMO_CHARTS" | while read -r chart; do
        echo "  - $chart"
    done
    
    # Check if we have the main chart
    if echo "$NEMO_CHARTS" | grep -q "nemo-microservices-helm-chart"; then
        echo "✅ Found nemo-microservices-helm-chart in repository"
        CHART_AVAILABLE=true
        # Get the full chart name for installation
        FULL_CHART_NAME=$(echo "$NEMO_CHARTS" | grep "nemo-microservices-helm-chart" | head -1)
        echo "📋 Will install using: $FULL_CHART_NAME"
    else
        echo "❌ nemo-microservices-helm-chart not found in repository"
        echo "🔍 Looking for alternative deployment approach..."
        
        # Check if we have individual components available
        if echo "$NEMO_CHARTS" | grep -q "nemo-guardrails" && echo "$NEMO_CHARTS" | grep -q "nim-llm"; then
            echo "✅ Found individual components: nemo-guardrails and nim-llm"
            echo "📝 Note: We'll need to deploy these separately or find the main chart"
            CHART_AVAILABLE=false
        else
            echo "❌ No suitable NeMo charts found"
            exit 1
        fi
    fi
else
    echo "❌ No NeMo charts found or error occurred during search"
    echo "🔍 Raw Helm search output:"
    helm search repo nvidia --output json | head -100
    exit 1
fi

# Install NeMo Microservices with Guardrails and NIM enabled
if [ "$CHART_AVAILABLE" = true ]; then
    echo "📥 Installing NeMo Guardrails with NIM LLM..."
    helm install nemo-guardrails "$FULL_CHART_NAME" \
        --namespace $NAMESPACE \
        --values guardrails-values.yaml \
        --timeout 15m
else
    echo "❌ Cannot proceed with installation - required chart not available"
    exit 1
fi

echo "✅ NeMo Guardrails with NIM LLM deployment completed!"
echo ""
echo "📋 To check the status:"
echo "   kubectl get pods -n $NAMESPACE"
echo "   kubectl get services -n $NAMESPACE"
echo ""
echo "🌐 To access the services:"
echo "   # NeMo Guardrails:"
echo "   kubectl port-forward -n $NAMESPACE svc/nemo-guardrails 7331:7331"
echo "   # NIM LLM:"
echo "   kubectl port-forward -n $NAMESPACE svc/nemo-guardrails-nim 8000:8000"
echo ""
echo "📚 For more information, visit:"
echo "   https://docs.nvidia.com/nemo/microservices/latest/set-up/index.html"
echo ""
echo "🔑 NGC API Key Management:"
if [[ "$CREATE_SECRET" == true ]]; then
    echo "   - Kubernetes secret 'nvcrimagepullsecret' created in namespace '$NAMESPACE'"
    echo "   - Secret will be used for pulling NGC images"
    echo "   - To update the key, run this script again with -k flag"
else
    echo "   - Using existing NGC CLI configuration"
    echo "   - To use Kubernetes secret instead, run with -k flag"
fi
