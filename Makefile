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

# Run everything
all: 
	$(MAKE) cluster
	$(MAKE) argo-cd-bootstrap
	$(MAKE) prometheus-operarator-cdrs
	$(MAKE) sealed-secrets
	$(MAKE) add-devops-app-repo

# Teardown 
destroy:
	kind delete cluster --name devops-toys
