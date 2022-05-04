# Preparation

You will need to prepare at least 3 nodes, one master node, one compute node with 2 GPUs or above and one provision node. In this lab, I'm using DGX Station as a compute node


# Prerequisites

- **OS** : Ubuntu 20.04
- **GPU** : NVIDIA Pascal, Volta, Turing, and Ampere Architecture GPU families
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
mason-compute-node1  ansible_host=<GPU_NODE_IP>
mason-compute-node2  ansible_host=<GPU_NODE_IP>

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
# set: gpu_operator_preinstalled_nvidia_software: true
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
NAME                  STATUS   ROLES                  AGE   VERSION
mason-compute-node1   Ready    <none>                 18m   v1.21.6
mason-compute-node2   Ready    <none>                 18m   v1.21.6
mason-master-node     Ready    control-plane,master   19m   v1.21.6
```

Check pods status, make suare all pods are running, you may need to wait a while for nvidia-cuda-validator complete:
```
$ kubectl get pods -A
NAMESPACE                        NAME                                                              READY   STATUS      RESTARTS   AGE
deepops-nfs-client-provisioner   nfs-subdir-external-provisioner-7967cbb457-vcsgj                  1/1     Running     0          8m25s
default                          gpu-operator-5f8b7c4f59-kfq7n                                     1/1     Running     0          13m
default                          nvidia-gpu-operator-node-feature-discovery-master-74db7c56fbhsv   1/1     Running     0          13m
default                          nvidia-gpu-operator-node-feature-discovery-worker-fhknv           1/1     Running     0          13m
default                          nvidia-gpu-operator-node-feature-discovery-worker-q9j9h           1/1     Running     0          13m
default                          nvidia-gpu-operator-node-feature-discovery-worker-qbplg           1/1     Running     0          13m
gpu-operator-resources           gpu-feature-discovery-fgdpt                                       1/1     Running     3          11m
gpu-operator-resources           gpu-feature-discovery-z2hvm                                       1/1     Running     1          12m
gpu-operator-resources           nvidia-container-toolkit-daemonset-n2zfj                          1/1     Running     0          12m
gpu-operator-resources           nvidia-container-toolkit-daemonset-sp6fq                          1/1     Running     0          11m
gpu-operator-resources           nvidia-cuda-validator-6j6qh                                       0/1     Completed   0          80s
gpu-operator-resources           nvidia-cuda-validator-jpfnx                                       0/1     Completed   0          90s
gpu-operator-resources           nvidia-dcgm-56fsk                                                 1/1     Running     0          12m
gpu-operator-resources           nvidia-dcgm-exporter-dznc8                                        1/1     Running     0          11m
gpu-operator-resources           nvidia-dcgm-exporter-kw57n                                        1/1     Running     3          12m
gpu-operator-resources           nvidia-dcgm-ffctm                                                 1/1     Running     1          11m
gpu-operator-resources           nvidia-device-plugin-daemonset-c8mjh                              1/1     Running     2          11m
gpu-operator-resources           nvidia-device-plugin-daemonset-zxm5c                              1/1     Running     1          12m
gpu-operator-resources           nvidia-device-plugin-validator-kck95                              0/1     Completed   0          84s
gpu-operator-resources           nvidia-device-plugin-validator-t2lnc                              0/1     Completed   0          73s
gpu-operator-resources           nvidia-driver-daemonset-7bkqb                                     1/1     Running     1          13m
gpu-operator-resources           nvidia-driver-daemonset-7sjmk                                     1/1     Running     0          13m
gpu-operator-resources           nvidia-operator-validator-58dcz                                   1/1     Running     0          12m
gpu-operator-resources           nvidia-operator-validator-qppgb                                   1/1     Running     1          11m
kube-system                      calico-kube-controllers-8575b76f66-2972h                          1/1     Running     0          25m
kube-system                      calico-node-c9t45                                                 1/1     Running     1          25m
kube-system                      calico-node-gxppq                                                 1/1     Running     0          25m
kube-system                      calico-node-pzbft                                                 1/1     Running     1          25m
kube-system                      coredns-8474476ff8-9t7t7                                          1/1     Running     0          12m
kube-system                      coredns-8474476ff8-wn6q5                                          1/1     Running     0          25m
kube-system                      dns-autoscaler-7df78bfcfb-l5wlw                                   1/1     Running     0          25m
kube-system                      kube-apiserver-mason-master-node                                  1/1     Running     0          26m
kube-system                      kube-controller-manager-mason-master-node                         1/1     Running     1          26m
kube-system                      kube-proxy-v4rmx                                                  1/1     Running     0          9m39s
kube-system                      kube-proxy-vpkbd                                                  1/1     Running     0          9m39s
kube-system                      kube-proxy-whl9c                                                  1/1     Running     0          9m39s
kube-system                      kube-scheduler-mason-master-node                                  1/1     Running     1          26m
kube-system                      kubernetes-dashboard-6c96f5b677-49dfc                             1/1     Running     1          25m
kube-system                      kubernetes-metrics-scraper-694c6bdbc9-ltrpp                       1/1     Running     1          25m
kube-system                      nginx-proxy-mason-compute-node1                                   1/1     Running     1          25m
kube-system                      nginx-proxy-mason-compute-node2                                   1/1     Running     1          25m
kube-system                      nodelocaldns-5w5sk                                                1/1     Running     1          25m
kube-system                      nodelocaldns-bt8k9                                                1/1     Running     0          25m
kube-system                      nodelocaldns-tzmtf                                                1/1     Running     1          25m
kube-system                      nvidia-device-plugin-2gczf                                        1/1     Running     0          5m20s
kube-system                      nvidia-device-plugin-gjpkb                                        1/1     Running     0          6m18s
node-feature-discovery           gpu-feature-discovery-9c8nt                                       1/1     Running     9          23m
node-feature-discovery           gpu-feature-discovery-g7h7f                                       1/1     Running     9          23m
node-feature-discovery           nfd-master-6dd87d999-vdlwj                                        1/1     Running     0          23m
node-feature-discovery           nfd-worker-fm5vd                                                  1/1     Running     0          8m50s
node-feature-discovery           nfd-worker-nbpkz                                                  1/1     Running     0          23m
node-feature-discovery           nfd-worker-p9tr9                                                  1/1     Running     0          23m
```


Optionally, test a GPU job to ensure that your Kubernetes setup can tap into GPUs
```
$ kubectl run nvidia-smi --rm -t -i --restart=Never --image=nvidia/cuda:11.0-runtime-ubi7 --limits=nvidia.com/gpu=1 -- nvidia-smi
Flag --limits has been deprecated, has no effect and will be removed in the future.
Fri Apr  1 08:17:03 2022
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 470.57.02    Driver Version: 470.57.02    CUDA Version: 11.4     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|                               |                      |               MIG M. |
|===============================+======================+======================|
|   0  NVIDIA RTX A6000    On   | 00000000:0B:00.0 Off |                    0 |
| 30%   42C    P8    32W / 300W |      0MiB / 45634MiB |      0%      Default |
|                               |                      |                  N/A |
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
default     triton-claim   Bound    pvc-eb358acc-874b-4f41-81c4-4974b2714220   10Gi       RWX            nfs-client     5s
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
Create a Kubernetes Secrets so that kubernetes will be able to pull docker images from [NVIDIA GPU Cloud](https://ngc.nvidia.com/setup/api-key)

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
NAME                                          TYPE                                  DATA   AGE
default-token-rmdlj                           kubernetes.io/service-account-token   3      117m
ngc                                           kubernetes.io/dockerconfigjson        1      7s
sh.helm.release.v1.gpu-feature-discovery.v1   helm.sh/release.v1                    1      113m
sh.helm.release.v1.nvidia-device-plugin.v1    helm.sh/release.v1                    1      113m

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
NAME                                            READY   STATUS    RESTARTS   AGE   IP             NODE          NOMINATED NODE   READINESS GATES
ingress-nginx-controller-6b4fdfdcf7-2t4p6       1/1     Running   0          44m   10.19.104.20   master-node   <none>           <none>
nvidia-tritoninferenceserver-686bc4c4bc-vjrvl   1/1     Running   0          92m   10.233.91.18   gpu-node1     <none>           <none>

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
kubernetes                     ClusterIP      10.233.0.1      <none>         443/TCP                                        3h10m
nvidia-tritoninferenceserver   LoadBalancer   10.233.42.105   10.19.104.10   8000:32197/TCP,8001:31639/TCP,8002:32131/TCP   62s
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

To stabilize GPU compute performance, lock GPU clock rate at Default Applications Clocks by following command:
```
#To get Applications Clocks by nvidia-smi -q
$ sudo nvidia-smi -lgc 1327,1327 # For NVIDIA Tesla V100
$ sudo nvidia-smi -lgc 1395,1395 # For NVIDIA Quadro RTX 8000
```
**NOTE: Lock GPU Clock rate is NOT require for production environment**
<br>
<br>
<br>
Launch Triton Client Example container
```
$ sudo docker run -it --rm --net=host nvcr.io/nvidia/tritonserver:22.03-py3-sdk
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
Keep the stress test running. Let's **go back to provision node**, deploy Prometheus and Grafana to monitor Kubernetes and cluster nodes
```
$ cd ~/deepops/scripts/k8s
$ ./deploy_monitoring.sh
```

Check monitoring service status
```
$ kubectl get pod -n monitoring
NAME                                                        READY   STATUS    RESTARTS   AGE
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   0          2m44s
dcgm-exporter-jmjqv                                         1/1     Running   0          2m49s
kube-prometheus-stack-grafana-7f97fc5446-zpltf              2/2     Running   0          2m55s
kube-prometheus-stack-kube-state-metrics-66789f8885-8c6tw   1/1     Running   0          2m55s
kube-prometheus-stack-operator-647c466c47-6jdn8             2/2     Running   0          2m55s
kube-prometheus-stack-prometheus-node-exporter-clxz8        1/1     Running   0          2m55s
kube-prometheus-stack-prometheus-node-exporter-tlvfg        1/1     Running   0          2m55s
prometheus-kube-prometheus-stack-prometheus-0               3/3     Running   1          2m44s
```

The services can be reached from the following addresses:

Grafana: http://\<kube-master>:30200<br>
Prometheus: http://\<kube-master>:30500<br>
Alertmanager: http://\<kube-master>:30400<br>


You should be able to observe metrics such as GPU Utilization, memory usage in GPU nodes dashboard. However, there are no Triton-related metrics to monitoring. Therefore, let’s add Triton-related metrics into Prometheus server in the following sections

![](https://i.imgur.com/k8yq59E.png)



# Monitor Triton Inference Server
## Add Triton Metrics into Prometheus server

Delete the current monitoring service because we will modify it
```
$ ./deploy_monitoring.sh -d
```

Triton Inference Server Metrics has benn added into monitoring.yaml, see full content in monitoring.yaml
```
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
1. Success request per sec
   1. Metrics: sum(delta(nv_inference_request_success[1m]))
   2. Legend : {{model}}
   3. Panel title: Success request per sec
   4. Apply
2. Avg queue time per request
   1. Metrics: avg(delta(nv_inference_queue_duration_us[1m])/(1+delta(nv_inference_request_success[1m]))/1000)
   2. Legend : Triton Inference Server
   3. Panel title: Avg queue time per request(ms)
   4. Edit Panel > Axes > Left Y > Decimals to 4 
   5. Apply
3. GPU Utilization
   1. Metrics: max by (gpu) (DCGM_FI_DEV_GPU_UTIL)
   2. Legend : GPU-{{gpu}}
   3. Panel title: GPU Utilization
   4. Visualization : Gauge
   5. Apply
4. Replica number
   1. Metrics: kube_deployment_status_replicas{deployment="nvidia-tritoninferenceserver"}
   2. Legend : {{deployment}}
   3. Panel title: Replica number
   4. Edit Panel > Axes > Left Y > Decimals to 0
5. Modified dashboard, make it easier to read, and change “time ranges” to “Last 5 minutes” and "refresh time" to "5s" at upper right side of Grafana dashboard.
6. Save the dashboard.
![](https://i.imgur.com/whJZj4x.png)



## Monitor Triton Inference Server status
Observe “GPU Utilization”, “Avg queue time per request” and “Success requests per sec”

Then, stop “stress_light.sh” in the client container, then run “stress_heavy.sh”. 
Observe “GPU Utilization”, “Avg queue time per request” and “Success requests per sec”

For V100@1327Mhz,
“Success requests per sec” should be arounds **120**. 
“Avg queue time per request” should be under **0.05ms** when running “stress_light.sh”

“Success requests per sec” should be arounds **240**. “Avg queue time per request” should be under **3.5ms** when running “stress_heavy.sh”

Now, stop “stress_heavy.sh” and continue to config HPA

# Horizontal Pod Autoscaling(HPA)
## Create a custom metric for HPA
Default metrics in Kubernetes doesn’t suitable for Triton Inferences Server scale out. Therefore, we will need to create a custom metric to trigger Triton Inferences Serve scale out. Prometheus Adapter is suitable for use with the autoscaling/v2 Horizontal Pod Autoscaler in Kubernetes 1.6+. It can also replace the metrics server on clusters that already run Prometheus and collect the appropriate metrics

Modify the **url** and **port** to match current Prometheus server, so that custom metrics can be collected to Prometheus server
```
$ cd ~/Triton-Inference-Server-on-Kubernetes/
$ vi yaml/prometheus-adapter.values
```

Add new custom metric for HPA, 
the metric already filled in prometheus-adapter.values:
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
        "name": "nvidia-tritoninferenceserver-686bc4c4bc-vjrvl",
        "apiVersion": "/v1"
      },
      "metricName": "nv_inference_request_success",
      "timestamp": "2021-03-23T09:51:57Z",
      "value": "4543",
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
        "name": "nvidia-tritoninferenceserver-686bc4c4bc-vjrvl",
        "apiVersion": "/v1"
      },
      "metricName": "avg_time_queue_ms",
      "timestamp": "2021-03-23T09:52:31Z",
      "value": "0",
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

For single V100@1327Mhz:

"avg_time_queue_ms" is **0.05ms** when running “stress_light.sh”

"avg_time_queue_ms" is **3.5ms** when running “stress_heavy.sh”

Therefor, you can set value between 3.5ms and 0.05ms. Let’s put 1.5ms (1500m) here. See hpa.yaml for full content
```
$ vi yaml/hpa.yaml
$ kubectl apply -f yaml/hpa.yaml
```

Validating HPA has successfully been created
```
$ kubectl get hpa
NAMESPACE   NAME                    REFERENCE                                 TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
default     triton-metirc-app-hpa   Deployment/nvidia-tritoninferenceserver   <unknown>/1500m   1         2         1          17s
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

















