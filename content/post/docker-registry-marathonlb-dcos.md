+++
date = "2017-04-24T16:45:12-07:00"
title = "Secure private Docker registry on DC/OS"
author = "Julian Neytchev"
draft = true
description = "Short guide on how to set up a private docker registry behind an internal marathon-lb instance all running on DC/OS"
tags = ["DCOS","marathon-lb","docker","registry","SSL","TLS"]
categories = ["Distributed Computing"]
+++

This is a short guide on how to set up a private docker registry behind an internal marathon-lb instance all running on DC/OS. Since marathon-lb is a Layer 7 load balancer we will use it to terminate SSL for our private registry and avoid using it in insecure mode. We will use self-signed TLS certificates for that purpose.

### Prerequisites
* DC/OS cluster (version 1.8+) running on RHEL 7.2
* SSH access to all nodes with root privileges.
* DC/OS super user account.

### Planning
+ We want to offer private docker registry to all users of our DC/OS cluster. 
+ We will use self signed certificates to secure the communications with the registry. 
+ We will make use of marathon-lb's ability to terminate SSL
+ We will deploy the internal marathon-lb in a group called "shared" for better separation of services.
+ The internal marathon-lb URL address will be `mlbint.shared.marathon.mesos`
+ We will offer the private registry on port 10050 of the above URL.
+ (Optional) Storage for our private registry is going to be on an NFS mount.

### Generating self signed keys
The following script snippet will generate a self-signed TLS keys you can use to terminate SSL with.
The most important part of it is setting the correct repo URL as the CN (Common Name) for your TLS key. You must use the exact URL where you will be offering the SSL termination or it will not work.
In our case, since we are terminating at our internal marathon-lb the CN is going to be the same as the marathon-lb URL.
For simplicty, run this snippet in you home directory on the bootstrap server:

``` bash
REPO_URL=mlbint.shared.marathon.mesos
echo "Generating key, crt and pem file for ${REPO_URL}"
openssl req -newkey rsa:4096 -nodes -sha256 \
 -keyout domain.key  -x509 -days 365 \
 -out domain.crt \
 -subj "/C=US/ST=Florida/L=Miami/O=IT/CN=${REPO_URL}"
echo "Generating pem"
cat domain.crt domain.key | tee registry.pem
```

Note: the length of you common name (CN) must be less than 64 characters.

### Making the self-signed keys available to the nodes in the cluster
Start a web server in a location accessible to all nodes in you DC/OS cluster and place the key, crt and pem files under the web root or any other directory, so they are accessible via simple `wget` or `curl -O` command.
Your bootstrap node is a perfect candidate for that location:

``` bash
WEB_PORT=8085
WEB_DIR=${HOME}/webserver
mkdir -p ${WEB_DIR}
# Copy domain.crt, domain.key, registry.pem to ~/webserver 
# in the previous step we generated them in the HOME directory of the bootstrap server so lets move them to the web server directory
cd ${HOME}
mv domain.crt domain.key registry.pem ${WEB_DIR}
pushd ${WEB_DIR}
python -m SimpleHTTPServer ${WEB_PORT} &> /dev/null &
popd
```
Verification: you should be able to issue wget http://<ip-of-bootstrap>:8085/domain.crt from any node and be able to download the file in question.

### Distribute self signed keys to all nodes in your cluster
The self signed TLS keys need to be placed in specific directories on all of your private nodes. This script can do the job for you:

``` bash
DOMAIN_NAME=mlbint.shared.marathon.mesos
PORT=10050
BOOT_WEB_URL="http://<bootstrap-ip>:8085"

echo "Adding cert from ${DOMAIN_NAME} to the local CA trust"
wget ${BOOT_WEB_URL}/{domain.crt,registry.pem}
echo "Adding cert from ${DOMAIN_NAME} to the list of trusted certs"
sudo cp domain.crt /etc/pki/ca-trust/source/anchors/${DOMAIN_NAME}.crt
sudo mkdir -p /etc/docker/certs.d/${DOMAIN_NAME}:${PORT}
sudo cp domain.crt /etc/docker/certs.d/${DOMAIN_NAME}:${PORT}/ca.crt
sudo update-ca-trust

# This is for DCOS version 1.8 and lower only
CACERT=/opt/mesosphere/active/python-requests/lib/python3.5/site-packages/requests
echo "DC/OS 1.8 specific cacerts manipulation"
sudo cp  ${CACERT}/{cacert.pem,cacert.pem_original}
sudo cat registry.pem >> ${CACERT}/cacert.pem

# ***WARNING***
# Be careful if you have any other services running on the private node.
# Restarting the docker service on the private node will force stateless
# services to migrate to another node.
sudo systemctl restart docker
```

### Installing internal Marathon-LB instance
If you are running the enterprise version of DC/OS you should create service account for your marathon-lb instance to work correctly.

