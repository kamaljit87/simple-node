# cicd_package - Full ECS + ALB + CI/CD CloudFormation

This package provisions (via CloudFormation):
- VPC (2 public subnets)
- ALB listening on port 80 and forwarding to container port 3000
- ECR repository (hello-world)
- ECS Fargate cluster, task and service
- CodeBuild project and CodePipeline (GitHub source)

Usage:
1. Unzip and inspect files.
2. Update `cloudformation/main.yaml` parameters when creating the stack:
   - GitHubRepo (owner/repo)
   - GitHubBranch
   - GitHubOAuthToken (NoEcho)
3. Ensure your GitHub repo contains the `buildspec.yml` and `cloudformation/ecs-update.yaml` in the repo root (this package includes a sample app layout).
4. Deploy the CloudFormation stack via Console or AWS CLI.
5. After stack creation, push a commit to trigger pipeline build->push->deploy.

Notes:
- This template is suitable for demo/testing. For production, tighten IAM policies, use private subnets, ALB IAM certs, and use CodeStar Connections instead of passing OAuth tokens.
- The pipeline's CloudFormation deploy action expects `cloudformation/ecs-update.yaml` in the build artifact with the replaced image URI (buildspec performs the substitution).