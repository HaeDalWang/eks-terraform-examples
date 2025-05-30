# # ACM 인증서 발급 요청
# resource "aws_acm_certificate" "service_domain" {
#   domain_name       = "*.${local.service_domain_name}"
#   validation_method = "DNS"

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# # 위에서 생성한 ACM 인증서 검증하는 DNS 레코드 생성
# resource "aws_route53_record" "acm_validation_service_domain" {
#   for_each = {
#     for dvo in aws_acm_certificate.service_domain.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }

#   allow_overwrite = true
#   name            = each.value.name
#   records         = [each.value.record]
#   ttl             = 60
#   type            = each.value.type
#   zone_id         = data.aws_route53_zone.this.zone_id
# }

# 인증서 발급 상태
# resource "aws_acm_certificate_validation" "service_domain" {
#   certificate_arn         = aws_acm_certificate.service_domain.arn
#   validation_record_fqdns = [for record in aws_route53_record.acm_validation_service_domain : record.fqdn]
# }