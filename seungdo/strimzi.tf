# # kafaka namespace 생성

# # 1. kafaka namespace 생성
# resource "kubernetes_namespace_v1" "kafka" {
#   metadata {
#     name = "kafka"
#   }
# }

# # 2. kafaka operator 설치
# resource "helm_release" "strimzi_operator" {
#   name      = "kafka-operator"
#   chart     = "oci://quay.io/strimzi-helm/strimzi-kafka-operator"
#   namespace = kubernetes_namespace_v1.kafka.metadata[0].name
#   version   = "0.51.0"

#   values = [
#     templatefile("${path.module}/helm-values/strimzi-operator.yaml", {})
#   ]
# }

# # 3. kafaka cluster 전역 설정 생성
# resource "kubectl_manifest" "kafka-metrics-config" {
#   yaml_body = templatefile("${path.module}/yamls/kafka-metrics-config.yaml", {
#     namespace = kubernetes_namespace_v1.kafka.metadata[0].name
#   })

#   depends_on = [helm_release.strimzi_operator]
# }

# resource "kubectl_manifest" "kafka-cluster" {
#   yaml_body = templatefile("${path.module}/yamls/kafka-cluster.yaml", {
#     namespace = kubernetes_namespace_v1.kafka.metadata[0].name
#   })

#   depends_on = [
#     helm_release.strimzi_operator,
#     kubectl_manifest.kafka-metrics-config
#   ]
# }

# # 4. kafaka nodepool 생성 (실제 브로커/컨트롤러 노드 생성) 확인은 strimzipodset 리소스
# resource "kubectl_manifest" "kafka-nodepool" {
#   yaml_body = templatefile("${path.module}/yamls/kafka-nodepool.yaml", {
#     namespace = kubernetes_namespace_v1.kafka.metadata[0].name
#   })

#   depends_on = [
#     helm_release.strimzi_operator,
#     kubectl_manifest.kafka-cluster
#   ]
# }

# # 5. Prometheus가 Kafka/Exporter 메트릭을 스크랩하도록 PodMonitor 생성
# resource "kubectl_manifest" "strimzi-podmonitor" {
#   yaml_body = templatefile("${path.module}/yamls/strimzi-podmonitor.yaml", {
#     kafka_namespace      = kubernetes_namespace_v1.kafka.metadata[0].name
#     monitoring_namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
#   })

#   depends_on = [
#     helm_release.strimzi_operator,
#     helm_release.prometheus,
#     kubectl_manifest.kafka-cluster
#   ]
# }

