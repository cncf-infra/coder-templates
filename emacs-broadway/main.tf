terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.12.1"
    }
  }
}

variable "use_kubeconfig" {
  type        = bool
  default     = false
  sensitive   = true
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
}

variable "namespace" {
  type        = string
  sensitive   = true
  description = "The namespace to create workspaces in (must exist prior to creating workspaces)"
  default     = "coder"
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = <<EOT
    #!/bin/bash

    # home folder currently contains .emacs.d and .doom.d
    # at some point later we'll move them to another folder
    sudo apt-get install -y tmux ttyd libwebsockets-evlib-uv
    # start broadwayd and emacs
    broadwayd :5 2>&1 | tee broadwayd.log &
    GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 emacs 2>&1 | tee emacs.log &
    # start ttyd / tmux
    tmux new -d
    ttyd tmux at 2>&1 | tee ttyd.log &
    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh  | tee code-server-install.log
    code-server --auth none --port 13337 | tee code-server-install.log &

  EOT
}

# emacs-broadway
resource "coder_app" "emacs-broadway" {
  subdomain    = true
  share        = "public"
  agent_id     = coder_agent.main.id
  slug         = "emacs-broadway"
  display_name = "Emacs on Broadway"
  icon         = "/icon/folder.svg"      # let's maybe get an emacs.svg somehow
  url          = "http://localhost:8085" # port 8080 + BROADWAY_DISPLAY

  # healthcheck {
  #   # don't want to disconnect current session, but hopefully this will 200OK
  #   url       = "http://localhost:8085/"
  #   interval  = 3
  #   threshold = 10
  # }
}

# ttyd
resource "coder_app" "ttyd" {
  subdomain    = true
  share        = "public"
  slug         = "ttyd"
  display_name = "ttyd for tmux"
  icon         = "/icon/folder.svg" # let's maybe get an emacs.svg somehow
  agent_id     = coder_agent.main.id
  url          = "http://localhost:7681" # 7681 is the default ttyd port

  # healthcheck {
  #   # don't want to disconnect current session, but hopefully this will 200OK
  #   url       = "http://localhost:7681/"
  #   interval  = 3
  #   threshold = 10
  # }
}

# tmux
resource "coder_app" "tmux" {
  agent_id     = coder_agent.main.id
  display_name = "tmux"
  slug         = "tmux"
  icon         = "/icon/folder.svg" # let's maybe get an emacs.svg somehow
  command      = "tmux at"
  share        = "public"
  subdomain    = true
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  display_name = "code-server"
  slug         = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = true

  # healthcheck {
  #   url       = "http://localhost:13337/healthz"
  #   interval  = 3
  #   threshold = 10
  # }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      name = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    }
  }
  spec {
    security_context {
      run_as_user = "1000"
      fs_group    = "1000"
    }
    container {
      name    = "dev"
      image   = "ghcr.io/ii/emacs-coder:latest"
      command = ["sh", "-c", coder_agent.main.init_script]
      security_context {
        run_as_user = "1000"
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
    }
  }
}
