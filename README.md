# 🔐 IAM Architecture: Samba 4 AD DC (Multi-DC) + FreeRADIUS MFA + Keycloak (SAML 2.0 / OIDC)

Enterprise identity, Active Directory, and federated authentication infrastructure (**SAML 2.0**, **OAuth2/OIDC**, **LDAP/Kerberos**, and **RADIUS with MFA**) natively integrated into the **same VPC as the Kubernetes cluster (`kube-demo-eks`)**, engineered to consume **the minimum possible resources (`t3.micro` + Swap)**.

---

## 🏗️ Full Solution Architecture (Inside the EKS VPC)

```text
                        [ EKS Cluster VPC: kube-demo-eks (10.0.0.0/16) ]
                                                 │
   ┌─────────────────────────────────────────────┴─────────────────────────────────────────────┐
   │ EKS Cluster Private Subnets (Multi-AZ)                                                    │
   │                                                                                           │
   │   ┌────────────────────────────────┐                 ┌────────────────────────────────┐   │
   │   │ EC2 #1: samba-ad-dc-1 (t3.micro)│                 │ EC2 #2: samba-ad-dc-2 (t3.micro)│   │
   │   │ • Primary Samba 4 AD DC        │ ◄─ Replication ► │ • Replica Samba 4 AD DC        │   │
   │   │ • --dns-backend=NONE           │   DRS/SMB/Krb5   │ • --dns-backend=NONE           │   │
   │   │ • FreeRADIUS + PAM TOTP MFA    │                 │ • FreeRADIUS + PAM TOTP MFA    │   │
   │   └───────────────┬────────────────┘                 └───────────────┬────────────────┘   │
   │                   │ (LDAP 389/636 + RADIUS 1812/1813 UDP)            │                    │
   │                   └─────────────────────────┬────────────────────────┘                    │
   │                                             │                                             │
   │                                             ▼                                             │
   │                            ┌────────────────────────────────┐                             │
   │                            │ EC2 #3: keycloak-server        │                             │
   │                            │ • Instance: t3.micro + Swap    │                             │
   │                            │ • SAML 2.0 / OIDC / MFA Broker │                             │
   │                            │ • User Federation: Samba 4 AD  │                             │
   │                            └────────────────┬───────────────┘                             │
   │                                             │                                             │
   │   ┌─────────────────────────────────────────┴─────────────────────────────────────────┐   │
   │   │                 AWS Route 53 (Private Hosted Zone: empresa.local)                 │   │
   │   │  • dc1.empresa.local     --> DC1 Private IP                                       │   │
   │   │  • dc2.empresa.local     --> DC2 Private IP                                       │   │
   │   │  • ad.empresa.local      --> [DC1, DC2] (Round-Robin LDAP/Kerberos + SRV Records) │   │
   │   │  • radius.empresa.local  --> [DC1, DC2] (Round-Robin FreeRADIUS UDP 1812/1813)    │   │
   │   │  • sso.empresa.local     --> Keycloak Private IP (SAML 2.0 / OIDC)                │   │
   │   └─────────────────────────────────────────┬─────────────────────────────────────────┘   │
   └─────────────────────────────────────────────┼─────────────────────────────────────────────┘
                                                 │ (SAML 2.0 / OIDC / LDAP / RADIUS MFA)
                                                 ▼
                  [ EKS Cluster (kube-demo-eks): Backstage, ArgoCD, Grafana, Demo Apps ]
```

---

## 💡 Resource Optimization (Lowest Possible Cost)

- **Zero duplicate networking**: Terraform automatically discovers the VPC, CIDR block, and private subnets of the `kube-demo-eks` cluster via `data "aws_eks_cluster" "target"`.
- **`t3.micro` instances (1 vCPU, 1 GB RAM) + Swap**:
  - `samba-ad-dc-1` and `samba-ad-dc-2` run on `t3.micro` with `10 GB` `gp3` storage and `1 GB` Swap.
  - **FreeRADIUS + MFA (Google Authenticator TOTP)** runs co-located on both Samba 4 Domain Controllers, eliminating the need for dedicated RADIUS instances.
  - `keycloak-server` runs on `t3.micro` with `2 GB` Swap and tuned JVM heap limits (`-Xms256m -Xmx512m`).
- **No internal Samba DNS (`--dns-backend=NONE`)**: Saves memory on the Domain Controllers and delegates all Active Directory name resolution (`A` and `SRV` records) to the **AWS Route 53 Private Hosted Zone** (`empresa.local`).

---

## 🔑 Pre-Configured SAML 2.0, OIDC Clients & Directory Users

On boot, the `empresa` Realm in Keycloak and Samba 4 AD are automatically populated with:

- **Samba 4 AD Users**:
  - `admin-eks` (Groups: `EKS-Admins`, `Backstage-Users`, `ArgoCD-Admins`, `Grafana-Admins`, `MFA-Radius-Users`)
  - `backstage-admin` (Groups: `Backstage-Users`, `MFA-Radius-Users`)
  - `dev-user` (Groups: `Backstage-Users`, `MFA-Radius-Users`)
- **SAML 2.0 and OIDC Clients in Keycloak (`sso.empresa.local`)**:
  - `backstage-saml` and `backstage-oidc`
  - `argocd-saml`
  - `grafana-saml`
  - `apps-demo-python-saml`
  - `apps-demo-dotnet-saml`
- **Internal Kubernetes Service Endpoints (`namespace: default`)**:
  - `Service/keycloak-sso` -> `sso.empresa.local`
  - `Service/samba-ad-ldap` -> `ad.empresa.local`
  - `Service/freeradius-mfa` -> `radius.empresa.local`
  - `ConfigMap/samba-ad-keycloak-sso-config`

---

## 🚀 How to Run

### 1. Via Terraform (Auto-Bootstrap with `user_data` or GitHub Actions)
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2. Via Ansible (Dynamic EC2 Inventory by `Role` Tags)
```bash
cd ansible
ansible-playbook -i inventory/aws_ec2.yml site.yml
```
