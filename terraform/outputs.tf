# output "network" {
#   description = "VPC 및 네트워크 관련 정보"
#   value = {
#     vpc_id                                = module.vpc.vpc_id
#     client_vpn_security_group_id          = module.client_vpn_sg.security_group_id
#     eks_cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
#   }
# }

# output "thanos" {
#   description = "thanos 관련 정보"
#   value = {
#     bucket_name     = aws_s3_bucket.thanos.bucket
#     bucket_endpoint = replace(aws_s3_bucket.thanos.bucket_regional_domain_name, "${aws_s3_bucket.thanos.bucket}.", "")
#     iam_policy_arn  = aws_iam_policy.thanos_s3_access.arn
#   }
# }