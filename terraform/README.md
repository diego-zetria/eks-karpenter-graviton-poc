# EKS Cluster with Karpenter, Graviton & Spot Instances

Terraform code that deploys a production-ready Amazon EKS cluster with [Karpenter](https://karpenter.sh/) for intelligent node autoscaling, supporting both **x86 (AMD64)** and **ARM64 (Graviton)** architectures with **Spot** and **On-Demand** capacity types.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                   │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Public Sub   │  │  Public Sub   │  │  Public Sub   │    │
│  │  AZ-a         │  │  AZ-b         │  │  AZ-c         │    │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │   NAT GW        │                  │              │
│  ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐      │
│  │  Private Sub  │  │  Private Sub  │  │  Private Sub  │    │
│  │  AZ-a         │  │  AZ-b         │  │  AZ-c         │    │
│  │               │  │               │  │               │    │
│  │  ┌─────────┐  │  │  ┌─────────┐  │  │               │    │
│  │  │Karpenter│  │  │  │Karpenter│  │  │               │    │
│  │  │System   │  │  │  │System   │  │  │               │    │
│  │  │(Graviton)│ │  │  │(Graviton)│ │  │               │    │
│  │  │On-Demand│  │  │  │On-Demand│  │  │               │    │
│  │  └─────────┘  │  │  └─────────┘  │  │               │    │
│  │               │  │               │  │               │    │
│  │  ┌─────────┐  │  │  ┌─────────┐  │  │  ┌─────────┐  │   │
│  │  │ Spot    │  │  │  │ Spot    │  │  │  │ Spot    │  │   │
│  │  │ x86/arm │  │  │  │ x86/arm │  │  │  │ x86/arm │  │   │
│  │  │Karpenter│  │  │  │Karpenter│  │  │  │Karpenter│  │   │
│  │  │ Managed │  │  │  │ Managed │  │  │  │ Managed │  │   │
│  │  └─────────┘  │  │  └─────────┘  │  │  └─────────┘  │   │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
│                    ┌──────────────┐                          │
│                    │  EKS Control │                          │
│                    │    Plane     │                          │
│                    └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## What Gets Deployed

| Resource | Description |
|----------|-------------|
| **VPC** | 3 AZs, public + private subnets, single NAT Gateway |
| **EKS Cluster** | Kubernetes 1.33, managed control plane |
| **System Node Group** | Graviton `m7g.medium` (On-Demand) — runs Karpenter controller |
| **Karpenter** | v1.5.0 via Helm, Pod Identity auth, SQS interruption queue |
| **NodePool** | x86 + ARM64, Spot + On-Demand, 6th gen+ instances (c/m/r families) |
| **EC2NodeClass** | Amazon Linux 2023 AMI, auto-discovers subnets and security groups |

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.10
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster interaction

## Usage

### Deploy the Infrastructure

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Configure kubectl

```bash
# Update kubeconfig (command also shown in terraform output)
aws eks update-kubeconfig --region us-east-1 --name opsfleet-eks
```

### Verify Karpenter is Running

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# Check NodePool and EC2NodeClass
kubectl get nodepools
kubectl get ec2nodeclasses
```

### Demo: Deploy on Graviton (ARM64)

```bash
kubectl apply -f examples/graviton-deployment.yaml

# Watch Karpenter provision a Graviton node
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=50 -f

# Verify pod is running on arm64 node
kubectl get pods -l app=graviton-demo -o wide
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type
```

### Demo: Deploy on x86 (AMD64)

```bash
kubectl apply -f examples/x86-deployment.yaml

# Verify pod is running on amd64 node
kubectl get pods -l app=x86-demo -o wide
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type
```

### Demo: Multi-Architecture (Karpenter Chooses)

```bash
kubectl apply -f examples/multi-arch-deployment.yaml

# Karpenter will pick the most cost-effective architecture (typically Spot Graviton)
kubectl get pods -l app=multi-arch-demo -o wide
kubectl get nodes -L kubernetes.io/arch,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

### Cleanup

```bash
# Remove demo workloads first (allows Karpenter to drain nodes)
kubectl delete -f examples/

# Wait for Karpenter nodes to terminate
kubectl get nodes -l karpenter.sh/registered

# Destroy infrastructure
terraform destroy
```

## Cost Optimization Strategy

| Strategy | Implementation |
|----------|---------------|
| **Graviton instances** | ARM64 support in NodePool — ~20% better price-performance vs x86 |
| **Spot instances** | Primary capacity type in NodePool — up to 70% savings vs On-Demand |
| **Consolidation** | `WhenEmptyOrUnderutilized` policy — Karpenter actively right-sizes the cluster |
| **Instance diversity** | Multiple families (c/m/r) and generations — reduces Spot interruptions |
| **Single NAT Gateway** | Cost optimization appropriate for non-production environments |
| **Resource limits** | NodePool limits (100 vCPU, 200Gi) prevent runaway scaling |

## Customization

Override defaults via `terraform.tfvars`:

```hcl
region             = "eu-west-1"
cluster_name       = "my-cluster"
kubernetes_version = "1.33"
vpc_cidr           = "10.1.0.0/16"
```

## Design Decisions

1. **Karpenter system nodes use Graviton** — The managed node group running Karpenter itself uses `m7g.medium` (ARM64) for cost efficiency. These are On-Demand for stability.

2. **Single NodePool for both architectures** — Instead of separate pools per arch, a single pool with `kubernetes.io/arch: In [amd64, arm64]` lets Karpenter optimize across both. Workloads use `nodeSelector` to pin architecture when needed.

3. **Pod Identity over IRSA** — Karpenter uses EKS Pod Identity (the modern approach) instead of IAM Roles for Service Accounts for cleaner IAM management.

4. **AL2023 AMI** — Amazon Linux 2023 provides the latest security patches and supports both x86 and ARM64.

5. **Local state** — For POC simplicity. Production would use S3 + DynamoDB backend.
