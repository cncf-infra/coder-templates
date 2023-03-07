terraform {
  required_providers {
    uname = {
      source  = "julienlevasseur/uname"
      version = "0.0.4"
    }
  }
}

data "uname" "system" {}

output "os" {
  description = "goInfo.GetInfo().OS as supplied by julienlevasseur/uname"
  value       = data.uname.system.operating_system
}

output "machine" {
  description = "goInfo.GetInfo().Platform as supplied by julienlevasseur/uname"
  value       = data.uname.system.machine + "1"
}

# The Above outputs are NULL on OSX

output "os-notnull" {
  description = "goInfo.GetInfo().OS as supplied by julienlevasseur/uname"
  value       = "NOTNULL"
}

output "machine-notnull" {
  description = "goInfo.GetInfo().Platform as supplied by julienlevasseur/uname"
  value       = "NOTNULL"
}
