+++
date = "2017-04-27T20:23:50-07:00"
title = "Automating advanced DC/OS installation."
draft = false
author = "Julian Neytchev"
description = "Automating advanced DC/OS installation on AWS EC2."
tags = ["dcos","docker","scripting","parallel"]
categories = ["distributed-computing","devops","automation"]
+++

In this article we will look at automating the advanced DC/OS installation procedure. We will break down the requirements and look for opportunities to speed up the lengthy installation. 

<!--more-->

### Prerequisites
* AWS account with permissions to spin up instances in EC2.
* Machine with the ability to run Bash scripts. The scripts are tested on Linux (Mac and Bash for Windows testing coming soon).
* PEM key that will allow us to SSH into our instances.
* Tmux

### Planning
* Install DC/OS version 1.8.8 on RHEL 7.2 EC2 instances.
* Identify the stages of an advanced installation.
* Develop automation around the stages.
* Make our solution scalable.

### AWS Infrastructure Considerations
We will install our DC/OS cluster on AWS EC2. This post deals only with the infrastructure part of it, i.e. how to configure and stand up the cluster. 

EC2 instance size-wise, please consider the table below. 

| | Minimal Install | Small Cluster | Recommended |
| ---: | :--- | :--- | :--- |
| Bootstrap | 1 m3.large | 1 m3.large | 1 m3.large
| Master | 1 m3.xlarge | 3 m3.xlarge | 3 m2.2xlarge
| Private | 1 m3.2xlarge | 3 m3.2xlarge | at least 5 r3.8xlarge
| Public | 1 m3.xlarge | 1 m3.xlarge | 2 r3.xlarge

Any of the above combinations will work for our purpose. Pick a smaller one if you have budgeting concerns.

Spin up all instances in EC2, making sure you configure the following:

* The AMI needs to be RHEL 7.2 (Search the AWS Market place for that string).
* Your VPC and a subnet that allows for automatic assignment of public IP addresses.
* Storage - at least 100GB root disk.
* Security group - place them all in a single security group that has the following enabled:
  + All TCP In/Out
  + All UDP In/Out
  + All ICPM

This obviously is not a secured set up at all. We will work with it just to demonstrate the set up automation. **Do not** use this configuration for any of your environments, not even Development.

Confirm that you can connect to any of your instances via SSH and your PEM key.

Create a text file with some of the IP addresses of the EC2 instances you just created.Here I have included a small cluster sample one:

`cluster.conf`
``` bash
#AWS private IPs
BOOTSTRAP=10.10.0.10
MASTER1=10.10.0.20
MASTER2=10.10.0.30
MASTER3=10.10.0.40
#AWS public IPs
AWSNODESB=54.1.2.3
AWSNODESM="54.1.2.4 54.1.2.5"
AWSNODESPRIV="54.1.2.6 54.1.2.7 54.1.2.8"
AWSNODESPUB=54.1.2.9
AWSNODES="${AWSNODESB} ${AWSNODESM} ${AWSNODESPUB} ${AWSNODESPRIV}"
```

**BOOTSTRAP, MASTER1 MASTER2 MASTER3** hold the AWS EC2 private IP addresses of the corresponding nodes.

**AWSNODES*** hold the AWS EC2 public IP address of

+ B - bootstrap node
+ M - master node(s) 
+ PRIV - private node(s)
+ PUB - public self.homelab node(s).


