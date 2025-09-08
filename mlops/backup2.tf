# backup namespace 생성
resource "kubernetes_namespace" "backup" {
  metadata {
    name = "backup"
  }
}

# SnapScheduler Helm 차트 설치
resource "helm_release" "snapscheduler" {
  name       = "snapscheduler"
  repository = "https://backube.github.io/helm-charts"
  chart      = "snapscheduler"
  version    = "3.5.0"  # 최신 버전
  namespace  = kubernetes_namespace.backup.metadata[0].name

  values = [
    <<-EOT
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
    EOT
  ]
  depends_on = [
    kubernetes_namespace.backup
  ]
}

# VolumeSnapshotClass 생성
resource "kubectl_manifest" "ebs_snapshot_class" {
  yaml_body = <<-YAML
    apiVersion: snapshot.storage.k8s.io/v1
    kind: VolumeSnapshotClass
    metadata:
      name: ebs-snapshot
      annotations:
        snapshot.storage.kubernetes.io/is-default-class: "true"
    driver: ebs.csi.aws.com
    deletionPolicy: Delete
    parameters:
      tagSpecification_1: "Name=EKS-PVC-Backup-{{ .VolumeSnapshotName }}"
      tagSpecification_2: "BackupType=PVC-Automated"
  YAML

  depends_on = [
    helm_release.snapscheduler
  ]
}

locals {
  backup_namespace = ["opensearch"]
}

# SnapScheduler SnapshotSchedule - PVC 백업 스케줄 정의
resource "kubectl_manifest" "pvc_backup_schedule" {
  for_each = toset(local.backup_namespace)

  yaml_body = <<-YAML
    apiVersion: snapscheduler.backube/v1
    kind: SnapshotSchedule
    metadata:
      name: daily-pvc-backup
      namespace: ${each.value}
    spec:
      schedule: "0 19 * * *"  # KST 04:00 (UTC 19:00)
      # schedule: "*/5 * * * *"  # 테스트용: 5분마다
      # 스냅샷 보존 정책 (7일)
      retention:
        # 7일 = 168시간
        expires: "168h"
        # 최대 7개 스냅샷 보존
        maxCount: 7
      # 스냅샷 템플릿
      snapshotTemplate:
        snapshotClassName: ebs-snapshot
        metadata:
          labels:
            created-by: snapscheduler
            backup-type: automated
  YAML

  depends_on = [
    kubectl_manifest.ebs_snapshot_class,
    helm_release.snapscheduler
  ]
}

# Slack 알림용 ServiceAccount
resource "kubernetes_service_account_v1" "slack_notifier" {
  count = var.argocd_slack_app_token != "" ? 1 : 0
  
  metadata {
    name      = "slack-notifier"
    namespace = "backup"
  }
}

# Slack 알림용 ClusterRole
resource "kubernetes_cluster_role_v1" "slack_notifier" {
  count = var.argocd_slack_app_token != "" ? 1 : 0
  
  metadata {
    name = "slack-notifier"
  }
  
  rule {
    api_groups = ["snapshot.storage.k8s.io"]
    resources  = ["volumesnapshots"]
    verbs      = ["get", "list", "watch"]
  }

  # ConfigMap 권한 추가
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "create", "patch", "update"]
  }
}

# Slack 알림용 ClusterRoleBinding
resource "kubernetes_cluster_role_binding_v1" "slack_notifier" {
  count = var.argocd_slack_app_token != "" ? 1 : 0
  
  metadata {
    name = "slack-notifier"
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.slack_notifier[0].metadata[0].name
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.slack_notifier[0].metadata[0].name
    namespace = "backup"
  }
}

