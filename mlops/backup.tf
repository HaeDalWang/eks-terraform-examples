# # EBS 스냅샷 백업 시스템
# # 이즐랩스 장승국님 요청사항에 따른 최소한의 EBS 백업 구성

# # SNS 토픽 (슬랙 알림용)
# resource "aws_sns_topic" "backup_notifications" {
#   name = "${local.project}-backup-notifications"
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-backup-notifications"
#     Purpose = "EBS backup notifications"
#   })
# }

# # SNS 토픽 정책 (슬랙 웹훅 접근 허용)
# resource "aws_sns_topic_policy" "backup_notifications" {
#   arn = aws_sns_topic.backup_notifications.arn

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           Service = "events.amazonaws.com"
#         }
#         Action = "sns:Publish"
#         Resource = aws_sns_topic.backup_notifications.arn
#       }
#     ]
#   })
# }

# # SSM Automation 문서 - EBS 스냅샷 생성
# resource "aws_ssm_document" "ebs_backup_automation" {
#   name          = "${local.project}-ebs-backup-automation"
#   document_type = "Automation"
#   document_format = "YAML"

#   content = <<-EOT
#     schemaVersion: '0.3'
#     description: 'EBS 볼륨 스냅샷 생성 및 정리'
#     parameters:
#       RetentionDays:
#         type: String
#         default: '7'
#         description: '스냅샷 보존 기간 (일)'
#       ClusterName:
#         type: String
#         default: '${module.eks.cluster_name}'
#         description: 'EKS 클러스터 이름'
#     mainSteps:
#     - action: aws:executeAwsApi
#       name: ListEBSVolumes
#       inputs:
#         Service: ec2
#         Api: DescribeVolumes
#         Filters:
#         - Name: tag:kubernetes.io/cluster/{{ClusterName}}
#           Values: ['owned']
#         - Name: tag:ebs.csi.aws.com/cluster
#           Values: ['true']
#         - Name: state
#           Values: ['available', 'in-use']
#       outputs:
#       - Name: VolumeIds
#         Selector: '$.Volumes[*].VolumeId'
#         Type: StringList
#     - action: aws:executeAwsApi
#       name: CreateSnapshots
#       inputs:
#         Service: ec2
#         Api: CreateSnapshot
#         VolumeId: '{{ListEBSVolumes.VolumeIds}}'
#         Description: 'EKS PVC 백업 - {{ClusterName}} - {{global:DATE_TIME}}'
#         TagSpecifications:
#         - ResourceType: snapshot
#           Tags:
#           - Key: Name
#             Value: 'EKS-PVC-Backup-{{ClusterName}}-{{global:DATE_TIME}}'
#           - Key: Cluster
#             Value: '{{ClusterName}}'
#           - Key: BackupType
#             Value: 'PVC-Automated'
#           - Key: CreatedBy
#             Value: 'SSM-Automation'
#           - Key: VolumeType
#             Value: 'PVC'
#       outputs:
#       - Name: SnapshotIds
#         Selector: '$.SnapshotId'
#         Type: StringList
#     - action: aws:executeAwsApi
#       name: CleanupOldSnapshots
#       inputs:
#         Service: ec2
#         Api: DescribeSnapshots
#         OwnerIds: ['self']
#         Filters:
#         - Name: tag:Cluster
#           Values: ['{{ClusterName}}']
#         - Name: tag:BackupType
#           Values: ['PVC-Automated']
#         - Name: tag:VolumeType
#           Values: ['PVC']
#       outputs:
#       - Name: OldSnapshots
#         Selector: '$.Snapshots[?StartTime < `{{global:DATE_TIME_MINUS_DAYS:{{RetentionDays}}}}`].SnapshotId'
#         Type: StringList
#     - action: aws:executeAwsApi
#       name: DeleteOldSnapshots
#       inputs:
#         Service: ec2
#         Api: DeleteSnapshot
#         SnapshotId: '{{CleanupOldSnapshots.OldSnapshots}}'
#       isEnd: true
#     EOT

#   tags = merge(local.tags, {
#     Name = "${local.project}-ebs-backup-automation"
#     Purpose = "EBS backup automation"
#   })
# }

