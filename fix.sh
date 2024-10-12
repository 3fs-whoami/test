#!/bin/bash

# Variables for certificate paths
CERT_DIR="/etc/docker/certs"
DOCKER_CONFIG="/etc/docker/daemon.json"
SYSCTL_CONFIG="/etc/sysctl.conf"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root!" 
   exit 1
fi

# Step 1: Enable IPv4 forwarding
echo "Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1

# Check if already in sysctl.conf, if not, add it
if ! grep -q "net.ipv4.ip_forward = 1" $SYSCTL_CONFIG; then
    echo "net.ipv4.ip_forward = 1" >> $SYSCTL_CONFIG
fi

# Step 2: Enable bridge-nf-call-iptables and bridge-nf-call-ip6tables
echo "Enabling bridge-nf-call-iptables and bridge-nf-call-ip6tables..."
sysctl -w net.bridge.bridge-nf-call-iptables=1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1

# Add these settings to sysctl.conf if not already present
if ! grep -q "net.bridge.bridge-nf-call-iptables = 1" $SYSCTL_CONFIG; then
    echo "net.bridge.bridge-nf-call-iptables = 1" >> $SYSCTL_CONFIG
fi
if ! grep -q "net.bridge.bridge-nf-call-ip6tables = 1" $SYSCTL_CONFIG; then
    echo "net.bridge.bridge-nf-call-ip6tables = 1" >> $SYSCTL_CONFIG
fi

# Step 3: Set up TLS for Docker API
echo "Setting up TLS for Docker API..."

# Create the certificate directory
mkdir -p $CERT_DIR

# Generate the CA key and certificate
openssl genrsa -aes256 -out $CERT_DIR/ca-key.pem 4096
openssl req -new -x509 -days 365 -key $CERT_DIR/ca-key.pem -sha256 -out $CERT_DIR/ca.pem -subj "/CN=ca-docker"

# Generate the server key and certificate
openssl genrsa -out $CERT_DIR/server-key.pem 4096
openssl req -new -key $CERT_DIR/server-key.pem -out $CERT_DIR/server.csr -subj "/CN=$(hostname)"
openssl x509 -req -days 365 -in $CERT_DIR/server.csr -CA $CERT_DIR/ca.pem -CAkey $CERT_DIR/ca-key.pem -CAcreateserial -out $CERT_DIR/server-cert.pem

# Step 4: Configure Docker daemon to use TLS
echo "Configuring Docker daemon..."

# Create or update Docker daemon.json
cat > $DOCKER_CONFIG <<EOF
{
  "tls": true,
  "tlsverify": true,
  "tlscacert": "$CERT_DIR/ca.pem",
  "tlscert": "$CERT_DIR/server-cert.pem",
  "tlskey": "$CERT_DIR/server-key.pem",
  "hosts": ["tcp://10.2.2.10:2376", "unix:///var/run/docker.sock"]
}
EOF

# Step 5: Restart Docker to apply changes
echo "Restarting Docker..."
systemctl restart docker

# Display the final status
echo "Docker setup is complete. Check the logs for any warnings."
journalctl -u docker --since "5 minutes ago"
