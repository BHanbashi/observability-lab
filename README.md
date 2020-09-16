# Service Mesh Observability
## Layer 7 Observability with Consul Service Mesh and ProGraf


### What?
Learn how to observe the behaviour of your interservice communication in real-time.
The intelligence you gather will enable you to tune your platform for higher levels of performance, to more readily diagnose problems, and for security purposes.

### How?
Use Grafana to observe Consul-Connect service-mesh metrics collected by Prometheus

### Still What?
1. Configure Consul to expose Envoy metrics to Prometheus
2. Deploy Consul using the official helm chart
3. Deploy Prometheus and Grafana using their official Helm charts
4. Deploy a multi-tier demo application that is configured to be scraped by Prometheus
5. Start a traffic simulation deployment, and observe the application traffic in Grafana

### Pre-requites…
Most people can run this on their laptops, and if you can then this is the recommended approach. If your laptop runs out of steam, try it on Sandbox. 

You'll need `curl, jq, vim, git, make, docker, helm, and kubectl` installed. These tools already exist in the sandbox, but you might have to install them onto your local machines if you are running the lab there. They generally useful for everything we're doing anyway, so why not?

## Let's start making things

You will progress faster if you use a makefile for your commands. Start with the following and we'll add more to it as we progress:

**`Makefile`**
```makefile
.PHONY: up down cluster install list

all: up install

up: cluster init

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

Running `make` or `make cluster` will create a k3d cluster capable of running this lab. You are all familiar with makefiles so we won’t delve into this file any further, but we will be adding more to it as we proceed. Note though that we have asked K3D not to install `Traefik` as an ingress controller. We will use `ingress-nginx` for this lab if necessary.

The `list` target exists to examine, and possibly debug, our work via helm.

There are a few more namespaces and repos in that makefile than we'll use immediately in this lab. They are for future expansion.

### Installing Consul
We will install consul from the official helm chart, with the following values which are in kept in the `helm` directory:

**`helm/consul-values.yaml`**
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
	helm install consul hashicorp/consul -f helm/consul-values.yaml -n consul | tee -a output.log

delete-consul:
	helm delete -n consul consul
```

The `| tee -a output.log` command allows stdout to be both written to the terminal and appended to a file simultaneously. This is how we keep a copy of all the output we create for later.

Before you run `make install` you'll have to run `make init` to create the required namespaces and install the correct helm repos.

