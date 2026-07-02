# ########################################################
# Thanos (toggle, count = var.enable_thanos ? 1 : 0)
# ########################################################
#
# Thanos는 Grafana Labs가 관리하는 공식 Helm 차트가 없습니다.
# (Bitnami/thanos: 2025-08-28부로 신규 게시 중단, 기존 차트도 out-of-the-box 동작 보장 안 됨
#  thanos-io/kube-thanos: jsonnet 기반, Helm 아님)
# 그래서 이 예제는 Thanos 컴포넌트를 순수 Kubernetes manifest로 직접 작성합니다.
# 컴포넌트 자체는 평범한 Deployment/StatefulSet이라 외부 차트 의존 없이 관리 가능합니다.
#
# Store Gateway  StatefulSet  S3 블록을 Store API로 서빙 (과거 데이터 조회)
# Compactor      StatefulSet  블록 압축 + 다운샘플링 (싱글톤, replica=1 고정)
# Query          Deployment   Prometheus sidecar + Store Gateway를 fan-out 쿼리
# Query Frontend Deployment   쿼리 분할 + memcached 캐싱
#
# enable_thanos = true 일 때 Grafana 메트릭 datasource가 Prometheus 직결 대신
# Query Frontend를 바라보도록 local.metrics_query_service가 전환됩니다.

locals {
  thanos_labels = { "app.kubernetes.io/part-of" = "thanos" }
}

resource "kubernetes_service_account_v1" "thanos" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.thanos_pod_identity[0].iam_role_arn
    }
  }
}

# ########################################################
# Query Frontend 캐시 (memcached)
# ########################################################
resource "kubernetes_deployment_v1" "thanos_memcached" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-memcached"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels    = local.thanos_labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "thanos-memcached" }
    }
    template {
      metadata {
        labels = { app = "thanos-memcached" }
      }
      spec {
        container {
          name  = "memcached"
          image = "memcached:1.6-alpine"
          args  = ["-m", "128", "-I", "5m"]
          port {
            container_port = 11211
            name           = "client"
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "192Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "thanos_memcached" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-memcached"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "thanos-memcached" }
    port {
      name        = "client"
      port        = 11211
      target_port = 11211
    }
  }
}

resource "kubernetes_config_map_v1" "thanos_cache_config" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-cache-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    "cache.yaml" = yamlencode({
      type = "MEMCACHED"
      config = {
        addresses = ["thanos-memcached.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local:11211"]
      }
    })
  }
}

# ########################################################
# Store Gateway
# ########################################################
resource "kubernetes_service_v1" "thanos_store_headless" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-store-headless"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  spec {
    cluster_ip = "None"
    selector   = { app = "thanos-store" }
    port {
      name        = "grpc"
      port        = 10901
      target_port = 10901
    }
    port {
      name        = "http"
      port        = 10902
      target_port = 10902
    }
  }
}