# 간편한 Slack 알림 - VolumeSnapshot 생성 감지
resource "kubernetes_deployment_v1" "slack_notifier" {
  count = var.argocd_slack_app_token != "" ? 1 : 0
  
  metadata {
    name      = "slack-backup-notifier"
    namespace = "backup"
    labels = {
      app = "slack-notifier"
    }
  }
  
  spec {
    replicas = 1
    
    selector {
      match_labels = {
        app = "slack-notifier"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "slack-notifier"
        }
      }
      
      spec {
        service_account_name = kubernetes_service_account_v1.slack_notifier[0].metadata[0].name
        
        container {
          name  = "slack-notifier"
          image = "alpine/k8s:1.31.12"
          
          command = ["/bin/bash"]
          args = [
            "-c",
            <<-EOT
            echo "🔔 Slack 알림 서비스 시작 - 디버깅 모드"
            echo "SLACK_BOT_TOKEN: $${SLACK_BOT_TOKEN:0:20}..."
            echo "SLACK_CHANNEL: $SLACK_CHANNEL"
            
            # 프로덕션용: 시간 기반 필터링으로 안정적인 스냅샷 감지
            echo "🔍 VolumeSnapshot 폴링 시작..."
            
            # 마지막 알림 시간을 저장할 파일
            LAST_NOTIFICATION_FILE="/tmp/last_notification_time"
            echo "$(date -u +%s)" > "$LAST_NOTIFICATION_FILE"
            
            while true; do
              echo "🔍 VolumeSnapshot 체크 중... $(date)"
              
              # 마지막 알림 시간 이후에 생성된 readyToUse=true인 스냅샷 찾기
              LAST_TIME=$(cat "$LAST_NOTIFICATION_FILE" 2>/dev/null || echo "$(date -u +%s)")
              CURRENT_TIME=$(date -u +%s)
              
              # 최근 5분 내 생성된 스냅샷만 확인 (너무 오래된 것은 제외)
              RECENT_SNAPSHOTS=$(kubectl get volumesnapshots --all-namespaces -o json | \
                jq -r --arg last_time "$LAST_TIME" --arg current_time "$CURRENT_TIME" \
                '.items[] | select(.status.readyToUse == true) | 
                select(.metadata.creationTimestamp | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime > ($last_time | tonumber)) |
                select(.metadata.creationTimestamp | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime > (($current_time | tonumber) - 300)) |
                "\(.metadata.namespace)/\(.metadata.name)/\(.spec.source.persistentVolumeClaimName)"')
              
              if [ -n "$RECENT_SNAPSHOTS" ]; then
                echo "$RECENT_SNAPSHOTS" | while IFS='/' read -r NAMESPACE SNAPSHOT_NAME PVC_NAME; do
                  echo "📸 새 스냅샷 발견: $SNAPSHOT_NAME"
                  
                  # Slack 메시지 전송
                  RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
                    -H "Content-type: application/json" \
                    --data "{\"channel\":\"$SLACK_CHANNEL\",\"text\":\"✅ EKS PVC 백업 완료\\n• 스냅샷: $SNAPSHOT_NAME\\n• PVC: $PVC_NAME\\n• 네임스페이스: $NAMESPACE\\n• 시간: $(date -d '+9 hours' '+%Y-%m-%d %H:%M:%S KST')\"}" \
                    "https://slack.com/api/chat.postMessage")
                  
                  echo "📤 Slack 응답: $RESPONSE"
                  
                  if echo "$RESPONSE" | grep -q '"ok":true'; then
                    echo "✅ Slack 알림 전송 성공: $SNAPSHOT_NAME"
                    # 마지막 알림 시간 업데이트
                    echo "$CURRENT_TIME" > "$LAST_NOTIFICATION_FILE"
                  else
                    echo "❌ Slack 알림 전송 실패: $RESPONSE"
                  fi
                done
              else
                echo "⏳ 새 스냅샷 없음"
              fi
              
              sleep 30
            done
            EOT
          ]
          
          env {
            name  = "SLACK_BOT_TOKEN"
            value = var.argocd_slack_app_token
          }
          env {
            name  = "SLACK_CHANNEL"
            value = "#${var.argocd_notification_slack_channel}"
          }
          
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
        
        restart_policy = "Always"
      }
    }
  }
  
  depends_on = [
    kubernetes_namespace.backup,
    kubernetes_service_account_v1.slack_notifier,
    kubernetes_cluster_role_v1.slack_notifier,
    kubernetes_cluster_role_binding_v1.slack_notifier
  ]
}