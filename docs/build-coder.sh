#Requires - Ubuntu 22.04 +
## Install WSL2
#Maybe 
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Install non-defaul Ubuntu 22.04
wsl --install -d Ubuntu_22.04
#if it exists
wsl --set-default -d Ubuntu_22.04

# Download and install Rancher Desktop
# https://rancherdesktop.io/
# https://github.com/rancher-sandbox/rancher-desktop/releases/download/v1.8.1/Rancher.Desktop.Setup.1.8.1.msi
# 1. Select dockerd
#   a. AND NOT Kubernetes
# 2. Preferences - Add integrations to WSL.

# Clone Coder
git clone --branch dean/tunnelsdk https://github.com/coder/coder.git ~/coder


#export CGO_ENABLED=1


#sudo apt-get install nodejs npm

# Install Node
cd ~
# Maybe Versions here https://github.com/nodesource/distributions/tree/master/deb
curl -sL https://deb.nodesource.com/setup_18.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
#sudo apt-get update
sudo apt-get install -y nodejs
sudo apt-get install -y gcc g++ make
sudo npm install --global yarn

sudo apt-get install -y protobuf-compiler
protoc --version  # Ensure compiler version is 3+

curl -sLO https://go.dev/dl/go1.20.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.20.2.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:~/go.bin' >> ~/.bashrc

go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install storj.io/drpc/cmd/protoc-gen-go-drpc@latest

go install github.com/kyleconroy/sqlc/cmd/sqlc@latest


cd ~/coder
make
