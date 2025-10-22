# # backup namespace 생성
# resource "kubernetes_namespace" "backup" {
#   metadata {
#     name = "backup"
#   }
# }

# # SnapScheduler Helm 차트 설치
# resource "helm_release" "snapscheduler" {
#   name       = "snapscheduler"
#   repository = "https://backube.github.io/helm-charts"
#   chart      = "snapscheduler"
#   version    = "3.5.0"  # 최신 버전
#   namespace  = kubernetes_namespace.backup.metadata[0].name

#   values = [
#     <<-EOT
#     replicaCount: 1
#     resources:
#       requests:
#         cpu: 100m
#         memory: 128Mi
#       limits:
#         cpu: 200m
#         memory: 256Mi
#     EOT
#   ]
#   depends_on = [
#     kubernetes_namespace.backup
#   ]
# }

# # VolumeSnapshotClass 생성
# resource "kubectl_manifest" "ebs_snapshot_class" {
#   yaml_body = <<-YAML
#     apiVersion: snapshot.storage.k8s.io/v1
#     kind: VolumeSnapshotClass
#     metadata:
#       name: ebs-snapshot
#       annotations:
#         snapshot.storage.kubernetes.io/is-default-class: "true"
#     driver: ebs.csi.aws.com
#     deletionPolicy: Delete
#     parameters:
#       tagSpecification_1: "Name=EKS-PVC-Backup-{{ .VolumeSnapshotName }}"
#       tagSpecification_2: "BackupType=PVC-Automated"
#   YAML

#   depends_on = [
#     helm_release.snapscheduler
#   ]
# }

# locals {
#   backup_namespace = ["opensearch"]
# }

# # SnapScheduler SnapshotSchedule - PVC 백업 스케줄 정의
# resource "kubectl_manifest" "pvc_backup_schedule" {
#   for_each = toset(local.backup_namespace)

#   yaml_body = <<-YAML
#     apiVersion: snapscheduler.backube/v1
#     kind: SnapshotSchedule
#     metadata:
#       name: daily-pvc-backup
#       namespace: ${each.value}
#     spec:
#       schedule: "0 19 * * *"  # KST 04:00 (UTC 19:00)
#       # schedule: "*/5 * * * *"  # 테스트용: 5분마다
#       # 스냅샷 보존 정책 (7일)
#       retention:
#         # 7일 = 168시간
#         expires: "168h"
#         # 최대 7개 스냅샷 보존
#         maxCount: 7
#       # 스냅샷 템플릿
#       snapshotTemplate:
#         snapshotClassName: ebs-snapshot
#         metadata:
#           labels:
#             created-by: snapscheduler
#             backup-type: automated
#   YAML

#   depends_on = [
#     kubectl_manifest.ebs_snapshot_class,
#     helm_release.snapscheduler
#   ]
# }

# # Slack 알림용 ServiceAccount
# resource "kubernetes_service_account_v1" "slack_notifier" {
#   count = var.slack_webhook_url != "" ? 1 : 0
  
#   metadata {
#     name      = "slack-notifier"
#     namespace = "backup"
#   }
# }

# # Slack 알림용 ClusterRole
# resource "kubernetes_cluster_role_v1" "slack_notifier" {
#   count = var.slack_webhook_url != "" ? 1 : 0
  
#   metadata {
#     name = "slack-notifier"
#   }
  
#   rule {
#     api_groups = ["snapshot.storage.k8s.io"]
#     resources  = ["volumesnapshots"]
#     verbs      = ["get", "list", "watch"]
#   }

#   # ConfigMap 권한 추가
#   rule {
#     api_groups = [""]
#     resources  = ["configmaps"]
#     verbs      = ["get", "list", "create", "patch", "update"]
#   }
# }

# # Slack 알림용 ClusterRoleBinding
# resource "kubernetes_cluster_role_binding_v1" "slack_notifier" {
#   count = var.slack_webhook_url != "" ? 1 : 0
  
#   metadata {
#     name = "slack-notifier"
#   }
  
#   role_ref {
#     api_group = "rbac.authorization.k8s.io"
#     kind      = "ClusterRole"
#     name      = kubernetes_cluster_role_v1.slack_notifier[0].metadata[0].name
#   }
  
#   subject {
#     kind      = "ServiceAccount"
#     name      = kubernetes_service_account_v1.slack_notifier[0].metadata[0].name
#     namespace = "backup"
#   }
# }

# # 간편한 Slack 알림 - VolumeSnapshot 생성 감지
# resource "kubernetes_deployment_v1" "slack_notifier" {
#   count = var.slack_webhook_url != "" ? 1 : 0
  
#   metadata {
#     name      = "slack-backup-notifier"
#     namespace = "backup"
#     labels = {
#       app = "slack-notifier"
#     }
#   }
  
#   spec {
#     replicas = 1
    
#     selector {
#       match_labels = {
#         app = "slack-notifier"
#       }
#     }
    
#     template {
#       metadata {
#         labels = {
#           app = "slack-notifier"
#         }
#       }
      
