terraform {
  required_providers {
    # https://registry.terraform.io/providers/coder/coder/latest
    coder = {
      source  = "coder/coder"
      version = "0.6.17" # current as of March 13th 2023
    }
    # https://registry.terraform.io/providers/julienlevasseur/uname/latest
    # provides us Platform and OS via go
    uname = {
      source  = "julienlevasseur/uname"
      version = "0.1.0" # current as of March 13th 2023
    }
  }
}

# https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace
data "coder_workspace" "me" {}
# https://registry.terraform.io/providers/julienlevasseur/uname/latest/docs/data-sources/uname
data "uname" "system" {}

# https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file#example-usage
resource "local_file" "coder_agent" {

  # https://registry.terraform.io/providers/coder/coder/latest/docs/data-sources/workspace#example-usage
  # https://developer.hashicorp.com/terraform/language/meta-arguments/count
  count = data.coder_workspace.me.transition == "start" ? 1 : 0

  # https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file#filename
  # https://developer.hashicorp.com/terraform/language/expressions/strings#interpolation
  # TLDR for String Interpolation
  # NAME=workspace1 OWNER=ii echo "/tmp/coder-${OWNER}-${NAME}/coder_agent_init.sh"
  # /tmp/coder-ii-workspace1/coder_agent_init.sh
  filename = "/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}/coder_agent_init.sh"

  # https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file#file_permission
  # https://en.wikipedia.org/wiki/File-system_permissions#Numeric_notation
  # Read (4), Write (2), Execute (1)
  # Owner is the second number = 4 + 2 + 1 = 7
  # Group is the third number = 4 + 1 = 5
  # Other is the forth number = 4 + 1 = 5
  file_permission = "0755"

  # https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file#content
  # https://developer.hashicorp.com/terraform/language/expressions/strings#indented-heredocs
  content = <<-EOT
    # https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent#token
    # https://coder.com/docs/v1/latest/workspaces/variables#other-variables
    # https://github.com/coder/coder/issues/6421 # docs missing
    export CODER_AGENT_TOKEN="${coder_agent.ii.token}"
    # coder agent -h | grep -B1 'Consumes .CODER_CONFIG_DIR' | head -1
    # --global-config coder   Path to the global coder config directory.
    export CODER_CONFIG_DIR="/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    # coder agent -h | grep -B1 'Consumes .CODER_AGENT_LOG_DIR' | head -1
    # --log-dir string         Specify the location for the agent log files.
    export CODER_AGENT_LOG_DIR="$CODER_CONFIG_DIR/logs"
    # coder agent -h | grep -B1 'Consumes .CODER_URL' | head -1
    # --url string            URL to a deployment.
    export CODER_URL="http://localhost:3000/"
    # FIXME: Can't find docs... is this used?
    export CODER_AGENT_URL="http://localhost:3000/"
    # coder agent -h | grep -B1 'Consumes .CODER_AGENT_PPROF_ADDRESS' | head -1
    # --pprof-address string   The address to serve pprof.
    export CODER_AGENT_PPROF_ADDRESS=127.0.0.1:6060 # Would love to use first available port
    # $$ when fed to a posix shell emits the current proccess id (PID)
    # We save it to coder_agent.pid so we can kill it later!
    echo $$ > $CODER_CONFIG_DIR/coder_agent.pid # Save Process ID so we can signal later
    cd /tmp # Choose any folder to serve from!
    # Going to assume the 'coder' binary in our path is good enough!
    # We won't download since we are local to the coder server
    # exec replaces the current process 'sh' with the coder process
    # https://github.com/coder/coder/blob/main/agent/agent.go#L92
    exec coder agent
  EOT

  # https://developer.hashicorp.com/terraform/language/resources/provisioners/syntax#how-to-use-provisioners
  # https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec
  # This simple calls coder_agent_init.sh and logs it to a per workspace/agent init.log
  provisioner "local-exec" {
    # This will get called when creating the workspace, after the local-file is on disk
    # https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec#when
    when = create
    # We do need a posix shell for now, need to rethink for windows
    # https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec#interpreter
    interpreter = ["sh", "-c"]
    # We want to start our coder agent in the folder this script is written to
    # https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec#working_dira
    # https://developer.hashicorp.com/terraform/language/functions/dirname
    # dirname('/tmp/file.txt') returns '/tmp/'
    working_dir = dirname(self.filename)
    # We want to log both the output and errors from our script
    # https://linuxize.com/post/bash-redirect-stderr-stdout/
    # We also want to run in the background, so this script can exit
    # https://askubuntu.com/questions/88091/how-to-run-a-shell-script-in-background
    command = "${self.filename} 2>&1 > coder-init.log &"
  }

  # Similar to our create provisioner, but called on destroy (technically when count = 0)
  # This simple calls coder_agent_init.sh and logs it to a per workspace/agent init.log
  # https://developer.hashicorp.com/terraform/language/resources/provisioners/syntax#destroy-time-provisioners
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["sh", "-c"]
    working_dir = dirname(self.filename)
    command     = "kill `cat coder_agent.pid`" # Send TERM signal to stop process
  }
}


