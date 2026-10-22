resource "keycloak_realm" "realm" {
  realm             = "lab"
  enabled           = true
}

##################
# Group Creation #
##################
resource "keycloak_group" "admins" {
  realm_id = keycloak_realm.realm.id
  name     = "platform-admins"
}

resource "keycloak_group" "dev" {
  realm_id = keycloak_realm.realm.id
  name     = "developers"
}

#################
# User Creation #
#################
resource "keycloak_user" "alice" {
  realm_id   = keycloak_realm.realm.id
  username   = "alice"
  enabled    = true

  initial_password {
    value     = "temp"
    temporary = true
  }
}

resource "keycloak_user" "bob" {
  realm_id   = keycloak_realm.realm.id
  username   = "bob"
  enabled    = true

  initial_password {
    value     = "temp"
    temporary = true
  }
}

####################
# Group Assignment #
####################
resource "keycloak_user_groups" "alice_groups" {
  realm_id = keycloak_realm.realm.id
  user_id = keycloak_user.alice.id

  group_ids  = [
    keycloak_group.admins.id
  ]
}

resource "keycloak_user_groups" "bob_groups" {
  realm_id = keycloak_realm.realm.id
  user_id = keycloak_user.bob.id

  group_ids  = [
    keycloak_group.dev.id
  ]
}

# Create the client for ArgoCD
resource "keycloak_openid_client" "this" {
	realm_id  = keycloak_realm.realm.id
	client_id = "argocd"

	name    = "argocd"
	enabled = true
    access_type = "CONFIDENTIAL"
    standard_flow_enabled = true

    root_url = "http://argocd.localtest.me"
	valid_redirect_uris = [
		"/auth/callback"
	]
    valid_post_logout_redirect_uris = [
		"/auth/callback"
	]
}

#########################
## Client Scope Config ##
#########################
# Create a dedicated client scope for groups
resource "keycloak_openid_client_scope" "this" {
  realm_id = keycloak_realm.realm.id
  name     = "groups"
}

# Map Keycloak user groups into the "groups" token claim
resource "keycloak_openid_group_membership_protocol_mapper" "this" {
  realm_id        = keycloak_realm.realm.id
  client_scope_id = keycloak_openid_client_scope.this.id
  name            = "groups"
  claim_name      = "groups"
  full_path       = false
}

# Add Groups to the default transmitted value from Keycloak to ArgoCD
resource "keycloak_openid_client_default_scopes" "this" {
  realm_id  = keycloak_realm.realm.id
  client_id = keycloak_openid_client.this.id

  default_scopes = [
    "profile",
    "email",
    "roles",
    "web-origins",
    "acr",
    "basic",
    keycloak_openid_client_scope.this.name
  ]
}