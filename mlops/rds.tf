# RDS 인스턴스에 부여할 보안그룹
module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"

  name        = "${local.app[0]}-rds-sg"
  description = "${local.app[0]} rds security group"
  vpc_id      = module.vpc.vpc_id

  # 기본값으로 허가할 IP 대역대
  ingress_cidr_blocks = local.whitelist_ip_range
  ingress_rules       = ["postgresql-tcp"]


  ingress_with_source_security_group_id = [
    # EKS 노드에서 RDS로 접근 가능하도록 보안그룹 규칙 추가
    {
      rule                     = "postgresql-tcp"
      source_security_group_id = module.eks.cluster_primary_security_group_id
    }
  ]
}

# RDS 초기 비밀번호
resource "random_password" "rds" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# RDS 인스턴스
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.5.4"

  identifier            = local.app[0]
  engine                = "postgres"
  engine_version        = "15.12"
  instance_class        = "db.t3.small"
  storage_type          = "gp3"
  allocated_storage     = 20
  max_allocated_storage = 100

  backup_retention_period      = 7
  performance_insights_enabled = false

  # 운영 환경만 HA 구성
  multi_az = false

  publicly_accessible    = true
  deletion_protection    = false
  vpc_security_group_ids = [module.rds_sg.security_group_id]

  # RDS 인증정보 - 비밀번호는 Lambda 함수가 30일마다 자동 변경
  manage_master_user_password = false
  username                    = "ezllabs_ezl_dev"
  password                    = random_password.rds.result

  # 기본값으로 생성할 DATABASE
  db_name = "intgapp_ezl_dev"

  # DB subnet group
  create_db_subnet_group = true
  subnet_ids             = module.vpc.private_subnets

  # DB parameter group
  family = "postgres15"

  # 로그 - audit 로그 추가
  enabled_cloudwatch_logs_exports        = ["postgresql"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 7

  # DB 변경사항을 바로 반영
  apply_immediately = true

  # RDS 마이너 버전 자동 업그레이드 비활성화
  auto_minor_version_upgrade = false
}