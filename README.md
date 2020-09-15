# Service Mesh Observability
## Layer 7 Observability with Consul Service Mesh and ProGraf


### What?
Learn how to observe the behaviour of your interservice communication in real-time.
The intelligence you gather will enable you to tune your platform for higher levels of performance, to more readily diagnose problems, and for security purposes.

### How?
Use Grafana to observe Consul-Connect service-mesh metrics collected by Prometheus

### Still What?
1. Configure Consul to expose Envoy metrics to Prometheus
2. Deploy Consul using the official helm chart.
3. Deploy Prometheus and Grafana using their official Helm charts.
4. Deploy a multi-tier demo application that is configured to be scraped by Prometheus.
5. Start a traffic simulation deployment, and observe the application traffic in Grafana.

### Pre-requites…
Most people can run this on their laptops, and if you can then this is the recommended approach. If your laptop runs out of steam, try it on Sandbox. You'll need docker, helm, and kubectl installed. The already exist in the sandbox, but you might have to install them onto your local machines if you are running the lab there.

## Getting started

You will progress faster if you use a makefile for your commands. Start with the following and we'll add more to it as we progress:

**`Makefile`**
```makefile
all: up install

up: init cluster

down:
	k3d cluster delete labs

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

```


> Note: If you intend to copy & paste this text in vim, watch out for transcription errors, especially with quote marks.

Running `make` or `make cluster` will create a k3d cluster capable of running this lab. You are all familiar with makefiles so we won’t delve into this file any further, but we will be adding more to it as we proceed. Note though that we have asked K3D not to install `Traefik` as an ingress controller. We will use `ingress-nginx` for this lab.

The `list` target exists to examine, and possibly debug, our work via helm.

## Installing Consul
We will install consul from the official helm chart, with the following values

**`consul-values.yaml`**
```yaml
global:
  name: consul
  datacenter: dc1

server:
  replicas: 1
  bootstrapExpect: 1
  disruptionBudget:
    enabled: true
    maxUnavailable: 0

client:
  enabled: true
  grpc: true

ui:
  enabled: true
  service:
    type: "NodePort"

connectInject:
  enabled: true
  default: true
  centralConfig:
    enabled: true
    defaultProtocol: 'http'
    proxyDefaults: |
      {
        "envoy_prometheus_bind_addr": "0.0.0.0:9102"
      }
```

The `centralConfig` section enables L7 telemetry and is configured for prometheus, though you could actually use any observer capable of storing and reporting on time-series data.

Review the `proxyDefaults` entry. This entry injects a proxy-defaults Consul configuration entry for the envoy_prometheus_bind_addr setting that is applied to all Envoy proxy instances. Consul then uses that setting to configure where Envoy will publish Prometheus metrics. This is important because you will need to annotate your pods with this port so that Prometheus can scrape them. We will cover this in more detail later in the tutorial.

We give the consul installation commands via make, as usual. Add the following to the Makefile:

**`Makefile`**
```makefile
install: install-consul

install-consul:
	helm install consul hashicorp/consul -f consul-values.yaml -n consul | tee -a output.log

delete-consul:
	helm delete -n consul consul
```

The `| tee -a output.log` command allows stdout to be both written to the terminal and appended to a file simultaneously. This is how we keep a copy of all the output we create for later.

Before you run `make install` you'll have to run `make init` to create the required namespaces and install the correct helm repos.

> This is a lab quality consul installation. For production hardening, please review [Secure Consul on K8S](https://learn.hashicorp.com/tutorials/consul/kubernetes-secure-agents)

