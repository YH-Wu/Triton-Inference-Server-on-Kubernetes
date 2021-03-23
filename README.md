---
title: Triton Inference Server on Kubernetes Hands on Lab
tags: NVIDIA, Kubernetes, Triton, DeepOps
description: 
---

# Preparation

You will need to prepare at least 3 nodes, one master node, one compute node with 2 GPUs or above and one provision node.


# Prerequisites

- **OS** : Ubuntu 20.04 or 18.04. 
- **GPU** : NVIDIA Pascal, Volta, Turing, and Ampere Architecture GPU families.
- **External NFS storage** : If you don’t have one, please refer to APPENDIX to build one.
- **IPs** : Available IPs for master node, provisioning node, compute node and load balancer.

# Build Kubernetes cluster by DeepOps

## Download DeepOps in Provision Node

We are going to use DeepOps to deploy kubernetes and related packages.

```
$ git clone https://github.com/NVIDIA/deepops.git
$ cd deepops
$ git checkout release-21.03
```

## Setup for Provision Node

This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the Ansible Guide.

```
$ scripts/setup.sh
```

## DeepOps Configuration

Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example inventory configuration to the config directory.
Edit the inventory:Edit inventory, fill in all nodes information in [ALL] section, master nodes in [kube-master] and [etcd] section, compute nodes in [kube-node] section.

```
$ vi config/inventory
```

[TODO]Screenshoot here

Verify the configuration, provision node should be able to reach each node by Ansible.

```
$ ansible all -m raw -a "hostname" -k -K -u <USERNAME> 
```

## Deploy Kubernetes cluster by Ansible

Set up NFS Client Provisioner

```
$ vi config/group_vars/k8s-cluster.yml 
```

The default behavior of DeepOps is to setup an NFS server on the first kube-master node. This temporary NFS server is used by the nfs-client-provisioner which is installed as the default StorageClass of a standard DeepOps deployment. You can also follow instructions to install NFS Server.[TODO]HyperLink.

To use an existing nfs server server update the k8s_nfs_server and k8s_nfs_export_path variables in config/group_vars/k8s-cluster.yml and set the k8s_deploy_nfs_server to false in config/group_vars/k8s-cluster.yml. 

Additionally, the k8s_nfs_mkdir variable can be set to false if the export directory is already configured on the server. In this lab, we will use an existing NFS server server, therefore we will modify following:

[TODO]Screenshoot here

Install Kubernetes using Ansible and Kubespray.
```
$ ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml -k -K -u <USERNAME> 
```

Verify that the Kubernetes cluster is running, you should be able to see ALL pods are at Running status and all nodes are in Ready status. It may take a few minutes to download and initialize pods.

Check nodes status:
```
$ kubectl get nodes
```
[TODO]Screenshoot here

Check pods status:
```
$ kubectl get pods -A
```
[TODO]Screenshoot here

Optionally, test a GPU job to ensure that your Kubernetes setup can tap into GPUs.
```
$ kubectl run nvidia-smi --rm -t -i --restart=Never --image=nvidia/cuda:10.0-runtime-ubi7 --limits=nvidia.com/gpu=1 -- nvidia-smi
```
[TODO]Screenshoot here
# Kubernetes Configuration 
## Create PVC
Create a Persistent Volumes Claims for Triton Inference Server use.
```
$ vi ~/pvc.yaml
$ kubectl apply -f ~/pvc.yaml
```
Validating PVC has successfully been created.
```
$ kubectl get pvc -A
```
RemovePVC (Optional, for debugging)
```
$ kubectl delete pvc <PVC_NAME>
```
## Create Kubernetes Secrets
Create a Kubernetes Secrets so that kubernetes is able to pull docker images from NGC
https://ngc.nvidia.com/setup/api-key
```
$ kubectl create secret docker-registry ngc \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=<your-api-key> \
  --docker-email=<YOUR_NGC_ACCOUNT>
```
Validating kubernetes secret for NGC access  has successfully been created.
```
$ kubectl get secrets
```
Remove Kubernetes Secret (Optional, for debugging)
```
$ kubectl delete secrets ngc
```
## Deploy Load Balancer
Kubernetes provides a variety of mechanisms to expose pods in your cluster to external networks. Two key concepts for routing traffic to your services are:

Load Balancers, which expose an external IP and route traffic to one or more pods inside the cluster. 

Ingress controllers, which provide a mapping between external HTTP routes and internal services. Ingress controllers are typically exposed using a Load Balancer external IP.
DeepOps provides scripts you can run to configure a simple Load Balancer and/or Ingress setup:

Set available IPs for load balancer, see metallb.yml content, This script will set up a software-based L2 Load Balancer using MetalLb.
```
$ cd ~/deepops
$ vi config/helm/metallb.yml
$ ./scripts/k8s/deploy_loadbalancer.sh
```
Remove metallb load balancer (Optional, for debugging)
```
$ helm list -A #Check helm name
$ helm delete metallb -n deepops-loadbalancer
```

