#!/usr/bin/env bash
# Xoa stack CloudFormation (va cac nested stack) de tranh phat sinh chi phi NAT/EC2.
set -euo pipefail
REGION="${AWS_REGION:-ap-southeast-1}"
STACK_NAME="${STACK_NAME:-nt548-lab1-cfn}"

aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK_NAME"
echo ">> Dang xoa $STACK_NAME ..."
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK_NAME"
echo ">> Da xoa xong. (S3 bucket chua template co the xoa thu cong neu khong can.)"
