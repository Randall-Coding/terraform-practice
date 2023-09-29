provider "vault" {
    address = "http://127.0.0.1:8200"
    token = var.vault_token
}

data "vault_generic_secret" "phone_number" {
    path = "secret/app/phone_number"
}

data "vault_generic_secret" "database_secret" {
    path = "secret/app/database_secret"
}