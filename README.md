# Preparation

You will need to prepare at least 3 nodes, one master node, one compute node with 2 GPUs or above and one provision node. In this lab, I'm using DGX Station as a compute node


# Prerequisites

- **OS** : Ubuntu 20.04
- **GPU** : NVIDIA Volta, Turing, and Ampere Architecture GPU families
- **IPs** : Available IPs for master node, provisioning node, compute node and load balancer
- **External NFS storage(Optional)** 

# Build Kubernetes cluster by DeepOps

## Download DeepOps in Provision Node

We are going to use DeepOps to deploy kubernetes and related packages
```
$ git clone https://github.com/NVIDIA/deepops.git
$ cd deepops
$ git checkout release-22.04
```

## Setup for Provision Node

This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the Ansible Guide
```
$ scripts/setup.sh
```

## DeepOps Configuration

Ansible uses an inventory which outlines the servers in your cluster. The setup script from the previous step will copy an example inventory configuration to the config directory.
For complete instructions to deploy Kubernetes cluster by DeepOps pleasae read [Kubernetes Deployment Guide](https://github.com/NVIDIA/deepops/tree/master/docs/k8s-cluster#kubernetes-deployment-guide)

Edit the inventory:
```
$ vi config/inventory
```
Edit inventory, fill in all nodes information in [ALL] section, master nodes in [kube-master] and [etcd] section, compute nodes in [kube-node] section
```
...
...
######
# ALL NODES
# NOTE: Use existing hostnames here, DeepOps will configure server hostnames to match these values
######
[all]
mason-master-node    ansible_host=<MASTER_NODE_IP>
mason-compute-node1  ansible_host=<GPU_NODE_IP1>
mason-compute-node2  ansible_host=<GPU_NODE_IP2>

######
# KUBERNETES
######
[kube-master]
mason-master-node

# Odd number of nodes required
[etcd]
mason-master-node

# Also add mgmt/master nodes here if they will run non-control plane jobs
[kube-node]
mason-compute-node1
mason-compute-node2

[k8s-cluster:children]
kube-master
kube-node
...
...
```

Verify the configuration, provision node should be able to reach each node by Ansible

```
$ ansible all -m raw -a "hostname" -k -K -u <USERNAME> 
```

## Deploy Kubernetes cluster by Ansible

Set up NFS Client Provisioner

```
$ vi config/group_vars/k8s-cluster.yml 
```

The default behavior of DeepOps is to setup an NFS server on the first kube-master node. This temporary NFS server is used by the nfs-client-provisioner which is installed as the default StorageClass of a standard DeepOps deployment

To use an existing nfs server server update the k8s_nfs_server and k8s_nfs_export_path variables in config/group_vars/k8s-cluster.yml and set the k8s_deploy_nfs_server to false in config/group_vars/k8s-cluster.yml

Additionally, the k8s_nfs_mkdir variable can be set to false if the export directory is already configured on the server

In this lab, we will use an existing NFS server server, therefore we will modify following:

```
...
...
# NFS Client Provisioner
# Playbook: nfs-client-provisioner.yml
k8s_nfs_client_provisioner: true

# Set to true if you want to create a NFS server in master node already
k8s_deploy_nfs_server: false

# Set to false if an export dir is already
k8s_nfs_mkdir: false  # Set to false if an export dir is already configured with proper permissions

# Fill your NFS Server IP and export path
k8s_nfs_server: '<NFS_SERVER_IP>'
k8s_nfs_export_path: '<EXPORT_PATH>'
...
...
```

Note that as part of the kubernetes deployment process, the default behavior is to also deploy the NVIDIA k8s-device-plugin for GPU support. The GPU Operator is an alternative all-in-one deployment method, which will deploy the device plugin and optionally includes GPU tooling such as driver containers, GPU Feature Discovery, DCGM-Exporter and MIG Manager. The default behavior of the GPU Operator in DeepOps is to deploy host-level drivers and NVIDIA software. To leverage driver containers as part of the GPU Operator, disable the gpu_operator_preinstalled_nvidia_software flag. To enable the GPU Operator in DeepOps...
```
...
...
# Enable GPU Operator
# set: deepops_gpu_operator_enabled: true

# Enable host-level drivers (must be 'true' for clusters with pre-installed NVIDIA drivers or DGX systems)
# set: gpu_operator_preinstalled_nvidia_software: false
...
...
```

Install Kubernetes using Ansible and Kubespray
```
$ ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml -k -K -u <USERNAME> 
```

Verify that the Kubernetes cluster is running, you should be able to see ALL pods are at Running status and all nodes are in Ready status. It may take a few minutes to download and initialize pods

Check nodes status:
```
$ kubectl get nodes
NAME                  STATUS   ROLES                  AGE     VERSION
mason-compute-node1   Ready    <none>                 7m25s   v1.22.8
mason-compute-node2   Ready    <none>                 7m25s   v1.22.8
mason-master-node     Ready    control-plane,master   8m22s   v1.22.8
```

Check pods status, make suare all pods are running, you may need to wait a while for nvidia-cuda-validator complete:
```
$ kubectl get pods -A
NAMESPACE                        NAME                                                              READY   STATUS      RESTARTS   AGE
deepops-nfs-client-provisioner   nfs-subdir-external-provisioner-7967cbb457-5p25v                  1/1     Running     0          3m6s
gpu-operator-resources           gpu-feature-discovery-2j8jv                                       1/1     Running     0          3m27s
gpu-operator-resources           gpu-feature-discovery-tglkn                                       1/1     Running     0          3m27s
gpu-operator-resources           gpu-operator-6497cbf9cd-zkfcp                                     1/1     Running     0          3m48s
gpu-operator-resources           nvidia-container-toolkit-daemonset-k6cfw                          1/1     Running     0          3m28s
gpu-operator-resources           nvidia-container-toolkit-daemonset-zg67g                          1/1     Running     0          3m28s
gpu-operator-resources           nvidia-cuda-validator-9th56                                       0/1     Completed   0          55s
gpu-operator-resources           nvidia-cuda-validator-hm6ct                                       0/1     Completed   0          74s
gpu-operator-resources           nvidia-dcgm-exporter-mxj7q                                        1/1     Running     0          3m27s
gpu-operator-resources           nvidia-dcgm-exporter-ppq8t                                        1/1     Running     0          3m27s
gpu-operator-resources           nvidia-device-plugin-daemonset-c6lbt                              1/1     Running     0          3m27s
gpu-operator-resources           nvidia-device-plugin-daemonset-gshvb                              1/1     Running     0          3m27s
gpu-operator-resources           nvidia-device-plugin-validator-67lzn                              0/1     Completed   0          23s
gpu-operator-resources           nvidia-device-plugin-validator-lh6t7                              0/1     Completed   0          42s
gpu-operator-resources           nvidia-driver-daemonset-dt94p                                     1/1     Running     0          3m28s
gpu-operator-resources           nvidia-driver-daemonset-pjj4c                                     1/1     Running     0          3m28s
gpu-operator-resources           nvidia-gpu-operator-node-feature-discovery-master-84566dffsk8dp   1/1     Running     0          3m48s
gpu-operator-resources           nvidia-gpu-operator-node-feature-discovery-worker-lcxz5           1/1     Running     0          3m48s
gpu-operator-resources           nvidia-gpu-operator-node-feature-discovery-worker-mw7jd           1/1     Running     0          3m48s
gpu-operator-resources           nvidia-gpu-operator-node-feature-discovery-worker-q7nh8           1/1     Running     0          3m48s
gpu-operator-resources           nvidia-mig-manager-hvp5m                                          1/1     Running     0          36s
gpu-operator-resources           nvidia-mig-manager-w4xbb                                          1/1     Running     0          33s
gpu-operator-resources           nvidia-operator-validator-6pq64                                   1/1     Running     0          3m27s
gpu-operator-resources           nvidia-operator-validator-h7tpx                                   1/1     Running     0          3m27s
kube-system                      calico-kube-controllers-5788f6558-rl9lj                           1/1     Running     0          5m53s
kube-system                      calico-node-cs57m                                                 1/1     Running     0          6m3s
kube-system                      calico-node-d87pf                                                 1/1     Running     0          6m3s
kube-system                      calico-node-dbx57                                                 1/1     Running     0          6m3s
kube-system                      coredns-8474476ff8-qqcvh                                          1/1     Running     0          5m46s
kube-system                      coredns-8474476ff8-wsxrr                                          1/1     Running     0          5m44s
kube-system                      dns-autoscaler-5ffdc7f89d-x9qs5                                   1/1     Running     0          5m45s
kube-system                      kube-apiserver-mason-master-node                                  1/1     Running     1          7m10s
kube-system                      kube-controller-manager-mason-master-node                         1/1     Running     1          7m9s
kube-system                      kube-proxy-4hr7r                                                  1/1     Running     0          6m13s
kube-system                      kube-proxy-d5frj                                                  1/1     Running     0          6m13s
kube-system                      kube-proxy-fchfc                                                  1/1     Running     0          6m13s
kube-system                      kube-scheduler-mason-master-node                                  1/1     Running     1          7m9s
kube-system                      kubernetes-dashboard-6c96f5b677-fsqfp                             1/1     Running     0          5m44s
kube-system                      kubernetes-metrics-scraper-54b676c794-hbvdz                       1/1     Running     0          5m44s
kube-system                      nginx-proxy-mason-compute-node1                                   1/1     Running     0          6m13s
kube-system                      nginx-proxy-mason-compute-node2                                   1/1     Running     0          6m14s
kube-system                      nodelocaldns-jsczp                                                1/1     Running     0          5m45s
kube-system                      nodelocaldns-pv25s                                                1/1     Running     0          5m45s
kube-system                      nodelocaldns-pwrm4                                                1/1     Running     0          5m45s

```


Optionally, test a GPU job to ensure that your Kubernetes setup can tap into GPUs
```
$ kubectl run nvidia-smi --rm -t -i --restart=Never --image=nvidia/cuda:11.0-runtime-ubi7 --limits=nvidia.com/gpu=1 -- nvidia-smi
Flag --limits has been deprecated, has no effect and will be removed in the future.
Fri May 13 14:16:09 2022
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 510.47.03    Driver Version: 510.47.03    CUDA Version: 11.6     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                               |                      |               MIG M. |
|===============================+======================+======================|
|   0  NVIDIA A100-PCI...  On   | 00000000:03:00.0 Off |                    0 |
| N/A   30C    P0    34W / 250W |      0MiB / 40960MiB |      0%      Default |
|                               |                      |             Disabled |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                                  |
|  GPU   GI   CI        PID   Type   Process name                  GPU Memory |
|        ID   ID                                                   Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
pod "nvidia-smi" deleted

```

# Kubernetes Configuration 
## Create PVC
Create a Persistent Volumes Claims for Triton Inference Server use. Storage size could be modified in yaml file
```
$ cd ~/
$ git clone https://github.com/YH-Wu/Triton-Inference-Server-on-Kubernetes.git
$ cd Triton-Inference-Server-on-Kubernetes/
$ kubectl apply -f yaml/pvc.yaml
```
Validating PVC has successfully been created
```
$ kubectl get pvc -A
NAMESPACE   NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
default     triton-claim   Bound    pvc-e065e42e-63db-4bfb-bcdf-36af53ca7e7c   64Gi       RWX            nfs-client     4m23s
```
Validating volume created on NFS server
```
$ mason@nfs-server:/nfsshare/k8s_nfs$ ls
default-triton-claim-pvc-eb358acc-874b-4f41-81c4-4974b2714220
```

RemovePVC (Optional, for debugging)
```
$ kubectl delete pvc <PVC_NAME> -n <NAMESPACE>
```
## Create Kubernetes Secrets
Create a Kubernetes Secrets so that kubernetes will be able to pull docker images from [NVIDIA GPU Cloud](https://ngc.nvidia.com/setup/api-key), you need to register NGC first, and the best thing is: it's free :)

```
$ kubectl create secret docker-registry ngc \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=<YOUR_API_KEY> \
  --docker-email=<YOUR_NGC_ACCOUNT>
```
Validating kubernetes secret for NGC access  has successfully been created
```
$ kubectl get secrets
NAME                  TYPE                                  DATA   AGE
default-token-v8m8g   kubernetes.io/service-account-token   3      16m
ngc                   kubernetes.io/dockerconfigjson        1      6s

```
Remove Kubernetes Secret (Optional, for debugging)
```
$ kubectl delete secrets ngc
```
## Deploy Load Balancer
Kubernetes provides a variety of mechanisms to expose pods in your cluster to external networks. Two key concepts for routing traffic to your services are:

Load Balancers, which expose an external IP and route traffic to one or more pods inside the cluster

Ingress controllers, which provide a mapping between external HTTP routes and internal services, typically exposed using a Load Balancer external IP

DeepOps provides scripts you can run to configure a simple Load Balancer and/or Ingress setup

Set available IPs for load balance:
```
$ vi yaml/metallb.yaml #at least provide 2 IPs
$ cp yaml/metallb.yaml ~/deepops/config/helm/metallb.yml
$ cd ~/deepops/scripts/k8s/
$ ./deploy_loadbalancer.sh
```
Remove metallb load balancer (Optional, for debugging)
```
$ helm delete metallb -n deepops-loadbalancer
```

# Triton Inference Server Configuration
## Prepare a Local Model Repository

Download model sample and upload to NFS storage
```
$ cd && git clone https://github.com/triton-inference-server/server.git
$ cd server/docs/examples
$ ./fetch_models.sh
$ scp -r model_repository/ <USERNAME>@<NFS_SERVER_IP>:<TRITION_CLAIM_PVC_LOCATION>/
```
Make sure model_repository already uploaded to NFS Server
```
$ mason@nfs-server:/nfsshare/k8s_nfs/default-triton-claim-pvc-eb358acc-874b-4f41-81c4-4974b2714220$ ls
model_repository
```

## Deploy Triton Inference Server by Helm Chart

Deploy Triton Inference Server
```
$ cd ~/Triton-Inference-Server-on-Kubernetes
$ helm install nvidia tritoninferenceserver
```

Remove Triton Inference Server (Optional, for debugging)
```
$ helm delete nvidia
```

## Verify Trion Inference Server Status
Make sure the pod is running, it may take a few mins to download the image
```
$ kubectl get pod -o wide
NAME                                            READY   STATUS    RESTARTS   AGE   IP              NODE                  NOMINATED NODE   READINESS GATES
nvidia-tritoninferenceserver-849c88bdbc-tsth5   0/1     Running   0          7s    10.233.100.17   mason-compute-node2   <none>           <none>
```

Check pod status
```
$ kubectl describe pod <TRITON_POD_NAME>
$ kubectl logs <TRITON_POD_NAME>
```

If the load balancer is set correctly, the Triton deployment should get an external IP
```
$ kubectl get service
NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                                        AGE
kubernetes                     ClusterIP      10.233.0.1      <none>         443/TCP                                        61m
nvidia-tritoninferenceserver   LoadBalancer   10.233.59.250   10.19.104.21   8000:31426/TCP,8001:31134/TCP,8002:31886/TCP   91s
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
Download Triton Inference Client Examples from NGC. In this lab, we **run this in compute node** in order to get stable throughput and reduce network bandwidth and latency impact

Launch Triton Client Example container
```
$ sudo ctr images pull nvcr.io/nvidia/tritonserver:22.03-py3-sdk
$ sudo ctr run -t --rm --net-host nvcr.io/nvidia/tritonserver:22.03-py3-sdk triton-client
```

Send inference request to Triton Inference Server
```
$ /workspace/install/bin/image_client -m inception_graphdef -c 1 -s INCEPTION /workspace/images/mug.jpg -u <TRITON_EXTERNAL_IP>:8000 -b 128
```

To learn the latest usage of client sample, please visit [Triton Inference Server](https://github.com/triton-inference-server/server)

Here are some examples to simulate light loading and heavy loading, let's run “stress_light.sh” and monitor its status by Grafana dashboard. Practice following to create a monitoring service for Triton Inference Server
```
$ git clone https://github.com/YH-Wu/Triton-Inference-Server-on-Kubernetes.git
$ cd Triton-Inference-Server-on-Kubernetes/scripts
$ chmod +x stress_light.sh && chmod +x stress_heavy.sh 

# Modified URL
$ vi stress_light.sh

$ ./stress_light.sh
```

## Deploy monitor service 
Keep the stress test running. Let's **go back to provision node**, deploy Prometheus and Grafana to monitor Kubernetes and cluster nodes. I've made some Prometheus and Grafana yaml patch fix for this lab, please copy two files to DeepOps folder for installation.
```
$ cp ~/Triton-Inference-Server-on-Kubernetes/yaml/monitoring.yaml ~/deepops/config/helm/monitoring.yml 
$ cp ~/Triton-Inference-Server-on-Kubernetes/dashboard/gpu-dashboard.json ~/deepops/src/dashboards/gpu-dashboard.json
```
Deploy Prometheus and Grafana
```
$ cd ~/deepops/scripts/k8s
$ ./deploy_monitoring.sh
```

Check monitoring service status
```
$ kubectl get pod -n monitoring
NAME                                                       READY   STATUS    RESTARTS   AGE
alertmanager-kube-prometheus-stack-alertmanager-0          2/2     Running   0          108s
kube-prometheus-stack-grafana-8699669c75-xqkpn             3/3     Running   0          118s
kube-prometheus-stack-kube-state-metrics-d699cc95f-vq8pj   1/1     Running   0          118s
kube-prometheus-stack-operator-5b58cb5c7-sqpq6             1/1     Running   0          118s
kube-prometheus-stack-prometheus-node-exporter-22qzd       1/1     Running   0          118s
kube-prometheus-stack-prometheus-node-exporter-8tpl6       1/1     Running   0          118s
kube-prometheus-stack-prometheus-node-exporter-h6g54       1/1     Running   0          118s
prometheus-kube-prometheus-stack-prometheus-0              2/2     Running   0          108s
```

The services can be reached from the following addresses:

Grafana: http://\<kube-master>:30200<br>
Grafana user: admin<br>
Grafana password: deepops<br><br>
Prometheus: http://\<kube-master>:30500<br>
Alertmanager: http://\<kube-master>:30400<br>


In the left panel, select Dashboard icon, click Browse then select "GPU Node - fixed". You should be able to observe metrics such as GPU Utilization, memory usage in GPU nodes dashboard. However, there are no Triton-related metrics to monitoring. Therefore, let’s add Triton-related metrics into Prometheus server in the following sections

![](https://i.imgur.com/k8yq59E.png)



# Monitor Triton Inference Server
## Add Triton Metrics into Prometheus server

Delete the current monitoring service because we will modify  yaml file.
```
$ ./deploy_monitoring.sh -d
```

Actually Triton Inference Server Metrics setting has been added into monitoring.yaml, see full content in L61 to L76 in monitoring.yaml and uncomment those.

```
Uncomment L61 to L76
$ vi ~/Triton-Inference-Server-on-Kubernetes/yaml/monitoring.yaml

$ cp ~/Triton-Inference-Server-on-Kubernetes/yaml/monitoring.yaml ~/deepops/config/helm/monitoring.yml 
```

After adding Triton Metrics, re-deploy monitoring service again
```
$ ./deploy_monitoring.sh
```

The services can be reached from the following addresses:

Grafana: http://\<kube-master>:30200<br>
Prometheus: http://\<kube-master>:30500<br>
Alertmanager: http://\<kube-master>:30400<br>


Go to Prometheus server and simply search “nv_inference”, you should be able to see Triton-related metrics

## Create monitor dashboard for Triton Inference Server
Go to Grafana, create a dashboard and add new panels by following:
1. Success request per minute
   1. Metrics: sum(delta(nv_inference_request_success[1m]))
   2. Legend : {{model}}
   3. Panel title: Success request per minute
   4. Apply
2. Avg queue time per request
   1. Metrics: avg(delta(nv_inference_queue_duration_us[1m])/(1+delta(nv_inference_request_success[1m]))/1000)
   2. Legend : Triton Inference Server
   3. Panel title: Avg queue time per request(ms)
   4. Edit Panel > Standard options Decimals > 4 
   5. Apply
3. GPU Utilization
   1. Metrics: max by (gpu) (DCGM_FI_PROF_GR_ENGINE_ACTIVE)
   2. Legend : GPU-{{gpu}}
   3. Panel title: GPU Utilization
   4. Visualization : Time series > Gauge
   5. Apply
4. Replica number
   1. Metrics: kube_deployment_status_replicas{deployment="nvidia-tritoninferenceserver",job="gpu-metrics"}
   2. Legend : {{deployment}}
   3. Panel title: Replica number
   4. Edit Panel > Standard options Decimals > 0 
5. Modified dashboard, make it easier to read, and change “time ranges” to “Last 5 minutes” and "refresh time" to "5s" at upper right side of Grafana dashboard.
6. Save the dashboard and naeme "Triton Inference Server Dashboard".
![](https://i.imgur.com/whJZj4x.png)



## Monitor Triton Inference Server status
Observe “GPU Utilization”, “Avg queue time per request” and “Success requests per sec”

Then, stop “stress_light.sh” in the client container, then run “stress_heavy.sh”. 
Observe “GPU Utilization”, “Avg queue time per request” and “Success requests per sec”

For V100,
“Success requests per sec” should be arounds **120**. 
“Avg queue time per request” should be under **0.05ms** when running “stress_light.sh”

For A100,
“Success requests per sec” should be arounds **120**. 
“Avg queue time per request” should be under **0.05ms** when running “stress_light.sh”

“Success requests per sec” should be arounds **240**. “Avg queue time per request” should be under **3.5ms** when running “stress_heavy.sh”

Now, stop “stress_heavy.sh” and continue to config HPA

# Autoscales Triton Inference Server
## Create a custom metric for Horizontal Pod Autoscaling(HPA)
Default metrics in Kubernetes doesn’t suitable for Triton Inferences Server scale out. Therefore, we will need to create a custom metric to trigger Triton Inferences Serve scale out. Prometheus Adapter is suitable for use with the autoscaling/v2 Horizontal Pod Autoscaler in Kubernetes 1.6+. It can also replace the metrics server on clusters that already run Prometheus and collect the appropriate metrics


```
$ cd ~/Triton-Inference-Server-on-Kubernetes/
$ vi yaml/prometheus-adapter.values
```
1. Modify the **url** and **port** to match current Prometheus server in L34~L35, so that custom metrics can be collected to Prometheus server

2. Add new custom metric for HPA, 
the metric already filled in prometheus-adapter.values, please uncomment L52 to L62
```
...
...
rules:
  custom:
  #Custom Trion metric for trigger Kubernetes HPA
  - seriesQuery: 'nv_inference_queue_duration_us{namespace="default"}'
    resources:
      overrides:
        namespace: {resource: "namespace"}
        pod: {resource: "pod"}
    name:
      matches: "nv_inference_queue_duration_us"
      as: "avg_time_queue_ms"
    metricsQuery: "avg(delta(nv_inference_queue_duration_us{<<.LabelMatchers>>}[1m])/(1+delta(nv_inference_request_success{<<.LabelMatchers>>}[1m]))/1000) by (<<.GroupBy>>)"
...
...

```

This is to calculate average inference request queue time in 30 seconds in ms.
Learn more about custom metric, please visit [Metrics Discovery and Presentation Configuration](https://github.com/kubernetes-sigs/prometheus-adapter/blob/master/docs/config.md)

Deploy prometheus-adapter
```
$ helm install prometheus-community/prometheus-adapter \
   --namespace monitoring \
   --generate-name \
   --values yaml/prometheus-adapter.values
```

Check available custom metrics, it will take a few mins to collect metrics. You may need to install jq by “sudo apt install jq”
```
$ kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .

{
  "kind": "APIResourceList",
  "apiVersion": "v1",
  "groupVersion": "custom.metrics.k8s.io/v1beta1",
  "resources": []
}

```

Verify Triton metric could be collected by Kubernetes custom.metrics API
```
$ kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/nv_inference_request_success" | jq .
{
  "kind": "MetricValueList",
  "apiVersion": "custom.metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/%2A/nv_inference_request_success"
  },
  "items": [
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "default",
        "name": "nvidia-tritoninferenceserver-849c88bdbc-tsth5",
        "apiVersion": "/v1"
      },
      "metricName": "nv_inference_request_success",
      "timestamp": "2022-05-14T12:58:26Z",
      "value": "33756",
      "selector": null
    }
  ]
}

