# Project Concept: DevOps Pipeline for Spring PetClinic
**Author:** Moetaz Cherni
**Registration Number:** 109463
**Repository:** https://github.com/ChMoetaz/DevOps_PetCli

---

## 1. The Application

The app I'm working with is **Spring PetClinic**, a Spring Boot web application that manages a veterinary clinic — owners, pets, visits, and vets. It's already on GitHub at https://github.com/ChMoetaz/DevOps_PetCli and has a Dockerfile in place, so the goal of this project is to build a proper automated pipeline around it and deploy it to the cloud.

### 12-Factor Compliance

Spring PetClinic fits the 12-factor app model well enough for this project:

| Factor | How |
|---|---|
| **I – Codebase** | One Git repo, one codebase deployed everywhere |
| **II – Dependencies** | Everything declared in `pom.xml`, nothing installed manually |
| **III – Config** | DB credentials and active profile passed as environment variables, not hardcoded |
| **IV – Backing services** | MySQL is just an attached resource, swappable without touching the code |
| **VI – Processes** | The app is stateless — no session data stored in memory |
| **VII – Port binding** | Port is configurable via `SERVER_PORT` |
| **IX – Disposability** | Starts fast, shuts down cleanly via Spring Actuator |
| **X – Dev/prod parity** | Same Docker image runs in all environments |
| **XI – Logs** | Logs go to stdout and get picked up by the platform |

---

## 2. Tech Stack

| Component | Tool | Why |
|---|---|---|
| Application | Spring PetClinic (Spring Boot 3, Java 21) | Already exists, already works |
| Build | Maven (`./mvnw`) | Already set up in the project |
| Version Control | GitHub | Where the code lives |
| CI/CD | GitLab CI | No extra server to set up; the pipeline lives in the repo as a `.yml` file |
| Code Quality | SonarQube | Catches bugs and bad code patterns in the source |
| Dependency Security | OWASP Dependency-Check | Checks third-party libraries for known security issues |
| Container Registry | Google Artifact Registry | Private image storage, works natively with GCP |
| Containerisation | Docker | Same image runs everywhere, no "works on my machine" issues |
| Orchestration | Google Kubernetes Engine (GKE) | Runs the containers, handles restarts and updates automatically |
| Infrastructure as Code | Terraform | All GCP resources defined in files so nothing is manually clicked |
| Database | MySQL 8 via Google Cloud SQL | PetClinic supports MySQL out of the box; Cloud SQL handles backups and maintenance |
| Secrets | Google Secret Manager + External Secrets Operator | Keeps passwords out of the code and out of the pipeline |
| Monitoring | Cloud Monitoring + Prometheus + Grafana | Covers both infrastructure and app-level metrics |
| Logging | Google Cloud Logging | GKE sends all container logs there automatically |
| TLS / DNS | Google-managed certificate + Cloud DNS | HTTPS with auto-renewal, DNS managed in GCP |

---

## 3. Infrastructure

Everything runs on **GCP**. The infrastructure is set up using **Terraform** — so instead of clicking around in the GCP console, everything is defined in `.tf` files in the `/infra` folder and created automatically. Terraform's state file is stored in a GCS bucket so it doesn't get lost.

What Terraform sets up:

- A private VPC network
- A GKE Autopilot cluster (GCP handles the nodes, I just deploy to it)
- A Cloud SQL MySQL 8 instance (private IP only, not exposed to the internet)
- Google Artifact Registry for Docker images
- Cloud DNS zone and domain records
- IAM service accounts with Workload Identity (pods can talk to GCP services without passwords)
- Secret Manager entries for database credentials

The Kubernetes manifests (what actually runs in the cluster) live in `/k8s` and are applied by the pipeline separately — infrastructure changes and app deployments happen on different schedules, so they're kept apart.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           GCP Project                               │
│                                                                     │
│   GitHub ──── GitLab CI ──────────────────────────────────────┐    │
│   (source)   (pipeline)   Build → Test → Push image           │    │
│                                                                │    │
│   ┌────────────────────────┐                                   │    │
│   │  Google Artifact       │◀──────────────────────────────────┘    │
│   │  Registry (images)     │                                        │
│   └────────────┬───────────┘                                        │
│                │ pull image                                         │
│   ┌────────────▼───────────────────────────────────────┐           │
│   │         Google Kubernetes Engine (GKE Autopilot)   │           │
│   │                                                    │           │
│   │  namespace: staging      namespace: production      │           │
│   │  ┌────────────────┐      ┌────────────────────┐    │           │
│   │  │ petclinic pod  │      │  petclinic pod(s)  │    │           │
│   │  │ (1 replica)    │      │  (2+ replicas)     │    │           │
│   │  └────────────────┘      └────────────────────┘    │           │
│   └────────────┬───────────────────────┬───────────────┘           │
│                │                       │                            │
│   ┌────────────▼───────────────────────▼───────────┐               │
│   │  Cloud Load Balancer (HTTPS, TLS termination)  │               │
│   │  staging.petclinic.example.com                 │               │
│   │  petclinic.example.com                         │               │
│   └────────────────────────────────────────────────┘               │
│                                                                     │
│   ┌──────────────────┐   ┌──────────────────┐                      │
│   │  Cloud SQL MySQL │   │  Secret Manager  │                      │
│   │  (private IP)    │   │  (DB credentials)│                      │
│   └──────────────────┘   └──────────────────┘                      │
│                                                                     │
│   ┌──────────────────────────────────────────────┐                 │
│   │  Cloud Monitoring + Cloud Logging            │                 │
│   │  Prometheus (in-cluster) + Grafana           │                 │
│   └──────────────────────────────────────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Environments

