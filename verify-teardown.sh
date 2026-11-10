#!/usr/bin/env bash
# Proves the lab left nothing in AWS. Run with: ./verify-teardown.sh
set -u
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "No working AWS credentials." >&2; exit 1; }
echo "Checking account $ACCOUNT, region $(aws configure get region)"
pass=0; failn=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
empty() { local r; r=$(eval "$1" 2>/dev/null); [ -z "$r" ] || [ "$r" = None ]; }
T="Name=tag:lab,Values=aws-vpc-peering"
check "no running or stopped server tagged lab=aws-vpc-peering" empty "aws ec2 describe-instances --filters $T Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text"
check "no VPC tagged lab=aws-vpc-peering" empty "aws ec2 describe-vpcs --filters $T --query 'Vpcs[].VpcId' --output text"
check "no internet gateway or subnet tagged lab=aws-vpc-peering" empty "aws ec2 describe-internet-gateways --filters $T --query 'InternetGateways[].InternetGatewayId' --output text; aws ec2 describe-subnets --filters $T --query 'Subnets[].SubnetId' --output text"
check "no active or pending peering connection with 10.1.0.0/16 or 10.2.0.0/16" empty "aws ec2 describe-vpc-peering-connections --filters Name=status-code,Values=active,pending-acceptance,provisioning --query \"VpcPeeringConnections[?RequesterVpcInfo.CidrBlock=='10.1.0.0/16'||RequesterVpcInfo.CidrBlock=='10.2.0.0/16'].VpcPeeringConnectionId\" --output text"
check "no role or instance profile clippy-peering-role" bash -c "! aws iam get-role --role-name clippy-peering-role && ! aws iam get-instance-profile --instance-profile-name clippy-peering-role"
echo
if [ "$failn" -eq 0 ]; then echo "TEARDOWN VERIFIED ($pass/$pass) in account $ACCOUNT"; else echo "NOT CLEAN: $failn leftover(s). Remove them and run this again."; fi
exit "$failn"
