# Include environment variables
ENV	:= $(PWD)/.env
include $(ENV)
OS := $(shell uname -s)

# Create a local Kubernetes cluster
cluster:
	@if ! kind get clusters | grep -q '^devops-toys$$'; then \
		echo "Cluster 'devops-toys' not found. Creating..."; \
		kind create cluster --config ./kind/cluster-devops-toys.yaml; \
	else \
		echo "Cluster 'devops-toys' already exists."; \
	fi

# Bootstrap Argo CD
argo-cd-bootstrap:
	@echo "Installing initial version of Argo CD ..."
	@helm repo add argo https://argoproj.github.io/argo-helm --force-update
	@helm upgrade --install \
		argocd argo/argo-cd \
			--namespace argocd \
			--create-namespace \
			--set notifications.secret.create=false \
			--wait
	@kubectl apply -n argocd -f ./projects.yaml
	@kubectl port-forward -n argocd svc/argocd-server 10000:80 & echo $$! > /tmp/port-forward.pid & sleep 5
	@argocd login localhost:10000 --insecure --grpc-web --username admin --password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
	@argocd account update-password --current-password $$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --new-password $(ARGOCD_PASSWORD)
	@argocd repo add git@github.com:devops-toys/devops-app.git --ssh-private-key-path ./ssh-key-devops-app
	@kill $$(cat /tmp/port-forward.pid) && rm -f /tmp/port-forward.pid

# Add devops-toys repo to argocd
add-devops-app-repo:
	@echo "Adding 'devops-app' repo to argocd ..."
	kubectl --namespace argocd \
	create secret \
		generic repo-devops-app \
			--from-literal=type=git \
			--from-literal=url=git@github.com:$(GITHUB_ORGANIZATION)/devops-app.git \
			--from-file=sshPrivateKey=ssh-key-devops-app \
			--dry-run=client -oyaml | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets -oyaml - | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"argocd.argoproj.io/secret-type":"repository"}}}}}' \
			--dry-run=client \
			--type=merge \
			--local -oyaml > ./manifests/dev/argo-cd/secret-repo-devops-app.yaml
	@kubectl apply -f ./manifests/dev/argo-cd/secret-repo-devops-app.yaml

# Install Prometheus Operator CRDs
prometheus-operarator-cdrs:
	@echo "Installing Prometheus Operator CRDs ..."
	@kubectl apply -f ./applicationsets/prometheus-operator-crds.yaml
	@sleep 10

# Install Sealed Secrets
sealed-secrets:
	@echo "Installing Sealed Secrets ..."
	@kubectl apply -f ./applicationsets/sealed-secrets.yaml
	@sleep 60

# Create Certificate Authority
cert-manager-ca:
	@if kubectl get namespace cert-manager >/dev/null 2>&1; then \
		echo "Namespace cert-manager already exists."; \
	else \
		echo "Namespace cert-manager does not exist. Creating..."; \
		kubectl create namespace cert-manager; \
		echo "Namespace cert-manager has been created."; \
	fi
	@echo "Creating Certificate Authority (CA)"
	@openssl genrsa -out ca.key 4096
	@openssl req -new -x509 -sha256 -days 3650 \
		-key ca.key \
		-out ca.crt \
		-subj '/CN=$(CN)/emailAddress=$(CERT_EMAIL)/C=$(C)/ST=$(ST)/L=$(L)/O=$(O)/OU=$(OU)'

# Create cert-manager secrets
cert-manager-secret:
	@if kubectl get namespace cert-manager >/dev/null 2>&1; then \
		echo "Namespace cert-manager already exists."; \
	else \
		echo "Namespace cert-manager does not exist. Creating..."; \
		kubectl create namespace cert-manager; \
		echo "Namespace cert-manager has been created."; \
	fi
	@echo "Creating secrets for Cert Manager..."
	@kubectl --namespace cert-manager \
		create secret \
		generic devopslabolatory-org-ca \
			--from-file=tls.key=ca.key \
			--from-file=tls.crt=ca.crt \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets -oyaml - | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"annotations": {"argocd.argoproj.io/sync-wave":"0"}}}}}' \
			--dry-run=client \
			--type=merge \
			--local -oyaml > ./manifests/dev/cert-manager/secret-ca.yaml

cert-manager: cert-manager-ca cert-manager-secret

cloudflare-tunnel:
	@if [ ! -f ~/.cloudflared/cert.pem ]; then \
		echo "The cert.pem file does not exist. Running cloudflared tunnel login ..."; \
		cloudflared tunnel login; \
		cloudflared tunnel create devopslabolatory; \
	else \
		echo "The cert.pem file already exists."; \
	fi

