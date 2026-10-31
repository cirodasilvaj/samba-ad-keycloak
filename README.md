# 🔐 Arquitetura IAM: Samba 4 AD DC (Multi-DC) + FreeRADIUS MFA + Keycloak (SAML 2.0 / OIDC)

Infraestrutura corporativa de controle de acesso, diretório ativo e autenticação federada (**SAML 2.0**, **OAuth2/OIDC**, **LDAP/Kerberos** e **RADIUS com MFA**) integrada nativamente à **mesma VPC do cluster Kubernetes (`kube-demo-eks`)**, projetada para consumir **o mínimo de recursos possível (`t3.micro` + Swap)**.

---

## 🏗️ Arquitetura Completa da Solução (Na VPC do EKS)

```text
                        [ VPC do Cluster EKS: kube-demo-eks (10.0.0.0/16) ]
                                                 │
   ┌─────────────────────────────────────────────┴─────────────────────────────────────────────┐
   │ Sub-redes Privadas do Cluster EKS (Multi-AZ)                                              │
   │                                                                                           │
   │   ┌────────────────────────────────┐                 ┌────────────────────────────────┐   │
   │   │ EC2 #1: samba-ad-dc-1 (t3.micro)│                 │ EC2 #2: samba-ad-dc-2 (t3.micro)│   │
   │   │ • Samba 4 AD DC Principal      │ ◄─ Replicação ─► │ • Samba 4 AD DC Réplica        │   │
   │   │ • --dns-backend=NONE           │   DRS/SMB/Krb5   │ • --dns-backend=NONE           │   │
   │   │ • FreeRADIUS + PAM TOTP MFA    │                 │ • FreeRADIUS + PAM TOTP MFA    │   │
   │   └───────────────┬────────────────┘                 └───────────────┬────────────────┘   │
   │                   │ (LDAP 389/636 + RADIUS 1812/1813 UDP)            │                    │
   │                   └─────────────────────────┬────────────────────────┘                    │
   │                                             │                                             │
   │                                             ▼                                             │
   │                            ┌────────────────────────────────┐                             │
   │                            │ EC2 #3: keycloak-server        │                             │
   │                            │ • Instância: t3.micro + Swap   │                             │
   │                            │ • Broker SAML 2.0 / OIDC / MFA │                             │
   │                            │ • User Federation: Samba 4 AD  │                             │
   │                            └────────────────┬───────────────┘                             │
   │                                             │                                             │
   │   ┌─────────────────────────────────────────┴─────────────────────────────────────────┐   │
   │   │                 AWS Route 53 (Private Hosted Zone: empresa.local)                 │   │
   │   │  • dc1.empresa.local     --> IP Privado DC1                                       │   │
   │   │  • dc2.empresa.local     --> IP Privado DC2                                       │   │
   │   │  • ad.empresa.local      --> [DC1, DC2] (Round-Robin LDAP/Kerberos + SRV Records) │   │
   │   │  • radius.empresa.local  --> [DC1, DC2] (Round-Robin FreeRADIUS UDP 1812/1813)    │   │
   │   │  • sso.empresa.local     --> IP Privado Keycloak (SAML 2.0 / OIDC)                │   │
   │   └─────────────────────────────────────────┬─────────────────────────────────────────┘   │
   └─────────────────────────────────────────────┼─────────────────────────────────────────────┘
                                                 │ (SAML 2.0 / OIDC / LDAP / RADIUS MFA)
                                                 ▼
                  [ Cluster EKS (kube-demo-eks): Backstage, ArgoCD, Grafana, Apps Demo ]
```

---

## 💡 Otimização de Recursos (Menor Custo Possível)

- **Zero criação de rede duplicada**: O Terraform descobre automaticamente a VPC, o bloco CIDR e as sub-redes privadas do cluster `kube-demo-eks` via `data "aws_eks_cluster" "target"`.
- **Instâncias `t3.micro` (1 vCPU, 1 GB RAM) + Swap**:
  - `samba-ad-dc-1` e `samba-ad-dc-2` utilizam `t3.micro` com disco `gp3` de `10 GB` e `1 GB` de Swap.
  - **FreeRADIUS + MFA (Google Authenticator TOTP)** roda co-localizado nos 2 DCs Samba 4, eliminando a necessidade de instâncias extras para RADIUS.
  - `keycloak-server` roda em `t3.micro` com `2 GB` de Swap e limites de heap da JVM (`-Xms256m -Xmx512m`).
- **Sem DNS embutido no Samba (`--dns-backend=NONE`)**: Economiza memória nos DCs e delega toda a resolução de nomes (`A` e `SRV` do Active Directory) para a **Private Hosted Zone do AWS Route 53** (`empresa.local`).

---

## 🔑 Clientes SAML 2.0, OIDC e Usuários Pré-Configurados

Ao subir, o Realm `empresa` no Keycloak e o Samba 4 AD já vêm populados com:

- **Usuários no Samba 4 AD**:
  - `admin-eks` (Grupos: `EKS-Admins`, `Backstage-Users`, `ArgoCD-Admins`, `Grafana-Admins`, `MFA-Radius-Users`)
  - `backstage-admin` (Grupos: `Backstage-Users`, `MFA-Radius-Users`)
  - `dev-user` (Grupos: `Backstage-Users`, `MFA-Radius-Users`)
- **Clientes SAML 2.0 e OIDC no Keycloak (`sso.empresa.local`)**:
  - `backstage-saml` e `backstage-oidc`
  - `argocd-saml`
  - `grafana-saml`
  - `apps-demo-python-saml`
  - `apps-demo-dotnet-saml`
- **Endpoints Internos no Cluster EKS (`namespace: default`)**:
  - `Service/keycloak-sso` -> `sso.empresa.local`
  - `Service/samba-ad-ldap` -> `ad.empresa.local`
  - `Service/freeradius-mfa` -> `radius.empresa.local`
  - `ConfigMap/samba-ad-keycloak-sso-config`

---

## 🚀 Como Executar

### 1. Via Terraform (Auto-Bootstrap com `user_data` ou GitHub Actions)
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### 2. Via Ansible (Inventário Dinâmico EC2 por Tags `Role`)
```bash
cd ansible
ansible-playbook -i inventory/aws_ec2.yml site.yml
```
