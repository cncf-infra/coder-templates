terraform {
  required_providers {
    equinix = {
      source  = "equinix/equinix"
      version = "1.13.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
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

provider "template" {
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
  # This needs to run until it doesn't need to run :)
  # null_resource.local_coder_agent: (local-exec):
  # Error: The agent cannot authenticate until the workspace provision job has been completed.
  # If the job is no longer running, this agent is invalid.
  # shutdown_script = <<EOT
  #   #!/bin/bash
  #   # We could stop any resources we started
  #   echo Keep it Simple
  # EOT
}

# data "template_cloudinit_config" "coder" {
#   # gzip          = true
#   # base64_encode = true

#   # # Main cloud-config configuration file.
#   # part {
#   #   filename     = "init.cfg"
#   #   content_type = "text/cloud-config"
#   #   content      = data.template_file.script.rendered
#   # }
#   part {
#     content_type = "text/x-shellscript"
#     content      = coder_agent.ii.init_script
#   }

#   # part {
#   #   content_type = "text/x-shellscript"
#   #   content      = "ffbaz"
#   # }
# }


# equinix_metal_device.emacs:
resource "equinix_metal_device" "pair" {
  project_id          = "f4a7273d-b1fc-4c50-93e8-7fed753c86ff"
  hostname            = "pair.sharing.io"
  description         = "Infra for Pair"
  metro               = "sy"
  plan                = "m3.large.x86"
  operating_system    = "ubuntu_22_04"
  user_data           = templatefile("cloud-config.yaml.tftpl", {
    username          = "coder"  # data.coder_workspace.me.owner
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
    # # Required if you are using our example policy, see template README
    # Coder_Provisioned = "true"
  ]
  # tags = [
  # ]
  # ssh_key_ids = [
  # ]
  # billing_cycle    = "hourly"
  # network_type     = "layer3"
}
