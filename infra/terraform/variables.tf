# --- Subscription / general -----------------------------------------------

variable "subscription_id" {
  description = "Target subscription ID. Leave null to use ARM_SUBSCRIPTION_ID or the Azure CLI default subscription."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "germanywestcentral"
}

variable "owner" {
  description = "Value for the 'owner' tag."
  type        = string
}

variable "delete_after" {
  description = "Value for the 'delete-after' tag (date after which the lab may be removed), e.g. 2026-11-30."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.delete_after))
    error_message = "delete_after must be a date in the format YYYY-MM-DD."
  }
}

# --- Naming ---------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group for the cluster, network, identity and ACR."
  type        = string
  default     = "rg-aks-lab-tf"
}

variable "cluster_name" {
  description = "Name of the AKS cluster (also used as DNS prefix)."
  type        = string
  default     = "aks-lab-tf"
}

variable "node_resource_group_name" {
  description = "Name of the AKS-managed node resource group (VMSS, load balancer, public IP, disks)."
  type        = string
  default     = "rg-aks-lab-tf-nodes"
}

variable "acr_name" {
  description = "Azure Container Registry name. Globally unique, 5-50 lowercase alphanumeric characters, no hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 characters, lowercase letters and digits only."
  }
}

# --- Network --------------------------------------------------------------
# With Azure CNI Overlay, pods get IPs from pod_cidr (not from the subnet), so the
# node subnet only needs one IP per node. The VNet must not overlap pod/service CIDRs.

variable "vnet_address_space" {
  description = "Address space of the VNet. Must not overlap pod_cidr or service_cidr."
  type        = string
  default     = "10.10.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "Address prefix of the AKS node subnet (inside vnet_address_space)."
  type        = string
  default     = "10.10.0.0/24"
}

variable "pod_cidr" {
  description = "Overlay CIDR for pod IPs (not routable in the VNet)."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes ClusterIP services."
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP of the kube-dns service; must be inside service_cidr."
  type        = string
  default     = "10.0.0.10"
}

# --- AKS ------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Kubernetes version. Minor version alias (e.g. 1.37) lets the 'patch' auto-upgrade channel move patches without Terraform drift."
  type        = string
  default     = "1.37"
}

# --- RBAC -----------------------------------------------------------------

variable "admin_user_object_id" {
  description = "Entra object ID of the user that gets 'Azure Kubernetes Service RBAC Cluster Admin' (az ad signed-in-user show --query id -o tsv)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.admin_user_object_id))
    error_message = "admin_user_object_id must be a GUID."
  }
}

# --- GitOps ----------------------------------------------------------------

variable "gitops_repo_url" {
  description = "HTTPS URL of the Git repository Flux reconciles from (public, no auth)."
  type        = string
  default     = "https://github.com/svenveit/aks-gitops-platform"
}

variable "gitops_branch" {
  description = "Branch Flux tracks. Changes take effect only after they are pushed to it."
  type        = string
  default     = "main"
}
