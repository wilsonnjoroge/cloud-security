# 🏗️ Building the Enterprise Environment — Step by Step

> **Capstone · Document 28 of 29**  
> **Estimated cost:** ~$15–25 total · **Estimated time:** 3–4 hours  
> **Prerequisites:** `27-enterprise-architecture-overview.md` and all Phase 1–4 documents

---

## Overview

This document builds the complete AcmeFintech enterprise environment from scratch. Every step references the earlier documents where you learned that component. By the end, you have a production-replica AWS environment running.

```
Build order:
  1. Foundation:    VPC, subnets, gateways, route tables
  2. Security:      IAM structure, KMS keys, Secrets Manager
  3. Compute:       Bastion, App server, RDS
  4. Access:        ALB, WAF, security groups
  5. Logging:       CloudTrail, VPC Flow Logs, CloudWatch
  6. Detection:     GuardDuty, Config, Security Hub
  7. Response:      Lambda auto-isolation
  8. Verification:  Test all components
```

---

## Stage 1 — VPC Foundation

### Create the enterprise VPC

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 create-tags \
  --resources $VPC_ID \
  --tags Key=Name,Value=acme-enterprise-vpc Key=Environment,Value=Production

echo "VPC: $VPC_ID"
```

### Create four subnets across two AZs

```bash
# Public subnet (AZ-a) — bastion and ALB
PUBLIC_SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-2a \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUBLIC_SUBNET_A \
  --tags Key=Name,Value=acme-public-a Key=Tier,Value=Public

# Public subnet (AZ-b) — ALB requires 2 AZs
PUBLIC_SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.5.0/24 \
  --availability-zone us-east-2b \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $PUBLIC_SUBNET_B \
  --tags Key=Name,Value=acme-public-b Key=Tier,Value=Public

# Private app subnet
APP_SUBNET=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-2a \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $APP_SUBNET \
  --tags Key=Name,Value=acme-app-private Key=Tier,Value=Application

# Private DB subnet (AZ-a)
DB_SUBNET_A=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone us-east-2a \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $DB_SUBNET_A \
  --tags Key=Name,Value=acme-db-private-a Key=Tier,Value=Database

# Private DB subnet (AZ-b) — RDS requires 2 AZs
DB_SUBNET_B=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.6.0/24 \
  --availability-zone us-east-2b \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $DB_SUBNET_B \
  --tags Key=Name,Value=acme-db-private-b Key=Tier,Value=Database

# Security subnet
SEC_SUBNET=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.4.0/24 \
  --availability-zone us-east-2a \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SEC_SUBNET \
  --tags Key=Name,Value=acme-security Key=Tier,Value=Security

echo "Subnets created"
```

### Internet gateway and NAT gateway

```bash
# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=acme-igw

# Elastic IP for NAT Gateway
NAT_EIP=$(aws ec2 allocate-address --domain vpc \
  --query 'AllocationId' --output text)

# NAT Gateway (in public subnet — allows private subnets outbound internet)
NAT_GW=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_A \
  --allocation-id $NAT_EIP \
  --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources $NAT_GW --tags Key=Name,Value=acme-nat-gw

echo "Waiting for NAT Gateway to be available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW
echo "NAT Gateway ready"
```

### Route tables

```bash
# Public route table — routes to internet via IGW
PUBLIC_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $PUBLIC_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_A
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_B
aws ec2 create-tags --resources $PUBLIC_RT --tags Key=Name,Value=acme-public-rt

# Private route table — routes to internet via NAT GW
PRIVATE_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $PRIVATE_RT \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $APP_SUBNET
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $SEC_SUBNET
aws ec2 create-tags --resources $PRIVATE_RT --tags Key=Name,Value=acme-private-rt

# DB route table — no internet access
DB_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 associate-route-table --route-table-id $DB_RT --subnet-id $DB_SUBNET_A
aws ec2 associate-route-table --route-table-id $DB_RT --subnet-id $DB_SUBNET_B
aws ec2 create-tags --resources $DB_RT --tags Key=Name,Value=acme-db-rt

