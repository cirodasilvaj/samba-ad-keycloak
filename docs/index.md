# Enterprise IAM & Single Sign-On Architecture

This repository defines the infrastructure and identity foundation for the **kube-demo-2026** platform on AWS.

## Architecture Highlights

1. **Samba 4 Active Directory Multi-DC (`samba-ad-dc`):**
   - Active Directory Domain Controller deployed in Multi-AZ without internal DNS (`--dns-backend=NONE`).
   - Integrated with Route 53 Private Hosted Zone for RFC-compliant SRV, LDAP, and Kerberos discovery.

2. **FreeRADIUS with Google Authenticator MFA (`freeradius-mfa`):**
   - Centralized RADIUS proxy with PAM Google Authenticator (TOTP) module.
   - Provides Multi-Factor Authentication for VPN, SSH bastions, and enterprise portals.

3. **Keycloak SSO Identity Broker (`keycloak-sso`):**
   - Central identity provider federation via LDAP/Kerberos into Samba 4 AD.
   - Exposes OpenID Connect (OIDC) Discovery endpoints and SAML 2.0 Identity Provider metadata.
   - Enables seamless SSO across Backstage, ArgoCD, Grafana, and demo applications.

## Endpoints

- **Keycloak SSO Base URL:** `http://sso.<lab-id>.realhandsonlabs.net`
- **OIDC Discovery:** `/realms/empresa/.well-known/openid-configuration`
- **SAML 2.0 Descriptor:** `/realms/empresa/protocol/saml/descriptor`
