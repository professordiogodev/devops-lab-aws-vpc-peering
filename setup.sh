#!/usr/bin/env bash
# Builds the two isolated networks and two servers. Run once: ./setup.sh
#   staging   VPC 10.1.0.0/16   server 10.1.1.10, answers HTTP on port 80
#   analytics VPC 10.2.0.0/16   server 10.2.1.10, tries to call the staging server every 20 seconds
#             and writes the result on ITS OWN tags (peer-http = ok or fail), so you and verify.sh can read it.
set -u
cd "$(dirname "$0")"
aws sts get-caller-identity >/dev/null 2>&1 || { echo "No working AWS credentials." >&2; exit 1; }
L=aws-vpc-peering
if aws ec2 describe-vpcs --filters Name=tag:lab,Values=$L --query 'Vpcs[].VpcId' --output text | grep -q vpc-; then echo "The networks already exist."; exit 0; fi
tags() { echo "ResourceType=$1,Tags=[{Key=lab,Value=$L},{Key=Name,Value=$2}]"; }
AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text)
AZ=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
# the role lets each server tag itself, nothing else
aws iam create-role --role-name clippy-peering-role --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --tags Key=lab,Value=$L >/dev/null
aws iam put-role-policy --role-name clippy-peering-role --policy-name tag-myself --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"ec2:CreateTags","Resource":"arn:aws:ec2:*:*:instance/*","Condition":{"StringEquals":{"ec2:ResourceTag/lab":"aws-vpc-peering"}}}]}'
aws iam create-instance-profile --instance-profile-name clippy-peering-role >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name clippy-peering-role --role-name clippy-peering-role
build() { # name cidr subnet-cidr private-ip userdata-file
  local N=$1 C=$2 S=$3 IP=$4 UD=$5
  local V=$(aws ec2 create-vpc --cidr-block $C --tag-specifications "$(tags vpc $N)" --query Vpc.VpcId --output text)
  aws ec2 modify-vpc-attribute --vpc-id $V --enable-dns-hostnames
  local G=$(aws ec2 create-internet-gateway --tag-specifications "$(tags internet-gateway $N)" --query InternetGateway.InternetGatewayId --output text)
  aws ec2 attach-internet-gateway --internet-gateway-id $G --vpc-id $V
  local SN=$(aws ec2 create-subnet --vpc-id $V --cidr-block $S --availability-zone $AZ --tag-specifications "$(tags subnet $N)" --query Subnet.SubnetId --output text)
  aws ec2 modify-subnet-attribute --subnet-id $SN --map-public-ip-on-launch
  local RT=$(aws ec2 create-route-table --vpc-id $V --tag-specifications "$(tags route-table $N)" --query RouteTable.RouteTableId --output text)
  aws ec2 create-route --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $G >/dev/null
  aws ec2 associate-route-table --route-table-id $RT --subnet-id $SN >/dev/null
  local SG=$(aws ec2 create-security-group --group-name clippy-$N --description "$N server" --vpc-id $V --tag-specifications "$(tags security-group $N)" --query GroupId --output text)
  sleep 1
  aws ec2 run-instances --image-id $AMI --instance-type t3.micro --subnet-id $SN --private-ip-address $IP --security-group-ids $SG \
    --iam-instance-profile Name=clippy-peering-role --user-data file://$UD --metadata-options HttpTokens=required,HttpEndpoint=enabled \
    --tag-specifications "$(tags instance $N-server)" --query 'Instances[0].InstanceId' --output text
}
sleep 10
ID1=$(build staging 10.1.0.0/16 10.1.1.0/24 10.1.1.10 .userdata-staging.sh)
ID2=$(build analytics 10.2.0.0/16 10.2.1.0/24 10.2.1.10 .userdata-analytics.sh)
echo "Two networks, two servers:"
echo "  staging   10.1.0.0/16  server $ID1 (10.1.1.10)"
echo "  analytics 10.2.0.0/16  server $ID2 (10.2.1.10)"
echo "The analytics server starts calling staging in about a minute. Watch its tag peer-http."