resource "kubernetes_stateful_set_v1" "thanos_store" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-store"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels    = local.thanos_labels
  }
  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.thanos_store_headless[0].metadata[0].name
    selector {
      match_labels = { app = "thanos-store" }
    }
    template {
      metadata {
        labels = { app = "thanos-store" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.thanos[0].metadata[0].name
        container {
          name  = "thanos-store"
          image = "quay.io/thanos/thanos:${var.thanos_image_tag}"
          args = [
            "store",
            "--data-dir=/data",
            "--objstore.config-file=/etc/thanos/objstore.yml",
            "--grpc-address=0.0.0.0:10901",
            "--http-address=0.0.0.0:10902",
          ]
          port {
            name           = "grpc"
            container_port = 10901
          }
          port {
            name           = "http"
            container_port = 10902
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "objstore-config"
            mount_path = "/etc/thanos"
            read_only  = true
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
        }
        volume {
          name = "objstore-config"
          secret {
            secret_name = kubernetes_secret_v1.thanos_objstore_config[0].metadata[0].name
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp3"
        resources {
          requests = { storage = "10Gi" }
        }
      }
    }
  }
}

# ########################################################
# Compactor (싱글톤, replica=1 고정 - Thanos 요구사항)
# ########################################################
resource "kubernetes_stateful_set_v1" "thanos_compactor" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-compactor"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels    = local.thanos_labels
  }
  spec {
    replicas     = 1
    service_name = "thanos-compactor"
    selector {
      match_labels = { app = "thanos-compactor" }
    }
    template {
      metadata {
        labels = { app = "thanos-compactor" }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.thanos[0].metadata[0].name
        container {
          name  = "thanos-compactor"
          image = "quay.io/thanos/thanos:${var.thanos_image_tag}"
          args = [
            "compact",
            "--data-dir=/data",
            "--objstore.config-file=/etc/thanos/objstore.yml",
            "--http-address=0.0.0.0:10902",
            "--wait",
            "--wait-interval=5m",
            "--retention.resolution-raw=30d",
            "--retention.resolution-5m=90d",
            "--retention.resolution-1h=365d",
          ]
          port {
            name           = "http"
            container_port = 10902
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "objstore-config"
            mount_path = "/etc/thanos"
            read_only  = true
          }
          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
        }
        volume {
          name = "objstore-config"
          secret {
            secret_name = kubernetes_secret_v1.thanos_objstore_config[0].metadata[0].name
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp3"
        resources {
          requests = { storage = "10Gi" }
        }
      }
    }
  }
}

# ########################################################
# Query (Prometheus sidecar + Store Gateway fan-out)
# ########################################################
resource "kubernetes_deployment_v1" "thanos_query" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-query"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels    = local.thanos_labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "thanos-query" }
    }
    template {
      metadata {
        labels = { app = "thanos-query" }
      }
      spec {
        container {
          name  = "thanos-query"
          image = "quay.io/thanos/thanos:${var.thanos_image_tag}"
          args = [
            "query",
            "--grpc-address=0.0.0.0:10901",
            "--http-address=0.0.0.0:10902",
            "--query.replica-label=replica",
            "--store=dnssrv+_grpc._tcp.prometheus-server-headless.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local",
            "--store=dnssrv+_grpc._tcp.thanos-store-headless.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local",
          ]
          port {
            name           = "grpc"
            container_port = 10901
          }
          port {
            name           = "http"
            container_port = 10902
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { memory = "256Mi" }
          }
        }
      }
    }
  }

  depends_on = [helm_release.prometheus]
}

resource "kubernetes_service_v1" "thanos_query" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-query"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "thanos-query" }
    port {
      name        = "grpc"
      port        = 10901
      target_port = 10901
    }
    port {
      name        = "http"
      port        = 10902
      target_port = 10902
    }
  }
}

# ########################################################
# Query Frontend (쿼리 분할 + memcached 캐싱)
# ########################################################
resource "kubernetes_deployment_v1" "thanos_query_frontend" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-query-frontend"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels    = local.thanos_labels
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "thanos-query-frontend" }
    }
    template {
      metadata {
        labels = { app = "thanos-query-frontend" }
      }
      spec {
        container {
          name  = "thanos-query-frontend"
          image = "quay.io/thanos/thanos:${var.thanos_image_tag}"
          args = [
            "query-frontend",
            "--http-address=0.0.0.0:10902",
            "--query-frontend.downstream-url=http://thanos-query.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local:10902",
            "--query-range.response-cache-config-file=/etc/thanos/cache.yaml",
            "--labels.response-cache-config-file=/etc/thanos/cache.yaml",
          ]
          port {
            name           = "http"
            container_port = 10902
          }
          volume_mount {
            name       = "cache-config"
            mount_path = "/etc/thanos"
            read_only  = true
          }
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "256Mi" }
          }
        }
        volume {
          name = "cache-config"
          config_map {
            name = kubernetes_config_map_v1.thanos_cache_config[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.thanos_query]
}

resource "kubernetes_service_v1" "thanos_query_frontend" {
  count = var.enable_thanos ? 1 : 0
  metadata {
    name      = "thanos-query-frontend"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  spec {
    selector = { app = "thanos-query-frontend" }
    port {
      name        = "http"
      port        = 10902
      target_port = 10902
    }
  }
}
