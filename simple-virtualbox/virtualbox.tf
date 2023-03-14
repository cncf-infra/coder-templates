terraform {
  required_providers {
    # https://registry.terraform.io/providers/coder/coder/latest
    coder = {
      source  = "coder/coder"
      version = "0.6.17" # current as of March 13th 2023
    }
    # https://registry.terraform.io/providers/bmatcuk/vagrant/latest/docs/resources/vm
    vagrant = {
      source  = "bmatcuk/vagrant"
      version = "4.1.0" # current as of March 14th 2023
    }
  }
}

# https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace
data "coder_workspace" "me" {}

resource "local_file" "vagrant_file" {
  count    = 1
  filename = "/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}/Vagrantfile"
  content = templatefile("Vagrantfile.template", {
    vbox_name = data.coder_workspace.me.name,
    gui       = "true",
    memory    = "16384",
    cpus      = "8"
  })
  file_permission = "0644"
}

# https://registry.terraform.io/providers/bmatcuk/vagrant/latest
# https://registry.terraform.io/providers/bmatcuk/vagrant/latest/docs/resources/vm#optional
resource "vagrant_vm" "my_vagrant_vm" {
  # https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace#example-usage
  # https://developer.hashicorp.com/terraform/language/meta-arguments/count
  count = data.coder_workspace.me.transition == "start" ? 1 : 0

  # https://developer.hashicorp.com/vagrant/docs/providers/virtualbox/configuration#virtual-machine-name
  # https://developer.hashicorp.com/vagrant/docs/vagrantfile/machine_settings#config-vm-hostname
  # name (String) If the name changes, it will force terraform to destroy and recreate the resource. Defaults to "vagrantbox".
  name = data.coder_workspace.me.name

  # I suspect it calls vagrant up from this folder
  vagrantfile_dir = dirname(local_file.vagrant_file.filename)

  # get_ports (Boolean) Whether or not to retrieve forwarded port information.
  # See ports. Defaults to false.
  get_ports = true

  # https://registry.terraform.io/providers/bmatcuk/vagrant/latest/docs/resources/vm#forcing-an-update
  # env (Map of String) Environment variables to pass to the Vagrantfile.
  # env = {
  #   # force terraform to re-run vagrant if the Vagrantfile changes
  #   # VAGRANTFILE_HASH = md5(file("${path.module}/Vagrantfile")),
  #   # ERROR:   Invalid value for "path" parameter: no file exists at "./Vagrantfile"; this function works only with files that are distributed as part of the configuration source code, so if this file will be created by a resource in this configuration you must instead obtain this result from an attribute of that resource.
  # }
  depends_on = [
    local_file.vagrant_file
  ]
  # see schema for additional options
}
