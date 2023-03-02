terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.14" # current as of March 1st 2023
    }
  }
}

data "coder_workspace" "me" {}

resource "coder_agent" "dev" {
  arch = "arm64"  # M1
  os   = "darwin" # OSX
  dir  = "$HOME"  # Could set to somewhere
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

# template from coder_agent.dev.init_script modified to grab coder from local 'coder server'
# TODO: updated to possibly not download at all if we can locate the running binary
# TODO: updated to discover the listening port of the running binary to connect back ti
# TODO: if downloading, discover local os (darwin/linux-amd64/arm64)
resource "local_file" "localhost_coder_agent_init" {
  filename        = "/tmp/local_coder_agent_init.sh"
  file_permission = "0755"
  content         = <<EOT
#!/usr/bin/env sh
set -eux
# Sleep for a good long while before exiting.
# This is to allow folks to exec into a failed workspace and poke around to
# troubleshoot.
waitonexit() {
	echo "=== Agent script exited with non-zero code. Sleeping 24h to preserve logs..."
	sleep 86400
}
trap waitonexit EXIT
BINARY_DIR=$(mktemp -d -t coder.XXXXXX)
BINARY_NAME=coder
# We want to download locally... it's already downloaded somewhere and running!
# The default port is 3000, and for now hardcoding to target OSX
# TODO: dynimacially figure out port
BINARY_URL=http://localhost:3000/bin/coder-darwin-arm64
cd "$BINARY_DIR"
# Attempt to download the coder agent.
# This could fail for a number of reasons, many of which are likely transient.
# So just keep trying!
while :; do
	curl -fsSL --compressed "$BINARY_URL" -o "$BINARY_NAME" && break
	status=$?
	echo "error: failed to download coder agent using curl"
	echo "curl exit code: $status"
	echo "Trying again in 30 seconds..."
	sleep 30
done

if ! chmod +x $BINARY_NAME; then
	echo "Failed to make $BINARY_NAME executable"
	exit 1
fi

export CODER_CONFIG_DIR=$BINARY_DIR
export CODER_AGENT_LOG_DIR=$BINARY_DIR
export CODER_AGENT_PPROF_ADDRESS=127.0.0.1:6161
# AUTH default to 'token' TOKEN comes from coder_agent
export CODER_AGENT_AUTH=token
export CODER_AGENT_TOKEN="${nonsensitive(coder_agent.dev.token)}"
# The coder agent service is actually already running localyl
# We just need to connect to it!
export CODER_URL="http://localhost:3000/"
# Not sure CODER_AGENT_URL is consumed
export CODER_AGENT_URL="http://localhost:3000/"
exec ./$BINARY_NAME agent
EOT
}

# resource "null_resource" "local_coder_agent" {
#   provisioner "local-exec" {
#     interpreter = ["sh", "-c"]
#     command     = coder_agent.dev.init_script
#     environment = {
#       CODER_AGENT_TOKEN = nonsensitive(coder_agent.dev.token)
#       # https://github.com/hashicorp/terraform/blob/56d21381df8d1a3728f9928be7cee366be1ae4c6/website/docs/language/functions/nonsensitive.html.md
#     }
#   }
# }
# This resource is how we extracted the built in template from coder_agent.dev.init_script
# We modified it above to use localhost instead
# resource "local_file" "coder_agent_init" {
#   content         = coder_agent.dev.init_script
#   filename        = "/tmp/coder_agent_init.sh"
#   file_permission = "0755"
# }
# resource "local_file" "coder_agent_token" {
#   content         = nonsensitive(coder_agent.dev.token)
#   filename        = "/tmp/coder_agent_token.env"
#   file_permission = "0755"
# }