Create a configuration file on your machine (or any machine that has the dcos CLI installed and authenticated) and name it mlbint.json. Paste the following contents in it:
``` json
{
    "marathon-lb": {
        "name": "shared/mlbint",
        "bind-http-https": false,
        "haproxy-group": "internal",
        "role": "",
        "secret_name": "mlb-secret"
    }
}
```
Note: "secret_name" is only needed if you are running the enterprise version of DC/OS. This refers to the service account you created for marathon-lb.

Install marathon-lb with the following command:
``` bash
dcos package install --options=mlbint.json marathon-lb --yes
```

Open the DC/OS web UI, login with super user account and click on Services / shared / mlbint / Edit / Optional. Click on the URIs field and enter the web server URL/path to the registry.pem file `http://<boot-ip>:8085/registry.pem`. Click on "Deploy Changes".

### Installing Docker registry service
Before starting the private docker registry service, decide on a private node (`<private-ip>`) to pin the service to. Best practice is to attach external storage to that node and point the registry to it. Popular and decent choice for that is a NFS mount. In our case I've mounted my NFS export to /mnt/nfs/registry.

Create registry.json with the following contents:

``` json
{
  "volumes": [],
  "id": "/shared/registry",
  "cmd": null,
  "args": null,
  "user": null,
  "env": {
    "STORAGE_PATH": "/var/lib/registry"
  },
  "instances": 1,
  "cpus": 0.2,
  "mem": 256,
  "disk": 0,
  "gpus": 0,
  "executor": "",
  "constraints": [
    [
      "hostname",
      "LIKE",
      "<private-ip>"
    ]
  ],
  "fetch": [
    {
      "uri": "http://<bootstrap-ip>:8085/domain.crt",
      "extract": true,
      "executable": false,
      "cache": false
    },
    {
      "uri": "http://<bootstrap-ip>:8085/domain.key",
      "extract": true,
      "executable": false,
      "cache": false
    }
  ],
  "storeUrls": [],
  "backoffSeconds": 1,
  "backoffFactor": 1.15,
  "maxLaunchDelaySeconds": 3600,
  "container": {
    "type": "DOCKER",
    "volumes": [
      {
        "containerPath": "/var/lib/registry",
        "hostPath": "/mnt/nfs/registry",
        "mode": "RW"
      }
    ],
    "docker": {
      "image": "registry:2.5.1",
      "network": "BRIDGE",
      "portMappings": [
        {
          "containerPort": 5000,
          "hostPort": 5000,
          "servicePort": 10050,
          "protocol": "tcp",
          "name": "registry",
          "labels": {
            "VIP_0": "/registry:5000"
          }
        }
      ],
      "privileged": true,
      "parameters": [],
      "forcePullImage": false
    }
  },
  "healthChecks": [
    {
      "protocol": "TCP",
      "portIndex": 0,
      "gracePeriodSeconds": 300,
      "intervalSeconds": 60,
      "timeoutSeconds": 20,
      "maxConsecutiveFailures": 3,
      "ignoreHttp1xx": false
    }
  ],
  "readinessChecks": [],
  "dependencies": [],
  "upgradeStrategy": {
    "minimumHealthCapacity": 0,
    "maximumOverCapacity": 0
  },
  "labels": {
    "HAPROXY_GROUP": "internal",
    "HAPROXY_0_SSL_CERT": "/mnt/mesos/sandbox/registry.pem",
    "HAPROXY_0_BACKEND_REDIRECT_HTTP_TO_HTTPS": "false",
    "HAPROXY_0_VHOST": "<private-ip>"
  },
  "acceptedResourceRoles": null,
  "ipAddress": null,
  "residency": null,
  "secrets": {},
  "taskKillGracePeriodSeconds": null,
  "portDefinitions": [
    {
      "port": 10050,
      "protocol": "tcp",
      "labels": {}
    }
  ],
  "requirePorts": true
}
```
Don't forget to replace `bootstrap-ip` with the IP address of your bootstrap node and `private-ip` with the IP address of the private DC/OS node we are going to pin the docker registry to.
Th important part of this long JSON file can be found under the `labels` definition. This is how we tell our internal marathon-lb instance to expose the docker registry service and use the specified pem file to secure the communications.

Install the private docker registry with the following command:

``` bash
dcos marathon app add registry.json
```

### Testing our setup
Log in into any of the private nodes in your cluster and test with something like:

```bash
curl https://mlbint.shared.marathon.mesos:10050/v2/_catalog
sudo docker pull alpine
sudo docker tag alpine mlbint.shared.marathon.mesos:10050/alpine
sudo docker push mlbint.shared.marathon.mesos:10050/alpine
```

### Bonus 1: using this setup from Jenkins running on DC/OS
In Part 2 of this blog series we will spin up a Jenkins instance and have it use our set up to build push and pull images from our private repository.

### Bonus 2: using Let's Encrypt certificates
Let's Encrypt issues free TLS certificates with 90 days validity. In Part 3 of this blog series we will see how we can automate this process to keep our private docker repo safe.