echo "Route tables configured"
```

---

## Stage 2 — Security Groups

```bash
# Bastion SG — SSH from your IP only
BASTION_SG=$(aws ec2 create-security-group \
  --group-name acme-bastion-sg \
  --description "Bastion host - SSH from admin IP only" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $BASTION_SG \
  --protocol tcp --port 22 --cidr $(curl -s https://checkip.amazonaws.com)/32

# ALB SG — HTTP/HTTPS from internet
ALB_SG=$(aws ec2 create-security-group \
  --group-name acme-alb-sg \
  --description "ALB - web traffic from internet" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# App SG — port 8080 from ALB only
APP_SG=$(aws ec2 create-security-group \
  --group-name acme-app-sg \
  --description "App server - from ALB and bastion only" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $APP_SG \
  --protocol tcp --port 8080 --source-group $ALB_SG
aws ec2 authorize-security-group-ingress --group-id $APP_SG \
  --protocol tcp --port 22 --source-group $BASTION_SG

# DB SG — MySQL from app tier only
DB_SG=$(aws ec2 create-security-group \
  --group-name acme-db-sg \
  --description "RDS - MySQL from app tier only" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $DB_SG \
  --protocol tcp --port 3306 --source-group $APP_SG

# Isolation SG — emergency quarantine (no rules)
ISOLATION_SG=$(aws ec2 create-security-group \
  --group-name ISOLATION-NO-ACCESS \
  --description "Emergency isolation - no traffic allowed" \
  --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 revoke-security-group-egress --group-id $ISOLATION_SG \
  --protocol -1 --port -1 --cidr 0.0.0.0/0

echo "Security groups created"
```

---

## Stage 3 — IAM Structure

```bash
# Create IAM groups
aws iam create-group --group-name acme-developers
aws iam create-group --group-name acme-security
aws iam create-group --group-name acme-dba
aws iam create-group --group-name acme-readonly

# Attach policies to groups
aws iam attach-group-policy --group-name acme-developers \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-group-policy --group-name acme-developers \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-group-policy --group-name acme-security \
  --policy-arn arn:aws:iam::aws:policy/SecurityAudit
aws iam attach-group-policy --group-name acme-security \
  --policy-arn arn:aws:iam::aws:policy/AmazonGuardDutyFullAccess

aws iam attach-group-policy --group-name acme-dba \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

aws iam attach-group-policy --group-name acme-readonly \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

# Create IAM users
for USER in dev-alice dev-bob dev-charlie; do
  aws iam create-user --user-name $USER
  aws iam add-user-to-group --user-name $USER --group-name acme-developers
done

aws iam create-user --user-name sec-analyst
aws iam add-user-to-group --user-name sec-analyst --group-name acme-security

aws iam create-user --user-name dba-diana
aws iam add-user-to-group --user-name dba-diana --group-name acme-dba

aws iam create-user --user-name auditor-eve
aws iam add-user-to-group --user-name auditor-eve --group-name acme-readonly

echo "IAM structure created"
```

### Create EC2 roles

```bash
TRUST_EC2='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}'

# App server role
aws iam create-role --role-name acme-app-role \
  --assume-role-policy-document "$TRUST_EC2"
aws iam attach-role-policy --role-name acme-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam attach-role-policy --role-name acme-app-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws iam create-instance-profile --instance-profile-name acme-app-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name acme-app-profile --role-name acme-app-role

# Bastion role (Session Manager)
aws iam create-role --role-name acme-bastion-role \
  --assume-role-policy-document "$TRUST_EC2"
aws iam attach-role-policy --role-name acme-bastion-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name acme-bastion-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name acme-bastion-profile --role-name acme-bastion-role

echo "IAM roles created"
```

---

## Stage 4 — KMS and Secrets Manager

```bash
# Create master KMS key
KMS_KEY=$(aws kms create-key \
  --description "AcmeFintech master encryption key" \
  --query 'KeyMetadata.KeyId' --output text)
aws kms create-alias \
  --alias-name alias/acme-master-key \
  --target-key-id $KMS_KEY

echo "KMS Key: $KMS_KEY"

# Store database credentials in Secrets Manager
aws secretsmanager create-secret \
  --name acme/database/credentials \
  --description "AcmeFintech RDS admin credentials" \
  --kms-key-id $KMS_KEY \
  --secret-string '{"username":"acmeadmin","password":"AcmeF1ntech@2024!"}'

# Store API key
aws secretsmanager create-secret \
  --name acme/api/payment-gateway \
  --description "Payment gateway API credentials" \
  --kms-key-id $KMS_KEY \
  --secret-string '{"api_key":"pk_live_acmefintech_test","api_secret":"sk_live_test_secret"}'

echo "Secrets stored"
```

---

## Stage 5 — RDS Database

```bash
# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name acme-db-subnet-group \
  --db-subnet-group-description "AcmeFintech DB subnets" \
  --subnet-ids $DB_SUBNET_A $DB_SUBNET_B

# Launch RDS MySQL
aws rds create-db-instance \
  --db-instance-identifier acme-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version 8.0 \
  --master-username acmeadmin \
  --master-user-password "AcmeF1ntech@2024!" \
  --db-name acmefintech \
  --vpc-security-group-ids $DB_SG \
  --db-subnet-group-name acme-db-subnet-group \
  --storage-type gp2 \
  --allocated-storage 20 \
  --storage-encrypted \
  --kms-key-id $KMS_KEY \
  --backup-retention-period 7 \
  --no-publicly-accessible \
  --enable-cloudwatch-logs-exports general error slowquery audit \
  --tags Key=Name,Value=acme-db Key=Environment,Value=Production

echo "RDS launching (takes ~5 minutes)..."
```

---

## Stage 6 — EC2 Instances

### Bastion host

```bash
# Create key pair
aws ec2 create-key-pair --key-name acme-bastion-key \
  --query 'KeyMaterial' --output text > acme-bastion-key.pem
chmod 400 acme-bastion-key.pem

# Enable auto-assign public IP for public subnet
aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_A \
  --map-public-ip-on-launch

# Launch bastion
BASTION_ID=$(aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --key-name acme-bastion-key \
  --subnet-id $PUBLIC_SUBNET_A \
  --security-group-ids $BASTION_SG \
  --iam-instance-profile Name=acme-bastion-profile \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --user-data '#!/bin/bash
yum update -y
yum install -y amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=acme-bastion},{Key=Environment,Value=Production}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "Bastion: $BASTION_ID"
```

### App server

```bash
APP_ID=$(aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.small \
  --key-name acme-bastion-key \
  --subnet-id $APP_SUBNET \
  --security-group-ids $APP_SG \
  --iam-instance-profile Name=acme-app-profile \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --user-data '#!/bin/bash
yum update -y
yum install -y python3 python3-pip amazon-cloudwatch-agent

# Install app dependencies
pip3 install flask boto3

# Create simple fintech web app
cat > /home/ec2-user/app.py << EOF
from flask import Flask, jsonify, request
import boto3, json

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "AcmeFintech API"})

@app.route("/api/accounts")
def accounts():
    return jsonify({"accounts": [
        {"id": "ACC001", "balance": 15420.50},
        {"id": "ACC002", "balance": 8300.00}
    ]})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

python3 /home/ec2-user/app.py &' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=acme-app-server},{Key=Environment,Value=Production}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "App server: $APP_ID"
```

---

## Stage 7 — ALB and WAF

```bash
# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name acme-alb \
  --subnets $PUBLIC_SUBNET_A $PUBLIC_SUBNET_B \
  --security-groups $ALB_SG \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Create target group
TG_ARN=$(aws elbv2 create-target-group \
  --name acme-tg \
  --protocol HTTP --port 8080 \
  --vpc-id $VPC_ID \
  --health-check-path /health \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Register app server
aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=$APP_ID

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

echo "ALB configured"

# Create WAF Web ACL
WEBACL_ID=$(aws wafv2 create-web-acl \
  --name acme-web-acl \
  --scope REGIONAL \
  --default-action Allow={} \
  --rules '[
    {
      "Name": "AWSManagedRulesCRS",
      "Priority": 1,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CRS"
      }
    },
    {
      "Name": "RateLimitRule",
      "Priority": 2,
      "Action": {"Block": {}},
      "Statement": {
        "RateBasedStatement": {
          "Limit": 1000,
          "AggregateKeyType": "IP"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "RateLimit"
      }
    }
  ]' \
  --visibility-config \
    SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=acme-waf \
  --region us-east-2 \
  --query 'Summary.Id' --output text)

# Associate WAF with ALB
aws wafv2 associate-web-acl \
  --web-acl-arn "arn:aws:wafv2:us-east-2:$(aws sts get-caller-identity --query Account --output text):regional/webacl/acme-web-acl/$WEBACL_ID" \
  --resource-arn $ALB_ARN

echo "WAF configured and associated with ALB"
```

---

## Stage 8 — Logging and Detection

```bash
# S3 bucket for all logs
LOG_BUCKET="acme-security-logs-$(aws sts get-caller-identity --query Account --output text)"
aws s3 mb s3://$LOG_BUCKET --region us-east-2
aws s3api put-public-access-block --bucket $LOG_BUCKET \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable CloudTrail
aws cloudtrail create-trail \
  --name acme-audit-trail \
  --s3-bucket-name $LOG_BUCKET \
  --s3-key-prefix cloudtrail \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation

aws cloudtrail start-logging --name acme-audit-trail

# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids $VPC_ID \
  --traffic-type ALL \
  --log-destination-type s3 \
  --log-destination "arn:aws:s3:::$LOG_BUCKET/flowlogs/"

# Enable GuardDuty
DETECTOR_ID=$(aws guardduty create-detector \
  --enable \
  --finding-publishing-frequency FIFTEEN_MINUTES \
  --query 'DetectorId' --output text)

# Enable Security Hub
aws securityhub enable-security-hub \
  --enable-default-standards

# Enable AWS Config
aws configservice put-configuration-recorder \
  --configuration-recorder \
    name=acme-recorder,roleARN=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig

aws configservice put-delivery-channel \
  --delivery-channel \
    name=acme-channel,s3BucketName=$LOG_BUCKET

aws configservice start-configuration-recorder \
  --configuration-recorder-name acme-recorder

echo "All logging and detection services enabled"
```

---

## Stage 9 — Verify the Environment

```bash
# Save all resource IDs for reference
cat > acme-environment.env << EOF
VPC_ID=$VPC_ID
PUBLIC_SUBNET_A=$PUBLIC_SUBNET_A
PUBLIC_SUBNET_B=$PUBLIC_SUBNET_B
APP_SUBNET=$APP_SUBNET
DB_SUBNET_A=$DB_SUBNET_A
DB_SUBNET_B=$DB_SUBNET_B
SEC_SUBNET=$SEC_SUBNET
BASTION_SG=$BASTION_SG
ALB_SG=$ALB_SG
APP_SG=$APP_SG
DB_SG=$DB_SG
ISOLATION_SG=$ISOLATION_SG
BASTION_ID=$BASTION_ID
APP_ID=$APP_ID
ALB_ARN=$ALB_ARN
KMS_KEY=$KMS_KEY
LOG_BUCKET=$LOG_BUCKET
DETECTOR_ID=$DETECTOR_ID
EOF

echo "Environment saved to acme-environment.env"

# Test the web application
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)

echo "Testing application: http://$ALB_DNS/health"
curl http://$ALB_DNS/health

echo ""
echo "===== ENVIRONMENT READY ====="
echo "ALB DNS: $ALB_DNS"
echo "Bastion: $(aws ec2 describe-instances --instance-ids $BASTION_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
echo "App Server (private): $(aws ec2 describe-instances --instance-ids $APP_ID \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)"
echo "GuardDuty Detector: $DETECTOR_ID"
echo "CloudTrail: Active"
echo "Security Hub: Active"
echo "==============================="
```

---

## Full Teardown Script

```bash
#!/bin/bash
# Source the environment
source acme-environment.env

echo "Starting teardown..."

# EC2
aws ec2 terminate-instances --instance-ids $BASTION_ID $APP_ID
aws ec2 wait instance-terminated --instance-ids $BASTION_ID $APP_ID

# RDS
aws rds delete-db-instance --db-instance-identifier acme-db \
  --skip-final-snapshot --delete-automated-backups

# ALB and target group
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
sleep 30
aws elbv2 delete-target-group --target-group-arn $TG_ARN

# NAT Gateway
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW
aws ec2 release-address --allocation-id $NAT_EIP

# Security groups
for SG in $BASTION_SG $ALB_SG $APP_SG $DB_SG $ISOLATION_SG; do
  aws ec2 delete-security-group --group-id $SG 2>/dev/null
done

# Subnets
for SUBNET in $PUBLIC_SUBNET_A $PUBLIC_SUBNET_B $APP_SUBNET $DB_SUBNET_A $DB_SUBNET_B $SEC_SUBNET; do
  aws ec2 delete-subnet --subnet-id $SUBNET
done

# Route tables
for RT in $PUBLIC_RT $PRIVATE_RT $DB_RT; do
  aws ec2 delete-route-table --route-table-id $RT 2>/dev/null
done

# Internet Gateway
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

# Secrets and KMS
aws secretsmanager delete-secret --secret-id acme/database/credentials --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id acme/api/payment-gateway --force-delete-without-recovery
aws kms schedule-key-deletion --key-id $KMS_KEY --pending-window-in-days 7

# GuardDuty and Security Hub
aws guardduty delete-detector --detector-id $DETECTOR_ID
aws securityhub disable-security-hub

# S3 log bucket
aws s3 rm s3://$LOG_BUCKET --recursive
aws s3 rb s3://$LOG_BUCKET

echo "Teardown complete"
```

---

*Capstone · AWS Cybersecurity & Digital Forensics Roadmap*