# Triton Inference Server Configuration
## Prepare a Local Model Repository
Get Triton Inference Server sample from GitHub into home directory
```
$ cd
$ git clone https://github.com/triton-inference-server/server.git
```

Download model sample to NFS storage
```
$ cd server/docs/examples
$ ./fetch_models.sh
$ scp -r model_repository/ <USERNAME>@<NFS_SERVER_IP>:<NFS_PVC_LOCATION>
```
## Deploy Triton Inference Server by Helm Chart
Download Triton Inference Server Helm Chart from NGC
```
$ cd
$ helm fetch https://helm.ngc.nvidia.com/nvidia/charts/tritoninferenceserver-1.0.0.tgz
```

Unzip it for modify content
```
$ tar zxvf tritoninferenceserver-1.0.0.tgz
$ cd tritoninferenceserver
```

Modify docker image name and model repository path, because the helm chart are not up to date, see value.yaml for full content
```
$ vi values.yaml
```

Change cmd,args and the path of liveness/readiness probe,also need to add volume mount and kubernetes secrets because the helm chart are not up to date, see deployment.yaml for full content
```
$ vi templates/deployment.yaml
```

Deploy Triton Inference Server
```
$ helm install nvidia .
```

Remove Triton Inference Server (Optional, for debugging)
```
$ helm list #Check helm name
$ helm delete nvidia
```
## Verify Trion Inference Server Status
Make sure the pod is running, it may take a few mins to download the image.
```
$ kubectl get pod -A -o wide
```

Check pod status.
```
$ kubectl describe pod <TRITON_POD_NAME>
$ kubectl logs <TRITON_POD_NAME>
```

If the load balancer is set correctly, the Triton deployment should get an external IP.
```
$ kubectl get service
```


Check health status of Triton Inference Server
```
$ curl -v <TRITON_EXTERNAL_IP>:8000/v2/health/ready
```


Check metrics of Triton Inference Server
```
$ curl <TRITON_EXTERNAL_IP>:8002/metrics
```

## Run Triton Client Examples
Download Triton Inference Client Examples from NGC. In this lab, we run this in compute node in order to get stable throughput and reduce network bandwidth and latency impact.

To stabilize GPU compute performance, lock GPU clock rate by following command
```
$ sudo nvidia-smi -lgc 1327,1327
```

Launch Triton Client Example container
```
$ docker run -it --rm --net=host nvcr.io/nvidia/tritonserver:20.09-py3-clientsdk
```

Send inference request to Triton Inference Server.
```
$ /workspace/install/bin/image_client -m inception_graphdef -c 1 -s INCEPTION /workspace/images/mug.jpg -u <TRITON_EXTERNAL_IP>:8000 -b 128
```

To learn the latest usage of client sample, please visit Triton Inference Server GitHub page 

Here are some examples to simulate light loading and heavy loading, see stress_light.sh and stress_heavy.sh

Let's run “stress_light.sh” and monitor its status by Grafana dashboard. Practice following to create a monitoring service for Triton Inference Server.
```
$ chmod +x stress_light.sh
$ ./stress_light.sh
```

## Deploy monitor service 
Let's go back to provision node, deploy Prometheus and Grafana to monitor Kubernetes and cluster nodes.
```
$ cd ~/deepops/scripts/k8s
$ ./deploy_monitoring.sh
```

The services can be reached from the following addresses:

Grafana: http://\<kube-master>:30200<br>
Prometheus: http://\<kube-master>:30500<br>
Alertmanager: http://\<kube-master>:30400<br>


You should be able to observe metrics such as GPU Utilization, memory usage in GPU nodes dashboard but there are no Triton-related metrics for monitoring. Therefore, let’s add Triton-related metrics into Prometheus server in the following sections.

# Monitor Triton Inference Server
## Add Triton Metrics into Prometheus server

Delete the current monitoring service because we will modify it.
```
$ cd ~/deepops/scripts/k8s
$ ./deploy_monitoring.sh -d
```

Add Triton Inference Server Metrics, we will need to modify deepops/config/helm/monitoring.yml, see full content of monitoring.yml
```
$ vi ~/deepops/config/helm/monitoring.yml
```

After adding Triton Metrics, re-deploy monitoring service again
```
$ ./deploy_monitoring.sh
```

The services can be reached from the following addresses:

Grafana: http://\<kube-master>:30200<br>
Prometheus: http://\<kube-master>:30500<br>
Alertmanager: http://\<kube-master>:30400<br>


Go to Prometheus server and simply search “inference”, you should be able to see Triton-related metrics.

