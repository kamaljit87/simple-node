# ECS + CI/CD Deployment Guide

This guide will help you deploy your Node.js application to AWS ECS with a complete CI/CD pipeline using CloudFormation.

## Architecture Overview

The CloudFormation stack creates:
- **VPC** with 2 public subnets across 2 availability zones
- **Application Load Balancer** (ALB) on port 80
- **ECR Repository** for Docker images
- **ECS Fargate Cluster** with a service running 2 tasks
- **CodeBuild** project to build and push Docker images
- **CodePipeline** for automated deployments
- **GitHub Webhook** for automatic pipeline triggers

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **GitHub Repository** with your code
4. **GitHub Personal Access Token** (classic) with these permissions:
   - `repo` (full control)
   - `admin:repo_hook` (write access)

### Creating a GitHub Token

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Select scopes: `repo` and `admin:repo_hook`
4. Generate and copy the token (starts with `ghp_`)

## Project Structure

```
.
├── cloudformation/
│   └── main.yaml              # Main CloudFormation template
├── public/
│   ├── index.html             # Frontend HTML
│   └── styles.css             # Frontend CSS
├── app.js                     # Express server
├── package.json               # Node.js dependencies
├── Dockerfile                 # Docker configuration
├── buildspec.yml              # CodeBuild instructions
├── docker-compose.yml         # Local development
└── deploy.sh                  # Deployment script
```

## Quick Start

### Option 1: Using the Deployment Script (Recommended)

1. **Make the script executable:**
   ```bash
   chmod +x deploy.sh
   ```

2. **Deploy the stack:**
   ```bash
   ./deploy.sh my-app-stack ghp_YOUR_GITHUB_TOKEN us-east-1 your-username/simple-node main
   ```

   Parameters:
   - `my-app-stack`: Your CloudFormation stack name
   - `ghp_YOUR_GITHUB_TOKEN`: Your GitHub personal access token
   - `us-east-1`: AWS region (optional, defaults to us-east-1)
   - `your-username/simple-node`: Your GitHub repo (optional)
   - `main`: Git branch (optional, defaults to main)

3. **Wait for deployment** (takes ~10-15 minutes)

4. **Get your application URL:**
   ```bash
   aws cloudformation describe-stacks \
     --stack-name my-app-stack \
     --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
     --output text
   ```

### Option 2: Using AWS Console

1. **Create the CloudFormation folder:**
   ```bash
   mkdir -p cloudformation
   ```

2. **Save the template** as `cloudformation/main.yaml`

3. **Go to AWS Console** → CloudFormation → Create Stack

4. **Upload the template** (`main.yaml`)

5. **Fill in parameters:**
   - Stack name: `simple-node-stack`
   - GitHubRepo: `your-username/simple-node`
   - GitHubBranch: `main`
   - GitHubOAuthToken: Your GitHub token
   - EnvironmentName: `simple-node`

6. **Acknowledge IAM capabilities** and create the stack

7. **Wait for completion** and check the Outputs tab for URLs

### Option 3: Using AWS CLI

```bash
aws cloudformation create-stack \
  --stack-name simple-node-stack \
  --template-body file://cloudformation/main.yaml \
  --parameters \
    ParameterKey=GitHubRepo,ParameterValue=your-username/simple-node \
    ParameterKey=GitHubBranch,ParameterValue=main \
    ParameterKey=GitHubOAuthToken,ParameterValue=ghp_YOUR_TOKEN \
    ParameterKey=EnvironmentName,ParameterValue=simple-node \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

## Post-Deployment

### 1. Verify Stack Creation

```bash
aws cloudformation describe-stacks \
  --stack-name simple-node-stack \
  --query 'Stacks[0].StackStatus'
```

### 2. Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name simple-node-stack \
  --query 'Stacks[0].Outputs' \
  --output table
```

Key outputs:
- **LoadBalancerURL**: Your application URL
- **ECRRepositoryURI**: Docker image repository
- **PipelineURL**: CodePipeline console link

### 3. Trigger Initial Deployment

