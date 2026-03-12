# OpsFleet Tech Assignment v1.2.0

This repository contains the technical assessment for OpsFleet, consisting of two deliverables:

## Repository Structure

```
.
├── terraform/      # Task 1: EKS + Karpenter + Graviton/Spot infrastructure
└── architecture/   # Task 2: Architecture design for "Innovate Inc."
```

## Task 1: Technical — EKS with Karpenter

Terraform code that deploys a production-ready EKS cluster with Karpenter autoscaling, supporting both x86 and ARM64 (Graviton) instances with Spot optimization.

See [terraform/README.md](terraform/README.md) for full details.

## Task 2: Architecture — Innovate Inc.

Architecture design for a Flask/React web application on AWS, covering environment structure, networking, compute, database, and CI/CD.

See [architecture/README.md](architecture/README.md) for full details.

## Author

Diego Ramos — Senior DevOps/SRE Engineer
