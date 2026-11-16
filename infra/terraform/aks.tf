# Control plane identity (user-assigned instead of system-assigned).
# Its principal exists before the cluster, so we can grant it rights on the subnet
# up front; it also survives a cluster rebuild, keeping its role assignments.
resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "id-${var.cluster_name}-control-plane"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # AKS creates this RG for VMSS, LB, public IP and disks; naming it explicitly
  # avoids the default MC_<rg>_<cluster>_<region> name.
  node_resource_group = var.node_resource_group_name

  # Free tier: no uptime SLA and fewer control plane resources; fine for a lab.
  sku_tier     = "Free"
  support_plan = "KubernetesOfficial"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_control_plane.id]
  }
  # No kubelet_identity block: AKS creates the kubelet identity in the node RG.
  # Its object ID is used for AcrPull in rbac.tf.

  # --- Authentication / authorization ------------------------------------
  # Entra ID login with Kubernetes authorization done by Azure RBAC role
  # assignments (no ClusterRoleBindings or Entra groups needed).
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    # The provider requires tenant_id or admin groups; we use no admin groups
    # (guest user cannot create them), so pass the tenant of the CLI login.
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
  role_based_access_control_enabled = true

  # Disables the static cluster-admin certificate (`--admin` kubeconfig), so
  # every access goes through Entra ID and is auditable.
  local_account_disabled = true

  # --- Workload identity -------------------------------------------------
  # OIDC issuer publishes the service account token signing keys; workload identity
  # lets pods exchange those tokens for Entra tokens (needed later for Flux/apps).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Removes unused images from nodes weekly (168 h, same as the portal default).
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 168

  # --- API server ----------------------------------------------------------
  # Public endpoint, no authorized IP ranges (no api_server_access_profile block).
  private_cluster_enabled = false

  # --- Upgrades ----------------------------------------------------------
  # "patch" upgrades to the newest patch of the current minor automatically;
  # minor upgrades stay a deliberate change of var.kubernetes_version.
  automatic_upgrade_channel = "patch"
  # Weekly reimage with the latest node image (OS + runtime security fixes).
  node_os_upgrade_channel = "NodeImage"

  # Both windows: weekly, Sunday 00:00 UTC. 4 hours is the minimum duration.
  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "00:00"
    utc_offset  = "+00:00"
    duration    = 4
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "00:00"
    utc_offset  = "+00:00"
    duration    = 4
  }

  # --- Network ---------------------------------------------------------
  network_profile {
    # Azure CNI Overlay: nodes get VNet IPs, pods get IPs from a private overlay
    # CIDR, so the subnet stays small and pods do not consume VNet addresses.
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    # Cilium (eBPF) replaces kube-proxy/iptables; Cilium then also enforces NetworkPolicy.
    network_data_plane = "cilium"
    network_policy     = "cilium"

    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip

    # Egress via the AKS-managed Standard LB with one managed public IP.
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  # Required block since azurerm 5.x. Manual = classic node pools (no Node Auto
  # Provisioning/Karpenter), same as the portal cluster.
  node_provisioning_profile {
    mode = "Manual"
  }

  # --- System node pool --------------------------------------------------
  default_node_pool {
    name    = "system"
    vm_size = "Standard_D2as_v5"
    type    = "VirtualMachineScaleSets"

    # Manual scaling, one node: the cheapest system pool that still runs all add-ons.
    auto_scaling_enabled = false
    node_count           = 1

    # Taints the pool with CriticalAddonsOnly=true:NoSchedule so only system pods
    # land here; app workloads go to the user pool.
    only_critical_addons_enabled = true

    os_sku          = "Ubuntu"
    os_disk_size_gb = 64
    max_pods        = 110

    vnet_subnet_id = azurerm_subnet.aks_nodes.id
    # No zones: single-zone placement is cheaper and the lab needs no zone redundancy.

    # Changing vm_size, disk size, max_pods etc. rotates the pool through this
    # temporary pool instead of forcing a cluster replacement.
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      # 10% of a 1-node pool rounds up to 1 surge node during upgrades.
      max_surge = "10%"
    }

    tags = local.tags
  }

  tags = local.tags

  # The control plane identity must hold Network Contributor on the subnet BEFORE
  # AKS creates the LB and joins nodes to it. The cluster only references the
  # identity, not the role assignment, so Terraform would otherwise create both
  # in parallel and cluster creation could fail with a permission error.
  depends_on = [
    azurerm_role_assignment.aks_control_plane_network_contributor,
  ]
}

# --- User node pool ------------------------------------------------------
# Separate resource (not a second block in the cluster) so it can be changed,
# scaled or replaced without touching the cluster or the system pool.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  mode                  = "User"

  # B-series (burstable) is the cheapest option for mostly idle lab workloads.
  vm_size = "Standard_B2as_v2"

  auto_scaling_enabled = false
  node_count           = 1

  # Without this the pool gets the "latest recommended" version at creation time,
  # which could differ from the cluster's minor version.
  orchestrator_version = var.kubernetes_version

  os_type         = "Linux"
  os_sku          = "Ubuntu"
  os_disk_size_gb = 64
  max_pods        = 110

  # Same subnet as the system pool; with CNI Overlay nodes need one IP each.
  vnet_subnet_id = azurerm_subnet.aks_nodes.id

  # No node_taints: this pool takes all regular workloads.

  temporary_name_for_rotation = "usertmp"

  upgrade_settings {
    max_surge = "10%"
  }

  tags = local.tags
}