The pipeline will automatically trigger when you push code to GitHub:

```bash
git add .
git commit -m "Initial deployment"
git push origin main
```

### 4. Monitor Pipeline

1. Go to AWS Console → CodePipeline
2. Click on your pipeline (`simple-node-pipeline`)
3. Watch the stages: Source → Build → Deploy

### 5. Access Your Application

Once the pipeline completes, visit the Load Balancer URL from the stack outputs.

## Local Development

### Run with Docker

```bash
docker build -t simple-node .
docker run -p 3000:3000 simple-node
```

### Run with Docker Compose

```bash
docker-compose up
```

### Run without Docker

```bash
npm install
npm start
```

Visit `http://localhost:3000`

## Monitoring & Troubleshooting

### View ECS Logs

```bash
aws logs tail /ecs/simple-node --follow
```

### Check ECS Service Status

```bash
aws ecs describe-services \
  --cluster simple-node-cluster \
  --services simple-node-service \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
```

### Check Task Health

```bash
aws ecs list-tasks \
  --cluster simple-node-cluster \
  --service-name simple-node-service
```

### View CodeBuild Logs

1. Go to AWS Console → CodeBuild
2. Click on your build project
3. Click on a build run to see logs

### Common Issues

**Pipeline fails at Build stage:**
- Check CodeBuild logs for errors
- Verify buildspec.yml is in repository root
- Ensure Docker builds successfully locally

**Pipeline fails at Deploy stage:**
- Check ECS service events
- Verify security groups allow ALB → ECS communication
- Check task definition for errors

**Application not accessible:**
- Wait 2-3 minutes after deployment for health checks
- Verify ALB security group allows inbound port 80
- Check target group health status

## Updating Your Application

### Automatic Deployment (Recommended)

Simply push to GitHub:
```bash
git add .
git commit -m "Update application"
git push origin main
```

The pipeline will automatically build and deploy.

### Manual Deployment

Update task definition:
```bash
aws ecs update-service \
  --cluster simple-node-cluster \
  --service simple-node-service \
  --force-new-deployment
```

## Stack Management

### Update Stack

```bash
./deploy.sh simple-node-stack ghp_YOUR_TOKEN us-east-1
```

Or using AWS CLI:
```bash
aws cloudformation update-stack \
  --stack-name simple-node-stack \
  --template-body file://cloudformation/main.yaml \
  --parameters ... \
  --capabilities CAPABILITY_IAM
```

### Delete Stack

**Warning:** This will delete all resources!

```bash
aws cloudformation delete-stack --stack-name simple-node-stack
```

Or using the deploy script:
```bash
aws cloudformation delete-stack --stack-name simple-node-stack
aws cloudformation wait stack-delete-complete --stack-name simple-node-stack
```

## Cost Optimization

The stack includes:
- **Fargate tasks**: $0.04048/hour per vCPU + $0.004445/hour per GB
- **ALB**: ~$16.20/month + data transfer
- **ECR storage**: $0.10/GB/month
- **NAT Gateway**: Not used (using public subnets)

Expected monthly cost: **~$30-40** for this setup.

To reduce costs:
- Set `DesiredCount: 1` in ECS service (instead of 2)
- Use smaller task sizes (256 CPU / 512 MB is minimum)
- Delete unused ECR images regularly

## Security Best Practices

For production deployments:

1. **Use Private Subnets** for ECS tasks with NAT Gateway
2. **Enable HTTPS** on ALB with ACM certificates
3. **Use AWS Secrets Manager** for sensitive data
4. **Enable CloudTrail** for audit logging
5. **Use CodeStar Connections** instead of GitHub OAuth tokens
6. **Implement IAM least privilege** policies
7. **Enable container insights** for ECS
8. **Add WAF** to ALB for web application firewall

## Additional Resources

- [ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)

## Support

For issues with:
- **AWS Resources**: Check CloudFormation events and stack outputs
- **Application Code**: Review ECS task logs
- **Pipeline**: Check CodeBuild and CodePipeline logs

## License

