module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "2.2.1"

  # local에 있는 app 배열을 꺼네어 차례대로 진행
  for_each = {
    for k, v in toset(local.app) : k => v
  }
  
  repository_name = each.key

  # image Tag 변동 불가
  repository_image_tag_mutability = "MUTABLE"

  # 이미지 레포지토리 접근 제어 필요 시 추가
  # repository_read_access_arns = [
  #   "Change ME! Role ARN plz",
  # ]

  # 수명주기 정책 설명
  # 1 순위: 태그가 없는 이미지가 3개가 넘을 경우 만료 처리
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Expire untagged images",
        selection = {
          tagStatus   = "untagged",
          countType   = "imageCountMoreThan",
          countNumber = 3
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}