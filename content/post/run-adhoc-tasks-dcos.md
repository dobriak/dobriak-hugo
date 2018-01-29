+++
date = 2018-01-28T20:46:39-07:00
title = "Run Adhoc Tasks on DC/OS"
author = "Julian Neytchev"
draft = false
description = "Run Adhoc Tasks on DC/OS"
tags = ["dcos","eremetic","ad-hoc"]
categories = ["compute"]
+++

DC/OS can run Marathon or Kubernetes for orchestrating long running tasks and Metronome / Chronos for scheduled ones. That leaves space for a mechanism to run ad-hoc tasks that do not need to be treated as long running nor scheduled ones.

<!--more-->

To address this gap we can easily install and use [Eremetic](https://github.com/eremetic-framework/eremetic)

### Prerequisites
* DC/OS cluster version 1.10+
* DC/OS CLI installed and configured
* Ability to SSH into any node.

### Installation
Eremetic can easily be installed from the DC/OS Catalog or the CLI.

```bash
[laptop]$ dcos package install eremetic --yes
By Deploying, you agree to the Terms and Conditions https://mesosphere.com/catalog-terms-conditions/#community-services
This DC/OS Service is currently in preview. There may be bugs, incomplete features, incorrect documentation, or other discrepancies. Preview packages should never be used in production!
Installing Marathon app for package [eremetic] version [0.27.0-0.0.1]
DC/OS Eremetic service has been installed. You can access the API within the cluster at http://eremetic.marathon.l4lb.thisdcos.directory:8000 or outside the cluster at https://<dcos-master>/service/eremetic/.

New User Tutorial: https://github.com/dcos/examples/tree/master/eremetic
```

### Operation
To run an ad-hoc task, one can use the UI that comes with the framework. It will be available at ```http://<master IP>/service/eremetic/```.

![EremeticUI](/images/eremetic-ui.png)

Eremetic can also be interacted with programatically. It exposes a RESTful interface that allows for easy operation:

```bash
[laptop]$ eval `ssh-agent`; ssh-add /path/to/key
[laptop]$ dcos node ssh --leader --master-proxy

[master]$ task_id=$(curl -H "Content-type: application/json" -X POST -d  '{"docker_image":"busybox","command":"date","task_cpus":0.1,"task_mem":100}'  http://eremetic.marathon.l4lb.thisdcos.directory:8000/task)
# Inspect the status of our task
[master]$ curl http://eremetic.marathon.l4lb.thisdcos.directory:8000/task/${task_id} | jq .
{
  "task_cpus": 0.1,
  "task_mem": 100,
  "command": "date",
  "args": null,
  "user": "root",
  "env": null,
  "masked_env": null,
  "image": "busybox",
  "volumes": null,
  "ports": null,
  "status": [
    {
      "time": 1517192445,
      "status": "TASK_QUEUED"
    },
    {
      "time": 1517192446,
      "status": "TASK_STAGING"
    },
    {
      "time": 1517192449,
      "status": "TASK_RUNNING"
    },
    {
      "time": 1517192449,
      "status": "TASK_FINISHED"
    }
  ],
  "id": "eremetic-task.0ec1ed88-2bde-47ec-aa46-a867686fa3fe",
  "name": "Eremetic task k7Ml7bZ5",
  "network": "",
  "dns": "",
  "framework_id": "eremetic1",
  "slave_id": "d9a24214-7d0c-4255-a38d-d0f4eba2a13c-S1",
  "slave_constraints": null,
  "hostname": "10.0.0.249",
  "retry": 0,
  "callback_uri": "",
  "sandbox_path": "/var/lib/mesos/slave/slaves/d9a24214-7d0c-4255-a38d-d0f4eba2a13c-S1/frameworks/eremetic1/executors/eremetic-task.0ec1ed88-2bde-47ec-aa46-a867686fa3fe/runs/715c5f99-0a92-40dd-ace8-dda8ea1b92cc",
  "agent_ip": "10.0.0.249",
  "agent_port": 5051,
  "force_pull_image": false,
  "fetch": null
}
```

### Uninstall
Uninstalling Eremetic is also very straight forward:

```bash
[laptop]$ dcos package uninstall eremetic --yes
Uninstalled package [eremetic] version [0.27.0-0.0.1]
DC/OS Eremetic service has been uninstalled.
```













