# # Lambda 역할 생성
# resource "aws_iam_role" "alarm_lambda_role" {
#   name = "cloudwatch-alarm-lambda-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action    = "sts:AssumeRole",
#         Effect    = "Allow",
#         Principal = { Service = "lambda.amazonaws.com" }
#       }
#     ]
#   })
# }

# # Lambda 역할 정책 연결
# resource "aws_iam_role_policy_attachment" "alarm_lambda_sns_policy_attach" {
#   role       = aws_iam_role.alarm_lambda_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
# }

# resource "aws_iam_role_policy_attachment" "alarm_lambda_basic_policy_attach" {
#   role       = aws_iam_role.alarm_lambda_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# # Lambda 함수 생성
# resource "aws_lambda_function" "cloudwatch_alarm_handler" {
#   filename         = "${path.module}/lambda-functions/cloudwatch-alarm-to-slack.zip" # 패키징된 Lambda zip 파일 경로
#   function_name    = "cloudwatch-alarm-to-slack"
#   role             = aws_iam_role.alarm_lambda_role.arn
#   handler          = "cloudwatch-alarm-to-slack.lambda_handler"
#   runtime          = "python3.9"
#   timeout          = 15

#   environment {
#     variables = {
#       SLACK_WEBHOOK_URL = var.alert_slack_webhook_url
#     }
#   }

#   source_code_hash = filebase64sha256("${path.module}/lambda-functions/cloudwatch-alarm-to-slack.zip")
# }

# # SNS Topic
# resource "aws_sns_topic" "alarm_topic" {
#   name = "cloudwatch-alarm-topic"
# }

# # SNS Topic 과 Lambda 트리거 연결
# resource "aws_sns_topic_subscription" "lambda_subscription" {
#   topic_arn = aws_sns_topic.alarm_topic.arn
#   protocol  = "lambda"
#   endpoint  = aws_lambda_function.cloudwatch_alarm_handler.arn

#   depends_on = [aws_lambda_permission.allow_sns]
# }

# # Lambda 권한 부여
# resource "aws_lambda_permission" "allow_sns" {
#   statement_id  = "AllowExecutionFromSNS"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.cloudwatch_alarm_handler.arn
#   principal     = "sns.amazonaws.com"
#   source_arn    = aws_sns_topic.alarm_topic.arn
# }

# # SNS Topic 정책
# resource "aws_sns_topic_policy" "alarm_topic_policy" {
#   arn = aws_sns_topic.alarm_topic.arn

#   policy = data.aws_iam_policy_document.alarm_topic_policy_document.json
# }

# data "aws_iam_policy_document" "alarm_topic_policy_document" {
#   policy_id = "__default_policy_ID"

#   statement {
#     actions = [
#       "SNS:Subscribe",
#       "SNS:SetTopicAttributes",
#       "SNS:RemovePermission",
#       "SNS:Publish",
#       "SNS:ListSubscriptionsByTopic",
#       "SNS:GetTopicAttributes",
#       "SNS:DeleteTopic",
#       "SNS:AddPermission",
#     ]

#     condition {
#       test     = "StringEquals"
#       variable = "AWS:SourceOwner"

#       values = [
#         data.aws_caller_identity.current.account_id
#       ]
#     }

#     effect = "Allow"

#     principals {
#       type        = "AWS"
#       identifiers = ["*"]
#     }

#     resources = [
#       aws_sns_topic.alarm_topic.arn
#     ]

#     sid = "__default_statement_ID"
#   }

#   statement {
#     sid       = "crossaccount_alarm_statement_ID"
#     effect    = "Allow"

#     principals {
#       type        = "AWS"
#       identifiers = ["*"]
#     }

#     actions = [
#       "SNS:Publish"
#     ]

#     resources = [
#       aws_sns_topic.alarm_topic.arn
#     ]

#     condition {
#       test     = "ArnLike"
#       variable = "aws:SourceArn"
#       values = [
#         "arn:aws:cloudwatch:ap-northeast-2:590183736724:alarm:*",
#         "arn:aws:cloudwatch:ap-northeast-2:471112573721:alarm:*",
#         "arn:aws:cloudwatch:ap-northeast-2:533267146834:alarm:*"
#       ]
#     }
#   }
# }