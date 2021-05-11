#!/bin/bash

#wait for box
sleep 30

#hashicorp packages
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

#azure packages
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo apt-key add -
AZ_REPO=$(lsb_release -cs)
sudo apt-add-repository "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main"

#install packages
sudo apt update -y
sudo apt install azure-cli consul-enterprise=1.9.4+ent vault-enterprise=1.7.1+ent nomad-enterprise=1.0.4+ent docker.io jq -y

#envoy
curl -L https://getenvoy.io/cli | bash -s -- -b /usr/local/bin
sudo getenvoy fetch standard:1.16.3
sudo cp /root/.getenvoy/builds/standard/*/linux_glibc/bin/envoy /usr/local/bin/envoy

exit 0
