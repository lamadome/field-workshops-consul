#!/bin/bash

#metadata
local_ipv4="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
public_ipv4="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

#update packages
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt update -y

#install consul
sudo apt install consul-enterprise vault-enterprise awscli jq unzip -y

#get the secrets tokens from Vault
export VAULT_ADDR=http://$(aws ec2 describe-instances --filters "Name=tag:Name,Values=vault" \
 --region us-east-1 --query 'Reservations[*].Instances[*].PrivateIpAddress' \
 --output text):8200
vault login -method=aws role=consul
AGENT_TOKEN=$(vault kv get -field=master_token kv/consul)
GOSSIP_KEY=$(vault kv get -field=gossip_key kv/consul)
CA_CERT=$(vault read -field certificate pki/cert/ca)

#config
cat <<EOF> /etc/consul.d/client.json
{
  "datacenter": "aws-us-east-1",
  "primary_datacenter": "aws-us-east-1",
  "advertise_addr": "$${local_ipv4}",
  "data_dir": "/opt/consul/data",
  "client_addr": "0.0.0.0",
  "log_level": "INFO",
  "retry_join": ["provider=aws tag_key=Env tag_value=consul-${env}"],
  "ui": true,
  "connect": {
    "enabled": true
  },
  "ports": {
    "grpc": 8502
  }
}
EOF

cat <<EOF> /etc/consul.d/secrets.hcl
acl {
  enabled        = true
  default_policy = "deny"
  enable_token_persistence = true
  tokens {
    agent  = "$${AGENT_TOKEN}"
  }
}

encrypt = "$${GOSSIP_KEY}"

EOF

mkdir -p /opt/consul/tls/
echo "$${CA_CERT}" > /opt/consul/tls/ca-cert.pem

cat <<EOF> /etc/consul.d/tls.json
{
  "verify_incoming": false,
  "verify_outgoing": true,
  "verify_server_hostname": true,
  "ca_file": "/opt/consul/tls/ca-cert.pem",
  "auto_encrypt": {
    "tls": true
  }
}
EOF

sudo systemctl enable consul.service
sudo systemctl start consul.service

#esm
curl -s -O https://releases.hashicorp.com/consul-esm/0.4.0/consul-esm_0.4.0_linux_amd64.tgz
tar -xvzf consul-esm*
mv consul-esm /usr/local/bin/consul-esm
rm -f *.tgz

mkdir -p /etc/consul-esm.d/
cat <<EOF> /etc/consul-esm.d/config.hcl
token = "$${AGENT_TOKEN}"
EOF

cat <<EOF> /usr/lib/systemd/system/consul-esm.service
[Unit]
Description=Consul ESM
Documentation=https://github.com/hashicorp/consul-esm

Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul-esm -config-dir /etc/consul-esm.d/
KillMode=process
Restart=on-failure
RestartSec=2

PermissionsStartOnly=true
ExecStartPre=/sbin/setcap 'cap_net_raw=+ep' /usr/local/bin/consul-esm

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable consul-esm.service
sudo systemctl start consul-esm.service

exit 0
