+++
date = 2018-01-25T17:56:03-07:00
title = "Create VPN Tunnel to your DC/OS Cluster"
author = "Julian Neytchev"
draft = false
description = "Create VPN Tunnel to your DC/OS Cluster"
tags = ["dcos","openvpn","vpn"]
categories = ["networking"]
+++

A frequently asked question is how one can connect their client machine to a DC/OS cluster in such a way that the internal cluster network is locally addressable.

<!--more-->

This can be useful when debugging applications and testing functionality at Networking Layer of the [OSI model](https://en.wikipedia.org/wiki/OSI_model).

Another application to such connectivity is the ability to connect remotely, for example from outside of your company's network.

The proposed solution is to install and configure [OpenVPN](https://openvpn.net/) server on your DC/OS cluster. Luckily, the DC/OS Universe offers such server with nice RESTful interface on top, so adding and removing VPN users is a breeze.

Please note that this is one way of solving the above problem. This post is for pure hobby or academic purposes and you should definitely not use it in a production environment.

### Prerequisites
- DC/OS cluster with at least 1 public node accessible over the internet. This article was written using version 1.10 of DC/OS, 1.8 and 1.9 are known to also [work](https://github.com/dcos/examples/tree/master/openvpn).
- [DC/OS CLI](https://dcos.io/docs/1.10/usage/cli/install/) installed and authenticated against your cluster.
- DC/OS cluster account with super user privileges.
- Your client machine / laptop should have access to the public IP address of your public node. The OpenVPN connection will be offered on port 1194/UDP so you should make sure that this port is not closed to the outside world in your environment.
- OpenVPN client for your machine.


### Installation
Create a file called ```openvpn.json``` with the following contents:

```bash
{
  "openvpn": {
    "framework-name": "openvpn",
    "cpus": 1,
    "mem": 128,
    "instances": 1,
    "admin_port": 5000,
    "server_port": 1194,
    "ovpn_username": "<Your admin user name here>",
    "ovpn_password": "<Your admin password here>"
  }
}
```

Pass that file as an option to the ```dcos package``` command to install the OpenVPN package:

```bash
dcos package install --options=openvpn.json openvpn --yes
```

Wait until the installation has finished - it will appear as ```Running``` in your DC/OS UI -> Services UI.

### Operation
If the installation was successful you should have an OpenVPN server running on one of your public nodes. The RESTful API will be exposed on https://<Public IP>:5000 and the VPN connection end point will be at UDP <Public IP>:1194.

#### Verify
You can check the health of your VPN service by issuing a GET to its ```/status``` endpoint:

```bash
curl -k https://<Public IP>:5000/status
```
#### Adding a VPN User
An authenticated POST request to the ```/client``` endpoint should do the trick. The interface will respond with the contents of a ```ovpn``` file that can be used by the newly created user.

```bash
curl -k -u <Your admin username>:<Your admin password> -X POST -d "name=<VPN user name>" https://<Public IP>:5000/client > <VPN user name>.ovpn
```
Using the ```ovpn``` file, a user can now connect to your OpenVPN server and have access to the internal DC/OS network:

```bash
[vpn-user-laptop]sudo openvpn --config <VPN user name>.ovpn &
[vpn-user-laptop]ping -c 3 <Any internal IP address>
```

#### Removing a VPN User
In a similar fashion, removing a VPN user is just a curl away:

```bash
curl -k -u <Your admin username>:<Your admin password> -X DELETE https://<Public IP>:5000/client/<VPN user name>
```

### OpenVPN removal
You can only remove that package from the command line:

```bash
dcos package uninstall openvpn --app-id=/openvpn
```

_Notes:_

* If port 5000/TCP is not publicly accessible, the same RESTful calls can be made from inside any master or agent node, just substitute ```<Public IP>``` with your private IP address.
* The admin username and password are stored in Zookeeper. They will be reused during a re-spawn if for any reason the OpenVPN server instance is destroyed. If you would like to uninstall OpenVPN, as a best practice, make sure to remove the ```/openvpn``` data node in Zookeeper as well.
