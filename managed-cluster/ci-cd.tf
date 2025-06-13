# # GitHub에 있는 리포지토리와 연결
# resource "aws_codestarconnections_connection" "this" {
#   for_each = toset(local.app)

#   name          = each.key
#   provider_type = "GitHub"
# }

# # 코드 파이프라인에서 사용할 버킷
# resource "aws_s3_bucket" "codepipeline" {
#   bucket = "ezl-codepipeline-storage"

#   force_destroy = true
# }

# # 코드 파이프라인에서 사용할 IAM 역할
# resource "aws_iam_policy" "codepipeline" {
#   name = "ezl-codepipeline-policy"

#   policy = <<-POLICY
#     {
#       "Version": "2012-10-17",
#       "Statement": [
#         {
#           "Action": [
#             "s3:*",
#             "codestar-connections:UseConnection",
#             "codebuild:*"
#           ],
#           "Effect": "Allow",
#           "Resource": "*"
#         }
#       ]
#     }
#   POLICY
# }

# resource "aws_iam_role" "codepipeline" {
#   name = "ezl-codepipeline-service-role"
#   path = "/service-role/"

#   managed_policy_arns = [aws_iam_policy.codepipeline.arn]

#   assume_role_policy = <<-POLICY
#     {
#       "Version": "2012-10-17",
#       "Statement": [
#         {
#           "Action": "sts:AssumeRole",
#           "Effect": "Allow",
#           "Principal": {
#             "Service": "codepipeline.amazonaws.com"
#           }
#         }
#       ]
#     }
#   POLICY
# }

# # 코드 빌드에서 사용할 IAM 역할
# resource "aws_iam_policy" "codebuild" {
#   name = "ezl-codebuild-policy"

#   policy = <<-POLICY
#     {
#       "Version": "2012-10-17",
#       "Statement": [
#         {
#           "Sid": "CloudWatchLogsPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "logs:CreateLogGroup",
#             "logs:CreateLogStream",
#             "logs:PutLogEvents"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "CodeStartPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "codestar-connections:UseConnection"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "S3GetObjectPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "s3:GetObject",
#             "s3:GetObjectVersion"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "S3PutObjectPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "s3:PutObject"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "ECRPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "ecr:GetDownloadUrlForLayer",
#             "ecr:BatchGetImage",
#             "ecr:BatchCheckLayerAvailability",
#             "ecr:CompleteLayerUpload",
#             "ecr:GetAuthorizationToken",
#             "ecr:InitiateLayerUpload",
#             "ecr:PutImage",
#             "ecr:DescribeImages",
#             "ecr:UploadLayerPart"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "S3BucketIdentity",
#           "Effect": "Allow",
#           "Action": [
#             "s3:GetBucketAcl",
#             "s3:GetBucketLocation"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "SecretManagerPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "secretsmanager:GetSecretValue"
#           ],
#           "Resource": "${data.aws_secretsmanager_secret_version.this.arn}"
#         },
#         {
#           "Sid": "CodePipelinePolicy",
#           "Effect": "Allow",
#           "Action": [
#             "codepipeline:ListPipelineExecutions"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "STSPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "sts:AssumeRole"
#           ],
#           "Resource": "*"
#         },
#         {
#           "Sid": "VpcPolicy",
#           "Effect": "Allow",
#           "Action": [
#             "ec2:CreateNetworkInterface",
#             "ec2:DescribeDhcpOptions",
#             "ec2:DescribeNetworkInterfaces",
#             "ec2:DeleteNetworkInterface",
#             "ec2:DescribeSubnets",
#             "ec2:DescribeSecurityGroups",
#             "ec2:DescribeVpcs",
#             "ec2:CreateNetworkInterfacePermission"
#           ],
#           "Resource": "*"
#         }
#       ]
#     }
#   POLICY
# }

# resource "aws_iam_role" "codebuild" {
#   name = "ezl-codebuild-service-role"
#   path = "/service-role/"

#   managed_policy_arns = [aws_iam_policy.codebuild.arn]

#   assume_role_policy = <<-POLICY
#     {
#       "Version": "2012-10-17",
#       "Statement": [
#         {
#           "Effect": "Allow",
#           "Principal": {
#             "Service": "codebuild.amazonaws.com"
#           },
#           "Action": "sts:AssumeRole"
#         }
#       ]
#     }
#   POLICY

#   lifecycle {
#     ignore_changes = [
#       # 자동으로 추가되는 정책 삭제 방지
#       managed_policy_arns
#     ]
#   }
# }

# # 코드 빌드 로그를 저장할 로그 그룹
# resource "aws_cloudwatch_log_group" "this" {
#   for_each = toset(local.app)

#   name              = "/aws/codebuild/${each.key}"
#   retention_in_days = 7
# }

# # 코드 빌드 프로젝트
# resource "aws_codebuild_project" "this" {
#   for_each = toset(local.app)

#   name         = each.key
#   service_role = aws_iam_role.codebuild.arn

#   artifacts {
#     type = "NO_ARTIFACTS"
#   }

#   environment {
#     compute_type    = "BUILD_GENERAL1_SMALL"
#     image           = "aws/codebuild/standard:5.0"
#     privileged_mode = "true"
#     type            = "LINUX_CONTAINER"
#   }

#   vpc_config {
#     vpc_id             = module.vpc.vpc_id
#     subnets            = module.vpc.private_subnets
#     security_group_ids = [module.vpc.default_security_group_id]
#   }

#   logs_config {
#     cloudwatch_logs {
#       status     = "ENABLED"
#       group_name = aws_cloudwatch_log_group.this[each.key].name
#     }
#   }

#   source {
#     type      = "GITHUB"
#     location  = "https://github.com/ezllabs/${each.key}.git"
#     buildspec = file("${path.module}/buildspec/${each.key}.yaml")
#   }
# }