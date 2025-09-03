# Configuring Traffic Management with a Load Balancer

## Video

https://youtu.be/Ohx8XJFkjjs

A comprehensive implementation of Google Cloud's Regional Internal Application Load Balancer with blue-green deployment and traffic management capabilities.

## 🎯 Project Overview  

This project demonstrates how to configure a regional internal Application Load Balancer in Google Cloud Platform to implement blue-green deployment patterns with weighted traffic distribution. The load balancer distributes traffic between two backend services:
- **Blue Service**: 70% of traffic (current production version)
- **Green Service**: 30% of traffic (new application version)

## 🏗️ Architecture 

The infrastructure consists of:
- **Network**: Custom VPC (`my-internal-app`) with two subnets
- **Compute**: Two managed instance groups in different zones
- **Load Balancer**: Regional internal Application Load Balancer
- **Traffic Management**: Weighted routing (70/30 split)
- **Health Checks**: TCP health checks for both backend services

```
┌─────────────────────────────────────────────────────────────┐
│                    my-internal-app VPC                     │
│                                                             │
│  ┌─────────────┐              ┌─────────────┐              │
│  │  subnet-a   │              │  subnet-b   │              │
│  │10.10.20.0/24│              │10.10.30.0/24│              │
│  │             │              │             │              │
│  │┌───────────┐│              │┌───────────┐│              │
│  ││instance-  ││              ││instance-  ││              │
│  ││group-1    ││              ││group-2    ││              │
│  ││(Blue 70%) ││              ││(Green 30%)││              │
│  │└───────────┘│              │└───────────┘│              │
│  └─────────────┘              └─────────────┘              │
│         │                             │                    │
│         └─────────────┬─────────────────┘                  │
│                       │                                    │
│              ┌─────────────────┐                           │
│              │ Load Balancer   │                           │
│              │ (10.10.30.5)    │                           │
│              └─────────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Features

- **Blue-Green Deployment**: Seamless application version switching
- **Weighted Traffic Distribution**: 70/30 traffic split between services
- **Health Monitoring**: Automated health checks for backend instances
- **Internal Load Balancing**: Secure, internal-only traffic distribution
- **Multi-Zone Deployment**: High availability across multiple zones

## 📋 Prerequisites 

- Google Cloud Platform account
- Google Cloud SDK installed and configured
- Appropriate IAM permissions for:
  - Compute Engine
  - VPC Networks
  - Load Balancing
  - Cloud Router

## 🛠️ Setup Instructions

### Step 1: Network Infrastructure Setup

The following components are pre-configured in this lab:

1. **VPC Network**: `my-internal-app`
2. **Subnets**:
   - `subnet-a`: 10.10.20.0/24
   - `subnet-b`: 10.10.30.0/24
3. **Instance Groups**:
   - `instance-group-1` (Blue service)
   - `instance-group-2` (Green service)
4. **Firewall Rules**:
   - `app-allow-icmp`: ICMP communication
   - `app-allow-ssh-rdp`: SSH/RDP access
   - `fw-allow-health-checks`: Health check traffic
   - `fw-allow-lb-access`: Load balancer subnet access

### Step 2: Create Test VM

```bash
# Create utility VM for testing
gcloud compute instances create utility-vm \
    --zone=<YOUR_ZONE> \
    --machine-type=e2-medium \
    --subnet=subnet-a \
    --private-network-ip=10.10.20.50 \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

### Step 3: Configure Load Balancer

#### 3.1 Create Proxy Subnet
```bash
# Create proxy-only subnet for load balancer
gcloud compute networks subnets create my-proxy-subnet \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --region=<YOUR_REGION> \
    --network=my-internal-app \
    --range=10.10.40.0/24
```

#### 3.2 Create Health Checks
```bash
# Blue service health check
gcloud compute health-checks create tcp blue-health-check \
    --port=80 \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3

# Green service health check
gcloud compute health-checks create tcp green-health-check \
    --port=80 \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3
```

#### 3.3 Create Backend Services
```bash
# Blue backend service
gcloud compute backend-services create blue-service \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=HTTP \
    --region=<YOUR_REGION> \
    --health-checks=blue-health-check

# Add instance group to blue service
gcloud compute backend-services add-backend blue-service \
    --region=<YOUR_REGION> \
    --instance-group=instance-group-1 \
    --instance-group-zone=<YOUR_ZONE_1>

# Green backend service
gcloud compute backend-services create green-service \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=HTTP \
    --region=<YOUR_REGION> \
    --health-checks=green-health-check

# Add instance group to green service
gcloud compute backend-services add-backend green-service \
    --region=<YOUR_REGION> \
    --instance-group=instance-group-2 \
    --instance-group-zone=<YOUR_ZONE_2>
```

