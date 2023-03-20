#!/usr/bin/env bash
set -x
set -e

case $(uname -o) in
  GNU/Linux)
    sudo apt-get update
    sudo apt-get install -y ttyd tmux wireguard-tools curl
    export OS=linux
  ;;
  Darwin)
    brew install ttyd tmux wireguard-tools curl
    export OS=darwin
  ;;
esac
# What Architecture
case $(uname -m) in
  arm64)
    export ARCH=arm64
  ;;
  amd64)
    export ARCH=amd64
  ;;
  x86_64)
    export ARCH=amd64
  ;;
esac

# We need tunnel client for now
# # Thank you to our friends at coder.com releasing an linux-amd64 build
# ## TODO: Get coder folks to publish tunnel client binaries for other archs
# case "${OS}-${ARCH}" in
#     linux-amd64)
#       curl -L -o /usr/local/bin/tunneld  \
#         https://github.com/coder/wgtunnel/releases/download/v0.1.6/tunneld
#       chmod +x /usr/local/bin/tunneld
#       exit 0
# esac

# Othewise we need to build tunnel
# WARNING WE WILL OVER WRITE THE VERSION OF GO in /usr/local/go
GO_VERSION=1.20.2

export GO_TMP_DIR=$(mktemp -d)
# Ensure tunnel binary exists
curl -sSL https://dl.google.com/go/go${GO_VERSION}.${OS}-${ARCH}.tar.gz \
    | gunzip -d \
    | tar --directory $GO_TMP_DIR --extract

# # If SHELL=bash
# # GREP FIRST
# echo 'export PATH=~/go/bin:/usr/local/go/bin:$PATH' >> ~/.bashrc
# # If SHELL=zsh
# echo 'export PATH=~/go/bin:/usr/local/go/bin:$PATH' >> ~/.zshrc

# GO
export PATH=$GO_TMP_DIR/go/bin:$PATH
go install github.com/coder/wgtunnel/cmd/tunnel@v0.1.5
# Move generated tunnel go binary to /usr/local/bin
sudo mv $HOME/go/bin/tunnel /usr/local/bin/tunnel
rm -rf $GO_TMP_DIR

# WHAT WE NEED
tmux -V
ttyd --version
wg version
/usr/local/bin/tunnel --version
