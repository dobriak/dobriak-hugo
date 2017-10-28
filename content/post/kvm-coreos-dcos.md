+++
date = 2017-10-28T13:29:29-07:00
title = "DC/OS on KVM CoreOS VMs"
author = "Julian Neytchev"
draft = true
description = "Automating installation of DC/OS on KVM CoreOS VMs"
tags = ["dcos","coreos","kvm","libvirt","qemu","scripting","parallel"]
categories = ["distributed-computing","devops","automation"]
+++

In this article we will automate the DC/OS installation procedure specifically for CoreOS VMs running on KVM (libvirt).

<!--more-->

I have been toying with the idea of setting up a home lab server where I can freely break things and abuse the hardware to my liking, without having to pay a monstrous AWS bill. I currently have my eyes set on two different boxes and have decided to not pull the trigger until I find their [WAF](https://en.wikipedia.org/wiki/Wife_acceptance_factor). 

Meanwhile, I am going to try to make use of a relatively old NUC with i5 processor and 16GB of memory and see if I can experiment with DC/OS (on the cheap). On it, I have a fresh installation of headless Fedora Server with the KVM group installed. Everything is going to be automated so there is no need of a graphical server. I will run all steps of the set up from that machine.

### Prerquisites
* Box with at least 16GB of memory you can SSH into and manipulate
* Wired connection to the internet. Wireless would be much harder to set up.
* Latest Fedora Server, of course anything else from the RHEL family would work, or Debian / Ubuntu Server (if you want to adjust the commands from dnf to apt)
* Latest KVM software - ```sudo dnf install -y @virtualization ; sudo systemctl enable libvirtd ; sudo systemctl start libvirtd```
* Tmux, sshpass, git ```sudo dnf install -y tmux sshpass git```
* Make sure you have public and private keys in your ```~/.ssh/``` directory. If you do not, generate them with ```ssh-keygen```.

### Networking setup

Our DC/OS cluster will operate on the default internal NAT-ed network bridge (virbr0) created by the KVM installer. This usually is in the ```192.168.122.0/24``` range.

We will also need to expose our DC/OS UI and public node to our home network so those can be accessed without having to create any tunnels. 
My home network is in the ```192.168.1.0/24``` range. In order for our VMs to be able to get an IP address on the home network, we will create a [network bridge](https://fedoramagazine.org/build-network-bridge-fedora/) (```br0```).

The wired network adapter on my NUC is named ```enp0s25```. I am going to use it to set up the ```br0``` bridge connection.

``` bash
sudo nmcli connection add ifname br0 type bridge con-name br0
sudo nmcli connection add type bridge-slave ifname enp0s25 master br0
```

### Planning
* Create automation script that downloads a disk image of the correct CoreOS verion
* Configure and spin up CoreOS VMs
* Run a script to automate the installation of the DC/OS bits on those VMs
* Verify the installation


### Get the code from github

``` bash
git checkout https://github.com/dobriak/kvm-coreos-dcos.git
```

### Explanation of ```setup.sh```
* Download the correct CoreOS version - as of the current DC/OS version (1.10.0) the recommended CoreOS version is 1235.9.0 and we do that in the ```initialSetup()``` [function](https://github.com/dobriak/kvm-coreos-dcos/blob/a19e10fc6162c2ce9f8eefa417e3b66bfbdc8ddb/setup.sh#L9)

* Edit ```setup.sh``` and set the ```USER``` variable to your user (or user whose public and private keys will be used to authenticate against your CoreOS VMs)

* The following VMs will be created:
    * **b** - bootstrap, used only to set up the cluster. Can later be removed if you are not planning to run any upgrades
    * **m1** - master node 1, this will be a single master cluster as the resources are limited. The master node gets an "external" facing leg on the home network so we can access the DC/OS GUI.
    * **a1** and **a2** - agent nodes 1 and 2, this is where our services will be running
    * **p1** - public node 1, this is our "external" facing node for anything that you may want to expose outside of your cluster

* All network MAC and IP addresses are hardcoded in an [array](https://github.com/dobriak/kvm-coreos-dcos/blob/a19e10fc6162c2ce9f8eefa417e3b66bfbdc8ddb/setup.sh#L161) . so if any of those IPs collide with yours, feel free to change them (don't forget to do so in the cluster.conf file too).

* Same with the directories under /var/lib/libvirt - standard naming scheme is followed, but you have a different set up, feel free to edit the ```domain_dir``` and ```image_dir``` variables in ```setup.sh```.

### Explanation of ```dcos_parallel_install.sh```
* This script is based on a [previous article](https://dobriak.github.io/post/automated-advanced-dcos-installation/) and it is, obviously, adapted to work on CoreOS.

* If you need to change any IP addressing, please make sure to also update cluster.conf, as this is what all installation scripts use to connect to the CoreOS VMs

* Make sure to echo your user's password to a file: ```echo "<my password here>" > pass.txt``` this is used by sshpass to automate ssh key exchange with your VMs


### Run the installation

``` bash
sudo ./setup.sh 
./dcos_parallel_install.sh
```

To clean up everything created by the above scripts, just re-run setup with a clean as the only parameter:

``` bash
sudo ./setup.sh clean
```

You are done!
You should be able to access the [DC/OS UI](http://192.168.1.222) at ```http://192.168.1.222``` (or whichever IP you have decided to use)

### References
* [Advanced DC/OS Installer](https://docs.mesosphere.com/1.10/installing/custom/advanced/)

* [Running CoreOS Container Linux on libvirt](https://coreos.com/os/docs/latest/booting-with-libvirt.html)

