# Interview Answers

## 1. Terraform & AWS — State Management

S3 + DynamoDB is the standard here. S3 holds the state file, DynamoDB handles the locking — when one engineer runs `apply`, a lock is written to the table and everyone else gets blocked until it's released. I'd also make sure the S3 bucket has versioning enabled so you can roll back a bad state, and KMS encryption so the state file (which often contains sensitive outputs) isn't sitting in plaintext.

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-lock"
    encrypt        = true
  }
}
```

The DynamoDB table just needs a `LockID`.

---

## 2. Kubernetes Networking — Service Types

- **ClusterIP** — internal only, for service-to-service traffic inside the cluster
- **NodePort** — opens a port on every node, mostly useful for local testing
- **LoadBalancer** — provisions a cloud load balancer, works but gets expensive fast if you're doing it per-service

In production EKS I'd use an **Ingress with the AWS Load Balancer Controller**. One ALB handles routing for multiple services based on host or path rules, TLS termination is clean, and it's far cheaper than spinning up a separate NLB/ALB per service. NodePort and bare LoadBalancer services have their place but I wouldn't expose a production web app with either.

---

## 3. ArgoCD — Self-Healing vs. Automated Pruning

As soon as that `kubectl` change lands, ArgoCD sees the live state diverge from Git and marks the app **OutOfSync**.

If **Self-Healing** is enabled, ArgoCD reverts it, replicas go back to 3, the manual change is gone. That's the relevant feature here since a resource was modified, not deleted.

**Automated Pruning** is a different thing, it handles resources that exist in the cluster but have been removed from Git. ArgoCD will delete them. Without pruning enabled, orphaned resources just sit there silently, which can cause subtle issues over time.


---

## 4. Kafka — Scaling Consumer Lag

Three things I'd look at:

1. **Add more consumers to the group** — Kafka distributes partitions across consumers, so more consumers means more parallel processing. The ceiling is the partition count though; extra consumers beyond that just sit idle.

2. **Increase partitions** — if you've already hit that ceiling, add partitions to the topic. Just be aware this is a one-way operation on an existing topic and can affect ordering guarantees.

3. **Speed up the consumer itself** — sometimes the bottleneck isn't throughput, it's slow processing per message. Batching, async I/O, or offloading heavy work to a thread pool can make a big difference without touching Kafka's config at all.

I'd check consumer processing time before jumping straight to scaling .

---

## 5. Helm — Multi-Environment Configuration

One chart, multiple values files:

```
chart/
  values.yaml          # shared defaults
  values.dev.yaml
  values.staging.yaml
  values.prod.yaml
```

Deploy with:

```bash
helm upgrade --install my-app ./chart \
  -f values.yaml \
  -f values.prod.yaml
```

Later files override earlier ones, so prod-specific things like stricter resource limits, the real ingress hostname, or higher replica counts live in `values.prod.yaml` and don't touch the base file. The chart templates just reference `{{ .Values.whatever }}` and don't need to know which environment they're running in. Keeps things clean and auditable.

---

## 6. GitHub Actions — Keyless AWS Auth

OIDC. No static keys at all.

You set up a trust policy on an IAM role that allows GitHub's OIDC provider to assume it, scoped to your specific repo and branch. The workflow then uses `aws-actions/configure-aws-credentials` with `role-to-assume`:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-deploy-role
    aws-region: us-east-1
```

GitHub and AWS handle the token exchange behind the scenes. You get short-lived credentials per workflow run — nothing to rotate, nothing to leak. Storing `AWS_ACCESS_KEY_ID` in GitHub Secrets is the old way and I'd avoid it for anything beyond a quick personal project.

---

## 7. Kubernetes — OOMKilled with Free Node RAM

The container's memory `limit` is too low. This trips people up — Kubernetes enforces limits at the container level via Linux cgroups, not at the node level. So it doesn't matter that the node has free RAM; if the container exceeds its own limit, the kernel kills it.

Fix is to raise the memory `limit` in the pod spec. I'd also check whether `requests` actually reflects the app's real baseline, if requests are set too low, the scheduler might place the pod on a node that can't realistically support it under load, and you end up chasing the same problem again.

---

## 8. Terraform Refactoring — Moved Block

The `moved` block. When you move a resource into a module, its address changes — `aws_vpc.main` becomes `module.vpc.aws_vpc.main` — and Terraform plans a destroy/create because it thinks it's a new resource.

```hcl
moved {
  from = aws_vpc.main
  to   = module.vpc.aws_vpc.main
}
```

That tells Terraform it's the same resource at a new address. The plan will show a move instead of a replacement, no infrastructure is touched, and you can delete the `moved` block after everyone on the team has applied. I've seen people reach for `terraform state mv` for this but the `moved` block is cleaner — it's tracked in code and reviewable in a PR.

---

## 9. Kafka on Kubernetes — StatefulSet

StatefulSet with `volumeClaimTemplates`. A Deployment won't cut it here because pods are interchangeable — they get random names, share storage, and don't maintain identity across restarts.

Kafka brokers need two things a StatefulSet gives you: stable network identity (`kafka-0`, `kafka-1`, etc.) used in broker configs and leader election, and their own PersistentVolumeClaim that survives pod restarts so the broker's log data doesn't vanish. Without that, every restart is essentially a fresh broker and the cluster has to re-replicate data constantly.

---

## 10. CI/CD — Commit to Production

```
Git Push
  → GitHub Actions (CI)
      → Lint, test, security scan
      → Build Docker image, push to ECR tagged with commit SHA
      → Update image tag in GitOps repo (values file or kustomization)

  → ArgoCD (CD)
      → Detects the manifest change in Git
      → Syncs to the cluster, does health checks
      → Rolls back automatically if the rollout fails
```

CI ends when the artifact is built and the desired state in Git is updated. CD begins when ArgoCD picks that up. The pipeline never talks to the cluster directly — ArgoCD does, and it only trusts Git. That separation matters: it means your cluster state is always auditable, rollbacks are just git reverts, and you're not giving the CI system direct cluster credentials.