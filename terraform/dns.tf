# ==============================================================================
# Auto-Descoberta da Hosted Zone Route 53 da Conta AWS (*realhandsonlabs.net)
# ==============================================================================

data "aws_route53_zones" "all" {}

data "aws_route53_zone" "all" {
  for_each = toset(data.aws_route53_zones.all.ids)
  zone_id  = each.value
}

locals {
  # Filtra a zona pública fornecida pela conta temporária do laboratório
  lab_zones = [
    for z in data.aws_route53_zone.all : z
    if can(regex("realhandsonlabs\\.net", z.name)) && !z.private_zone
  ]

  has_lab_zone = length(local.lab_zones) > 0
  lab_zone_id  = local.has_lab_zone ? local.lab_zones[0].zone_id : ""
  # Remove o ponto final do FQDN (ex: "123456.realhandsonlabs.net." -> "123456.realhandsonlabs.net")
  lab_domain = local.has_lab_zone ? trimsuffix(local.lab_zones[0].name, ".") : ""
}

# ==============================================================================
# Registros DNS no Route 53 da Conta do Lab (Domínio do Laboratório)
# ==============================================================================

# Registro A para DC1
resource "aws_route53_record" "lab_dc1" {
  count   = local.has_lab_zone ? 1 : 0
  zone_id = local.lab_zone_id
  name    = "dc1.${local.lab_domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.samba_dc1.private_ip]
}

# Registro A para DC2
resource "aws_route53_record" "lab_dc2" {
  count   = local.has_lab_zone ? 1 : 0
  zone_id = local.lab_zone_id
  name    = "dc2.${local.lab_domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.samba_dc2.private_ip]
}

# Registro A Round-Robin para Active Directory (ad.<lab_domain>)
resource "aws_route53_record" "lab_ad" {
  count   = local.has_lab_zone ? 1 : 0
  zone_id = local.lab_zone_id
  name    = "ad.${local.lab_domain}"
  type    = "A"
  ttl     = 60
  records = [
    aws_instance.samba_dc1.private_ip,
    aws_instance.samba_dc2.private_ip,
  ]
}

# Registro A Round-Robin para FreeRADIUS MFA (radius.<lab_domain>)
resource "aws_route53_record" "lab_radius" {
  count   = local.has_lab_zone ? 1 : 0
  zone_id = local.lab_zone_id
  name    = "radius.${local.lab_domain}"
  type    = "A"
  ttl     = 60
  records = [
    aws_instance.samba_dc1.private_ip,
    aws_instance.samba_dc2.private_ip,
  ]
}

# Registro A para Keycloak IAM SSO (sso.<lab_domain> e keycloak.<lab_domain>)
resource "aws_route53_record" "lab_sso" {
  count   = local.has_lab_zone ? 1 : 0
  zone_id = local.lab_zone_id
  name    = "sso.${local.lab_domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.keycloak.private_ip]
}

resource "aws_route53_record" "lab_keycloak" {
  count   = local.has_lab_zone ? 1 : 0
  zone_id = local.lab_zone_id
  name    = "keycloak.${local.lab_domain}"
  type    = "A"
  ttl     = 60
  records = [aws_instance.keycloak.private_ip]
}
