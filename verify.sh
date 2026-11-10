#!/usr/bin/env bash
# Reads the peering, the routes, the firewall and what the servers say. Run with: ./verify.sh
cd "$(dirname "$0")" || exit 1
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
exec python3 .lab/awscheck.py
