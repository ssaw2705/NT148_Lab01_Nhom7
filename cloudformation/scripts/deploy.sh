#!/usr/bin/env bash
# Dong goi nested stacks len S3 va trien khai stack CloudFormation.
# Bien moi truong (tuy chon):
#   AWS_REGION        (mac dinh ap-southeast-1)
#   STACK_NAME        (mac dinh nt548-lab1-cfn)
#   KEY_NAME          (mac dinh nt548-lab1-key; phai ton tai san trong region)
#   ALLOWED_SSH_CIDR  (mac dinh: IP public hien tai cua ban /32)
#   ARTIFACT_BUCKET   (mac dinh nt548-lab1-cfn-<account-id>-<region>)
set -euo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-ap-southeast-1}"
STACK_NAME="${STACK_NAME:-nt548-lab1-cfn}"
KEY_NAME="${KEY_NAME:-nt548-lab1-key}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${ARTIFACT_BUCKET:-nt548-lab1-cfn-${ACCOUNT_ID}-${REGION}}"
ALLOWED_SSH_CIDR="${ALLOWED_SSH_CIDR:-$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')/32}"
AZ="${AVAILABILITY_ZONE:-$(aws ec2 describe-availability-zones --region "$REGION" \
  --query 'AvailabilityZones[0].ZoneName' --output text)}"

echo ">> Region=$REGION Stack=$STACK_NAME Key=$KEY_NAME AZ=$AZ SSH from $ALLOWED_SSH_CIDR"

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo ">> Tao S3 bucket $BUCKET de chua template con"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
  aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

mkdir -p build
aws cloudformation package \
  --region "$REGION" \
  --template-file main.yaml \
  --s3-bucket "$BUCKET" \
  --output-template-file build/packaged.yaml

aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-file build/packaged.yaml \
  --parameter-overrides \
    AvailabilityZone="$AZ" \
    AllowedSshCidr="$ALLOWED_SSH_CIDR" \
    KeyName="$KEY_NAME"

aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs' --output table
