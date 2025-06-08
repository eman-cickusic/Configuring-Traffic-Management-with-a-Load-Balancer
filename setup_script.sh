#!/bin/bash

# Google Cloud Load Balancer Setup Script
# This script sets up a regional internal Application Load Balancer with blue-green deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
PROJECT_ID=""
REGION=""
ZONE_1=""
ZONE_2=""
NETWORK_NAME="my-internal-app"
SUBNET_A="subnet-a"
SUBNET_B="subnet-b"
PROXY_SUBNET="my-proxy-subnet"
LOAD_BALANCER_NAME="my-ilb"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if gcloud is installed and authenticated
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        print_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to get user input for configuration
get_configuration() {
    print_status "Getting configuration..."
    
    if [ -z "$PROJECT_ID" ]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
    fi
    
    if [ -z "$REGION" ]; then
        read -p "Enter your region (e.g., us-central1): " REGION
    fi
    
    if [ -z "$ZONE_1" ]; then
        read -p "Enter zone 1 (e.g., us-central1-a): " ZONE_1
    fi
    
    if [ -z "$ZONE_2" ]; then
        read -p "Enter zone 2 (e.g., us-central1-b): " ZONE_2
    fi
    
    # Set the project
    gcloud config set project $PROJECT_ID
    
    print_success "Configuration set: Project=$PROJECT_ID, Region=$REGION, Zone1=$ZONE_1, Zone2=$ZONE_2"
}

# Function to create proxy subnet
create_proxy_subnet() {
    print_status "Creating proxy-only subnet..."
    
    if gcloud compute networks subnets describe $PROXY_SUBNET --region=$REGION --project=$PROJECT_ID &> /dev/null; then
        print_warning "Proxy subnet already exists"
    else
        gcloud compute networks subnets create $PROXY_SUBNET \
            --purpose=REGIONAL_MANAGED_PROXY \
            --role=ACTIVE \
            --region=$REGION \
            --network=$NETWORK_NAME \
            --range=10.10.40.0/24 \
            --project=$PROJECT_ID
        
        print_success "Proxy subnet created"
    fi
}

# Function to create health checks
create_health_checks() {
    print_status "Creating health checks..."
    
    # Blue service health check
    if gcloud compute health-checks describe blue-health-check --project=$PROJECT_ID &> /dev/null; then
        print_warning "Blue health check already exists"
    else
        gcloud compute health-checks create tcp blue-health-check \
            --port=80 \
            --check-interval=10s \
            --timeout=5s \
            --healthy-threshold=2 \
            --unhealthy-threshold=3 \
            --project=$PROJECT_ID
        
        print_success "Blue health check created"
    fi
    
    # Green service health check
    if gcloud compute health-checks describe green-health-check --project=$PROJECT_ID &> /dev/null; then
        print_warning "Green health check already exists"
    else
        gcloud compute health-checks create tcp green-health-check \
            --port=80 \
            --check-interval=10s \
            --timeout=5s \
            --healthy-threshold=2 \
            --unhealthy-threshold=3 \
            --project=$PROJECT_ID
        
        print_success "Green health check created"
    fi
}

# Function to create backend services
create_backend_services() {
    print_status "Creating backend services..."
    
    # Blue backend service
    if gcloud compute backend-services describe blue-service --region=$REGION --project=$PROJECT_ID &> /dev/null; then
        print_warning "Blue backend service already exists"
    else
        gcloud compute backend-services create blue-service \
            --load-balancing-scheme=INTERNAL_MANAGED \
            --protocol=HTTP \
            --region=$REGION \
            --health-checks=blue-health-check \
            --project=$PROJECT_ID
        
        # Add instance group to blue service
        gcloud compute backend-services add-backend blue-service \
            --region=$REGION \
            --instance-group=instance-group-1 \
            --instance-group-zone=$ZONE_1 \
            --project=$PROJECT_ID
        
        print_success "Blue backend service created"
    fi
    
    # Green backend service
    if gcloud compute backend-services describe green-service --region=$REGION --project=$PROJECT_ID &> /dev/null; then
        print_warning "Green backend service already exists"
    else
        gcloud compute backend-services create green-service \
            --load-balancing-scheme=INTERNAL_MANAGED \
            --protocol=HTTP \
            --region=$REGION \
            --health-checks=green-health-check \
            --project=$PROJECT_ID
        
        # Add instance group to green service
        gcloud compute backend-services add-backend green-service \
            --region=$REGION \
            --instance-group=instance-group-2 \
            --instance-group-zone=$ZONE_2 \
            --project=$PROJECT_ID
        
        print_success "Green backend service created"
    fi
}