# Collision is technically possibly, but unlikely.
# Also, other software may be listening on chosen port... YOLO
# UNEXPECTEDLY :: if you use two random_integer resources...
# The seed may be the same if close enough...
# default seed = seedInt = time.Now().UnixNano()
# To avoid use a different seed for each one
# I hit it a couple times...
# https://github.com/hashicorp/terraform-provider-random/issues/19
# Fixed by using different min/max ranges
resource "random_integer" "ttyd_port" {
  min = 61000
  max = 63000
  # seed = tonumber(formatdate("YYYYMMDDhh", timestamp()))
}
resource "random_integer" "codeserver_port" {
  min = 51000
  max = 53000
  # seed = tonumber(formatdate("YYYYMMDDhh", timeadd(timestamp(), "10m")))
}

# FIXME: Can we update the script to detect OS and ARCH?
# curl / mozilla etc all send arch and os in http header strings


# FIXME: uname needs wrappers to get correct stuff
#  Error: expected arch to be one of [amd64 armv7 arm64], got x86_64
#  Error: expected os to be one of [linux darwin windows], got Linux^
# https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent
resource "coder_agent" "ii" {

  # https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent#arch
  # https://registry.terraform.io/providers/julienlevasseur/uname/latest/docs/data-sources/uname#machine
  #  Error: expected arch to be one of [amd64 armv7 arm64], got x86_64
  # arch               = data.uname.system.machine
  arch = "amd64"

  # https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent#os
  # https://registry.terraform.io/providers/julienlevasseur/uname/latest/docs/data-sources/uname#kernel_name
  #  Error: expected os to be one of [linux darwin windows], got Linux^
  #  os                 = data.uname.system.kernel_name
  os = "linux"

  # https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent#dir
  dir = "$HOME" # Could set to somewhere

  # https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent#login_before_ready
  login_before_ready = true

  # We could start an editor here... but we won't yet... this is the simple version
  # coder agent will run this .... once it starts, but not sure what needs to happen before it runs
  # https://registry.terraform.io/providers/coder/coder/latest/docs/resources/agent#startup_script
  startup_script = <<EOT
    #!/bin/bash
    # FIXME: shbang not used, current shell used... zsh on OSX, which breaks type -P detection
    echo Checking to see if tmux, ttyd, and code-server exists, if they do start them
    AGENT_DIR="/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    # Log to a sub folder as the agent script
    LOG_DIR="$AGENT_DIR/logs"
    # Put our tmux socket in our agent / workspace folder
    TMUX_SOCKET="$AGENT_DIR/tmux.socket"
    # Log URLS for apps for debugging
    echo "http://localhost:${random_integer.codeserver_port.id}" > $AGENT_DIR/codserver.url
    echo "http://localhost:${random_integer.ttyd_port.id}" > $AGENT_DIR/ttyd.url
    # detect, start, and log tmux
    # bash -c '[[ $(type -P "tmux") ]] && \
      tmux -S $TMUX_SOCKET new -d
    # detect, start, and log ttyd
    # bash -c '[[ $(type -P "ttyd") ]] && \
      ttyd -p ${random_integer.ttyd_port.id} tmux -S $TMUX_SOCKET at 2>&1 | \
        tee $LOG_DIR/ttyd.log &
    # detect, start, and log code-server
    # bash -c '[[ $(type -P "code-server") ]] && \
      code-server --auth none --port ${random_integer.codeserver_port.id} 2>&1 | \
        tee $LOG_DIR/code-server.log &
  EOT
}

# tmux
resource "coder_app" "tmux" {
  # subdomain    = true
  share        = "public"
  display_name = "tmux"
  slug         = "tmux"
  icon         = "/icon/folder.svg" # let's maybe get an emacs.svg somehow
  command      = "tmux -S /tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}/tmux.socket at"
  agent_id     = coder_agent.ii.id
}


# ttyd
resource "coder_app" "ttyd" {
  subdomain    = true
  share        = "public"
  slug         = "ttyd"
  display_name = "ttyd for tmux"
  icon         = "/icon/folder.svg"                                # let's maybe get an emacs.svg somehow
  url          = "http://localhost:${random_integer.ttyd_port.id}" # 7681 is the default ttyd port
  agent_id     = coder_agent.ii.id

  # healthcheck {
  #   # don't want to disconnect current session, but hopefully this will 200OK
  #   url       = "http://localhost:7681/"
  #   interval  = 3
  #   threshold = 10
  # }
}

# code-server
resource "coder_app" "code-server" {
  subdomain    = true
  share        = "public"
  display_name = "code-server"
  slug         = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:${random_integer.codeserver_port.id}/?folder=/tmp/coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}/"
  agent_id     = coder_agent.ii.id
  #"?folder=/"
  #"?folder=/home/coder"

  # healthcheck {
  #   url       = "http://localhost:13337/healthz"
  #   interval  = 3
  #   threshold = 10
  # }
}

# FIXME: Doesn't work for me yet
# https://registry.terraform.io/providers/coder/coder/latest/docs/resources/metadata

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