# Create cloudflare tunnel credentials
cloudflare-tunnel-credentials-secret:
	@if kubectl get namespace cloudflare >/dev/null 2>&1; then \
		echo "Namespace cloudflare already exists."; \
	else \
		echo "Namespace cloudflare does not exist. Creating..."; \
		kubectl create namespace cloudflare; \
		echo "Namespace cloudflare has been created."; \
	fi
	@echo "Creating cloudflare tunnel credentials secret ..."
	kubectl --namespace cloudflare \
		create secret \
		generic tunnel-credentials \
			--from-file=credentials.json=$(HOME)/.cloudflared/$(CLOUDFLARE_TUNNEL_ID).json \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/cloudflare-tunnel/secret-tunnel-credentials.yaml > /dev/null

# Create cloudflare api key secret
cloudflare-api-key-secret:
	@if kubectl get namespace cloudflare >/dev/null 2>&1; then \
		echo "Namespace cloudflare already exists."; \
	else \
		echo "Namespace cloudflare does not exist. Creating..."; \
		kubectl create namespace cloudflare; \
		echo "Namespace cloudflare has been created."; \
	fi
	@echo "Creating cloudflare api key secret ..."
	@kubectl --namespace cloudflare \
		create secret \
		generic cloudflare-api-key \
			--from-literal=apiKey=$(CLOUDFLARE_API_KEY) \
			--from-literal=email=$(CLOUDFLARE_EMAIL) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/cloudflare-tunnel/secret-api-key.yaml > /dev/null

cloudflare: cloudflare-tunnel cloudflare-tunnel-credentials-secret cloudflare-api-key-secret

external-dns-cloudflare-secret:
	@if kubectl get namespace external-dns >/dev/null 2>&1; then \
		echo "Namespace external-dns already exists."; \
	else \
		echo "Namespace external-dns does not exist. Creating..."; \
		kubectl create namespace external-dns; \
		echo "Namespace external-dns has been created."; \
	fi
	echo "Creating external-dns cloudflare api key credentials secret ..."
	@kubectl --namespace external-dns \
		create secret \
		generic cloudflare-api-key \
			--from-literal=cloudflare_api_key=$(CLOUDFLARE_API_KEY) \
			--from-literal=email=$(CLOUDFLARE_EMAIL) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/external-dns/secret-cloudflare-api-key.yaml > /dev/null

external-dns: external-dns-cloudflare-secret

