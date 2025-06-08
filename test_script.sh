#!/bin/bash

# Google Cloud Load Balancer Testing Script
# This script tests the load balancer functionality and traffic distribution

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOAD_BALANCER_IP="10.10.30.5"
BLUE_SERVICE_IP="10.10.20.2"
GREEN_SERVICE_IP="10.10.30.2"
UTILITY_VM="utility-vm"
PROJECT_ID=""
ZONE=""

# Counters for traffic distribution
BLUE_COUNT=0
GREEN_COUNT=0
TOTAL_REQUESTS=0

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

# Function to get configuration
get_configuration() {
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project)
        if [ -z "$PROJECT_ID" ]; then
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        fi
    fi
    
    if [ -z "$ZONE" ]; then
        read -p "Enter the zone where utility-vm is located (e.g., us-central1-a): " ZONE
    fi
    
    print_status "Using Project: $PROJECT_ID, Zone: $ZONE"
}

# Function to test direct backend connectivity
test_backend_connectivity() {
    print_status "Testing direct backend connectivity..."
    
    echo "Testing Blue service (instance-group-1)..."
    gcloud compute ssh $UTILITY_VM --zone=$ZONE --project=$PROJECT_ID --command="curl -s $BLUE_SERVICE_IP" --quiet
    
    echo
    echo "Testing Green service (instance-group-2)..."
    gcloud compute ssh $UTILITY_VM --zone=$ZONE --project=$PROJECT_ID --command="curl -s $GREEN_SERVICE_IP" --quiet
    
    print_success "Backend connectivity test completed"
}

# Function to test load balancer basic functionality
test_load_balancer_basic() {
    print_status "Testing load balancer basic functionality..."
    
    echo "Testing load balancer at $LOAD_BALANCER_IP..."
    response=$(gcloud compute ssh $UTILITY_VM --zone=$ZONE --project=$PROJECT_ID --command="curl -s $LOAD_BALANCER_IP" --quiet)
    
    if [[ $response == *"Internal Load Balancing Lab"* ]]; then
        print_success "Load balancer is responding correctly"
        echo "Response preview:"
        echo "$response" | head -3
    else
        print_error "Load balancer is not responding as expected"
        echo "Response: $response"
        return 1
    fi
}

# Function to test traffic distribution
test_traffic_distribution() {
    local num_requests=${1:-20}
    print_status "Testing traffic distribution with $num_requests requests..."
    
    BLUE_COUNT=0
    GREEN_COUNT=0
    TOTAL_REQUESTS=0
    
    echo "Sending $num_requests requests to load balancer..."
    
    for i in $(seq 1 $num_requests); do
        response=$(gcloud compute ssh $UTILITY_VM --zone=$ZONE --project=$PROJECT_ID --command="curl -s $LOAD_BALANCER_IP" --quiet)
        
        if [[ $response == *"Zone 1"* ]] || [[ $response == *"instance-group-1"* ]]; then
            ((BLUE_COUNT++))
            echo -n "B"
        elif [[ $response == *"Zone 2"* ]] || [[ $response == *"instance-group-2"* ]]; then
            ((GREEN_COUNT++))
            echo -n "G"
        else
            echo -n "?"
        fi
        
        ((TOTAL_REQUESTS++))
        
        # Add small delay between requests
        sleep 0.1
    done
    
    echo
    echo
    print_status "Traffic distribution results:"
    echo "Blue service (instance-group-1): $BLUE_COUNT requests ($(( BLUE_COUNT * 100 / TOTAL_REQUESTS ))%)"
    echo "Green service (instance-group-2): $GREEN_COUNT requests ($(( GREEN_COUNT * 100 / TOTAL_REQUESTS ))%)"
    echo "Total requests: $TOTAL_REQUESTS"
    
    # Validate traffic distribution (allow some variance)
    local blue_percentage=$((BLUE_COUNT * 100 / TOTAL_REQUESTS))
    local green_percentage=$((GREEN_COUNT * 100 / TOTAL_REQUESTS))
    
    if [ $blue_percentage -ge 60 ] && [ $blue_percentage -le 80 ] && [ $green_percentage -ge 20 ] && [ $green_percentage -le 40 ]; then
        print_success "Traffic distribution is within expected range (Blue: 70%, Green