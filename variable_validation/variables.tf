variable "cloud" {
  type = string

  validation {
    condition     = contains(["aws", "azure", "gcp", "vmware"], lower(var.cloud))
    error_message = "Not a valid cloud provider.  Use: ${join(", ", ["aws", "azure", "gcp", "vmware"])}"
  }

  validation {
    condition     = lower(var.cloud) == var.cloud
    error_message = "Cloud names must be lowercase."
  }
}


variable "no_caps" {
  type = string
  validation {
    condition     = lower(var.no_caps) == var.no_caps
    error_message = "no_caps must be all lower case.  duh!"
  }
}


variable "character_limit_5" {
  type = string
  validation {
    condition     = length(var.character_limit_5) <= 5
    error_message = "This variable can't be more than 5 characters"
  }
}

variable "ip_address" {
  type        = string
  description = "A valid ip address"

  validation {
    condition     = can(regex("^((25[0-5]|(2[0-4]|1\\d|[1-9]|)\\d)\\.?\\b){4}$", var.ip_address))
    error_message = "Not a valid ip address"
  }
}

variable "password" {
  type      = string
  sensitive = true
}

output "password" {
  sensitive = true
  value     = var.password
}