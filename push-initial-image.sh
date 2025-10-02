#!/bin/bash

# Push Initial Docker Image to ECR
# Run this AFTER creating the CloudFormation stack but BEFORE the ECS service starts
# Usage: ./push-initial-image.sh <stack-name> [region]

set -e

STACK_NAME=${1}
AWS_REGION=${2:-us-east-1}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$STACK_NAME" ]; then
    echo "Usage: $0 <stack-name> [region]"
    echo "Example: $0 simple-node-stack us-east-1"
    exit 1
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Pushing Initial Image to ECR${NC}"
echo -e "${BLUE}============================================${NC}"
echo "Stack: $STACK_NAME"
echo "Region: $AWS_REGION"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    echo "Please start Docker and try again"
    exit 1
fi

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in current directory${NC}"
    exit 1
fi

# Get AWS Account ID
echo "Getting AWS Account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✓ Account ID: $AWS_ACCOUNT_ID${NC}"

# Get ECR Repository URI from stack
echo ""
echo "Getting ECR Repository URI from CloudFormation stack..."
ECR_REPO_URI=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text 2>/dev/null)

if [ -z "$ECR_REPO_URI" ] || [ "$ECR_REPO_URI" == "None" ]; then
    echo -e "${YELLOW}Could not get ECR URI from stack outputs, constructing manually...${NC}"
    ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hello-world"
fi

echo -e "${GREEN}✓ ECR Repository: $ECR_REPO_URI${NC}"

# Login to ECR
echo ""
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully logged in to ECR${NC}"
else
    echo -e "${RED}✗ Failed to login to ECR${NC}"
    exit 1
fi

# Build Docker image
echo ""
echo "Building Docker image..."
docker build -t hello-world:latest .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
else
    echo -e "${RED}✗ Failed to build Docker image${NC}"
    exit 1
fi

# Tag image for ECR
echo ""
echo "Tagging image for ECR..."
docker tag hello-world:latest "${ECR_REPO_URI}:latest"
docker tag hello-world:latest "${ECR_REPO_URI}:initial"

echo -e "${GREEN}✓ Image tagged${NC}"

# Push to ECR
echo ""
echo "Pushing image to ECR..."
echo "This may take a few minutes..."
docker push "${ECR_REPO_URI}:latest"
docker push "${ECR_REPO_URI}:initial"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Image pushed successfully${NC}"
else
    echo -e "${RED}✗ Failed to push image${NC}"
    exit 1
fi

# Verify image in ECR
echo ""
echo "Verifying image in ECR..."
aws ecr describe-images \
    --repository-name hello-world \
    --region "$AWS_REGION" \
    --query 'imageDetails[*].[imageTags[0],imagePushedAt]' \
    --output table

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✓ Initial image pushed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "1. ECS service will now start successfully"
echo "2. Check service status:"
echo "   aws ecs describe-services --cluster ${STACK_NAME}-cluster --services ${STACK_NAME}-service --region $AWS_REGION"
echo ""
echo "3. Monitor task status:"
echo "   aws ecs list-tasks --cluster ${STACK_NAME}-cluster --region $AWS_REGION"
echo ""
echo "4. View logs:"
echo "   aws logs tail /ecs/${STACK_NAME} --follow --region $AWS_REGION"
echo ""