#       spec {
#         service_account_name = kubernetes_service_account_v1.slack_notifier[0].metadata[0].name
        
#         container {
#           name  = "slack-notifier"
#           image = "alpine/k8s:1.31.12"
          
#           command = ["/bin/bash"]
#           args = [
#             "-c",
#             <<-EOT
#             echo "🔔 Slack Webhook 알림 서비스 시작 - 디버깅 모드"
#             echo "SLACK_WEBHOOK_URL: $${SLACK_WEBHOOK_URL:0:30}..."
            
#             # 5분마다 새로운 스냅샷들을 한번에 알림하는 방식
#             echo "🔍 VolumeSnapshot 폴링 시작 (5분 간격)..."
            
#             # 마지막 알림 시간을 저장할 파일
#             LAST_NOTIFICATION_FILE="/tmp/last_notification_time"
#             echo "$(date -u +%s)" > "$LAST_NOTIFICATION_FILE"
            
#             while true; do
#               echo "🔍 VolumeSnapshot 체크 중... $(date)"
              
#               # 마지막 알림 시간 이후에 생성된 readyToUse=true인 스냅샷들 찾기
#               LAST_TIME=$(cat "$LAST_NOTIFICATION_FILE" 2>/dev/null || echo "$(date -u +%s)")
#               CURRENT_TIME=$(date -u +%s)
              
#               # 최근 10분 내 생성된 스냅샷들만 확인 (5분 간격이므로 여유있게)
#               RECENT_SNAPSHOTS=$(kubectl get volumesnapshots --all-namespaces -o json | \
#                 jq -r --arg last_time "$LAST_TIME" --arg current_time "$CURRENT_TIME" \
#                 '.items[] | select(.status.readyToUse == true) | 
#                 select(.metadata.creationTimestamp | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime > ($last_time | tonumber)) |
#                 select(.metadata.creationTimestamp | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime > (($current_time | tonumber) - 600)) |
#                 "\(.metadata.namespace)/\(.metadata.name)/\(.spec.source.persistentVolumeClaimName)/\(.metadata.creationTimestamp)"')
              
#               if [ -n "$RECENT_SNAPSHOTS" ]; then
#                 echo "📸 새로운 스냅샷들 발견:"
#                 echo "$RECENT_SNAPSHOTS"
                
#                 # 스냅샷들을 그룹화하여 메시지 구성
#                 SNAPSHOT_COUNT=$(echo "$RECENT_SNAPSHOTS" | wc -l)
                
#                 # 스냅샷 리스트를 간단하게 구성
#                 SNAPSHOT_NAMES=$(echo "$RECENT_SNAPSHOTS" | cut -d'/' -f2 | tr '\n' ',' | sed 's/,$//')
                
#                 # 현재 시간을 KST로 변환 (Alpine Linux 호환)
#                 KST_TIME=$((CURRENT_TIME + 32400))
#                 CURRENT_KST=$(date -u -d "@$KST_TIME" '+%Y-%m-%d %H:%M:%S KST' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S KST')

#                 # Slack Webhook 메시지 전송 (간단한 형식)
#                 MESSAGE="✅ EKS PVC 백업 완료 ($${SNAPSHOT_COUNT}개)\\n스냅샷: $SNAPSHOT_NAMES\\n시간: $CURRENT_KST"
                
#                 echo "📤 전송할 메시지: $MESSAGE"
                
#                 RESPONSE=$(curl -s -X POST -H "Content-type: application/json" \
#                   --data "{\"text\":\"$MESSAGE\"}" \
#                   "$SLACK_WEBHOOK_URL")
                
#                 echo "📤 Slack Webhook 응답: $RESPONSE"
                
#                 # Webhook 성공 응답은 "ok" 문자열
#                 if echo "$RESPONSE" | grep -q "ok"; then
#                   echo "✅ Slack Webhook 알림 전송 성공: $${SNAPSHOT_COUNT}개 스냅샷"
#                   # 마지막 알림 시간 업데이트
#                   echo "$CURRENT_TIME" > "$LAST_NOTIFICATION_FILE"
#                 else
#                   echo "❌ Slack Webhook 알림 전송 실패: $RESPONSE"
#                 fi
#               else
#                 echo "⏳ 새 스냅샷 없음"
#               fi
              
#               # 5분 대기
#               sleep 300
#             done
#             EOT
#           ]
          
#           env {
#             name  = "SLACK_WEBHOOK_URL"
#             value = var.slack_webhook_url
#           }
          
#           resources {
#             requests = {
#               cpu    = "50m"
#               memory = "64Mi"
#             }
#             limits = {
#               cpu    = "100m"
#               memory = "128Mi"
#             }
#           }
#         }
        
#         restart_policy = "Always"
#       }
#     }
#   }
  
#   depends_on = [
#     kubernetes_namespace.backup,
#     kubernetes_service_account_v1.slack_notifier,
#     kubernetes_cluster_role_v1.slack_notifier,
#     kubernetes_cluster_role_binding_v1.slack_notifier
#   ]
# }