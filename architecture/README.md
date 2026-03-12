# Architecture Design — Innovate Inc.

## Overview

This document presents the cloud architecture for Innovate Inc.'s web application: a **Python/Flask REST API** backend with a **React SPA** frontend, backed by **PostgreSQL**. The design addresses the full growth trajectory from hundreds of daily users to millions, with strong security, high availability, and CI/CD automation.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Cloud Environment Structure](#2-cloud-environment-structure)
3. [Network Design](#3-network-design)
4. [Compute Platform](#4-compute-platform)
5. [Database](#5-database)
6. [CI/CD Pipeline](#6-cicd-pipeline)
7. [Observability](#7-observability)
8. [Cost Optimization](#8-cost-optimization)

---

## 1. High-Level Architecture

```
    Users (Browser / Mobile)
              │
              ▼
  ┌───────────────────────────────────────────────────────────────────────┐
  │  EDGE LAYER                                                          │
  │                                                                      │
  │   ┌──────────┐      ┌─────────────────┐      ┌──────────────────┐   │
  │   │ Route 53 │─────▶│ ACM Certificate │      │  AWS Shield      │   │
  │   │  (DNS)   │      │   (TLS/HTTPS)   │      │  (DDoS protect)  │   │
  │   └────┬─────┘      └─────────────────┘      └──────────────────┘   │
  │        │                                                             │
  │        ├──── app.innovate.io ────┐                                   │
  │        │                         │                                   │
  │        │  api.innovate.io        ▼                                   │
  │        │                 ┌──────────────┐     ┌───────────┐         │
  │        │                 │  CloudFront  │────▶│  S3       │         │
  │        │                 │  (CDN)       │     │ React SPA │         │
  │        │                 │  + WAF Edge  │     │ (Static)  │         │
  │        │                 └──────────────┘     └───────────┘         │
  │        ▼                                                             │
  │  ┌───────────┐                                                       │
  │  │ WAF (API) │  OWASP Top 10, rate limiting, geo-blocking           │
  │  └─────┬─────┘                                                       │
  └────────┼─────────────────────────────────────────────────────────────┘
           │
           ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │  NETWORK LAYER — VPC (10.0.0.0/16)                                    │
  │                                                                        │
  │  ┌─── Public Subnets ──────────────────────────────────────────────┐  │
  │  │                                                                  │  │
  │  │  ┌───────────────┐     ┌──────────┐     ┌──────────┐           │  │
  │  │  │  ALB (API)    │     │  NAT GW  │     │  NAT GW  │           │  │
  │  │  │  HTTPS → 8000 │     │  (AZ-a)  │     │  (AZ-b)  │           │  │
  │  │  └───────┬───────┘     └──────────┘     └──────────┘           │  │
  │  └──────────┼──────────────────────────────────────────────────────┘  │
  │             │                                                          │
  │             ▼                                                          │
  │  ┌─── Private Subnets (Compute) ───────────────────────────────────┐  │
  │  │                                                                  │  │
  │  │    AZ-a               AZ-b               AZ-c                   │  │
  │  │  ┌───────────┐     ┌───────────┐     ┌───────────┐             │  │
  │  │  │ EKS Node  │     │ EKS Node  │     │ EKS Node  │             │  │
  │  │  │ (Graviton) │     │ (Graviton) │     │ (x86/arm) │             │  │
  │  │  │           │     │           │     │           │             │  │
  │  │  │ ┌───────┐ │     │ ┌───────┐ │     │ ┌───────┐ │             │  │
  │  │  │ │ Flask │ │     │ │ Flask │ │     │ │ Flask │ │             │  │
  │  │  │ │API Pod│ │     │ │API Pod│ │     │ │API Pod│ │             │  │
  │  │  │ └───────┘ │     │ └───────┘ │     │ └───────┘ │             │  │
  │  │  │ ┌───────┐ │     │ ┌───────┐ │     │           │             │  │
  │  │  │ │Karpent│ │     │ │ArgoCD │ │     │           │             │  │
  │  │  │ │  er   │ │     │ │       │ │     │           │             │  │
  │  │  │ └───────┘ │     │ └───────┘ │     │           │             │  │
  │  │  └───────────┘     └───────────┘     └───────────┘             │  │
  │  └──────────────────────────┬───────────────────────────────────────┘  │
  │                             │                                          │
  │                             ▼                                          │
  │  ┌─── Private Subnets (Data) ──────────────────────────────────────┐  │
  │  │                                                                  │  │
  │  │  ┌────────────────┐     ┌────────────────┐     ┌─────────────┐  │  │
  │  │  │ Aurora PG      │     │ Aurora PG      │     │ ElastiCache │  │  │
  │  │  │ Primary (AZ-a) │     │ Replica (AZ-b) │     │ Redis       │  │  │
  │  │  │ Writer         │     │ Reader         │     │ (Sessions + │  │  │
  │  │  │                │     │ Auto-failover  │     │  Caching)   │  │  │
  │  │  └────────────────┘     └────────────────┘     └─────────────┘  │  │
  │  └──────────────────────────────────────────────────────────────────┘  │
  │                                                                        │
  │  ┌─── VPC Endpoints (Private Connectivity) ────────────────────────┐  │
  │  │  S3 · ECR · STS · CloudWatch · SQS                              │  │
  │  └──────────────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────────────┘

  Traffic Flows:
    Frontend:  Route53 → CloudFront (+ WAF edge rules) → S3 (React SPA)
    Backend:   Route53 → WAF → ALB → EKS Pods (Flask API) → Aurora/Redis
```

---

## 2. Cloud Environment Structure

### Recommended AWS Account Structure

| Account | Purpose | Justification |
|---------|---------|---------------|
| **Management** | AWS Organizations root, billing, SSO | Centralized governance, consolidated billing |
| **Shared Services** | CI/CD (GitHub Actions runners), ECR, monitoring | Shared tooling avoids duplication across environments |
| **Development** | Dev and staging environments | Isolation from production; developers have broader access |
| **Production** | Production workloads only | Strictest access controls, separate blast radius |
| **Security/Audit** | CloudTrail logs, GuardDuty, Security Hub | Centralized security — no one can tamper with audit logs |

### Why 5 accounts instead of 1?

- **Blast radius isolation**: A misconfiguration in dev cannot impact production
- **Billing clarity**: Per-environment cost attribution without tagging complexity
- **Security boundaries**: Production IAM policies are strictly scoped; audit logs are immutable in a separate account
- **Compliance**: Separation of duties — developers can't access production data directly
- **AWS Organizations SCPs**: Enforce guardrails (e.g., block regions, require encryption) at the organizational level

**For the startup's initial phase** (hundreds of users), start with 3 accounts: Management, Development, Production. Add Shared Services and Security accounts as the team and compliance requirements grow.

---

## 3. Network Design

### VPC Architecture (per environment)

```
┌─────────────────── VPC (10.0.0.0/16) ───────────────────┐
│                                                           │
│  ┌─── Public Subnets ──────────────────────────────────┐ │
│  │  10.0.1.0/24 (AZ-a)  │  10.0.2.0/24 (AZ-b)  │ AZ-c│ │
│  │  ┌─────┐  ┌─────┐    │  ┌─────┐               │     │ │
│  │  │ NAT │  │ ALB │    │  │ NAT │               │     │ │
│  │  │ GW  │  │     │    │  │ GW  │               │     │ │
│  │  └─────┘  └─────┘    │  └─────┘               │     │ │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─── Private Subnets (Application) ──────────────────┐ │
│  │  10.0.10.0/24 (AZ-a) │ 10.0.11.0/24 (AZ-b) │ AZ-c │ │
│  │  ┌──────────┐        │ ┌──────────┐          │     │ │
│  │  │ EKS Nodes│        │ │ EKS Nodes│          │     │ │
│  │  │ (Flask)  │        │ │ (Flask)  │          │     │ │
│  │  └──────────┘        │ └──────────┘          │     │ │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─── Private Subnets (Data) ─────────────────────────┐ │
│  │  10.0.20.0/24 (AZ-a) │ 10.0.21.0/24 (AZ-b) │ AZ-c │ │
│  │  ┌──────────┐        │ ┌──────────┐          │     │ │
│  │  │ Aurora   │        │ │ Aurora   │          │     │ │
│  │  │ Primary  │        │ │ Replica  │          │     │ │
│  │  └──────────┘        │ └──────────┘          │     │ │
│  └───────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

### Network Security Approach

| Layer | Control | Description |
|-------|---------|-------------|
| **Edge** | AWS WAF + Shield | OWASP Top 10 protection, DDoS mitigation, rate limiting |
| **Ingress** | ALB + Security Groups | Only ports 80/443 from internet to ALB; ALB to EKS pods only |
| **Pod-to-Pod** | Kubernetes Network Policies | Default deny all, explicit allow between Flask and database |
| **Data tier** | Security Groups | Database accepts traffic only from EKS node security group |
| **Egress** | NAT Gateway | All outbound traffic through NAT; VPC Flow Logs for audit |
| **Encryption** | TLS everywhere | ACM certificates on ALB; in-transit encryption to Aurora; KMS for data at rest |
| **DNS** | Private Hosted Zones | Internal service discovery without public exposure |
| **Access** | VPC Endpoints | Private connectivity to AWS services (S3, ECR, STS) — no internet traversal |

**Additional security controls:**
- **GuardDuty**: Threat detection for anomalous API calls and network activity
- **Security Hub**: Centralized security posture dashboard with CIS/PCI benchmarks
- **CloudTrail**: All API calls logged to the Security account (immutable)
- **IAM**: Least-privilege roles, no long-lived credentials, OIDC for CI/CD

---

## 4. Compute Platform

### Kubernetes (EKS) Strategy

#### Cluster Configuration

| Aspect | Configuration | Rationale |
|--------|--------------|-----------|
| **Service** | Amazon EKS (managed) | Reduces operational overhead, automatic control plane updates |
| **Version** | Latest stable (1.35) | Security patches, latest features, in-place pod resource updates |
| **Node scaling** | Karpenter | Right-sized nodes, Spot + Graviton support, faster than Cluster Autoscaler |
| **Regions** | Single region (us-east-1) initially | Cost efficiency; multi-region when traffic justifies it |
| **AZs** | 3 availability zones | High availability |

#### Node Groups & Scaling

**System Node Group** (managed, always-on):
- Instance: `m7g.medium` (Graviton) — runs Karpenter, CoreDNS, monitoring
- Capacity: On-Demand (stability required)
- Size: 2-3 nodes

**Application Nodes** (Karpenter-managed):
- Architectures: x86 and ARM64 (Graviton)
- Capacity: Spot (primary) with On-Demand fallback
- Instance families: c7g, m7g, r7g (Graviton); c6i, m6i (x86)
- Scaling: Automatic based on pending pods; consolidation when underutilized
- Disruption budget: Configured to handle Spot interruptions gracefully

**Resource Allocation:**
- Flask pods: `requests: {cpu: 250m, memory: 256Mi}`, `limits: {cpu: 1, memory: 512Mi}`
- HPA: Scale 2 → 50 pods based on CPU (70%) and custom metrics (requests/sec)
- PodDisruptionBudgets: `minAvailable: 50%` for zero-downtime during node rotations

#### Containerization Strategy

**Image Building:**
```
Developer pushes code → GitHub Actions triggers →
  1. Multi-arch build (docker buildx: linux/amd64 + linux/arm64)
  2. Security scan (Trivy)
  3. Push to ECR (tagged with git SHA + environment)
  4. Image signing (cosign/Sigstore)
```

**Registry:**
- Amazon ECR with lifecycle policies (keep last 30 images per env)
- Immutable tags enabled — no tag overwriting
- Vulnerability scanning on push

**Deployment Process:**
```
Image pushed to ECR → ArgoCD detects new image →
  1. Syncs Kubernetes manifests from Git
  2. Rolling update (maxSurge: 25%, maxUnavailable: 0)
  3. Readiness probes must pass before traffic shifts
  4. Automatic rollback on failed health checks
```

**Helm Charts:**
- One chart per service (backend API, frontend, workers)
- Values files per environment: `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`
- Chart versioned independently from application code

---

## 5. Database

### Recommended Service: Amazon Aurora PostgreSQL

| Criteria | Aurora PostgreSQL | RDS PostgreSQL | Why Aurora Wins |
|----------|-------------------|----------------|-----------------|
| **Performance** | 3-5x faster than standard PostgreSQL | Standard | Query-intensive REST API benefits |
| **Scalability** | Up to 15 read replicas, auto-scaling storage | Limited | Supports growth to millions of users |
| **HA** | 6-way replication across 3 AZs (automatic) | Multi-AZ failover | Faster failover (<30s), no data loss |
| **Cost at scale** | More efficient at high throughput | Cheaper at low scale | Startup will scale — Aurora pays off |
| **Serverless option** | Aurora Serverless v2 | N/A | Scale to zero during low traffic (dev/staging) |

**Recommendation:** Start with **Aurora Serverless v2** for dev/staging (scale to zero = minimal cost), **Aurora Provisioned** for production with read replicas as traffic grows.

### Backup Strategy

| Component | Approach | RPO/RTO |
|-----------|----------|---------|
| **Continuous backups** | Aurora automatic backups (35-day retention) | RPO: 5 min |
| **Snapshots** | Daily automated snapshots + pre-deployment manual snapshots | RPO: 24h (worst case) |
| **Cross-region** | Snapshot copy to us-west-2 via AWS Backup | DR recovery |
| **Point-in-time recovery** | Aurora PITR to any second within retention | RPO: ~1 sec |
| **Logical backups** | Weekly `pg_dump` to S3 (for corruption scenarios) | Complements physical backups |

### High Availability

- **Multi-AZ by default**: Aurora replicates data 6 ways across 3 AZs
- **Failover**: Automatic, <30 seconds, DNS-based endpoint routing
- **Read replicas**: Add up to 15 for read scaling; Aurora auto-promotes on primary failure
- **Connection pooling**: PgBouncer sidecar or RDS Proxy to handle connection storms during scaling events

### Disaster Recovery

| Scenario | Strategy | RTO |
|----------|----------|-----|
| **AZ failure** | Automatic failover to replica in another AZ | < 30s |
| **Region failure** | Aurora Global Database (async replication to us-west-2) | < 1 min |
| **Data corruption** | Point-in-time recovery or snapshot restore | 15-30 min |
| **Accidental deletion** | Deletion protection enabled + snapshot restore | 15-30 min |

---

## 6. CI/CD Pipeline

```
┌──────────┐     ┌───────────┐     ┌──────────┐     ┌──────────┐
│  GitHub   │────▶│  GitHub   │────▶│   ECR    │────▶│  ArgoCD  │
│  (Code)   │     │  Actions  │     │ (Images) │     │  (Deploy) │
└──────────┘     └─────┬─────┘     └──────────┘     └────┬─────┘
                       │                                   │
                 ┌─────┴─────┐                      ┌─────┴─────┐
                 │  Tests    │                      │   EKS     │
                 │  Lint     │                      │  Cluster  │
                 │  Scan     │                      └───────────┘
                 └───────────┘

Pipeline Stages:
PR → Lint + Unit Tests + SAST → Build Multi-Arch Image → Trivy Scan →
Push to ECR → Update Manifest Repo → ArgoCD Sync → Smoke Tests
```

**GitOps model:**
- Application code and Kubernetes manifests in separate repos
- ArgoCD watches the manifest repo; any change triggers deployment
- Rollback = `git revert` on the manifest repo

---

## 7. Observability

| Pillar | Tool | Purpose |
|--------|------|---------|
| **Metrics** | Prometheus + Grafana | Application and infrastructure metrics, Karpenter node metrics, HPA decisions |
| **Logs** | Loki + Fluentd | Centralized log aggregation from all pods and nodes |
| **Traces** | Tempo + OpenTelemetry | Distributed tracing for Flask API requests |
| **Alerts** | Alertmanager + PagerDuty | On-call alerting for SLO breaches |
| **Dashboards** | Grafana | SLI/SLO monitoring, cost dashboards (Kubecost), Karpenter node utilization |

**Deployment:** Full observability stack deployed via Helm on the EKS cluster. OpenTelemetry Collector as a DaemonSet for metrics/logs/traces collection. Grafana dashboards pre-configured for application latency (p50/p95/p99), error rates, and infrastructure utilization.

**Key SLIs:**
- API latency: p99 < 500ms
- Error rate: < 0.1%
- Availability: 99.9% uptime

---

## 8. Cost Optimization

### Growth Phases

| Phase | Users | Key Optimizations |
|-------|-------|-------------------|
| **Launch** | Hundreds/day | Aurora Serverless v2, single NAT GW, Spot nodes, minimal replicas |
| **Growth** | Thousands/day | Add read replicas, CDN caching, HPA tuning, Graviton nodes |
| **Scale** | Millions/day | Multi-AZ NAT GWs, Aurora Global DB, multi-region CDN, reserved capacity for baseline |

### Estimated Monthly Costs (Launch Phase)

| Service | Estimated Cost |
|---------|---------------|
| EKS Control Plane | $73 |
| EC2 (Karpenter, Spot Graviton) | ~$50-100 |
| Aurora Serverless v2 | ~$30-60 |
| NAT Gateway | ~$35 |
| ALB | ~$20 |
| CloudFront + S3 | ~$5 |
| **Total** | **~$215-295/month** |

---

## Summary

This architecture provides Innovate Inc. with a **scalable, secure, and cost-effective** foundation that grows from hundreds to millions of users. Key decisions:

1. **Multi-account AWS** structure for isolation and security
2. **EKS + Karpenter** for intelligent, cost-optimized Kubernetes
3. **Aurora PostgreSQL** for performance, HA, and seamless scaling
4. **GitOps with ArgoCD** for reliable, auditable deployments
5. **Security-first** with WAF, encryption, least-privilege IAM, and centralized audit
