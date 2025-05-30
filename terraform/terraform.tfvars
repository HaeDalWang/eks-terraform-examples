vpc_cidr            = "10.100.0.0/16"
eks_cluster_version = "1.32"
domain_name         = "seungdobae.com"
eks_node_ami_alias  = "al2023@v20250410"

# 기준일: 2025년 5월 29일
karpenter_chart_version                    = "1.5.0"
aws_load_balancer_controller_chart_version = "1.13.2"
ingress_nginx_chart_version                = "4.12.2"
argocd_chart_version                       = "8.0.11"
kube_prometheus_stack_chart_version        = "72.6.3"
thanos_chart_version                       = "16.0.7" # bitnami
k8tz_chart_version                         = "0.16.2"
kong_chart_version                         = "2.48.0"
# keycloak_chart_version                     = "22.1.0"
# kubernetes_event_exporter_chart_version    = "3.2.10"
# external_dns_chart_version                 = "1.14.5"