> This is a lab quality consul installation. For production hardening, please review [Secure Consul on K8S](https://learn.hashicorp.com/tutorials/consul/kubernetes-secure-agents)

### Installing Prometheus & Grafana

We need values files for both of these components:

**`helm/prometheus-values.yaml`**
```yaml
server:
  persistentVolume:
    enabled: false
alertmanager:
  enabled: false
```

We are disabling the alert manager because we're not using it for this lab. In a production environment you would want alerts enabled and you would want to configure them to let you know via email, slack, and other more formal and continuosly monitored channels (ServiceNow for example) if there is any kind of systemic outage that you need to attend to.

Also, because this is a lab environment, we're not going to need to persist prometheus' data for later, so we're disabling the persistent volume capability.

**`helm/grafana-values.yaml`**
```yaml
adminUser: wibble
adminPassword: "pleasechangethispassword.IthasbeencommittedincleartexttoGitHut."

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server
      access: proxy
      isDefault: true
service:
  type: NodePort
  targetPort: 3000
```

We have exposed a NodePort to make using the service a little easier, and set the admin user and password to a static value to make using it easy.

**`Makefile`**
```makefile
install: install-consul install-prometheus install-grafana

install-prometheus:
	helm install -f helm/prometheus-values.yaml prometheus prometheus-community/prometheus -n prograf | tee -a output.log

delete-prometheus:
	helm delete -n prograf prometheus

install-grafana:
	helm install -f helm/grafana-values.yaml grafana grafana/grafana -n prograf | tee -a output.log

delete-grafana:
	helm delete -n prograf grafana
```

> *Please, change the `install` target rather than creating a new one*

You can use `kubectl` to find grafana's service NodePort and use this to navigate to grafana in a browser. You should login and keep the page open as you'll need it soon.

---

### Demo App
Included in the `demo-app` folder are the manifests for a Hashicorp app used for demonstrations (hence the name) called **HashiCup**: ***an application that emulates an online order app for a coffee shop***. For this lab, the app includes a `React` front end, a `GraphQL` API, a REST API and a `Postgres` database.

Examine the `demo-app/frontend.yaml` file. It contains the following prometheus configuration:

```yaml
prometheus.io/scrape: 'true'
prometheus.io/port: '9102'
```

We have applied the same config to the other objects/resources/manifes in the app. You'll have to do something similar in your apps if you want the same behaviour. This allows Prometheus to discover resources in the K8S cluster that should be exposing metrics (data producers), and tells Prometheus what port to the metrics are exposed at. The proxyDefaults entry in the `consul-values.yaml` file that you created earlier, along with the envoy_prometheus_bind_addr (0.0.0.0:9102), is configuring the data consumer (sink). You configured Consul and Envoy to publish metrics on port 9102, and now you have configured  Prometheus to subscribe on each proxy at port 9102.

We have deployed this to the `default` namespace. Use `kubectl get services` to find the port we have exposed the frontend on and navigate to it your browser. This will be on localhost if you're running this locally, or on your ec2 instance's public-ip if you're running in the sandbox.

You can scroll the coffee cup left and right and pay for it with a mock fingerprint-scanner. It's not a very complicated app really.

![HashiCup](https://learn.hashicorp.com/img/consul-hashicups-frontend.png)


Now, let's confirm that consul did configure Envoy to publish metrics on port 9102. The Envoy side-car proxy can be reached at port 19000. Open a new terminal, and issue the following command:

```bash
kubectl port-forward deploy/frontend 19000:19000
```

Then in a different terminal (on the same machine, obvs.):

```bash
curl localhost:19000/config_dump | jq -C '.' | less -R
```

This should return a really long json file. Search it for 9102 -- there should be 2 entries for it.

> **Hint**: use <kbd>/</kbd> while viewing the output in `less` to search for that and you can use <kbd>j</kbd> and <kbd>k</kbd> like in `vim` in order to scroll up and down 


The configuration matches the configuration in the `proxyDefaults` entry in the `consul-values.yaml` file. This shows that Consul has configured Envoy to publish Prometheus metrics. You can stop the port-forwarder now (<kbd>ctrl</kbd>+<kbd>c</kbd>)

### Simulate Traffic
We have a tool, also from Hashi, that will generate traffic for the HashiCup application. Strangely enough this is called *Traffic*. Don't confuse this with Traefik, the ingress controller that ships by default with K3S as they are totally different things.

If you change to the branch `traffic` you'll find a new file in the root called `traffic.yaml`. It's too long to post here so I've just given it to you to use directly. 

When you apply this file to kubernetes it will immediately start exercising the components of the demo-app to generate traffic that we can monitor with Consul, Prometheus, and Grafana.

### Lies, Damn Lies, and Statistics
Envoy exposes a huge amount of metrics. Which ones you want to see is an application and task specific issue.

For now we have preconfigured a Grafana dashboard with a couple of basic metrics, but you should systematically consider what others you will need to collect as you move from testing into production.

You'll find the grafana dashboard spec in the file `hashicups-dashboard.json`, also in the `traffic` branch. You can go back to the grafana tab in your browser now. Hit the big **+** symbol on the left and select **import**, then hit the big blue **Upload JSON file** button and select the `hashicups-dashboard.json` we mentioned at the top of this paragraph. Alternatively, you might get away with pasting the contents of that file in the tiny little text box they've provided for lamers who can't download/upload a file :)

---
# Retrospective
In this lab, you set up layer 7 metrics collection and visualization in a Kuberenetes cluster using Consul service mesh, Prometheus, and Grafana, all deployed via Helm charts. Specifically, you:

1. Configured Consul and Envoy to expose application metrics to Prometheus
2. Deployed Consul using the official helm chart
3. Deployed Prometheus and Grafana using their official Helm charts
4. Deployed a multi-tier demo application that was configured to be scraped by Prometheus
5. Started a traffic simulation deployment, and observed the metrics in Grafana

---
# Lab Extension

# Nginx Ingress controller

The Nginx ingress controller is perhaps the most popular in the inudstry. You're going to add it to this application to expose the Grafana dashboard.

The `nginx` branch has the necessary files. Unlike the previous half of the lab, you're not getting any more help with this one. I have provided the nginx installation commands in the makefile, and a values file that you can get started with.

I will give you 2 clues though -- you can google for the answer, and:

```bash
helm show values ingress-nginx/ingress-nginx
```