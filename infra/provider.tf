terraform {
  required_providers {
    keycloak = {
      source = "keycloak/keycloak"
      version = ">= 5.10.0"
    }
  }
}

provider "keycloak" {
	client_id     = "terraform"
	client_secret = var.tf_kc_client_secret
	url           = "https://keycloak.localtest.me"
    tls_insecure_skip_verify = true
}