# Function to create URL map
create_url_map() {
    print_status "Creating URL map with traffic splitting..."
    
    if gcloud compute url-maps describe my-ilb-map --region=$REGION --project=$PROJECT_ID &> /dev/null; then
        print_warning "URL map already exists"
    else
        # Create temporary URL map config file
        cat > /tmp/url-map-config.yaml << EOF
name: my-ilb-map
defaultService: regions/$REGION/backendServices/blue-service
hostRules:
- hosts:
  - '*'
  pathMatcher: matcher1
pathMatchers:
- name: matcher1
  defaultService: regions/$REGION/backendServices/blue-service
  routeRules:
  - priority: 0
    matchRules:
    - prefixMatch: /
    routeAction:
      weightedBackendServices:
      - backendService: regions/$REGION/backendServices/blue-service
        weight: 70
      - backendService: regions/$REGION/backendServices/green-service
        weight: 30
EOF
        
        # Create URL map
        gcloud compute url-maps create my-ilb-map \
            --default-service=blue-service \
            --region=$REGION \
            --project=$PROJECT_ID
        
        # Import traffic splitting configuration
        gcloud compute url-maps import my-ilb-map \
            --source=/tmp/url-map-config.yaml \
            --region=$REGION \
            --project=$PROJECT_ID
        
        # Clean up temporary file
        rm /tmp/url-map-config.yaml
        
        print_success "URL map created with traffic splitting"
    fi
}

# Function to create load balancer
create_load_balancer() {
    print_status "Creating load balancer..."
    
    # Create target HTTP proxy
    if gcloud compute target-http-proxies describe my-ilb-proxy --region=$REGION --project=$PROJECT_ID &> /dev/null; then
        print_warning "Target HTTP proxy already exists"
    else
        gcloud compute target-http-proxies create my-ilb-proxy \
            --url-map=my-ilb-map \
            --region=$REGION \
            --project=$PROJECT_ID
        
        print_success "Target HTTP proxy created"
    fi
    
    # Create forwarding rule
    if gcloud compute forwarding-rules describe my-ilb-forwarding-rule --region=$REGION --project=$PROJECT_ID &> /dev/null; then
        print_warning "Forwarding rule already exists"
    else
        gcloud compute forwarding-rules create my-ilb-forwarding-rule \
            --load-balancing-scheme=INTERNAL_MANAGED \
            --network=$NETWORK_NAME \
            --subnet=$SUBNET_B \
            --address=10.10.30.5 \
            --ports=80 \
            --region=$REGION \
            --target-http-proxy=my-ilb-proxy \
            --target-http-proxy-region=$REGION \
            --project=$PROJECT_ID
        
        print_success "Forwarding rule created"
    fi
}

# Function to create utility VM
create_utility_vm() {
    print_status "Creating utility VM for testing..."
    
    if gcloud compute instances describe utility-vm --zone=$ZONE_1 --project=$PROJECT_ID &> /dev/null; then
        print_warning "Utility VM already exists"
    else
        gcloud compute instances create utility-vm \
            --zone=$ZONE_1 \
            --machine-type=e2-medium \
            --subnet=$SUBNET_A \
            --private-network-ip=10.10.20.50 \
            --no-address \
            --image-family=debian-12 \
            --image-project=debian-cloud \
            --project=$PROJECT_ID
        
        print_success "Utility VM created"
    fi
}

# Function to verify setup
verify_setup() {
    print_status "Verifying setup..."
    
    # Check backend services health
    print_status "Checking backend services health..."
    gcloud compute backend-services get-health blue-service --region=$REGION --project=$PROJECT_ID
    gcloud compute backend-services get-health green-service --region=$REGION --project=$PROJECT_ID
    
    # Display load balancer details
    print_status "Load balancer details:"
    gcloud compute forwarding-rules describe my-ilb-forwarding-rule --region=$REGION --project=$PROJECT_ID
    
    print_success "Setup verification completed"
}

# Function to display next steps
display_next_steps() {
    print_success "Load balancer setup completed successfully!"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. SSH into the utility VM:"
    echo "   gcloud compute ssh utility-vm --zone=$ZONE_1 --project=$PROJECT_ID"
    echo
    echo "2. Test the load balancer:"
    echo "   curl 10.10.30.5"
    echo
    echo "3. Test traffic distribution:"
    echo "   for i in {1..10}; do curl 10.10.30.5; done"
    echo
    echo "4. Expected results:"
    echo "   - ~70% requests from instance-group-1 (Blue service)"
    echo "   - ~30% requests from instance-group-2 (Green service)"
    echo
    echo -e "${BLUE}Load balancer IP:${NC} 10.10.30.5"
    echo -e "${BLUE}Blue service IP:${NC} 10.10.20.2"
    echo -e "${BLUE}Green service IP:${NC} 10.10.30.2"
}

# Main execution
main() {
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}  Google Cloud Load Balancer Setup   ${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo
    
    check_prerequisites
    get_configuration
    
    echo
    print_status "Starting load balancer setup..."
    
    create_proxy_subnet
    create_health_checks
    create_backend_services
    create_url_map
    create_load_balancer
    create_utility_vm
    
    echo
    verify_setup
    
    echo
    display_next_steps
}

# Run main function
main "$@"