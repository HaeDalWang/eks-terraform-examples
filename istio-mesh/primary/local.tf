locals {
  project             = "istio-primary"
  project_prefix      = "istio"
  domain_name         = var.domain_name
  project_domain_name = "${local.project_prefix}.${local.domain_name}"
  tags = {
    "terraform" = "true"
    "project"   = local.project
  }
}
