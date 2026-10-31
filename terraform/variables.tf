variable "aws_region" {
  description = "AWS region where the EKS cluster and IAM infrastructure run"
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster whose VPC will host Samba 4 AD, FreeRADIUS, and Keycloak"
  type        = string
  default     = "kube-demo-eks"
}

variable "samba_instance_type" {
  description = "Cheapest possible EC2 instance type for Samba 4 AD + FreeRADIUS nodes"
  type        = string
  default     = "t3.micro"
}

variable "keycloak_instance_type" {
  description = "Cheapest possible EC2 instance type for Keycloak server (tuned with 2GB swap + JVM limits)"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size_gb" {
  description = "Minimal EBS gp3 root volume size in GB for each instance"
  type        = number
  default     = 10
}

variable "domain_name" {
  description = "Active Directory DNS domain name managed via Route 53 Private Hosted Zone"
  type        = string
  default     = "empresa.local"
}

variable "domain_realm" {
  description = "Kerberos/AD realm name (uppercase)"
  type        = string
  default     = "EMPRESA.LOCAL"
}

variable "domain_workgroup" {
  description = "NetBIOS workgroup name for Samba 4 AD"
  type        = string
  default     = "EMPRESA"
}

variable "ad_admin_password" {
  description = "Administrator password for Samba 4 Active Directory"
  type        = string
  default     = "SuaSenhaForte123!"
}

variable "radius_shared_secret" {
  description = "Shared secret for FreeRADIUS MFA authentication across the EKS VPC"
  type        = string
  default     = "RadiusSecret2026!"
}

variable "keycloak_version" {
  description = "Keycloak version to install"
  type        = string
  default     = "24.0.1"
}

variable "keycloak_admin_user" {
  description = "Initial admin username for Keycloak"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Initial admin password for Keycloak"
  type        = string
  default     = "KeycloakAdmin2026!"
}
