# Take-home-test

A production-ready infrastructure repository demonstrating GitOps, IaC, and container deployment practices using Terraform, Helm, and GitHub Actions.

---

## Repository Structure

```
take-home-test/
├── .github/
│   └── workflows/
│       └── main.yml          # CI pipeline
├── app/
│   └── server.js             # Placeholder Node.js microservice
├── helm/
│   └── microservice/         # Reusable Helm chart
│       ├── Chart.yaml
│       ├── values.yaml       # Base defaults
│       ├── values.dev.yaml
│       ├── values.staging.yaml
│       ├── values.prod.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── hpa.yaml
│           ├── pdb.yaml
│           ├── resourcequota.yaml
│           ├── configmap.yaml
│           └── serviceaccount.yaml
├── terraform/
│   ├── main.tf               # Root module — calls all child modules
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── outputs.tf
│   ├── providers.tf
│   └── modules/
│       ├── networking/       # VPC, subnets, IGW, NAT gateways
│       ├── iam/              # EKS cluster and node IAM roles
│       ├── ecr/              # ECR repositories and lifecycle policies
│       └── eks/              # EKS cluster, node group, launch template
├── Dockerfile
└── .gitignore
```

---

## Infrastructure Overview

The Terraform configuration provisions the following AWS resources:

### Networking
- VPC with DNS support enabled
- 3 public subnets and 3 private subnets across 3 availability zones
- Internet Gateway for public subnet egress
- NAT Gateways (one per AZ) for private subnet egress
- Separate route tables for public and private subnets
- Subnet tags for EKS load balancer discovery (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`)

### IAM
- EKS Cluster IAM Role with `AmazonEKSClusterPolicy` and `AmazonEKSVPCResourceController`
- EKS Node IAM Role with:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryReadOnly`
  - `AmazonSSMManagedInstanceCore` (for SSM access without bastion)

### ECR
- Repositories created dynamically via `for_each` — add a new repo by updating `ecr_repositories` in `terraform.tfvars`
- Image scanning on push enabled
- Lifecycle policy to retain the last N images (configurable via `ecr_image_retention_count`)
- AES256 encryption at rest

### EKS
- EKS cluster on Kubernetes 1.29 deployed into private subnets
- Managed node group with EC2 instances (`t3.medium` by default)
- Custom launch template with:
  - 50GB encrypted gp3 EBS root volume
  - IMDSv2 enforced (`http_tokens = required`)
- Control plane logging enabled (api, audit, authenticator, controllerManager, scheduler)
- `ignore_changes` on `desired_size` so the cluster autoscaler can manage scaling without causing Terraform drift

---

## Terraform Usage

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- An S3 bucket and DynamoDB table for remote state (see backend setup below)

### Backend Setup

The S3 backend is intentionally kept out of `providers.tf` to allow the pipeline to run `init -backend=false` without hitting AWS. For real deployments, create a `terraform/backend.tf` file (this file is gitignored):

```hcl
terraform {
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-lock"
    encrypt        = true
  }
}
```

The DynamoDB table only needs a `LockID` string partition key.

### Deploy

```bash
cd terraform

terraform init
terraform plan
terraform apply
```

### Tear Down

```bash
terraform destroy
```

---

## Helm Chart

A single reusable chart that deploys a microservice to any environment using override values files.

### Key Features

- **Dynamic image URI** — `image.repository` is intentionally left empty in `values.yaml` and injected by the CI pipeline at deploy time via `--set`
- **Pod Disruption Budget** — configurable `minAvailable` or `maxUnavailable` to protect availability during node drains and rolling updates
- **Resource Quota** — namespace-level CPU, memory, and pod caps configurable per environment
- **HPA** — horizontal pod autoscaling on CPU and memory, with replica count omitted from the Deployment spec when HPA is enabled to prevent conflicts
- **Pod anti-affinity** — pods spread across nodes by default to avoid single points of failure
- **Security hardened** — non-root user, read-only root filesystem, all Linux capabilities dropped, IMDSv2 enforced at the node level

### Environment Overrides

```bash
# Dev
helm upgrade --install myapp helm/microservice \
  -f helm/microservice/values.yaml \
  -f helm/microservice/values.dev.yaml \
  --set image.repository=<IMAGE_URI> \
  --set image.tag=<TAG>

# Staging
helm upgrade --install myapp helm/microservice \
  -f helm/microservice/values.yaml \
  -f helm/microservice/values.staging.yaml \
  --set image.repository=<IMAGE_URI> \
  --set image.tag=<TAG>

# Production
helm upgrade --install myapp helm/microservice \
  -f helm/microservice/values.yaml \
  -f helm/microservice/values.prod.yaml \
  --set image.repository=<IMAGE_URI> \
  --set image.tag=<TAG>
```

### Local Validation

No cluster needed:

```bash
# Lint the chart
helm lint helm/microservice \
  -f helm/microservice/values.yaml \
  -f helm/microservice/values.prod.yaml

# Render all templates locally (no cluster needed)
helm template myapp helm/microservice \
  -f helm/microservice/values.yaml \
  -f helm/microservice/values.prod.yaml \
  --set image.repository=nginx \
  --set image.tag=latest \
  --debug \
```

---

## CI Pipeline

The GitHub Actions pipeline runs on every push to `main` or `develop`, and on pull requests targeting `main`. It has three sequential jobs:

```
terraform → docker → helm
```

### Job 1 — Terraform Quality Gate

Validates the Terraform configuration without deploying anything:

1. `terraform fmt -check` — fails if any file is not properly formatted
2. `terraform init -backend=false` — initialises providers locally, skips S3 backend
3. `terraform validate` — checks configuration syntax and internal consistency
4. `terraform plan` — produces a full execution plan to catch any resource or variable errors

### Job 2 — Docker Build & Push

1. Builds the Docker image using a multi-stage distroless build
2. Tags the image with the short commit SHA, branch name, and `latest` (on `main` only)
3. Pushes to Docker Hub — skipped on pull requests, push only on merge

### Job 3 — Helm Lint & Test Installation

1. `helm lint` — validates the chart structure and best practices
2. `helm template` — renders all manifests locally with the real image URI injected from Job 2. We use `helm template` over `helm install --dry-run=client` because even with the dry-run flag, Helm still attempts to reach a Kubernetes cluster to check the server version — which fails in CI with no cluster available. `helm template` is fully offline and produces identical rendered output without any cluster interaction

### Required GitHub Secrets

Add these in **Repo → Settings → Secrets and variables → Actions**:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS access key for Terraform plan |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for Terraform plan |
| `DOCKERHUB_USERNAME` | Docker Hub username for image push |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not password) |

