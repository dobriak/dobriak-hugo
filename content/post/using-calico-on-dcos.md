+++
author = "Julian Neytchev"
date = "2017-07-18T22:00:33-07:00"
draft = true
categories = ["networking"]
tags = ["dcos","sdn","ucr","cni"]
title = "IP per Container with Calico CNI on DC/OS"
description = "IP per Container with Calico CNI on DC/OS"
+++

Calico is a Layer 3 software defined network project that runs well on DC/OS. In this blog post we will walk through installing and configuring it on DC/OS 1.9. That will allow us to attach containers to Calico and receive unique IPs for them. We will also examine the security implications and policies that can be applied.

<!--more-->

DC/OS 1.9 supports 2 ways of running your containers:

* Docker daemon - with the pros and cons that come with that
* UCR (Universal Container Runtime) - the new and future proof way to run not only native workloads but also packaged Docker images.

Our interest is with UCR and its ability to work with the CNI (Container Network Interface) open container networking standard.

### Prerquisites

* Running DC/OS cluster 1.9 with at least 3 private nodes. Either OSS or EE version will work.
* SSH access to all nodes in your cluster
* DC/OS CLI installed on your local machine and authenticated against the cluster. Also, an ssh-agent started with your key added so you can utilize ```dcos node ssh``` commands.

### Installation

* Install the etcd package from the Universe, wait until all of its nodes are functional (it takes about 10 minutes on AWS)

```bash
[laptop ~]$ dcos package install etcd --yes
This DC/OS Service is currently in preview. In order for etcd to start successfully all resources must be available in the cluster including ports, CPU shares and RAM.
We recommend a minimum of 3 nodes with 1 CPU share and 128 MB of RAM available for use by the etcd service.
Note that the service is alpha and there may be bugs, including possible data loss, incomplete features, incorrect documentation or other discrepancies.
Installing Marathon app for package [etcd] version [0.0.3]
Once the cluster initializes (<1 minute if offers are available), etcd proxies may connect by passing the argument -discovery-srv=etcd.mesos (or -discovery-srv=<framework-name>.mesos if you're not using the default), and you may discover live members by querying SRV records for _etcd-server._tcp.<framework-name>.mesos
```

* Install the Calico framework installer. This will also take long time and it will involve restarting of the private agents processes. Give it at least 20 minutes.

```bash
[laptop ~]$ dcos package install calico --yes
This DC/OS Service is currently in preview. Before installing Calico, ensure the DC/OS etcd package is installed (if not using own etcd server). Note: this scheduler may makes permament changes to all Agents and Docker Daemons in the cluster. Calico's DC/OS installation framework is currently in beta.
Installing Marathon app for package [calico] version [0.4.0]
Calico services are now running on your cluster. Follow the Calico DC/OS guide available at https://github.com/projectcalico/calico-containers/blob/master/docs/mesos/dcos.md

```

* If your cluster is running in AWS, please disable the Source/Destination Checks on all of your private nodes. To do so log into the AWS EC2 interface, right click on each of the instances that are used as private nodes and select Networking / Change Source/Dest. Check, [Yes, Disable]

Once you start using Calico for IP assignment to your containers you can make use of the automatic service discovery that comes baked in with DC/OS. This will allow you to refer to your (group of) containers by their service name instead of IP addresses. You get 2 choices of what those URLs can look like:

* <service-name>.marathon.containerip.dcos.thisdcos.directory - this one is available out of the box, no additional configuration needed
* <service-name>.marathon.mesos  - you will have to make a change to Mesos-DNS on your master nodes in order to get this working.

### Mesos-DNS change (if desired)
To get Mesos-DNS to resolve URLs in the form of <service-name>.marathon.mesos to the actual container IP, as opposed to the host on which the container is spun up, follow this procedure:

SSH log in to all of your master nodes and edit this file:

OSS DC/OS
```bash
[masterN ~]$ sudo vi /opt/mesosphere/etc/mesos-dns.json 
```
EE DC/OS
```bash
[masterN ~]$ sudo vi /opt/mesosphere/etc/mesos-dns-enterprise.json 
```

Swap the places of "host" and "netinfo" in the IPSources setting, so they read:
```bash
"IPSources": ["netinfo", "host"]
```

Restart the Mesos-DNS service
```bash
sudo systemctl restart dcos-mesos-dns
```

### Attaching containers to Calico's network via CNI

The Calico installation package creates a default network called "calico" to which we will attach our containers via CNI. The configuration file for it can be found on all private and public nodes under /opt/mesosphere/etc/dcos/network/cni/calico.cni. Note that if you want to add another network, you would have to create another .cni file in that directory and restart the dcos-mesos-slave (dcos-mesos-slave-public on public nodes) on each node.



Lets spin a few containers 









































[vagrant@localhost ~]$ dcos node
   HOSTNAME        IP                         ID                    TYPE
  10.0.0.120   10.0.0.120  b37af5ac-3cb5-4a76-93ab-86042c9c5cc9-S2  agent
  10.0.2.164   10.0.2.164  b37af5ac-3cb5-4a76-93ab-86042c9c5cc9-S0  agent
  10.0.2.247   10.0.2.247  b37af5ac-3cb5-4a76-93ab-86042c9c5cc9-S1  agent
  10.0.3.125   10.0.3.125  b37af5ac-3cb5-4a76-93ab-86042c9c5cc9-S3  agent
  10.0.4.253   10.0.4.253  b37af5ac-3cb5-4a76-93ab-86042c9c5cc9-S4  agent
master.mesos.  10.0.5.73     b37af5ac-3cb5-4a76-93ab-86042c9c5cc9   master (leader)
[vagrant@localhost ~]$ dcos node ssh --master-proxy --mesos-id=b37af5ac-3cb5-4a76-93ab-86042c9c5cc9-S2
Running `ssh -A -t core@34.209.62.229 ssh -A -t core@10.0.0.120 `
Last login: Wed Jul 19 17:03:22 UTC 2017 from 10.0.5.73 on pts/0
Container Linux by CoreOS stable (1235.12.0)
core@ip-10-0-0-120 ~ $




