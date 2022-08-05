resource "azurerm_user_assigned_identity" "aks_user_assigned_identity" {

  name                = coalesce(var.aks_user_assigned_identity_custom_name, local.aks_user_assigned_identity_name)
  resource_group_name = var.aks_user_assigned_identity_resource_group_name == null ? var.resource_group_name : var.aks_user_assigned_identity_resource_group_name
  location            = var.location

  tags = merge(local.default_tags, var.aks_user_assigned_identity_tags)
}

resource "azurerm_role_assignment" "aks_uai_private_dns_zone_contributor" {
  count = var.private_cluster_enabled && var.private_dns_zone_type == "Custom" ? 1 : 0

  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_user_assigned_identity.principal_id
}

resource "azurerm_role_assignment" "aks_uai_vnet_network_contributor" {
  count = var.private_cluster_enabled && var.private_dns_zone_type == "Custom" ? 1 : 0

  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_user_assigned_identity.principal_id
}

# Application gateway identity stuff, used to gather ssl certificate from keyvault
# https://github.com/Azure/application-gateway-kubernetes-ingress/issues/999
# https://github.com/Azure/application-gateway-kubernetes-ingress/blob/master/docs/features/appgw-ssl-certificate.md#configure-certificate-from-key-vault-to-appgw
resource "azurerm_user_assigned_identity" "appgw_assigned_identity" {
  count = var.appgw_identity_enabled ? 1 : 0

  name                = coalesce(var.appgw_user_assigned_identity_custom_name, local.appgw_user_assigned_identity_name)
  resource_group_name = var.appgw_user_assigned_identity_resource_group_name == null ? var.resource_group_name : var.appgw_user_assigned_identity_resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "aad_pod_identity_mio_appgw_identity" {
  count = var.appgw_identity_enabled ? 1 : 0

  scope                = azurerm_user_assigned_identity.appgw_assigned_identity[0].id
  role_definition_name = "Managed Identity Operator"
  principal_id         = module.infra.aad_pod_identity_principal_id
}
