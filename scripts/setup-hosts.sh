#!/bin/bash

HOSTS_FILE="/etc/hosts"
DOMAINS=("user1.example.com" "user2.example.com" "user3.example.com")
IP="127.0.0.1"

echo "Setting up /etc/hosts entries for local domain resolution..."
echo ""

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  echo "Try: sudo bash $0"
  exit 1
fi

for domain in "${DOMAINS[@]}"; do
  if grep -q "^$IP[[:space:]].*$domain" "$HOSTS_FILE"; then
    echo "✓ $domain already in $HOSTS_FILE"
  else
    echo "$IP  $domain" >> "$HOSTS_FILE"
    echo "✓ Added $domain → $IP"
  fi
done

echo ""
echo "Verifying entries in $HOSTS_FILE:"
grep example.com "$HOSTS_FILE" || true

echo ""
echo "Testing DNS resolution:"
for domain in "${DOMAINS[@]}"; do
  result=$(getent hosts "$domain" | awk '{print $1}')
  if [ -n "$result" ]; then
    echo "✓ $domain resolves to $result"
  else
    echo "✗ $domain does not resolve"
  fi
done

echo ""
echo "✓ /etc/hosts setup complete"
