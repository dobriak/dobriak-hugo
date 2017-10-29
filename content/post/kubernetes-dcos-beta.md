+++
date = 2017-10-28T18:13:41-07:00
title = "Install Kubernetes on DC/OS (beta)"
author = "Julian Neytchev"
draft = false
description = "Install Kubernetes on DC/OS 1.10 (beta)"
tags = ["dcos","kubernetes","installation"]
categories = ["services","orchestration"]
+++


My [employer](https://mesosphere.com/) recently [announced](https://mesosphere.com/blog/dcos-1_10-kubernetes/) first class support for running Kubernetes on top of DC/OS version 1.10. In this post we will examine how to get started with using Kubernetes on DC/OS.

<!--more-->

### Prerequisites

* DC/OS version 1.10, either OS or EE edition
* At least 3 private nodes with minimum of 6 CPU 6GB memory and 700MB disk
* Machine with the DC/OS CLI installed and connected to your cluster
* kubectl installed preferably on the same machine as the DC/OS CLI


### Install from the CLI

To initiate a basic Kubernetes cluster installation:

``` bash
dcos package install beta-kubernetes
```

This will take some time to install, you can watch the DC/OS UI for the progress of the operation. Once the Kubernetes service is in a healthy state and all 19 tasks are running, you can go to the next step.

### Connecting to your Kubernetes cluster

Currently, we will have to initiate a  proxy connection and instruct kubectl to use it in order to communicate with the Kubernetes cluster.

Open a separate terminal session and instatiate said connection on port 9000:

``` bash
ssh -4 -i /path/to/your/key -N -L 9000:apiserver-insecure.kubernetes.l4lb.thisdcos.directory:9000 <SSH_USER>@<MASTER_IP>
```

In the original terminal session, configure kubectl:

``` bash
kubectl config set-cluster dcos-k8s --server=http://localhost:9000
kubectl config set-context dcos-k8s --cluster=dcos-k8s --namespace=default
kubectl config use-context dcos-k8s
```

Verify that kubectl can interact with Kubernetes:

``` bash
kubectl get nodes
```

That is it! You can now use your own Kubernetes cluster running on top of DC/OS!

### Notes and disclaimers

* This tutorial is meant to introduce you to installing the beta version of the Kubernetes framework on DC/OS. As a beta software this _NOT_ suitable for production.

* Currently, you can only have one Kubernetes cluster per DC/OS cluster

* DC/OS and Mesos tasks can only reach Kubernetes Services if kube-proxy is running on the DC/OS agent where the request originates from.

* Here is a complete list of all [limitations](https://docs.mesosphere.com/service-docs/beta-kubernetes/0.2.2-1.7.7-beta/limitations/) as of this writing (DC/OS version 1.10.0, beta-kubernetes 0.2.2-1.7.7)