Three environments are planned, separated at the Kubernetes namespace level — staging and production run in the same GKE cluster but can't reach each other's services or databases.

| Environment | Where | Trigger | Replicas | Database |
|---|---|---|---|---|
| `dev` | Local (docker-compose) | Any feature branch push | — | H2 in-memory |
| `staging` | GKE namespace `staging` | Merge to `main` | 1 | Cloud SQL MySQL (small) |
| `production` | GKE namespace `production` | Git tag `v*` | 2+ | Cloud SQL MySQL (full) |

Dev runs locally using docker-compose with the default H2 in-memory database — no cloud costs, no setup needed. Staging and production both run on GKE but in isolated namespaces with their own secrets and resource limits.

The pipeline tells them apart using branch and tag rules:

```yaml
deploy:staging:
  environment: staging
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:production:
  environment: production
  rules:
    - if: $CI_COMMIT_TAG =~ /^v.*/
  when: manual
```

Production deployments require a manual trigger so nothing goes live by accident.

---

## 5. Pipeline / App Lifecycle

GitLab CI mirrors the GitHub repo, so every push to GitHub kicks off the pipeline automatically within seconds.

```
Developer pushes to GitHub
         │
         ▼
GitLab picks up the change (mirror)
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│  BUILD                                                  │
│  Compile with Maven, build Docker image,                │
│  tag with the commit SHA, push to Artifact Registry     │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  TEST                                                   │
│  Unit + integration tests (Maven)                       │
│  SonarQube code analysis                                │
│  OWASP dependency scan                                  │
└────────────────────────┬────────────────────────────────┘
                         │ on merge to main
                         ▼
┌─────────────────────────────────────────────────────────┐
│  DEPLOY STAGING                                         │
│  Apply k8s manifests to staging namespace               │
│  Wait for rollout, run a smoke test                     │
└────────────────────────┬────────────────────────────────┘
                         │ on git tag v*, manual approval
                         ▼
┌─────────────────────────────────────────────────────────┐
│  DEPLOY PRODUCTION                                      │
│  Apply k8s manifests to production namespace            │
│  Rolling update, old pods stay up until new ones ready  │
└─────────────────────────────────────────────────────────┘
```

The Docker image is the only artifact that gets stored — tagged with the commit SHA so you can always trace what's running back to a specific commit. No JAR files published separately.

---

## 6. Zero-Downtime Deployments

Kubernetes handles this with a rolling update strategy:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

With `maxUnavailable: 0`, the old pod only gets removed after the new one is up and passing its health check. The health check hits Spring Boot's `/actuator/health` endpoint — if the app isn't ready yet, Kubernetes won't send traffic to it.

Rolling back is straightforward — just re-deploy the previous image tag:

```bash
kubectl set image deployment/petclinic \
  petclinic=europe-west3-docker.pkg.dev/PROJECT/petclinic:PREVIOUS_SHA \
  -n production
```

---

## 7. Database

MySQL 8 runs as a Cloud SQL managed instance. It's only accessible via a private IP — nothing is exposed to the internet. Backups run daily with 7-day retention, and in production there's a standby replica for failover.

The app connects through the **Cloud SQL Auth Proxy**, which runs as a sidecar container next to the app. It authenticates using Workload Identity, so no database password needs to be stored in the container or passed as a plain environment variable.

Schema changes are handled by **Flyway**, which is built into Spring Boot. On startup it checks what migrations have already run and applies any new ones automatically.

In dev, the default H2 in-memory database is used so there's nothing to set up locally.

---

## 8. TLS, Domains, and DNS

HTTPS is terminated at the **Cloud Load Balancer**. Google issues and renews the TLS certificate automatically — no manual certificate work needed.

| Environment | Domain |
|---|---|
| Staging | `staging.petclinic.example.com` |
| Production | `petclinic.example.com` |

DNS is managed in **Cloud DNS**. Terraform creates the zone and points the domain records to a static IP reserved for the load balancer. The Kubernetes Ingress references both the certificate and the static IP:

```yaml
annotations:
  kubernetes.io/ingress.global-static-ip-name: "petclinic-prod-ip"
  networking.gke.io/managed-certificates: "petclinic-cert"
```

---

## 9. Monitoring and Logging

### What gets monitored

| What | Tool |
|---|---|
| Node and pod resource usage (CPU, memory) | Google Cloud Monitoring |
| Pod crashes and restarts | Google Cloud Monitoring |
| App request rate, latency, error rate | Prometheus scraping `/actuator/prometheus` |
| Database query performance | Cloud SQL Insights |
| Pipeline health | GitLab CI analytics |

Grafana runs inside the cluster and connects to both Prometheus and Cloud Monitoring for dashboards. Alerts go out via email when pods crash or error rates spike.

### Logging

The app logs to stdout in JSON format. GKE ships those logs to **Cloud Logging** automatically — no log agent needed. Logs can be filtered by namespace, pod, or severity and are kept for 30 days.

---

## 10. Repo Structure

```
/
├── .gitlab-ci.yml          # Pipeline
├── Dockerfile              # Multi-stage: build JAR → runtime image
├── docker-compose.yml      # Local dev setup
├── pom.xml
├── src/
│   └── main/resources/
│       ├── application.properties
│       └── db/migration/   # Flyway scripts
├── k8s/
│   ├── base/               # Shared manifests
│   ├── staging/            # Staging-specific config
│   └── production/         # Production-specific config
└── infra/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```