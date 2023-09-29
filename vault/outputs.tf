output "phone_number" {
    sensitive = true
    value = data.vault_generic_secret.phone_number.data["phone_number"]
}

output "database_secret" {
    sensitive = true
    value = data.vault_generic_secret.database_secret.data["database_secret"]
}