### DC/OS Installation
According to the official [documentation](https://docs.mesosphere.com/1.8/administration/installing/), there are 4 ways to stand up a DC/OS cluster:

* Local installer - using Vagrant you can spin a small cluster on your local machine. This is perfect for testing features in development or just getting a general idea of how the whole thing works. Major downside of this method is you can not suspend or pause your cluster, so if you have to close your laptop you will lose your cluster and you would have to destroy and up your VMs again.
* GUI installer - perfect for POCs, it allows for simplistic configuration and is a great choice for first time users.
* CLI installer - allows for full fledged configuration of every available option and guides you through each step, from preparation to verification of all prerequisites. Excellent choice for advanced system administrators who want to get good understanding of how it all works. Easy to automate and be used as a step in configuration management work flows. Best suited for small to medium size cluster installations.
* Advanced - gives you complete control of every aspect of the process and it can easily be automated to scale. Another major advantage of using this method is that it produces a maintainable DC/OS cluster. 
The only disadvantage it has is the fact that it requires advanced knowledge and careful planning of your cluster.

We will make use of the advanced installation method and combine it with an opinionated approach to our goal.

#### System and Software Requirements for all nodes
Consult the [documentation](https://docs.mesosphere.com/1.8/administration/installing/custom/system-requirements/) for the complete list and a detailed explanation for each item. 

For brevity, I am going to list the ones we are interested in here:

+ firewalld disabled.
+ Docker version 1.9.x to 1.11.x. This is important, DC/OS version 1.8.x will work **only** with those versions of the Docker engine.
+ OverlayFS storage driver.
+ Password-less sudo enabled
+ SELinux in Permissive or Disabled mode
+ `nogroup` group added
+ file compression and network tooling packages installed

Looking at those requirements we can see that we will have to reboot the machine in order for some of them to take effect (OverlayFS and SELinux mode for example). 
So, if we are to write a script that meets those requirements we would have to split it in 2 parts: 

+ one that installs prerequisites that require reboot

`prerequisites1.sh`
``` bash
# Enable OverlayFS
sudo tee /etc/modules-load.d/overlay.conf <<-'EOF'
overlay
EOF
# Disable SELinux
sudo su -c "sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config"
```

+ one that installs the rest of the prerequisites

`prerequisites2.sh`
``` bash
# Install software prerequisites and tooling
sudo yum install -y wget vim net-tools ipset telnet unzip
sudo groupadd nogroup
sudo su -c "tee /etc/yum.repos.d/docker.repo <<- 'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF"
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo su -c "tee /etc/systemd/system/docker.service.d/override.conf <<- 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay -H fd://
EOF"
# Installing docker 1.11.2
sudo yum install -y docker-engine-1.11.2
sudo systemctl start docker
sudo systemctl enable docker
```

#### Configuration and installer binary on the bootstrap node
In similar fashion, here are the prerequisites for our bootstrap node:

+ IP detection script - this script needs to be able to produce the IP (EC2 private) address.
+ genconf/config.yaml - this is the most important part of the advanced installation. Many of the settings in here once deployed, can not be changed without upgrade or even re-deployment. Since we are doing this the opinionated way, I will introduce a general case, easy to tweak starting point that will be a fine choice for 2/3 of all use cases.

`bootstrap.sh`
``` bash
source cluster.conf
IPDETECT="curl -fsSL http://169.254.169.254/latest/meta-data/local-ipv4"
IPDETECT_PUB="curl -fsSL https://ipinfo.io/ip"
BOOTSTRAP_PORT=9999
SUPASSWORD="deleteme"
# Getting 1.8.8 installer
wget https://downloads.dcos.io/dcos/stable/commit/602edc1b4da9364297d166d4857fc8ed7b0b65ca/dcos_generate_config.sh
sudo systemctl stop firewalld && sudo systemctl disable firewalld
sudo docker pull nginx
RESOLVER_IP=$(cat /etc/resolv.conf | grep nameserver | cut -d' ' -f2)
echo "Using ${RESOLVER_IP} as resolver"
BOOTSTRAP_IP=$(${IPDETECT})
mkdir genconf
# IP Detect script
cat <<EOF >genconf/ip-detect
#!/bin/bash
set -o nounset -o errexit
${IPDETECT}
EOF
# IP Detect public
cat <<EOF >genconf/ip-detect-public
#!/bin/bash
set -o nounset -o errexit
${IPDETECT_PUB}
EOF
# Making it work with 1 or 3 master nodes
EXTRA_MASTERS=""
if [ -n "${MASTER2}" ] && [ -n "${MASTER3}" ]; then
  EXTRA_MASTERS="
- ${MASTER2}
- ${MASTER3}
"
fi
# Writing config.yaml
cat <<EOF >genconf/config.yaml
bootstrap_url: http://${BOOTSTRAP_IP}:${BOOTSTRAP_PORT}
cluster_name: DCOS188
exhibitor_storage_backend: static
master_discovery: static
telemetry_enabled: true
security: permissive
rexray_config_method: file
rexray_config_filename: rexray.yaml
ip_detect_public_filename: genconf/ip-detect-public
master_list:
- ${MASTER1}
${EXTRA_MASTERS}
resolvers:
- ${RESOLVER_IP}
superuser_username: bootstrapuser
EOF
# Writing rexray.yaml
cat <<EOF >genconf/rexray.yaml
loglevel: info
storageDrivers:
  - ec2
volume:
  unmount:
    ignoreusedcount: true
EOF
# Setting superuser password to ${SUPASSWORD}
sudo bash dcos_generate_config.sh --set-superuser-password ${SUPASSWORD}
# Generating binaries
sudo bash dcos_generate_config.sh
# Running nginx on http://${BOOTSTRAP_IP}:${BOOTSTRAP_PORT}
sudo docker run -d -p ${BOOTSTRAP_PORT}:80 -v $PWD/genconf/serve:/usr/share/nginx/html:ro nginx
```

This script will:

+ create the needed configuration files 
+ download the DC/OS installation binary 
+ generate unique binary packages to be used for installation of all the other components of the cluster
+ start a web server that will offer said packages to all other nodes


#### Nodes installation
The process for installing the DC/OS software on master, private, and public nodes is roughly the same:

+ create a temporary directory on the node
+ download a script file from the web server we started in the previous step
+ run said script specifying what type of node you are installing. The choices are:

  + master
  + slave (private node)
  + slave_public (public node)

`master.sh, private.sh, public.sh`
``` bash
source cluster.conf
mkdir /tmp/dcos
pushd /tmp/dcos
wget http://${BOOTSTRAP}:9999/dcos_install.sh
sudo bash dcos_install.sh <node-type>
popd
```

### Automating the whole process 
So far, I have presented you with small scripts and a configuration file that can be copied onto the corresponding nodes, and run in a particular order.

This is what an automation work flow can look like in pseudo code:

```
copy cluster.conf, prerequisites1.sh, prerequisites2.sh -> all-nodes
copy bootstrap.sh -> boostrap-node
copy master.sh -> all-master-nodes
copy private.sh -> all-private-nodes
copy public.sh -> all-public-nodes

for node in all-nodes
  ssh -> node, run prerequisites1.sh

print "Hit Enter after rebooting all nodes in the AWS console"
wait-for-enter

for node in all-nodes
  ssh -> node, run prerequisites2.sh

ssh -> bootstrap-node, run bootstrap.sh

for node in all-master-nodes
  ssh -> node, run master.sh
  sleep 1 minute
for node in all-private-nodes
  ssh -> node, run private.sh
for node in all-public-nodes
  ssh -> node, run public.sh
```

Implementing such a work flow is trivial and I will leave that to the reader.

While simple and easy to work with, this is not scalable at all. All steps are run sequentially and the more nodes you add the longer it will take to install.

To solve this problem, I decided to issue all SCP and SSH command execution operations in parallel. In order to preserve the basic order of steps, I also implemented a waiting process that will block until all operations of the same kind have finished, for example  wait until all master nodes have finished installing before starting the private nodes installation.

The tool of my choice is the good ole' terminal multiplexor `tmux`. It happens to have all you need to tackle such a task - it is trivial to start a bunch of long running processes in parallel and then check on their state and continue once they are done.

`dcos-parallel-install.sh`
``` bash
#!/bin/bash
source cluster.conf
AWSKEY="${HOME}/.ssh/ec2default.pem"
AWSUSER="ec2-user"

function parallel_ssh(){
  local members=${1}
  local command=${2}
  tfile=$(mktemp)
  echo "Running ${tfile} on ${members}"
  cat <<EOF >${tfile}
#!/bin/bash
exec > ${tfile}.log.\$\$ 2>&1
echo "Processing member \${1}"
ssh -t -i ${AWSKEY} ${AWSUSER}@\${1} "${command}"
EOF
  chmod +x ${tfile}
  for member in ${members}; do
    if [ ! -z ${3} ]; then 
      echo "Sleeping for ${3}"
      sleep ${3}
    fi
    tmux new-window "${tfile} ${member}"
  done
}

function parallel_scp(){
  local members=${1}
  local files=${2}

  for member in ${members}; do
    echo "scp ${files} to ${member}"
    tmux new-window "scp -i ${AWSKEY} ${files} ${AWSUSER}@${member}:"
  done
}

function wait_sessions() {
  local max_wait=120
  local interval="30s"
  if [ ! -z ${1} ]; then interval=${1}; fi
  local wins=$(tmux list-sessions | cut -d' ' -f2)
  while [ ! "${wins}" == "1" ]; do
    sleep ${interval}
    (( max_wait-- ))
    wins=$(tmux list-sessions | cut -d' ' -f2)
    echo "Remaining tasks ${wins}"
    if [ ${max_wait} -le 0 ] ; then
      echo "Timeout waiting for all sessions to close."
      tmux kill-server
      exit 1
    fi
  done
}

# Main
echo "Starting tmux..."
tmux start-server
tmux new-session -d -s tester
echo "Scanning node public keys for SSH auth ..."
for i in ${AWSNODES}; do
  ssh-keygen -R ${i}
  ssh-keyscan -H ${i} >> ${HOME}/.ssh/known_hosts
done
echo "Making sure we can SSH to all nodes ..."
parallel_ssh "${AWSNODES}" "ls -l"
wait_sessions "5s"
echo "Scp-ing scripts to nodes ..."
parallel_scp "${AWSNODES}" "cluster.conf scripts/all-*"
parallel_scp "${AWSNODESB}" "scripts/boot-03-bootstrap_cust.sh"
parallel_scp "${AWSNODESM}" "scripts/master-*"
parallel_scp "${AWSNODESPRIV}" "scripts/private-*"
parallel_scp "${AWSNODESPUB}" "scripts/public-*"
wait_sessions "5s"
echo "Bootstraping all nodes, part 1"
parallel_ssh "${AWSNODES}" "sudo /home/${AWSUSER}/all-01-bootstrap1.sh"
wait_sessions
echo "---------------------------------------"
echo "Reboot from AWS console then hit Enter"
echo "---------------------------------------"
read
echo "Making sure the nodes came back up"
parallel_ssh "${AWSNODES}" "ls -l"
wait_sessions "5s"
echo "Bootstraping all nodes, part 2"
parallel_ssh "${AWSNODES}" "sudo /home/${AWSUSER}/all-02-bootstrap2.sh"
wait_sessions
echo "Preparing DC/OS binaries ..."
parallel_ssh "${AWSNODESB}" "sudo /home/${AWSUSER}/boot-03-bootstrap_cust.sh"
wait_sessions
echo "Installing master nodes ..."
parallel_ssh "${AWSNODESM}" "sudo /home/${AWSUSER}/master-01-install.sh" "1m"
wait_sessions "1m"
sleep 1m
echo "Installing private and public nodes ..."
parallel_ssh "${AWSNODESPRIV}" "sudo /home/${AWSUSER}/private-02-install.sh"
parallel_ssh "${AWSNODESPUB}" "sudo /home/${AWSUSER}/public-01-install.sh"
wait_sessions "1m"
echo "Shutting down tmux"
tmux kill-server
echo "Done"
```

Furthermore, I decided to capture to a log file the output of all processes ran in parallel for ease of debugging in case something goes wrong. All remote ssh commands are run via a temporary script in /tmp/tmp.{random} and the STDOUT and STDERR are captured to /tmp/tmp.{random}.{process-id}.

All code for this blog post can be found in my [github repository](https://github.com/dobriak/dcos-parallel-install).



