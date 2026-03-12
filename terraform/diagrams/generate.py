"""
Generate architecture diagram for the EKS + Karpenter Terraform deployment.
Requires: pip install diagrams && brew install graphviz
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EKS, EC2
from diagrams.aws.network import NATGateway
from diagrams.aws.integration import SQS
from diagrams.aws.security import IAMRole
from diagrams.k8s.compute import Pod, Deploy

graph_attr = {
    "fontsize": "22",
    "bgcolor": "white",
    "pad": "0.6",
    "nodesep": "0.7",
    "ranksep": "0.9",
}

with Diagram(
    "EKS Cluster with Karpenter, Graviton & Spot",
    filename="eks-karpenter-architecture",
    outformat=["png"],
    direction="TB",
    show=False,
    graph_attr=graph_attr,
):

    with Cluster("AWS Account — us-east-1"):

        # Account-level services (outside VPC)
        with Cluster("Account-Level Services"):
            iam = IAMRole("Pod Identity\n(Karpenter)")
            sqs = SQS("SQS Interruption\nQueue")

        with Cluster("VPC 10.0.0.0/16"):

            # EKS control plane — managed by AWS, not inside subnets
            eks = EKS("EKS Control Plane\n(Managed by AWS)")

            with Cluster("Public Subnets (3 AZs)"):
                nat = NATGateway("NAT Gateway\n(Outbound traffic)")

            with Cluster("Private Subnets (3 AZs)"):

                with Cluster("System Node Group — Graviton m7g.medium · On-Demand"):
                    karpenter = Pod("Karpenter\nController")
                    coredns = Pod("CoreDNS")

                with Cluster("Karpenter-Managed Nodes — Spot primary, On-Demand fallback"):
                    with Cluster("ARM64 (Graviton)"):
                        node_arm = EC2("c7g / m7g / r7g")
                        deploy_arm = Deploy("arm64 workloads")

                    with Cluster("AMD64 (x86)"):
                        node_x86 = EC2("c6i / m6i / r6i")
                        deploy_x86 = Deploy("amd64 workloads")

    # EKS manages system pods
    eks >> Edge(color="darkblue", style="bold") >> karpenter
    eks >> Edge(color="darkblue") >> coredns

    # Karpenter provisions compute nodes
    karpenter >> Edge(label="provisions", style="dashed", color="darkorange") >> node_arm
    karpenter >> Edge(label="provisions", style="dashed", color="darkorange") >> node_x86

    # Nodes run workloads
    node_arm >> deploy_arm
    node_x86 >> deploy_x86

    # Karpenter uses account-level services
    karpenter - Edge(label="auth", style="dotted", color="forestgreen") - iam
    karpenter - Edge(label="spot interruption handling", style="dotted", color="mediumpurple") - sqs