#### 3.4 Create URL Map with Traffic Splitting
```bash
# Create URL map with weighted routing
gcloud compute url-maps create my-ilb-map \
    --default-service=blue-service \
    --region=<YOUR_REGION>

# Import traffic splitting configuration
gcloud compute url-maps import my-ilb-map \
    --source=url-map-config.yaml \
    --region=<YOUR_REGION>
```

#### 3.5 Create Load Balancer
```bash
# Create target HTTP proxy
gcloud compute target-http-proxies create my-ilb-proxy \
    --url-map=my-ilb-map \
    --region=<YOUR_REGION>

# Create forwarding rule
gcloud compute forwarding-rules create my-ilb-forwarding-rule \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --network=my-internal-app \
    --subnet=subnet-b \
    --address=10.10.30.5 \
    --ports=80 \
    --region=<YOUR_REGION> \
    --target-http-proxy=my-ilb-proxy
```

## 🧪 Testing

### Verify Backend Connectivity
```bash
# SSH into utility VM
gcloud compute ssh utility-vm --zone=<YOUR_ZONE>

# Test blue service directly
curl 10.10.20.2

# Test green service directly
curl 10.10.30.2

# Test load balancer
curl 10.10.30.5
```

### Test Traffic Distribution
```bash
# Run multiple requests to verify traffic splitting
for i in {1..10}; do
    curl 10.10.30.5
    echo "Request $i completed"
done
```

Expected results:
- ~70% of requests should be served by instance-group-1 (Blue)
- ~30% of requests should be served by instance-group-2 (Green)

## 📊 Monitoring and Validation

### Key Metrics to Monitor
- **Request Distribution**: Verify 70/30 traffic split
- **Health Check Status**: Ensure both backends are healthy
- **Response Times**: Monitor latency across both services
- **Error Rates**: Track any failed requests

### Validation Commands
```bash
# Check backend service health
gcloud compute backend-services get-health blue-service --region=<YOUR_REGION>
gcloud compute backend-services get-health green-service --region=<YOUR_REGION>

# View load balancer details
gcloud compute forwarding-rules describe my-ilb-forwarding-rule --region=<YOUR_REGION>
```

## 🔄 Blue-Green Deployment Workflow

1. **Deploy Green Version**: Update instance-group-2 with new application version
2. **Health Check**: Verify green deployment is healthy
3. **Gradual Traffic Shift**: Adjust traffic weights (e.g., 50/50, 30/70, 0/100)
4. **Monitor and Validate**: Check metrics and user experience
5. **Complete Cutover**: Route 100% traffic to green (now blue)
6. **Cleanup**: Update blue deployment for next iteration

## 🛡️ Security Considerations

- **Internal Load Balancer**: No external internet exposure
- **Firewall Rules**: Restricted access via specific rules
- **Health Checks**: Automated monitoring prevents unhealthy traffic routing
- **Network Isolation**: Subnets provide logical separation

## 📁 Project Structure

```
.
├── README.md                 # Main documentation
├── docs/                     # Additional documentation
│   ├── architecture.md       # Detailed architecture guide
│   ├── troubleshooting.md    # Common issues and solutions
│   └── deployment-guide.md   # Step-by-step deployment
├── configs/                  # Configuration files
│   ├── url-map-config.yaml   # Traffic routing configuration
│   ├── firewall-rules.yaml   # Firewall configuration
│   └── health-checks.yaml    # Health check definitions
├── scripts/                  # Automation scripts
│   ├── setup.sh             # Complete setup script
│   ├── test.sh              # Testing script
│   └── cleanup.sh           # Resource cleanup
└── examples/                 # Usage examples
    ├── basic-setup.sh        # Basic configuration
    └── advanced-routing.sh   # Advanced traffic management
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Google Cloud Platform documentation
- Google Cloud Load Balancing best practices
- Community contributions and feedback

## 📞 Support

For questions and support:
- Create an issue in this repository
- Check the [troubleshooting guide](docs/troubleshooting.md)
- Review Google Cloud documentation

---
**Note**: Replace `<YOUR_REGION>`, `<YOUR_ZONE>`, `<YOUR_ZONE_1>`, and `<YOUR_ZONE_2>` with your actual GCP region and zone values when implementing this solution.
