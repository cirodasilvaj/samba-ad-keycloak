output "eks_cluster_name" {
  description = "EKS cluster integrated with Samba 4 AD, FreeRADIUS MFA, and Keycloak"
  value       = data.aws_eks_cluster.target.name
}

output "vpc_id" {
  description = "Shared EKS VPC ID where Samba 4 AD, FreeRADIUS, and Keycloak are deployed"
  value       = data.aws_vpc.target.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block allowed in Samba AD, FreeRADIUS, and Keycloak Security Groups"
  value       = data.aws_vpc.target.cidr_block
}

output "samba_dc1_instance_id" {
  description = "EC2 Instance ID of Samba 4 AD Primary Domain Controller (DC1)"
  value       = aws_instance.samba_dc1.id
}

output "samba_dc1_private_ip" {
  description = "Private IP address of Samba 4 AD Primary Domain Controller (dc1.empresa.local)"
  value       = aws_instance.samba_dc1.private_ip
}

output "samba_dc2_instance_id" {
  description = "EC2 Instance ID of Samba 4 AD Replica Domain Controller (DC2)"
  value       = aws_instance.samba_dc2.id
}

output "samba_dc2_private_ip" {
  description = "Private IP address of Samba 4 AD Replica Domain Controller (dc2.empresa.local)"
  value       = aws_instance.samba_dc2.private_ip
}

output "keycloak_instance_id" {
  description = "EC2 Instance ID of the Keycloak IAM Server"
  value       = aws_instance.keycloak.id
}

output "keycloak_private_ip" {
  description = "Private IP address of the Keycloak IAM Server (sso.empresa.local)"
  value       = aws_instance.keycloak.private_ip
}

output "instance_types_summary" {
  description = "Summary of minimal EC2 instance types used for cost optimization"
  value = {
    samba_dc1 = aws_instance.samba_dc1.instance_type
    samba_dc2 = aws_instance.samba_dc2.instance_type
    keycloak  = aws_instance.keycloak.instance_type
  }
}

output "route53_private_zone_id" {
  description = "Route 53 Private Hosted Zone ID for empresa.local"
  value       = aws_route53_zone.private_zone.zone_id
}

output "route53_dns_records" {
  description = "Private DNS records created in Route 53 for AD, FreeRADIUS, and Keycloak"
  value = {
    dc1      = "${aws_route53_record.dc1_record.fqdn} -> ${aws_instance.samba_dc1.private_ip}"
    dc2      = "${aws_route53_record.dc2_record.fqdn} -> ${aws_instance.samba_dc2.private_ip}"
    ad_rr    = "${aws_route53_record.ad_domain_record.fqdn} -> [${aws_instance.samba_dc1.private_ip}, ${aws_instance.samba_dc2.private_ip}]"
    radius   = "${aws_route53_record.radius_record.fqdn} -> [${aws_instance.samba_dc1.private_ip}, ${aws_instance.samba_dc2.private_ip}]"
    keycloak = "${aws_route53_record.keycloak_record.fqdn} -> ${aws_instance.keycloak.private_ip}"
  }
}

output "ad_ldap_connection_url" {
  description = "Round-Robin LDAP URL for connecting Keycloak and apps to Samba 4 AD"
  value       = "ldap://ad.${var.domain_name}:389"
}

output "ad_base_dn" {
  description = "Active Directory Base DN for user and group searches"
  value       = "DC=empresa,DC=local"
}

output "radius_mfa_endpoints" {
  description = "FreeRADIUS UDP authentication (1812) and accounting (1813) endpoints for general auth and MFA"
  value = {
    round_robin_dns = "radius.${var.domain_name}:1812"
    dc1_endpoint    = "${aws_instance.samba_dc1.private_ip}:1812"
    dc2_endpoint    = "${aws_instance.samba_dc2.private_ip}:1812"
  }
}

output "keycloak_sso_url" {
  description = "Internal URL for Keycloak IAM Server inside the EKS VPC"
  value       = "http://sso.${var.domain_name}"
}

output "keycloak_saml_descriptor_url" {
  description = "SAML 2.0 IdP Metadata Descriptor URL for all SAML apps"
  value       = "http://sso.${var.domain_name}/realms/empresa/protocol/saml/descriptor"
}

output "keycloak_oidc_discovery_url" {
  description = "OIDC OpenID Configuration URL for EKS and cluster apps"
  value       = "http://sso.${var.domain_name}/realms/empresa/.well-known/openid-configuration"
}