---

## Docker Image

The application image uses a **multi-stage distroless build** to minimise the attack surface:

- Build stage: `node:20-alpine` — copies application files
- Final stage: `gcr.io/distroless/nodejs20-debian12` — no shell, no package manager, runs as non-root by default

This approach significantly reduces the number of vulnerabilities compared to a standard Node base image.

### Build Locally

```bash
docker build -t myapp-api:local .
```

---

## Design Decisions

**Why separate the backend from `providers.tf`?**
Keeping the S3 backend in a gitignored `backend.tf` lets the CI pipeline run `terraform init -backend=false` without AWS credentials for state access, while real deployments use the full backend. It's a clean separation between CI validation and actual state management.

**Why distroless over alpine?**
Alpine reduces image size but still ships a shell and package manager — both unnecessary in production and potential attack vectors. Distroless ships only the runtime, cutting the vulnerability surface down to near zero.

**Why is `replicas` omitted from the Deployment when HPA is enabled?**
If both are set, the Deployment manifest and the HPA fight each other — every Terraform or Helm apply would reset the replica count that the HPA is actively managing. Omitting it lets the HPA own scaling entirely.

**Why one NAT Gateway per AZ?**
A single NAT Gateway is a single point of failure. If the AZ hosting it goes down, all private subnet traffic in other AZs loses internet access. One per AZ keeps egress resilient, at the cost of slightly higher spend.

**Why `ignore_changes` on `desired_size` in the node group?**
The cluster autoscaler modifies `desired_size` at runtime. Without `ignore_changes`, the next `terraform apply` would reset it back to the value in code, potentially removing nodes the autoscaler added under load.

**Why `helm template` instead of `helm install --dry-run` in CI?**
Even with `--dry-run=client`, Helm still tries to connect to a Kubernetes cluster to fetch the server version before rendering templates. In CI there's no cluster, so it fails with "connection refused". `helm template` is fully offline — it renders all manifests locally and produces identical output without touching any cluster. It's the right tool for template validation in a pipeline.