# Create argocd google oauth client secret
argocd-oauth-client-secret:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd oauth client secret ..."
	@kubectl --namespace argocd \
		create secret \
		generic argocd-google-oauth-client \
			--from-literal=client_id=$(GOOGLE_CLIENT_ID) \
			--from-literal=client_secret=$(GOOGLE_CLIENT_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
			--type=merge \
			--local -o yaml > ./manifests/dev/argo-cd/secret-argocd-google-oauth-client.yaml

# Create argocd google domain wide sa json secret
argocd-google-sa:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd google domain wide sa json secret ..."
	@kubectl --namespace argocd \
		create secret \
		generic argocd-google-domain-wide-sa-json \
			--from-file=googleAuth.json=devopslaboratory-f90072620e7c.json \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets -oyaml - | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
			--dry-run=client \
			--type=merge \
			--local -oyaml > ./manifests/dev/argo-cd/secret-argocd-google-sa.yaml

# Create argocd argo-workflows sso secret
argocd-argo-workflows-sso:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd argo-workflows sso secret ..."
	@kubectl --namespace argocd \
		create secret \
		generic argo-workflows-sso \
			--from-literal=client-id=$(ARGO_WORKFLOWS_CLIENT_ID) \
			--from-literal=client-secret=$(ARGO_WORKFLOWS_CLIENT_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		kubectl patch -f - \
			-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
			--type=merge \
			--local -oyaml > ./manifests/dev/argo-cd/secret-argo-workflows-sso.yaml

# Create argocd notifications secret
argocd-notifications-secret:
	@if kubectl get namespace argocd >/dev/null 2>&1; then \
		echo "Namespace argocd already exists."; \
	else \
		echo "Namespace argocd does not exist. Creating..."; \
		kubectl create namespace argocd; \
		echo "Namespace argocd has been created."; \
	fi
	echo "Creating argocd notifications secret ..."
	@kubectl --namespace argocd \
		create secret \
			generic argocd-notifications-secret \
				--from-file=github-privateKey=devops-toys.2024-10-04.private-key.pem \
				--output json \
				--dry-run=client | \
			kubeseal --format yaml \
				--controller-name=sealed-secrets \
				--controller-namespace=sealed-secrets -oyaml - | \
			kubectl patch -f - \
				-p '{"spec": {"template": {"metadata": {"labels": {"app.kubernetes.io/part-of":"argocd"}}}}}' \
				--dry-run=client \
				--type=merge \
				--local -oyaml > ./manifests/dev/argo-cd/secret-argocd-notifications.yaml

argo-cd: argocd-oauth-client-secret argocd-google-sa argocd-argo-workflows-sso argocd-notifications-secret

# Create argo argo-workflows sso secret
argo-workflows-sso-credentials:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	echo "Creating argo argo-workflows sso secret ..."
	@kubectl --namespace argo \
		create secret \
		generic argo-workflows-sso \
			--from-literal=client-id=$(ARGO_WORKFLOWS_CLIENT_ID) \
			--from-literal=client-secret=$(ARGO_WORKFLOWS_CLIENT_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/argo-workflows/secret-argo-workflows-sso.yaml > /dev/null

# Create argo git credentials
argo-workflows-git-credentials:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	@kubectl --namespace argo \
		create secret \
		generic git-credentials \
			--from-literal=token=$(WOSTAL_GITHUB_TOKEN) \
			--from-literal=username=$(WOSTAL_GITHUB_USERNAME) \
			--from-literal=email=$(WOSTAL_GITHUB_EMAIL) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/argo-workflows/secret-git-credentials.yaml > /dev/null

# Create argo devops-toys ssh key
argo-workflows-devops-toys-ssh-key:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	@echo "Creating argo devops-toys ssh key secret ..."
	kubectl --namespace argocd \
	create secret \
		generic repo-devops-app \
			--from-literal=url=git@github.com:$(GITHUB_ORGANIZATION)/devops-app.git \
			--from-file=sshPrivateKey=ssh-key-devops-app \
			--dry-run=client -oyaml | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/argo-workflows/secret-devops-toys-ssh-key.yaml > /dev/null

# Create argo argo-workflows storage secret
argo-workflows-storage-credentials:
	@if kubectl get namespace argo >/dev/null 2>&1; then \
		echo "Namespace argo already exists."; \
	else \
		echo "Namespace argo does not exist. Creating..."; \
		kubectl create namespace argo; \
		echo "Namespace argo has been created."; \
	fi
	echo "Creating argo argo-workflows storage secret ..."
	@kubectl --namespace argo \
		create secret \
		generic minio-creds \
			--from-literal=accesskey=${MINIO_USERNAME} \
			--from-literal=secretkey=${MINIO_PASSWORD} \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/argo-workflows/secret-storage-credentials.yaml > /dev/null

argo-workflows: argo-workflows-sso-credentials argo-workflows-git-credentials argo-workflows-devops-toys-ssh-key argo-workflows-storage-credentials

# Create argo argo-events devops-app webhook secret
argo-events-webhook-secret:
	@if kubectl get namespace argo-events >/dev/null 2>&1; then \
		echo "Namespace argo-events already exists."; \
	else \
		echo "Namespace argo-events does not exist. Creating..."; \
		kubectl create namespace argo-events; \
		echo "Namespace argo-events has been created."; \
	fi
	echo "Creating argo argo-events webhook secret ..."
	@kubectl --namespace argo-events \
		create secret generic webhook-secret-dt \
			--from-literal=secret=$(DA_WEBHOOK_SECRET) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/argo-events/secret-webhook-da.yaml > /dev/null

# Create argo argo-events github token
argo-events-github-token:
	@if kubectl get namespace argo-events >/dev/null 2>&1; then \
		echo "Namespace argo-events already exists."; \
	else \
		echo "Namespace argo-events does not exist. Creating..."; \
		kubectl create namespace argo-events; \
		echo "Namespace argo-events has been created."; \
	fi
	echo "Creating argo argo-events github token secret ..."
	@kubectl --namespace argo-events \
		create secret generic gh-token-dt \
			--from-literal=token=$(DA_GITHUB_TOKEN) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/argo-events/secret-gh-token-da.yaml > /dev/null

argo-events: argo-events-webhook-secret argo-events-github-token

# Create minio secret for root user
minio-root:
	kubectl --namespace minio \
		create secret \
		generic minio-root \
			--from-literal=root-user=$(MINIO_ROOT_USER) \
			--from-literal=root-password=$(MINIO_ROOT_PASSWORD) \
			--output json \
			--dry-run=client | \
		kubeseal --format yaml \
			--controller-name=sealed-secrets \
			--controller-namespace=sealed-secrets | \
		tee ./manifests/dev/minio/secret-minio-root.yaml

# Create minio users
minio-users:
	@./scripts/minio_users.sh "${MINIO_USERNAME}" "${MINIO_PASSWORD}"

minio: minio-root minio-users
	
# Push Secrets
push-secrets:
	@echo "Pushing secrets ..."
	@git add manifests
	@git commit -m "[skip ci] Update secrets"
	@git push

bootstrap-app:
	@echo "Installing Sealed Secrets ..."
	@kubectl apply -f ./bootstrap-app.yaml

# Run everything
all: 
	$(MAKE) cluster
	$(MAKE) argo-cd-bootstrap
	$(MAKE) prometheus-operarator-cdrs
	$(MAKE) sealed-secrets
	$(MAKE) add-devops-app-repo
	$(MAKE) cert-manager
	$(MAKE) cloudflare
	$(MAKE) external-dns
	$(MAKE) argo-cd
	$(MAKE) minio
	$(MAKE) argo-events
	$(MAKE) argo-workflows
	$(MAKE) push-secrets
	$(MAKE) bootstrap-app

# Teardown 
destroy:
	kind delete cluster --name devops-toys
