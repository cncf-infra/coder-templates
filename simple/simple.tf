terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.14" # current as of March 3rd 2023
    }
    # provides us Platform and OS via go ( but doesn't work on M1 / Arm )
    uname = {
      source  = "julienlevasseur/uname"
      version = "0.0.4"
    }
  }
}

data "coder_workspace" "me" {}
data "uname" "system" {}

resource "local_file" "coder_agent" {
  count           = data.coder_workspace.me.start_count # Script will not exist when shutdown
  filename        = "/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}/coder_agent_init.sh"
  file_permission = "0755"
  content         = <<-EOT
    export CODER_AGENT_TOKEN="${coder_agent.ii.token}"
    export CODER_CONFIG_DIR="/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    export CODER_AGENT_LOG_DIR="$CODER_CONFIG_DIR/logs"
    export CODER_URL="http://localhost:3000/"
    export CODER_AGENT_URL="http://localhost:3000/"
    export CODER_AGENT_PPROF_ADDRESS=127.0.0.1:6060 # Would love to use first available port
    echo $$ > $CODER_CONFIG_DIR/coder_agent.pid # Save Process ID so we can signal later
    cd /tmp # Choose any folder to serve from!
    # Going to assume the 'coder' binary in our path is good enough!
    exec coder agent
  EOT
  # This simple calls coder_agent_init.sh and logs it to a per workspace/agent init.log
  provisioner "local-exec" {
    interpreter = ["sh", "-c"]
    working_dir = dirname(self.filename)
    command     = "${self.filename} 2&> coder-init.log & disown"
  }
  # # This simple calls coder_agent_init.sh and logs it to a per workspace/agent init.log
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["sh", "-c"]
    working_dir = dirname(self.filename)
    command     = "kill `cat coder_agent.pid`" # Send TERM signal to stop process
  }
}

resource "coder_agent" "ii" {
  # When coder agent is run, it use a token generated here
  # coder agent will also use this startup script
  # TODO: Figure out what these are used for...
  # I'm suspecting these may only be to identify a download binary
  # FIXME: Can we update the script to detect OS and ARCH?
  # curl / mozilla etc all send arch and os in http header strings
  arch               = "arm64"  # M1
  os                 = "darwin" # OSX
  dir                = "$HOME"  # Could set to somewhere
  login_before_ready = true
  startup_script     = <<EOT
    #!/bin/bash
    # We could start an editor here... but we won't yet
    echo Keep it Simple
    sleep 999999999
  EOT
}

# resource "coder_metadata" "uname" {
#   # count       = 1 # data.coder_workspace.me.start_count
#   # count       = data.coder_workspace.me.start_count
#   count       = 1
#   resource_id = coder_agent.dev.id
#   # FIXME : Docs for coder_metadata use bad math (number + strings = errors)
#   # icon = data.coder_workspace.me.access_url + "/icon/k8s.png"
#   # Maybe + outside of templates is for numbers only
#   # instead use "${data.coder_workspace.me.access_url}/icon/k8s.png"
#   icon = "${data.coder_workspace.me.access_url}/icon/k8s.png"
#   # icon        = data.coder_workspace.me.access_url + "/icon/k8s.png"
#   # ^^^ this will generate an error about the right operand (to the + fuction) not being an number
#   #   Error: Invalid operand
#   # Unsuitable value for right operand: a number is required.
#   item {
#     key   = "iconurl"
#     value = "${data.coder_workspace.me.access_url}/icon/k8s.png"
#   }
#   item {
#     key   = "FOO"
#     value = "BAR"
#   }
#   item {
#     key   = "arch"
#     value = "arch FOO"
#     # value = data.uname.system.machine # goInfo.GetInfo().Platform
#   }
#   item {
#     key   = "os"
#     value = "BAR os"
#     # value = data.uname.system.operating_system # goInfo.GetInfo().OS)
#   }
# }
