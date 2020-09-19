.PHONY: up down init cluster install demo-app

up: cluster init install

down:
	k3d cluster delete labs

list:
	helm list --all-namespaces

init: logs repos namespaces

logs:
	touch output.log

repos:
	helm repo add stable https://kubernetes-charts.storage.googleapis.com/
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update

namespaces:
	kubectl create namespace consul
	kubectl create namespace vault
	kubectl create namespace elf
	kubectl create namespace prograf
	kubectl create namespace ingress-nginx

cluster:
	k3d cluster create labs \
	    -p 80:80@loadbalancer \
	    -p 443:443@loadbalancer \
	    -p 30000-32767:30000-32767@server[0] \
	    -v /etc/machine-id:/etc/machine-id:ro \
	    -v /var/log/journal:/var/log/journal:ro \
	    -v /var/run/docker.sock:/var/run/docker.sock \
	    --k3s-server-arg '--no-deploy=traefik' \
	    --agents 3

install: install-consul install-vault install-grafana install-ingress-nginx install-prometheus install-demo-app

install-demo-app:
	kubectl apply -f demo-app

delete-demo-app:
	kubectl delete -f demo-app

install-consul:
	helm install consul hashicorp/consul -f helm/consul-values.yaml -n consul | tee -a output.log
	sleep 60

delete-consul:
	helm delete -n consul consul

install-vault:
	helm install vault hashicorp/vault -f helm/vault-values.yaml -n vault | tee -a output.log

delete-vault:
	helm delete -n vault vault

install-ingress-nginx:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-0.32.0/deploy/static/provider/cloud/deploy.yaml | tee -a output.log
delete-ingress-nginx:
	kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-0.32.0/deploy/static/provider/cloud/deploy.yaml | tee -a output.log
install-prometheus:
	helm install -f helm/prometheus-values.yaml prometheus prometheus-community/prometheus -n prograf | tee -a output.log

delete-prometheus:
	helm delete -n prograf prometheus

install-grafana:
	helm install -f helm/grafana-values.yaml grafana grafana/grafana -n prograf | tee -a output.log

delete-grafana:
	helm delete -n prograf grafana


