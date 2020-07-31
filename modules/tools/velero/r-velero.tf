data "azurerm_subscription" "current" {
  count = var.enable_velero ? 1 : 0
}

resource "kubernetes_namespace" "velero" {
  count = var.enable_velero ? 1 : 0
  metadata {
    name = var.velero_namespace
    labels = {
      deployed-by = "Terraform"
    }
  }
}

resource "kubernetes_secret" "velero" {
  count = var.enable_velero ? 1 : 0
  metadata {
    name      = "cloud-credentials"
    namespace = kubernetes_namespace.velero.0.metadata.0.name
  }
  data = {
    cloud = local.velero_credentials
  }
}

resource "azurerm_storage_account" "velero" {
  count                    = var.enable_velero ? 1 : 0
  name                     = local.velero_storage.name
  resource_group_name      = local.velero_storage.resource_group_name
  location                 = local.velero_storage.location
  account_tier             = local.velero_storage.account_tier
  account_replication_type = local.velero_storage.account_replication_type
  account_kind             = "BlockBlobStorage"
  tags                     = local.velero_storage.tags

  lifecycle {
    ignore_changes = [network_rules]
  }
}

resource "azurerm_storage_account_network_rules" "velero" {
  count                      = var.enable_velero ? 1 : 0
  storage_account_name       = azurerm_storage_account.velero.0.name
  resource_group_name        = azurerm_storage_account.velero.0.resource_group_name
  default_action             = "Deny"
  virtual_network_subnet_ids = [var.nodes_subnet_id]
  ip_rules                   = local.velero_storage.allowed_cidrs
}

resource "azurerm_storage_container" "velero" {
  count                 = var.enable_velero ? 1 : 0
  name                  = local.velero_storage.container_name
  storage_account_name  = azurerm_storage_account.velero.0.name
  container_access_type = "private"
}

resource "helm_release" "velero" {
  count = var.enable_velero ? 1 : 0
  depends_on = [
    kubernetes_secret.velero,
    kubernetes_namespace.velero,
    azurerm_storage_account.velero,
  azurerm_storage_container.velero]
  name       = "velero"
  chart      = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  namespace  = kubernetes_namespace.velero.0.metadata.0.name
  version    = var.velero_chart_version

  dynamic "set" {
    for_each = local.velero_values
    iterator = setting
    content {
      name  = setting.key
      value = setting.value
    }
  }

  # FIXME: Wait for helm chart to allow to add labels
  # https://github.com/vmware-tanzu/helm-charts/pull/66
  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.aks_cluster_name} --admin --overwrite --subscription ${data.azurerm_subscription.current[0].subscription_id}"
  }
  provisioner "local-exec" {
    command = "kubectl label pods $(kubectl get pods -n ${kubernetes_namespace.velero.0.metadata.0.name} -o jsonpath='{.items[*].metadata.name}') aadpodidbinding=${azurerm_user_assigned_identity.velero-identity.0.name} -n ${kubernetes_namespace.velero.0.metadata.0.name}"
  }
}