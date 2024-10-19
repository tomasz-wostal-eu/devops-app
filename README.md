# DevOps App - Local Kubernetes Development Environment

## Overview

This repository provides a Makefile to help you set up a local Kubernetes cluster using Kind, bootstrap it with Argo CD, install Prometheus, Sealed Secrets, and other components necessary for a complete local development setup for cloud-native applications. This setup aims to make it easy to develop, test, and integrate cloud-native tools in an isolated and reproducible environment.

## Prerequisites

- [Kind](https://kind.sigs.k8s.io/): Used to create local Kubernetes clusters.
- [Helm](https://helm.sh/): Package manager for Kubernetes.
- [kubectl](https://kubernetes.io/docs/tasks/tools/): Kubernetes command-line tool.
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets): For managing Kubernetes secrets securely.
- [openssl](https://www.openssl.org/): For creating self-signed certificates.
- [htpasswd](https://httpd.apache.org/docs/2.4/programs/htpasswd.html): For creating basic authentication credentials.

## Setup Instructions

### 1. Environment Variables

This Makefile uses a `.env` file to store environment variables. Make sure you have the following variables set in `.env`:

- `ARGOCD_PASSWORD`
- `GITHUB_ORGANIZATION`
- `CLOUDFLARE_API_KEY`
- `CLOUDFLARE_EMAIL`
- `CERT_EMAIL`, `CN`, `C`, `ST`, `L`, `O`, `OU` (for Certificate Authority)
- `MINIO_USERNAME`, `MINIO_PASSWORD`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`
- `LOKI_USERNAME`, `LOKI_PASSWORD`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `DA_WEBHOOK_SECRET`, `DA_GITHUB_TOKEN`

### 2. Create a Local Kubernetes Cluster

To create a local Kubernetes cluster named `devops-toys` using Kind, run:

```sh
make cluster
```

### 3. Bootstrap Argo CD

To bootstrap the Argo CD installation, run:

```sh
make argo-cd-bootstrap
```

This will install Argo CD using Helm and set up a Git repository as an Argo CD application source.

### 4. Install Other Components

#### Prometheus Operator CRDs

```sh
make prometheus-operarator-cdrs
```

#### Sealed Secrets

```sh
make sealed-secrets
```

This step installs Sealed Secrets, which allows you to safely store Kubernetes secrets in Git.

### 5. Install Certificate Authority and Secrets for Cert-Manager

To create a Certificate Authority and set up Cert-Manager secrets:

```sh
make cert-manager
```

### 6. Install and Configure Cloudflare

To set up Cloudflare Tunnel and credentials secrets:

```sh
make cloudflare
```

### 7. Set Up External DNS with Cloudflare

To set up External DNS integration with Cloudflare:

```sh
make external-dns
```

### 8. Set Up MinIO and Storage Credentials

To create root credentials and user secrets for MinIO:

```sh
make minio
```

### 9. Configure Argo Workflows and Argo Events

To configure Argo Workflows and set up Git and Cloudflare secrets for Argo Events:

```sh
make argo-workflows
make argo-events
```

### 10. Configure Grafana, Loki, and Promtail

To set up Grafana, Loki, and Promtail:

```sh
make grafana
make grafana-loki
make grafana-promtail
```

### 11. Push Secrets to Git

Once all secrets are generated, push them to the repository:

```sh
make push-secrets
```

### 12. Bootstrap the Application

To bootstrap the application:

```sh
make bootstrap-app
```

### 13. Run All Steps

To run the entire setup process from cluster creation to application bootstrapping:

```sh
make all
```

### 14. Teardown

To destroy the Kubernetes cluster:

```sh
make destroy
```

## Notes

- The cluster is named `devops-toys` and uses a custom Kind configuration located at `./kind/cluster-devops-toys.yaml`.
- Secrets are sealed using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) to safely store them in version control.
- The Makefile contains various targets for creating namespaces, configuring secrets, and installing components such as Grafana, Loki, MinIO, Cloudflare, Argo CD, and others.

## License

This project is licensed under the Apache 2.0 License. See the LICENSE file for details.