## Create monitor dashboard for Triton Inference Server
Create a dashboard and add new panels by following:
1. Success request per sec
   1. Metrics: sum(delta(nv_inference_request_success[1m]))
   2. Legend : {{model}}
   3. Panel title: Success request per sec
2. Avg queue time per request
   1. Metrics: avg(delta(nv_inference_queue_duration_us[1m])/(1+delta(nv_inference_request_success[1m]))/1000)
   2. Legend : Triton Inference Server
   3. Panel title: Avg queue time per request(ms)
   4. In order to show integer number, edit Panel> Axes>Left Y>Decimals>4 
3. GPU Utilization
   1. Metrics: DCGM_FI_DEV_GPU_UTIL
   2. Legend : GPU{{gpu}}
   3. Panel title: GPU Utilization
   4. Visualization : Gauge
4. Replica number
   1. Metrics: kube_deployment_status_replicas{deployment="nvidia-tritoninferenceserver"}
   2. Legend : {{deployment}}
   3. Panel title: Replica number
   4. In order to show integer number, edit Panel> Axes>Left Y>Decimals>0
5. Modified dashboard, make it easier to read, and change “time ranges” to “Last 5 minutes” and refresh time to 5s at upper right side of Grafana dashboard.
6. Save the dashboard.

## Monitor Triton Inference Server status
Run “stress_light.sh” to send requests to Triton Inference Server. 
Observe “GPU Utilization”, “Avg queue time per request” and “Success requests per sec”. 
“Success requests per sec” should be arounds **120**. 
“Avg queue time per request” should be under **0.01ms**.

Stop “stress_light.sh”, then run “stress_heavy.sh”. 
Observe “GPU Utilization”, “Avg queue time per request” and “Success requests per sec”. 
“Success requests per sec” should be arounds **240**. 
“Avg queue time per request” should be under **3ms**.

Now, stop “stress_heavy.sh” and continue to config HPA.

# Horizontal Pod Autoscaling(HPA)
## Create a custom metric for HPA
Default metrics in Kubernetes doesn’t suitable for Triton Inferences Server scale out. Therefore, we will need to create a custom metric to trigger Triton Inferences Serve scale out. Prometheus Adapter is suitable for use with the autoscaling/v2 Horizontal Pod Autoscaler in Kubernetes 1.6+. It can also replace the metrics server on clusters that already run Prometheus and collect the appropriate metrics.

Let’s go back to Provisioning node, get prometheus-adapter helm chart
```
$ helm inspect values prometheus-community/prometheus-adapter > ~/prometheus-adapter.values
```

Modify the URL and IP to match current Prometheus server, so that custom metrics can be collected to Prometheus server.
```
$ vi ~/prometheus-adapter.values
```

Add new custom metric for HPA, see prometheus-adapter.values for full content.
The metricsQuery:
```
avg(delta(nv_inference_queue_duration_us[30s])/(1+delta(nv_inference_request_success[30s]))/1000)
```

Is to calculate average inference request queue time in 30 seconds in ms.
Learn more about custom metric, please visit Metrics Discovery and Presentation Configuration

Deploy prometheus-adapter
```
$ helm install prometheus-community/prometheus-adapter \
   --namespace monitoring \
   --generate-name \
   --values ~/prometheus-adapter.values
```

Check available custom metrics, it will take a few mins to collect metrics. You may need to install jq by “apt install jq”.
```
$ kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .
```

Verify Triton metric could be collected by Kubernetes custom.metrics API.
```
$ kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/nv_inference_request_success" | jq .
```

Verify the custom metric we created for HPA is set correctly.
```
$ kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/avg_time_queue_ms | jq .
```


Remove Prometheus Adapter (Optional, for debugging)
```
$ helm list -A #Check helm name
$ helm delete prometheus-adapter-1612505904 -n monitoring
```

## Create HPA for Triton Inference Server
Create a HPA, set a value so that custom metric can trigger HPA, in this lab, the target value should be between 3ms and 0.005 ms, which is between 3000m and 5m. See hpa.yaml for full content. Let’s put 1500m(1.5ms) here. 
```
$ vi ~/hpa.yaml
$ kubectl apply -f ~/hpa.yaml
```

Validating HPA has successfully been created.
```
$ kubectl get hpa -A
```

Wait for a few seconds to get the custom metric we set.


Remove HPA (Optional, for debugging)
```
$ kubectl delete -f ~/hpa.yaml
```

## Test Triton Inference Server with HPA
Run “stress_light.sh” and monitor the Trion dashboard you created.

No HPA triggered because the avg queue time is under 1.5ms.
Now stop “stress_light.sh” and  run “stress_heavy.sh”, monitor dashboard again.

When avg queue time is larger than the trigger we set, there you can see it does trigger HPA to add another replica so that there will be 2 Triton Inference Server could provide inference service and the avg queue time reduced.