# # EventBridge 규칙 - 일일 백업 스케줄 (KST 3-5시 = UTC 18-20시)
# resource "aws_cloudwatch_event_rule" "daily_backup_schedule" {
#   name                = "${local.project}-daily-backup-schedule"
#   description         = "EBS 일일 백업 스케줄 (KST 3-5시)"
#   schedule_expression = "cron(0 18-20 * * ? *)"  # UTC 18-20시 (KST 3-5시)
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-daily-backup-schedule"
#     Purpose = "Daily EBS backup schedule"
#   })
# }

# # EventBridge 타겟 - SSM Automation 실행
# resource "aws_cloudwatch_event_target" "backup_automation" {
#   rule      = aws_cloudwatch_event_rule.daily_backup_schedule.name
#   target_id = "BackupAutomationTarget"
#   arn       = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.ebs_backup_automation.name}:$DEFAULT"

#   role_arn = aws_iam_role.backup_automation_role.arn

#   input = jsonencode({
#     RetentionDays = "7"
#     ClusterName   = module.eks.cluster_name
#   })
# }

# # EventBridge 타겟 - SNS 알림
# resource "aws_cloudwatch_event_target" "backup_notification" {
#   rule      = aws_cloudwatch_event_rule.daily_backup_schedule.name
#   target_id = "BackupNotificationTarget"
#   arn       = aws_sns_topic.backup_notifications.arn

#   input_transformer {
#     input_paths = {
#       time = "$.time"
#     }
#     input_template = jsonencode({
#       default = "EKS PVC 백업이 시작되었습니다. 클러스터: ${module.eks.cluster_name}, 시간: <time>"
#     })
#   }
# }

# # IAM 역할 - SSM Automation 실행용
# resource "aws_iam_role" "backup_automation_role" {
#   name = "${local.project}-backup-automation-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "events.amazonaws.com"
#         }
#       }
#     ]
#   })

#   tags = merge(local.tags, {
#     Name = "${local.project}-backup-automation-role"
#     Purpose = "EBS backup automation execution"
#   })
# }

# # IAM 정책 - EBS 스냅샷 관리 권한
# resource "aws_iam_policy" "backup_automation_policy" {
#   name        = "${local.project}-backup-automation-policy"
#   description = "EBS 스냅샷 생성 및 삭제 권한"

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "ec2:CreateSnapshot",
#           "ec2:DeleteSnapshot",
#           "ec2:DescribeSnapshots",
#           "ec2:DescribeVolumes",
#           "ec2:CreateTags",
#           "ec2:DeleteTags"
#         ]
#         Resource = "*"
#       }
#     ]
#   })

#   tags = merge(local.tags, {
#     Name = "${local.project}-backup-automation-policy"
#     Purpose = "EBS backup permissions"
#   })
# }

# # IAM 역할에 정책 연결
# resource "aws_iam_role_policy_attachment" "backup_automation_policy" {
#   role       = aws_iam_role.backup_automation_role.name
#   policy_arn = aws_iam_policy.backup_automation_policy.arn
# }

# # EventBridge 규칙 - 백업 완료 알림
# resource "aws_cloudwatch_event_rule" "backup_completion" {
#   name                = "${local.project}-backup-completion"
#   description         = "EBS 백업 완료 알림"
#   event_pattern = jsonencode({
#     source      = ["aws.ssm"]
#     detail-type = ["SSM Automation Execution State-change"]
#     detail = {
#       status = ["Success", "Failed"]
#       documentName = [aws_ssm_document.ebs_backup_automation.name]
#     }
#   })
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-backup-completion"
#     Purpose = "Backup completion notification"
#   })
# }

# # EventBridge 타겟 - 백업 완료 알림
# resource "aws_cloudwatch_event_target" "backup_completion_notification" {
#   rule      = aws_cloudwatch_event_rule.backup_completion.name
#   target_id = "BackupCompletionNotification"
#   arn       = aws_sns_topic.backup_notifications.arn

#   input_transformer {
#     input_paths = {
#       status = "$.detail.status"
#       time = "$.time"
#       executionId = "$.detail.executionId"
#     }
#     input_template = jsonencode({
#       default = "EKS PVC 백업이 완료되었습니다. 상태: <status>, 클러스터: ${module.eks.cluster_name}, 시간: <time>, 실행ID: <executionId>"
#     })
#   }
# }

# # SNS 구독 - 슬랙 알림
# resource "aws_sns_topic_subscription" "slack_notifications" {
#   count     = var.slack_webhook_url != "" ? 1 : 0
#   topic_arn = aws_sns_topic.backup_notifications.arn
#   protocol  = "https"
#   endpoint  = var.slack_webhook_url
# }