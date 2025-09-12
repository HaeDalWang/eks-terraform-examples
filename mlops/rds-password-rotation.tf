# RDS 비밀번호 자동 변경 Lambda 함수
# 30일마다 RDS 비밀번호를 변경하고 Secrets Manager에 업데이트

# Lambda 함수용 IAM 역할
resource "aws_iam_role" "rds_password_rotation" {
  name = "${local.project}-rds-password-rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.project}-rds-password-rotation"
  }
}

# Lambda 함수용 IAM 정책
resource "aws_iam_policy" "rds_password_rotation" {
  name        = "${local.project}-rds-password-rotation"
  description = "Policy for RDS password rotation Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:ModifyDBInstance",
          "rds:DescribeDBInstances"
        ]
        Resource = "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:${local.app[0]}"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:UpdateSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:ezl-app-server-secrets-*"
      }
    ]
  })
}

# IAM 역할에 정책 연결
resource "aws_iam_role_policy_attachment" "rds_password_rotation" {
  role       = aws_iam_role.rds_password_rotation.name
  policy_arn = aws_iam_policy.rds_password_rotation.arn
}

# Lambda 함수 소스 코드 (hash 기반)
data "archive_file" "rds_password_rotation" {
  type        = "zip"
  output_path = "/tmp/rds_password_rotation.zip"
  source_dir  = "${path.module}/lambdas"
  
  # 특정 파일만 포함
  includes = ["rds_password_rotation.py"]
  
  # 파일명을 lambda_function.py로 변경
  output_file_mode = "0644"
}

# Lambda 함수
resource "aws_lambda_function" "rds_password_rotation" {
  filename         = data.archive_file.rds_password_rotation.output_path
  function_name    = "${local.project}-rds-password-rotation"
  role            = aws_iam_role.rds_password_rotation.arn
  handler         = "rds_password_rotation.lambda_handler"
  runtime         = "python3.11"
  timeout         = 300

  source_code_hash = data.archive_file.rds_password_rotation.output_base64sha256

  environment {
    variables = {
      DB_INSTANCE_IDENTIFIER = local.app[0]
      SECRETS_MANAGER_SECRET = "ezl-app-server-secrets"
    }
  }

  tags = {
    Name = "${local.project}-rds-password-rotation"
  }
}

# EventBridge Scheduler - 30일마다 실행
resource "aws_scheduler_schedule" "rds_password_rotation" {
  name       = "${local.project}-rds-password-rotation"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(30 days)"
  schedule_expression_timezone = "Asia/Seoul"

  target {
    arn      = aws_lambda_function.rds_password_rotation.arn
    role_arn = aws_iam_role.scheduler_lambda_invoke.arn

    input = jsonencode({
      source = "eventbridge-scheduler"
      action = "rds-password-rotation"
    })
  }

  tags = {
    Name = "${local.project}-rds-password-rotation"
  }
}

# EventBridge Scheduler가 Lambda를 호출할 수 있는 IAM 역할
resource "aws_iam_role" "scheduler_lambda_invoke" {
  name = "${local.project}-scheduler-lambda-invoke"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })
}

# EventBridge Scheduler IAM 정책
resource "aws_iam_policy" "scheduler_lambda_invoke" {
  name        = "${local.project}-scheduler-lambda-invoke"
  description = "Policy for EventBridge Scheduler to invoke Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.rds_password_rotation.arn
      }
    ]
  })
}

# IAM 역할에 정책 연결
resource "aws_iam_role_policy_attachment" "scheduler_lambda_invoke" {
  role       = aws_iam_role.scheduler_lambda_invoke.name
  policy_arn = aws_iam_policy.scheduler_lambda_invoke.arn
}

# Lambda 함수에 EventBridge Scheduler 권한 부여
resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowExecutionFromScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_password_rotation.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.rds_password_rotation.arn
}

# RDS 초기 비밀번호를 Secrets Manager에 저장 (Terraform으로 직접 처리)
resource "aws_secretsmanager_secret_version" "ezl_app_server_initial" {
  secret_id = data.aws_secretsmanager_secret.application["ezl-app-server"].id
  secret_string = jsonencode({
    DB_PASSWORD = random_password.rds.result
    DB_PASSWORD_UPDATED_AT = timestamp()
    DB_PASSWORD_TYPE = "initial"
  })

  depends_on = [
    module.rds
  ]
}
