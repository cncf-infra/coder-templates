terraform {
  required_providers {
    equinix = {
      source  = "equinix/equinix"
      version = "1.13.0"
    }
    coder = {
      source  = "coder/coder"
      version = "0.6.14" # current as of March 3rd 2023
    }
  }
}

provider "equinix" {
  # Configuration options
}

data "coder_workspace" "me" {}

resource "coder_agent" "ii" {
  arch = "amd64" # Intel
  os   = "linux" # Linux
  dir  = "$HOME" # Could set to somewhere
  # login_before_ready = true
  startup_script = <<EOT
    #!/bin/bash
    # We could start an editor here... but we won't
    echo Keep it Simple
    sleep 999999999
  EOT
}

# TODO: use https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs
resource "equinix_metal_device" "pair" {
  project_id       = var.project
  hostname         = var.hostname
  metro            = var.metro
  plan             = var.device_plan
  operating_system = var.os
  user_data = templatefile("cloud-config.yaml.tftpl", {
    username          = "coder" # data.coder_workspace.me.owner
    init_script       = base64encode(coder_agent.ii.init_script)
    coder_agent_token = coder_agent.ii.token
  })

  # custom_data      = local.custom_data
  behavior {
    allow_changes = [
      # "custom_data",
      "user_data"
    ]
  }

  tags = [
    "name:coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}",
    "Coder_Provisioned:true"
  ]
}