```

Verify the custom metric we created for HPA is set correctly
```
$ kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/avg_time_queue_ms | jq .
{
  "kind": "MetricValueList",
  "apiVersion": "custom.metrics.k8s.io/v1beta1",
  "metadata": {
    "selfLink": "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/%2A/avg_time_queue_ms"
  },
  "items": [
    {
      "describedObject": {
        "kind": "Pod",
        "namespace": "default",
        "name": "nvidia-tritoninferenceserver-849c88bdbc-tsth5",
        "apiVersion": "/v1"
      },
      "metricName": "avg_time_queue_ms",
      "timestamp": "2022-05-14T12:58:45Z",
      "value": "1768m",
      "selector": null
    }
  ]
}

```


Remove Prometheus Adapter (Optional, for debugging)
```
$ helm list -A #Check helm name
$ helm delete <PROMETHEUS_ADAPTER_NAME> -n monitoring
```

## Create HPA for Triton Inference Server
Create a HPA, set a value for custom metric to trigger HPA. In this lab, we will use "avg_time_queue_ms" metric to trigger HPA, the metric stand for the waiting time each inference request and we don't want a long waiting time. Fortunately, we already knew our "avg_time_queue_ms" under different stress level

For single V100:

"avg_time_queue_ms" is **0.05ms** when running “stress_light.sh”

"avg_time_queue_ms" is **3.5ms** when running “stress_heavy.sh”

Therefore, you can set value between 3.5ms and 0.05ms. Let’s put 1.5ms (1500m) here. See hpa.yaml for full content
```
$ vi yaml/hpa.yaml
$ kubectl apply -f yaml/hpa.yaml
```

Validating HPA has successfully been created
```
$ kubectl get hpa
NAME                    REFERENCE                                 TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
triton-metirc-app-hpa   Deployment/nvidia-tritoninferenceserver   0/1500m   1         2         2          57s
```

Let's wait for a few seconds for custom metric ready


## Test Triton Inference Server with HPA
Run “stress_light.sh” and monitor the Trion dashboard and HPA status
```
ubuntu@provision-node:~/Triton-Inference-Server-on-Kubernetes$ kubectl get hpa
NAME                    REFERENCE                                 TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
triton-metirc-app-hpa   Deployment/nvidia-tritoninferenceserver   7m/1500m   1         2         1          40s
```
![](https://i.imgur.com/JvpzDoM.png)




No HPA triggered because "avg_time_queue_ms" is under 1.5ms.
Now stop “stress_light.sh” and  run “stress_heavy.sh”, monitor dashboard and HPA status again
```
ubuntu@provision-node:~/Triton-Inference-Server-on-Kubernetes$ kubectl get hpa
NAME                    REFERENCE                                 TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
triton-metirc-app-hpa   Deployment/nvidia-tritoninferenceserver   2111m/1500m   1         2         1          5m5s
```

When “avg_time_queue_ms” is larger than the trigger we set, there you can see it triggered HPA to create another replica, so that there are 2 Triton Inference Server providing inference service and the avg queue time reduced
```
ubuntu@provision-node:~/Triton-Inference-Server-on-Kubernetes$ kubectl get hpa
NAME                    REFERENCE                                 TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
triton-metirc-app-hpa   Deployment/nvidia-tritoninferenceserver   4m/1500m   1         2         2          9m5s
```
![](https://i.imgur.com/dHAm07n.png)
















