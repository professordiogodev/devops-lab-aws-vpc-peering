#!/usr/bin/env bash
# Deletes the peering connection, both networks, the servers and the role. Run with: ./teardown.sh
set -u
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
L=aws-vpc-peering
IDS=$(aws ec2 describe-instances --filters Name=tag:lab,Values=$L Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && aws ec2 wait instance-terminated --instance-ids $IDS && echo "terminated $IDS"
for p in $(aws ec2 describe-vpc-peering-connections --filters Name=status-code,Values=active,pending-acceptance,provisioning,failed,rejected --query 'VpcPeeringConnections[].VpcPeeringConnectionId' --output text); do
  # only ours: one of the two sides is a lab VPC
  mine=$(aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids $p --query 'VpcPeeringConnections[0].[RequesterVpcInfo.VpcId,AccepterVpcInfo.VpcId]' --output text)
  for v in $mine; do aws ec2 describe-vpcs --vpc-ids $v --filters Name=tag:lab,Values=$L --query 'Vpcs[0].VpcId' --output text 2>/dev/null | grep -q vpc- && { aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $p >/dev/null && echo "deleted peering $p"; break; }; done
done
for V in $(aws ec2 describe-vpcs --filters Name=tag:lab,Values=$L --query 'Vpcs[].VpcId' --output text); do
  # some accounts have GuardDuty runtime monitoring, which adds its own VPC endpoint and security group to a VPC with servers
  E=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$V --query 'VpcEndpoints[].VpcEndpointId' --output text)
  [ -n "$E" ] && aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $E >/dev/null 2>&1 && echo "deleted VPC endpoint(s) $E"
  for _ in 1 2 3 4 5 6; do
    for g in $(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$V --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do aws ec2 delete-security-group --group-id $g >/dev/null 2>&1; done
    for a in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$V --query 'RouteTables[].Associations[?!Main].RouteTableAssociationId' --output text); do aws ec2 disassociate-route-table --association-id $a >/dev/null 2>&1; done
    for r in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$V --query 'RouteTables[?length(Associations[?Main])==`0`].RouteTableId' --output text); do aws ec2 delete-route-table --route-table-id $r >/dev/null 2>&1; done
    for s in $(aws ec2 describe-subnets --filters Name=vpc-id,Values=$V --query 'Subnets[].SubnetId' --output text); do aws ec2 delete-subnet --subnet-id $s >/dev/null 2>&1; done
    for g in $(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$V --query 'InternetGateways[].InternetGatewayId' --output text); do aws ec2 detach-internet-gateway --internet-gateway-id $g --vpc-id $V >/dev/null 2>&1; aws ec2 delete-internet-gateway --internet-gateway-id $g >/dev/null 2>&1; done
    aws ec2 delete-vpc --vpc-id $V >/dev/null 2>&1 && { echo "deleted VPC $V"; break; }
    sleep 20
  done
done
r=clippy-peering-role
aws iam remove-role-from-instance-profile --instance-profile-name $r --role-name $r 2>/dev/null
aws iam delete-instance-profile --instance-profile-name $r 2>/dev/null
aws iam delete-role-policy --role-name $r --policy-name tag-myself 2>/dev/null
aws iam delete-role --role-name $r 2>/dev/null && echo "deleted role"
echo "Now run ./verify-teardown.sh"
