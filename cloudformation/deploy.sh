#!/bin/bash

# Deploy CloudFormation Stack for ECS + CI/CD
# Usage: ./deploy.sh <stack-name> <github-token> [region]

set -e

STACK_NAME=${1:-simple-node-stack}
GITHUB_TOKEN=${2}
AWS_REGION=${3:-us-east-1}
GITHUB_REPO=${4:-"your-username/simple-node"}
GITHUB_BRANCH=${5:-"main"}

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token is required"
    echo "Usage: ./deploy.sh <stack-name> <github-token> [region] [github-repo] [branch]"
    echo "Example: ./deploy.sh my-app ghp_xxxxx us-east-1 myuser/myrepo main"
    exit 1
fi

echo "============================================"
echo "Deploying Stack: $STACK_NAME"
echo "Region: $AWS_REGION"
echo "GitHub Repo: $GITHUB_REPO"
echo "GitHub Branch: $GITHUB_BRANCH"
echo "============================================"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Check if CloudFormation template exists
if [ ! -f "cloudformation/main.yaml" ]; then
    echo "Error: cloudformation/main.yaml not found"
    exit 1
fi

# Create/Update Stack
echo "Creating/Updating CloudFormation stack..."
aws cloudformation deploy \
    --template-file cloudformation/main.yaml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides \
        GitHubRepo="$GITHUB_REPO" \
        GitHubBranch="$GITHUB_BRANCH" \
        GitHubOAuthToken="$GITHUB_TOKEN" \
        EnvironmentName="$STACK_NAME" \
    --capabilities CAPABILITY_IAM \
    --region "$AWS_REGION" \
    --no-fail-on-empty-changeset

echo ""
echo "============================================"
echo "Stack deployment initiated!"
echo "============================================"
echo ""

# Wait for stack creation/update
echo "Waiting for stack to complete..."
aws cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" 2>/dev/null || \
aws cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" 2>/dev/null || true

# Get outputs
echo ""
echo "============================================"
echo "Stack Outputs:"
echo "============================================"
aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

echo ""
echo "============================================"
echo "Next Steps:"
echo "============================================"
echo "1. Push your code to GitHub to trigger the pipeline"
echo "2. Monitor the pipeline in AWS Console"
echo "3. Access your application via the Load Balancer URL above"
echo ""
echo "To push an initial image to ECR (optional):"
echo "  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com"
echo "  docker build -t hello-world ."
echo "  docker tag hello-world:latest \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/hello-world:latest"
echo "  docker push \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com/hello-world:latest"
echo ""