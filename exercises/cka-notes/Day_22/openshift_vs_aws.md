# OpenShift ↔ AWS — service mapping

Not CKA material: job knowledge. OpenShift = Red Hat's Kubernetes distribution (OKD = community upstream). See the short intro in [`cka_notes_cluster_install.md`](cka_notes_cluster_install.md).

## Compute

| AWS | OpenShift | Note |
|---|---|---|
| EC2 | **OpenShift Virtualization** (KubeVirt) | VMs managed as K8s objects, next to pods |
| ECS / EKS | **OpenShift itself** | Deployments, StatefulSets… |
| Fargate | no exact equivalent | nodes are yours, devs never see them |
| Lambda | **OpenShift Serverless** (Knative Serving + Functions) | scale-to-zero, still containers |
| Step Functions | **OpenShift Serverless Logic** (SonataFlow) | workflow orchestration |
| Batch | Jobs / CronJobs | native |

## Messaging & events

| AWS | OpenShift |
|---|---|
| EventBridge / SNS | **Knative Eventing** |
| MSK (Kafka) | **Streams for Apache Kafka** (ex AMQ Streams, Strimzi) |
| SQS / Amazon MQ | **AMQ Broker** (ActiveMQ Artemis) |

## Network

| AWS | OpenShift |
|---|---|
| ALB | **Routes** / Ingress (built-in HAProxy router) |
| NLB | `LoadBalancer` Services + **MetalLB** on bare metal |
| VPC, Security Groups | OVN-Kubernetes + **NetworkPolicies** |
| App Mesh / VPC Lattice | **OpenShift Service Mesh** (Istio) |
| API Gateway | **3scale**, being replaced by **Connectivity Link** |
| Route 53 | nothing native: company DNS, ExternalDNS operator |

## Storage & backup

| AWS | OpenShift |
|---|---|
| EBS | **OpenShift Data Foundation** (Ceph RBD), or existing SAN via its CSI driver |
| EFS | Data Foundation (CephFS), or NFS NAS |
| S3 | Data Foundation (Ceph RGW / NooBaa, S3-compatible) |
| AWS Backup | **OADP** (OpenShift API for Data Protection) = Velero |

## CI/CD & registry

| AWS | OpenShift |
|---|---|
| ECR | internal registry, or **Red Hat Quay** |
| CodeBuild | **Builds for OpenShift** (Shipwright), S2I |
| CodePipeline | **OpenShift Pipelines** (Tekton) |
| CodeDeploy | **OpenShift GitOps** (ArgoCD) |
| (Proton / Service Catalog) | **Red Hat Developer Hub** (Backstage) |

## Identity & security

| AWS | OpenShift |
|---|---|
| IAM | RBAC + built-in OAuth server |
| Cognito / IAM Identity Center | **Red Hat build of Keycloak** |
| SCP, AWS Config | **SCC** + ACM governance policies (Gatekeeper / Kyverno possible) |
| GuardDuty, Inspector, Security Hub | **Advanced Cluster Security** (StackRox): image scan, runtime detection, compliance |
| Secrets Manager | K8s Secrets + External Secrets Operator / Vault |
| KMS | nothing native: external HSM or Vault |

## Observability & management

| AWS | OpenShift |
|---|---|
| CloudWatch Metrics / Alarms | built-in **Monitoring** (Prometheus + Alertmanager) |
| CloudWatch Logs | **Logging** (Loki) |
| X-Ray | **Distributed Tracing** (Tempo + OpenTelemetry) |
| Organizations / Control Tower | **Advanced Cluster Management** (cluster fleet) |
| Cost Explorer | **Cost Management** |
| CloudFormation | no equivalent: Operators + GitOps, Ansible or Terraform |
| Console | **web console** (per cluster; ACM console for a fleet) |

## Data & AI

| AWS | OpenShift |
|---|---|
| SageMaker / Bedrock | **Red Hat OpenShift AI** |
| RDS, Aurora, DynamoDB, ElastiCache | **no managed service**: vendor Operators (Crunchy/EDB Postgres, MongoDB, Redis…), operated by you |

## Keep in mind

- **Almost everything is optional**, installed as an Operator. Some pieces (ACM, ACS, Quay, Data Foundation, OpenShift AI) are **paid extras** or bundled in higher tiers (OpenShift Platform Plus).
- **Operations is the big difference**: on AWS, RDS/S3 are run by AWS. Here Ceph, Kafka, Postgres run on *your* cluster → upgrades, backups and outages are your team's job.
- **Red Hat product names change often** (AMQ Streams, 3scale…) → check before quoting them in an interview.
