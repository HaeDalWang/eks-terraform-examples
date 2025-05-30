vpc_cidr            = "10.100.0.0/16"
eks_cluster_version = "1.33"
domain_name         = "seungdobae.com"
# 아래 명령어를 통해서 최신 버전 확인 가능
# export K8S_VERSION="1.33"
# al2023: aws ssm get-parameters-by-path --path "/aws/service/eks/optimized-ami/$K8S_VERSION/amazon-linux-2023/" --recursive | jq -cr '.Parameters[].Name' | grep -v "recommended" | awk -F '/' '{print $10}' | sed -r 's/.*(v[[:digit:]]+)$/\1/' | sort | uniq
# bottlerocket: aws ssm get-parameters-by-path --path "/aws/service/bottlerocket/aws-k8s-$K8S_VERSION" --recursive | jq -cr '.Parameters[].Name' | grep -v "latest" | awk -F '/' '{print $7}' | sort | uniq
eks_node_ami_alias_al2023  = "al2023@v20250519"
eks_node_ami_alias_bottlerocket  = "bottlerocket@1.40.0-807acc8b"

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
