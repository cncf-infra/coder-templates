variable "device_plan" {
  type        = string
  description = "Type of Hardware from : https://deploy.equinix.com/developers/api/metal/#tag/Plans"
  default     = "m3.large.x86"
}

variable "metro" {
  type        = string
  description = "Location of Hardware from : https://deploy.equinix.com/developers/docs/metal/locations/metros/"
  default     = "sy" # Sydney is NZ's closest Metal Metro
}

variable "project" {
  type        = string
  description = "Project from https://deploy.equinix.com/developers/docs/metal/accounts/projects/"
  default     = "f4a7273d-b1fc-4c50-93e8-7fed753c86ff" # pair.sharing.io
}

# The hostname to use within the operating system.
# The same hostname may be used on multiple devices within a project.
variable "hostname" {
  type        = string
  description = "Hostname for https://deploy.equinix.com/developers/api/metal/#tag/Devices/operation/createDevice"
  default     = "packet.sharing.io"
}

variable "os" {
  type        = string
  description = "Operating System from https://deploy.equinix.com/developers/docs/metal/operating-systems/supported/"
  default     = "ubuntu_22_04"
}
