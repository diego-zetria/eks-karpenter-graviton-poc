"""
Generate high-level architecture diagram for Innovate Inc.
Requires: pip install diagrams && brew install graphviz
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS, EC2, EC2ContainerRegistry
from diagrams.aws.network import (
    Route53,
    CloudFront,
    ElasticLoadBalancing,
    NATGateway,
)
from diagrams.aws.storage import S3
from diagrams.aws.database import Aurora, ElasticacheForRedis
from diagrams.aws.security import WAF, CertificateManager
from diagrams.aws.management import Cloudwatch
from diagrams.k8s.compute import Pod, Deploy
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.client import Users
from diagrams.onprem.ci import GithubActions

graph_attr = {
    "fontsize": "22",
    "bgcolor": "white",
    "pad": "0.6",
    "nodesep": "0.6",
    "ranksep": "0.8",
}

with Diagram(
    "Innovate Inc. — Cloud Architecture",
    filename="innovate-architecture",
    outformat=["png"],
    direction="TB",
    show=False,
    graph_attr=graph_attr,
):
    users = Users("Users\n(Browser / Mobile)")

    # --- Edge Layer ---
    with Cluster("Edge Layer"):
        dns = Route53("Route 53\n(DNS)")

        with Cluster("Frontend Flow"):
            cdn = CloudFront("CloudFront (CDN)\n+ WAF Edge Rules")
            spa = S3("S3\nReact SPA")

        waf = WAF("WAF\n(OWASP Top 10\nRate Limiting)")

    # --- Supporting services (lateral, not in traffic flow) ---
    with Cluster("Security & Certificates"):
        acm = CertificateManager("ACM\n(TLS Certificates)")

    # --- VPC ---
    with Cluster("VPC 10.0.0.0/16"):

        with Cluster("Public Subnets (3 AZs)"):
            alb = ElasticLoadBalancing("Application\nLoad Balancer")
            nat = NATGateway("NAT Gateway")

        with Cluster("Private Subnets — Compute (3 AZs)"):

            # EKS control plane — managed by AWS, separate from worker nodes
            eks = EKS("EKS Control Plane\n(Managed by AWS)")

            with Cluster("System Nodes — Graviton m7g.medium · On-Demand"):
                karpenter = Pod("Karpenter\nController")
                argocd_pod = Pod("ArgoCD")

            with Cluster("App Nodes — Spot + On-Demand (Karpenter)"):
                flask_pods = Deploy("Flask API\nPods (HPA)")

        with Cluster("Private Subnets — Data (3 AZs)"):
            aurora_w = Aurora("Aurora PG\nWriter")
            aurora_r = Aurora("Aurora PG\nReader (Replica)")
            redis = ElasticacheForRedis("ElastiCache\nRedis")

    # --- CI/CD ---
    with Cluster("CI/CD Pipeline"):
        gh_actions = GithubActions("GitHub Actions\n(Build + Test)")
        ecr = EC2ContainerRegistry("ECR\n(Container Images)")

    # --- Observability ---
    with Cluster("Observability"):
        cw = Cloudwatch("CloudWatch\nPrometheus\nGrafana")

    # ===== Traffic Flows =====

    # Users → DNS
    users >> Edge(color="darkblue", style="bold") >> dns

    # Frontend: DNS → CloudFront (+WAF edge) → S3
    dns >> Edge(label="app.innovate.io", color="forestgreen") >> cdn
    cdn >> spa

    # Backend: DNS → WAF → ALB → Flask
    dns >> Edge(label="api.innovate.io", color="darkorange") >> waf
    waf >> Edge(color="darkorange") >> alb
    alb >> Edge(color="darkorange") >> flask_pods

    # WAF also protects ALB (association)
    waf - Edge(style="dotted", color="firebrick", label="protects") - alb

    # Flask → Data tier
    flask_pods >> Edge(label="queries", color="mediumpurple") >> aurora_w
    flask_pods >> Edge(label="read replicas", style="dashed", color="mediumpurple") >> aurora_r
    flask_pods >> Edge(label="cache / sessions", style="dashed", color="red") >> redis

    # EKS → system pods (control, not traffic)
    eks >> Edge(style="dotted", color="gray") >> karpenter
    eks >> Edge(style="dotted", color="gray") >> argocd_pod
    karpenter >> Edge(label="provisions", style="dashed", color="darkorange") >> flask_pods

    # CI/CD: GitHub Actions → ECR → ArgoCD → Flask
    gh_actions >> Edge(label="build + push", color="gray") >> ecr
    ecr >> Edge(label="image", color="gray") >> argocd_pod
    argocd_pod >> Edge(label="sync / deploy", style="dashed", color="gray") >> flask_pods

    # ACM provides certs to ALB and CloudFront (lateral, not traffic)
    acm - Edge(style="dotted", color="lightgray", label="TLS cert") - alb
    acm - Edge(style="dotted", color="lightgray", label="TLS cert") - cdn

    # Observability connections (multiple sources)
    flask_pods - Edge(style="dotted", color="steelblue") - cw
    alb - Edge(style="dotted", color="steelblue", label="access logs") - cw
    aurora_w - Edge(style="dotted", color="steelblue", label="metrics") - cw
    eks - Edge(style="dotted", color="steelblue") - cw
