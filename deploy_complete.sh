#!/bin/bash

# Complete Deployment Script - Creates Stack, Pushes Initial Image, Starts Service
# Usage: ./deploy-complete.sh <stack-name> <github-token> [region] [repo] [branch]

set -e

STACK_NAME=${1:-simple-node-stack}
GITHUB_TOKEN=${2}
AWS_REGION=${3:-us-east-1}
GITHUB_REPO=${4:-"your-username/simple-node"}
GITHUB_BRANCH=${5:-"main"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

function print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

function print_error() {
    echo -e "${RED}✗ $1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

function check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    print_success "AWS CLI installed"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    print_success "Docker installed"
    
    # Check Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running"
        exit 1
    fi
    print_success "Docker is running"
    
    # Check template exists
    if [ ! -f "cloudformation/main.yaml" ]; then
        print_error "cloudformation/main.yaml not found"
        exit 1
    fi
    print_success "CloudFormation template found"
    
    # Check Dockerfile exists
    if [ ! -f "Dockerfile" ]; then
        print_error "Dockerfile not found"
        exit 1
    fi
    print_success "Dockerfile found"
    
    # Check GitHub token
    if [ -z "$GITHUB_TOKEN" ]; then
        print_error "GitHub token is required"
        echo "Usage: $0 <stack-name> <github-token> [region] [repo] [branch]"
        exit 1
    fi
    print_success "GitHub token provided"
}

function check_stack_exists() {
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function deploy_stack() {
    print_header "Step 1: Deploying CloudFormation Stack"
    
    echo "Stack Name: $STACK_NAME"
    echo "Region: $AWS_REGION"
    echo "GitHub Repo: $GITHUB_REPO"
    echo "GitHub Branch: $GITHUB_BRANCH"
    echo ""
    
    if check_stack_exists; then
        echo "Stack exists - updating..."
        ACTION="update"
    else
        echo "Stack does not exist - creating..."
        ACTION="create"
    fi
    
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
    
    if [ $ACTION == "create" ]; then
        echo ""
        echo "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION"
    fi
    
    print_success "CloudFormation stack deployed"
}

function push_initial_image() {
    print_header "Step 2: Building and Pushing Initial Docker Image"
    
    # Get AWS Account ID
    echo "Getting AWS Account ID..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "Account ID: $AWS_ACCOUNT_ID"
    
    # Construct ECR URI
    ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/hello-world"
    echo "ECR Repository: $ECR_REPO_URI"
    echo ""
    
    # Login to ECR
    echo "Logging in to Amazon ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    print_success "Logged in to ECR"
    
    # Build Docker image
    echo ""
    echo "Building Docker image..."
    docker build -t hello-world:latest . --quiet
    print_success "Docker image built"
    
    # Tag image
    echo ""
    echo "Tagging image for ECR..."
    docker tag hello-world:latest "${ECR_REPO_URI}:latest"
    docker tag hello-world:latest "${ECR_REPO_URI}:initial"
    print_success "Image tagged"
    
    # Push to ECR
    echo ""
    echo "Pushing image to ECR (this may take a minute)..."
    docker push "${ECR_REPO_URI}:latest" --quiet
    docker push "${ECR_REPO_URI}:initial" --quiet
    print_success "Image pushed to ECR"
}

function start_ecs_service() {
    print_header "Step 3: Starting ECS Service"
    
    echo "Updating ECS service to desired count of 2..."
    aws ecs update-service \
        --cluster "${STACK_NAME}-cluster" \
        --service "${STACK_NAME}-service" \
        --desired-count 2 \
        --region "$AWS_REGION" \
        --no-cli-pager > /dev/null
    
    print_success "ECS service starting"
    
    echo ""
    echo "Waiting for service to become stable (this may take 2-3 minutes)..."
    
    # Wait for service to stabilize
    aws ecs wait services-stable \
        --cluster "${STACK_NAME}-cluster" \
        --services "${STACK_NAME}-service" \
        --region "$AWS_REGION" 2>&1 | grep -v "Waiter" || true
    
    print_success "ECS service is stable and running"
}

function display_outputs() {
    print_header "Deployment Complete!"
    
    echo ""
    echo "Stack Outputs:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    echo -e "${GREEN}Your application is now running!${NC}"
    echo ""
    
    # Get Load Balancer URL
    ALB_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
        --output text)
    
    echo "Application URL: ${ALB_URL}"
    echo ""
    echo "Useful commands:"
    echo ""
    echo "View logs:"
    echo "  aws logs tail /ecs/${STACK_NAME} --follow --region $AWS_REGION"
    echo ""
    echo "Check service status:"
    echo "  aws ecs describe-services --cluster ${STACK_NAME}-cluster --services ${STACK_NAME}-service --region $AWS_REGION"
    echo ""
    echo "List running tasks:"
    echo "  aws ecs list-tasks --cluster ${STACK_NAME}-cluster --region $AWS_REGION"
    echo ""
    echo "View pipeline:"
    PIPELINE_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`PipelineURL`].OutputValue' \
        --output text)
    echo "  ${PIPELINE_URL}"
    echo ""
    echo "To trigger a new deployment:"
    echo "  git push origin ${GITHUB_BRANCH}"
    echo ""
}

function cleanup_on_error() {
    print_error "Deployment failed!"
    echo ""
    echo "To view stack events:"
    echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $AWS_REGION --max-items 20"
    echo ""
    echo "To delete the stack:"
    echo "  aws cloudformation delete-stack --stack-name $STACK_NAME --region $AWS_REGION"
    exit 1
}

# Main execution
trap cleanup_on_error ERR

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   ECS Complete Deployment Script      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

check_prerequisites
deploy_stack
push_initial_image
start_ecs_service
display_outputs

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Deployment Successful! 🎉            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""