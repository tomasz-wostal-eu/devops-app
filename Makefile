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

# Install initial version of Argo CD
initial-argocd-setup:
	@echo "Installing initial version of Argo CD ..."
	@helm repo add argo https://argoproj.github.io/argo-helm --force-update
	@helm upgrade --install \
		argocd argo/argo-cd \
			--namespace argocd \
			--create-namespace \
			--set notifications.secret.create=false \
			--wait
	@kubectl apply -n argocd -f ./projects.yaml
	
# Install Prometheus Operator CRDs
prometheus-operarator-cdrs:
	@echo "Installing Prometheus Operator CRDs ..."
	@kubectl apply -f ./applicationsets/prometheus-operator-crds.yaml
	@sleep 10

# Run everything
all: cluster initial-argocd-setup

# Teardown 
destroy:
	kind delete cluster --name devops-toys
