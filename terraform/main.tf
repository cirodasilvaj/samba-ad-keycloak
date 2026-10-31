# ============================================================================
# 1. Security Groups (Integrated with EKS Cluster VPC & Nodes)
# ============================================================================

# Security Group for Samba 4 AD DCs + FreeRADIUS MFA (No port 53 / DNS)
resource "aws_security_group" "samba_ad_sg" {
  name        = "samba-ad-dc-sg"
  description = "SG para Samba 4 AD DC (Sem DNS interno) e FreeRADIUS MFA integrado ao EKS"
  vpc_id      = data.aws_vpc.target.id

  # LDAP & LDAPS (Keycloak, EKS Pods, FreeRADIUS -> Samba AD)
  ingress {
    description = "LDAP from VPC and EKS"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "LDAP UDP (CLDAP) from VPC and EKS"
    from_port   = 389
    to_port     = 389
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "LDAPS from VPC and EKS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  # Global Catalog (AD Multi-DC)
  ingress {
    description = "AD Global Catalog TCP"
    from_port   = 3268
    to_port     = 3269
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  # Kerberos Authentication & kpasswd
  ingress {
    description = "Kerberos TCP"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "Kerberos UDP"
    from_port   = 88
    to_port     = 88
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "Kerberos kpasswd TCP"
    from_port   = 464
    to_port     = 464
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "Kerberos kpasswd UDP"
    from_port   = 464
    to_port     = 464
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  # SMB / RPC (Native DRS Replication between DC1 and DC2)
  ingress {
    description = "SMB for AD DRS Replication"
    from_port   = 445
    to_port     = 445
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "RPC Endpoint Mapper for AD DRS Replication"
    from_port   = 135
    to_port     = 135
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "Dynamic RPC Ports for AD DRS Replication"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  # FreeRADIUS Authentication & Accounting (MFA + General Auth)
  ingress {
    description = "FreeRADIUS Auth (1812) and Acct (1813) UDP from VPC and EKS"
    from_port   = 1812
    to_port     = 1813
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  # SSH for Ansible management inside the VPC
  ingress {
    description = "SSH for Ansible inside VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "samba-ad-dc-sg"
  }
}

# Security Group for Keycloak IAM / SAML 2.0 / OIDC Server
resource "aws_security_group" "keycloak_sg" {
  name        = "keycloak-sg"
  description = "SG para o Servidor Keycloak (SAML 2.0 / OIDC / MFA) integrado ao EKS"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description = "HTTP from VPC and EKS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "HTTPS from VPC and EKS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "Keycloak 8080 from VPC and EKS"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  ingress {
    description = "SSH for Ansible inside VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "keycloak-sg"
  }
}

# ============================================================================
# 2. EC2 Instances (Minimum Footprint: t3.micro with Swap & Self-Bootstrap)
# ============================================================================

# EC2 #1 - Samba 4 AD DC 1 (Primary in AZ 1) + FreeRADIUS MFA
resource "aws_instance" "samba_dc1" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = var.samba_instance_type
  subnet_id              = local.subnet_az1_id
  vpc_security_group_ids = [aws_security_group.samba_ad_sg.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # 1. Create 1GB swapfile for t3.micro stability
    if [ ! -f /swapfile ]; then
      fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    hostnamectl set-hostname dc1.${var.domain_name}
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    echo "$${PRIVATE_IP} dc1.${var.domain_name} dc1" >> /etc/hosts

    # 2. Install Samba 4 AD DC + Kerberos + Winbind + FreeRADIUS + PAM Google Authenticator MFA
    apt-get update -y
    apt-get install -y samba krb5-user winbind libpam-winbind libnss-winbind smbclient python3-winbind \
      freeradius freeradius-ldap freeradius-utils libpam-google-authenticator

    # 3. Provision Samba 4 AD DC without internal DNS (--dns-backend=NONE)
    systemctl stop smbd nmbd winbind samba-ad-dc || true
    systemctl disable smbd nmbd winbind || true
    rm -f /etc/samba/smb.conf
    rm -rf /var/lib/samba/private/* /var/lib/samba/sysvol/*

    samba-tool domain provision \
      --use-rfc2307 \
      --realm=${var.domain_realm} \
      --domain=${var.domain_workgroup} \
      --server-role=dc \
      --dns-backend=NONE \
      --adminpass='${var.ad_admin_password}'

    sed -i '/\[global\]/a \        ldap server require strong auth = no' /etc/samba/smb.conf
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

    systemctl unmask samba-ad-dc
    systemctl enable --now samba-ad-dc

    # 4. Seed Organizational Groups & Users for EKS, Backstage, ArgoCD, Grafana & SAML/RADIUS
    sleep 5
    for grp in "EKS-Admins" "Backstage-Users" "ArgoCD-Admins" "Grafana-Admins" "MFA-Radius-Users"; do
      samba-tool group add "$grp" || true
    done

    samba-tool user create admin-eks '${var.ad_admin_password}' --given-name="Admin" --surname="EKS" --mail-address="admin-eks@${var.domain_name}" || true
    samba-tool user create backstage-admin '${var.ad_admin_password}' --given-name="Backstage" --surname="Admin" --mail-address="backstage@${var.domain_name}" || true
    samba-tool user create dev-user '${var.ad_admin_password}' --given-name="Developer" --surname="User" --mail-address="dev@${var.domain_name}" || true

    samba-tool group addmembers "EKS-Admins" admin-eks || true
    samba-tool group addmembers "Backstage-Users" admin-eks,backstage-admin,dev-user || true
    samba-tool group addmembers "ArgoCD-Admins" admin-eks || true
    samba-tool group addmembers "Grafana-Admins" admin-eks || true
    samba-tool group addmembers "MFA-Radius-Users" admin-eks,backstage-admin,dev-user || true

    # 5. Configure FreeRADIUS for General Auth + MFA with Samba 4 AD
    usermod -a -G winbindd_priv freerad || true
    cat <<'RADCLIENT' >> /etc/freeradius/3.0/clients.conf
    client vpc-eks-network {
      ipaddr = ${data.aws_vpc.target.cidr_block}
      secret = ${var.radius_shared_secret}
      require_message_authenticator = no
      nas_type = other
    }
    RADCLIENT

    ln -sf /etc/freeradius/3.0/mods-available/pam /etc/freeradius/3.0/mods-enabled/pam || true
    systemctl enable --now freeradius
  EOF

  tags = {
    Name = "samba-ad-dc-1"
    Role = "samba-dc-primary"
  }
}

# EC2 #2 - Samba 4 AD DC 2 (Replica in AZ 2) + FreeRADIUS MFA
resource "aws_instance" "samba_dc2" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = var.samba_instance_type
  subnet_id              = local.subnet_az2_id
  vpc_security_group_ids = [aws_security_group.samba_ad_sg.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # 1. Create 1GB swapfile for t3.micro stability
    if [ ! -f /swapfile ]; then
      fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    hostnamectl set-hostname dc2.${var.domain_name}
    PRIVATE_IP=$(hostname -I | awk '{print $1}')
    echo "$${PRIVATE_IP} dc2.${var.domain_name} dc2" >> /etc/hosts
    echo "${aws_instance.samba_dc1.private_ip} dc1.${var.domain_name} dc1 ${var.domain_name} ad.${var.domain_name}" >> /etc/hosts

    apt-get update -y
    apt-get install -y samba krb5-user winbind libpam-winbind libnss-winbind smbclient python3-winbind \
      freeradius freeradius-ldap freeradius-utils libpam-google-authenticator netcat-openbsd

    systemctl stop smbd nmbd winbind samba-ad-dc || true
    systemctl disable smbd nmbd winbind || true
    rm -f /etc/samba/smb.conf

    cat <<'KRB5' > /etc/krb5.conf
    [libdefaults]
      default_realm = ${var.domain_realm}
      dns_lookup_realm = false
      dns_lookup_kdc = false
    [realms]
      ${var.domain_realm} = {
        kdc = ${aws_instance.samba_dc1.private_ip}
        admin_server = ${aws_instance.samba_dc1.private_ip}
      }
    KRB5

    # Wait for DC1 LDAP (389) to become ready before joining as Replica DC
    for i in $(seq 1 60); do
      if nc -z ${aws_instance.samba_dc1.private_ip} 389; then
        break
      fi
      sleep 5
    done

    samba-tool domain join ${var.domain_realm} DC \
      -U"${var.domain_workgroup}\Administrator" \
      --password='${var.ad_admin_password}' \
      --dns-backend=NONE \
      --server=dc1.${var.domain_name}

    sed -i '/\[global\]/a \        ldap server require strong auth = no' /etc/samba/smb.conf
    systemctl unmask samba-ad-dc
    systemctl enable --now samba-ad-dc

    # Configure FreeRADIUS Replica
    usermod -a -G winbindd_priv freerad || true
    cat <<'RADCLIENT' >> /etc/freeradius/3.0/clients.conf
    client vpc-eks-network {
      ipaddr = ${data.aws_vpc.target.cidr_block}
      secret = ${var.radius_shared_secret}
      require_message_authenticator = no
      nas_type = other
    }
    RADCLIENT

    ln -sf /etc/freeradius/3.0/mods-available/pam /etc/freeradius/3.0/mods-enabled/pam || true
    systemctl enable --now freeradius
  EOF

  tags = {
    Name = "samba-ad-dc-2"
    Role = "samba-dc-replica"
  }

  depends_on = [aws_instance.samba_dc1]
}

# EC2 #3 - Keycloak IAM Server (SAML 2.0 / OIDC / LDAP Federation / MFA)
resource "aws_instance" "keycloak" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = var.keycloak_instance_type
  subnet_id              = local.subnet_az1_id
  vpc_security_group_ids = [aws_security_group.keycloak_sg.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive

    # 1. Create 2GB swapfile so Keycloak runs smoothly on t3.micro
    if [ ! -f /swapfile ]; then
      fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    hostnamectl set-hostname sso.${var.domain_name}
    echo "${aws_instance.samba_dc1.private_ip} dc1.${var.domain_name} ad.${var.domain_name}" >> /etc/hosts

    apt-get update -y
    apt-get install -y openjdk-21-jre-headless curl unzip jq

    mkdir -p /opt
    curl -fsSL "https://github.com/keycloak/keycloak/releases/download/${var.keycloak_version}/keycloak-${var.keycloak_version}.tar.gz" -o /tmp/keycloak.tar.gz
    tar -xzf /tmp/keycloak.tar.gz -C /opt/
    rm -f /tmp/keycloak.tar.gz
    mkdir -p /opt/keycloak-${var.keycloak_version}/data/import

    # Pre-seed Realm "empresa" with Samba 4 AD LDAP Federation, OTP/MFA, SAML 2.0 & OIDC Clients
    cat <<'REALMJSON' > /opt/keycloak-${var.keycloak_version}/data/import/realm-empresa.json
    {
      "realm": "empresa",
      "enabled": true,
      "displayName": "Empresa IAM (Samba 4 AD + SAML 2.0 + OIDC + MFA)",
      "sslRequired": "none",
      "registrationAllowed": false,
      "loginWithEmailAllowed": true,
      "duplicateEmailsAllowed": false,
      "resetPasswordAllowed": true,
      "otpPolicyType": "totp",
      "otpPolicyAlgorithm": "HmacSHA1",
      "otpPolicyInitialCounter": 0,
      "otpPolicyDigits": 6,
      "otpPolicyLookAheadWindow": 1,
      "otpPolicyPeriod": 30,
      "clients": [
        {
          "clientId": "backstage-saml",
          "name": "Backstage Developer Portal (SAML 2.0)",
          "protocol": "saml",
          "enabled": true,
          "publicClient": false,
          "redirectUris": ["*"],
          "baseUrl": "http://backstage.backstage.svc.cluster.local:7007"
        },
        {
          "clientId": "backstage-oidc",
          "name": "Backstage Developer Portal (OIDC)",
          "protocol": "openid-connect",
          "enabled": true,
          "publicClient": false,
          "secret": "backstage-oidc-secret-2026",
          "redirectUris": ["*"],
          "webOrigins": ["*"]
        },
        {
          "clientId": "argocd-saml",
          "name": "ArgoCD GitOps (SAML 2.0 / OIDC)",
          "protocol": "saml",
          "enabled": true,
          "redirectUris": ["*"]
        },
        {
          "clientId": "grafana-saml",
          "name": "Grafana Observability (SAML 2.0 / OIDC)",
          "protocol": "saml",
          "enabled": true,
          "redirectUris": ["*"]
        },
        {
          "clientId": "apps-demo-python-saml",
          "name": "Apps Demo 2026 - Python App (SAML 2.0)",
          "protocol": "saml",
          "enabled": true,
          "redirectUris": ["*"]
        },
        {
          "clientId": "apps-demo-dotnet-saml",
          "name": "Apps Demo 2026 - .NET C# App (SAML 2.0)",
          "protocol": "saml",
          "enabled": true,
          "redirectUris": ["*"]
        }
      ],
      "components": {
        "org.keycloak.storage.UserStorageProvider": [
          {
            "name": "samba4-ad-ldap",
            "providerId": "ldap",
            "config": {
              "enabled": ["true"],
              "vendor": ["ad"],
              "connectionUrl": ["ldap://ad.${var.domain_name}:389"],
              "usersDn": ["CN=Users,DC=empresa,DC=local"],
              "bindDn": ["CN=Administrator,CN=Users,DC=empresa,DC=local"],
              "bindCredential": ["${var.ad_admin_password}"],
              "authType": ["simple"],
              "editMode": ["WRITABLE"],
              "usernameLDAPAttribute": ["sAMAccountName"],
              "rdnLDAPAttribute": ["cn"],
              "uuidLDAPAttribute": ["objectGUID"],
              "userObjectClasses": ["person, organizationalPerson, user"],
              "searchScope": ["2"],
              "SyncRegistrations": ["true"]
            }
          }
        ]
      }
    }
    REALMJSON

    cat <<'SERVICE' > /etc/systemd/system/keycloak.service
    [Unit]
    Description=Keycloak IAM Server (SAML 2.0 / OIDC / Samba4 AD Federation)
    After=network.target

    [Service]
    Type=simple
    User=root
    Environment="KEYCLOAK_ADMIN=${var.keycloak_admin_user}"
    Environment="KEYCLOAK_ADMIN_PASSWORD=${var.keycloak_admin_password}"
    Environment="JAVA_OPTS_APPEND=-Xms256m -Xmx512m"
    ExecStart=/opt/keycloak-${var.keycloak_version}/bin/kc.sh start-dev --http-port=80 --import-realm
    Restart=always
    RestartSec=10
    TimeoutStartSec=600
    TimeoutStopSec=50

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now keycloak
  EOF

  tags = {
    Name = "keycloak-server"
    Role = "keycloak-server"
  }

  depends_on = [aws_instance.samba_dc1]
}

# ============================================================================
# 3. AWS Route 53 Private Hosted Zone (empresa.local) linked to EKS VPC
# ============================================================================

resource "aws_route53_zone" "private_zone" {
  name    = var.domain_name
  comment = "Private Hosted Zone for Samba 4 AD DC (No internal DNS), FreeRADIUS MFA & Keycloak SSO"

  vpc {
    vpc_id = data.aws_vpc.target.id
  }
}

resource "aws_route53_record" "dc1_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "dc1.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.samba_dc1.private_ip]
}

resource "aws_route53_record" "dc2_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "dc2.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.samba_dc2.private_ip]
}

# Root domain A record (Round-Robin across DC1 and DC2)
resource "aws_route53_record" "domain_root_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 60
  records = [
    aws_instance.samba_dc1.private_ip,
    aws_instance.samba_dc2.private_ip,
  ]
}

# Active Directory Round-Robin DNS record (ad.empresa.local)
resource "aws_route53_record" "ad_domain_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "ad.${var.domain_name}"
  type    = "A"
  ttl     = 60
  records = [
    aws_instance.samba_dc1.private_ip,
    aws_instance.samba_dc2.private_ip,
  ]
}

# FreeRADIUS Round-Robin DNS record (radius.empresa.local)
resource "aws_route53_record" "radius_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "radius.${var.domain_name}"
  type    = "A"
  ttl     = 60
  records = [
    aws_instance.samba_dc1.private_ip,
    aws_instance.samba_dc2.private_ip,
  ]
}

# Keycloak SSO DNS record (sso.empresa.local)
resource "aws_route53_record" "keycloak_record" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "sso.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.keycloak.private_ip]
}

# Active Directory SRV records in Route 53 (replaces internal Samba DNS)
resource "aws_route53_record" "ldap_srv" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "_ldap._tcp.${var.domain_name}"
  type    = "SRV"
  ttl     = 300
  records = [
    "0 100 389 dc1.${var.domain_name}.",
    "0 100 389 dc2.${var.domain_name}.",
  ]
}

resource "aws_route53_record" "ldap_dc_msdcs_srv" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "_ldap._tcp.dc._msdcs.${var.domain_name}"
  type    = "SRV"
  ttl     = 300
  records = [
    "0 100 389 dc1.${var.domain_name}.",
    "0 100 389 dc2.${var.domain_name}.",
  ]
}

resource "aws_route53_record" "kerberos_tcp_srv" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "_kerberos._tcp.${var.domain_name}"
  type    = "SRV"
  ttl     = 300
  records = [
    "0 100 88 dc1.${var.domain_name}.",
    "0 100 88 dc2.${var.domain_name}.",
  ]
}

resource "aws_route53_record" "kerberos_udp_srv" {
  zone_id = aws_route53_zone.private_zone.zone_id
  name    = "_kerberos._udp.${var.domain_name}"
  type    = "SRV"
  ttl     = 300
  records = [
    "0 100 88 dc1.${var.domain_name}.",
    "0 100 88 dc2.${var.domain_name}.",
  ]
}

# ============================================================================
# 4. Kubernetes Integration (ConfigMap & External Proxy in EKS Cluster)
# ============================================================================

resource "kubernetes_config_map_v1" "iam_sso_config" {
  metadata {
    name      = "samba-ad-keycloak-sso-config"
    namespace = "default"
    labels = {
      "app.kubernetes.io/part-of" = "samba-ad-keycloak"
    }
  }

  data = {
    AD_DOMAIN              = var.domain_name
    AD_REALM               = var.domain_realm
    AD_LDAP_URL            = "ldap://ad.${var.domain_name}:389"
    AD_DC1_IP              = aws_instance.samba_dc1.private_ip
    AD_DC2_IP              = aws_instance.samba_dc2.private_ip
    RADIUS_HOST            = "radius.${var.domain_name}"
    RADIUS_AUTH_PORT       = "1812"
    RADIUS_ACCT_PORT       = "1813"
    KEYCLOAK_INTERNAL_URL  = "http://sso.${var.domain_name}"
    KEYCLOAK_REALM         = "empresa"
    KEYCLOAK_SAML_METADATA = "http://sso.${var.domain_name}/realms/empresa/protocol/saml/descriptor"
    KEYCLOAK_OIDC_ISSUER   = "http://sso.${var.domain_name}/realms/empresa"
  }
}
