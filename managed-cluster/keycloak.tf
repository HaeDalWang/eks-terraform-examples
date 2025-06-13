# # AWS ClientVPN에서 사용할 Keycloak Realm
# resource "keycloak_realm" "this" {
#   realm = local.project

#   user_managed_access = true
# }

# # AWS ClientVPN에서 사용할  Keycloak SAML Client
# resource "keycloak_saml_client" "client_vpn" {
#   realm_id  = keycloak_realm.this.id
#   client_id = "urn:amazon:webservices:clientvpn"
#   name      = "AWS Client VPN"

#   client_signature_required = false

#   valid_redirect_uris = [
#     "http://127.0.0.1:35001",
#     "https://self-service.clientvpn.amazonaws.com/api/auth/sso/saml"
#   ]
# }

# # AWS ClientVPN에서 지원하지 않는 Scope 삭제 - 기본값으로 적용되는 role_list 삭제
# resource "keycloak_saml_client_default_scopes" "client_vpn" {
#   realm_id  = keycloak_realm.this.id
#   client_id = keycloak_saml_client.client_vpn.id

#   default_scopes = []
# }

# # XML형식으로된 SAML Client 메타데이터 다운로드 
# data "http" "client_vpn" {
#   url = "https://${data.kubernetes_ingress_v1.keycloak.spec[0].rule[0].host}/realms/${keycloak_realm.this.realm}/protocol/saml/descriptor"
# }

# # SAML 제공자 생성
# resource "aws_iam_saml_provider" "client_vpn" {
#   name                   = "client-vpn"
#   saml_metadata_document = replace(data.http.client_vpn.response_body, "WantAuthnRequestsSigned=\"true\"", "WantAuthnRequestsSigned=\"false\"")
# }