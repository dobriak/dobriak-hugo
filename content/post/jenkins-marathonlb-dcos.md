+++
date = "2017-04-25T22:05:07-07:00"
title = "Using Jenkins with a private docker registry on DC/OS"
author = "Julian Neytchev"
draft = false
description = "Using Jenkins with private Docker registry running on DC/OS"
tags = ["dcos","marathon-lb","docker","registry","ssl","jenkins"]
categories = ["distributed-computing","devops"]
+++

In this guide I will walk you through setting up your Jenkins instance to use the private docker registry we set up in the previous blog post.

<!--more-->

For reference, Part 1 can be found here: [Secure private Docker registry on DC/OS]({{< relref "docker-registry-marathonlb-dcos.md" >}} "First post of the blog series.").


### Prerequisites
* DC/OS cluster (version 1.8+) running on RHEL 7.2
* SSH access to all nodes with root privileges.
* DC/OS super user account.
* DC/OS CLI installed on your local machine and authenticated against the cluster.
* Private Docker registry configured as per [Part 1]({{< relref "docker-registry-marathonlb-dcos.md" >}} "First post of the blog series.") of this blog post series.

### Planning
In this article I am planning to outline how to:
+ start a Jenkins instance on DC/OS and configure it to use our private docker registry to pull and push images.
+ introduce the registry TLS key to the base Jenkins slave image so we can sign our push and pull operations.
+ configure a sample Jenkins build job to illustrate the set up and usage of the above.
+ make use of the internal Docker registry available through our internal marathon-lb instance at `mlbint.shared.marathon.mesos:10050`.

### Start Jenkins
For any stateful service such as Jenkins, it is always a good idea to figure out where to place your storage beforehand.
In my case, I have NFS mounts on all my private nodes in /mnt/nfs/jenkins. This way, I would not have to worry what may happen if the Jenkins process dies or gets relocated to a different node.
So I will tell DC/OS to use that location for my Jenkins instance. From my machine I will issue the following commands:

```bash
cat <<EOF >jenkins.json
{
    "storage": {
        "host-volume": "/mnt/nfs/jenkins"
    }
}
EOF
dcos package install jenkins --options=jenkins.json --yes
```
Jenkins' web UI should be accessible after couple of minutes. You can do that by clicking on the "Open in new window" icon right next to jenkins service listing in DC/OS web UI.

### Override base Jenkins slave images
The default Jenkins set up on DC/OS contains a "Cloud" Mesos configuration. As a result, Jenkins is working directly with the underlying Mesos kernel to manage a pool of build slaves that will execute the build steps we define in our jobs. 
In other words, those build slaves are just service instances (Docker containers) that will be brought up or killed depending on what Jenkins is doing.

#### Problem
Those build slaves do not know how to securely communicate with our private Docker registry out of the box. 
If we try to pull from or push an image to the private registry our build job will fail with `Get https://mlbint.shared.marathon.mesos:10050/v1/_ping: x509: certificate signed by unknown authority`.

#### Solution
We will introduce our TLS certificate to the base Docker image used to spin up the build slaves.
Said image is made available on DockerHub as `mesosphere/jenkins-dind` and can easily be altered and then used in place of the original in our build jobs. It is based on Alpine Linux and thus it is super light weight, has a package management we can leverage, and is very easy to work with.
So our plan of action is to:
 
1. create a Dockerfile that inherits from the latest release of the image (`0.5.0-alpine` as of this blog entry)
1. add the TLS key, which, if you followed [Part 1]({{< relref "docker-registry-marathonlb-dcos.md" >}} "First post of the blog series."), would be available from a web server running on the bootstrap node
1. push the resulting Docker image to our private registry so it can be used by Jenkins to instantiate build slaves
1. configure Jenkins Cloud Set up to use that new image

SSH into any private node and run the following script to accomplish steps 1 to 3:
``` bash
#!/bin/bash
BOOT_WEB_URL="http://<bootstrap-ip>:8085"
MLB_ALPINE="mlbint.shared.marathon.mesos:10050/jenkins-dind:0.5.0-alpine-mlb"
ALPINE_DIR=${HOME}/dnid-alpine
mkdir -p ${ALPINE_DIR}
pushd ${ALPINE_DIR}
# Writing Dockerfile
cat <<EOF >Dockerfile
FROM mesosphere/jenkins-dind:0.5.0-alpine
RUN ln -s /usr/lib/jvm/default-jvm/bin/java /bin/java ; ln -s /usr/lib/jvm/default-jvm/bin/javac /bin/javac
RUN apk -U add ca-certificates
ADD domain.crt /usr/local/share/ca-certificates/mlbint.shared.marathon.mesos:10050.crt
RUN update-ca-certificates
EOF
# Downloading domain.crt
wget ${BOOT_WEB_URL}/domain.crt
if [ ! -f domain.crt ]; then
  echo "domain.crt not found"
  exit 1
fi
# Building dind-alpine
sudo docker build -t ${MLB_ALPINE} .
sudo docker push ${MLB_ALPINE}
popd
echo "Done."
```
You should now have the image published to your private Docker registry.

Now for part 4:

Open the Jenkins web UI and click on **Manage Jenkins / Configure System**. At end of the page, there should be a **Cloud / Mesos Cloud section**. Click on the **"Advanced"** button. That will show you how the default base slave build image is configured. Do not touch that. Instead, let's click on the **"Add"** button (bottom left) and create our own base image configuration.

In this screen shot I have clicked on the **"Add"** button and altered most of the fields. I have chosen *"borg"* as my label, and this is the name we will use later on to tell our build job to only run on build slaves based on our modified image.

![SlaveConfig1](/images/slave1c.png)

We are not done yet. Click on the **"Advanced..."** button to configure the Docker Containerizer with all the specific details needed to pull our modified base image. The **"Docker Image"** box is too small to show the complete address, but I can imagine you already have figured out what the entry is going to look like: `mlbint.shared.marathon.mesos:10050/jenkins-dind:0.5.0-alpine-mlb`

![SlaveConfig2](/images/slave2c.png)

Do not forget to click on the **"Save"** button at the very bottom of the page.

### Jenkins job to illustrate the use case
Now let's see this new base image in action.

In the Jenkins web UI, click on **"New Item"**, fill out an item name of your choosing, then click on **"Freestyle project"** and the on the **"OK"** button at the bottom of the screen.

In the job configuration dialog, check the **"Restrict where this project can be run"** box and type the label you picked for your base image. In my example I entered *"borg"*, so this is what I am going to use here too.

Under **"Source Code Management"**, click on the **"Git"** radio button and enter the following **Repository URL**: `https://github.com/mhausenblas/cicd-demo.git`. This is a simple CI/CD demo repository that contains a Dockerfile we are going to target for a build, then push to our private Docker registry.

Under **"Build"**, click on the **"Add build step"** drop down menu and select **"Execute shell"**. Paste the following code in the **"Command"** text box that will show up:

``` bash
IMAGE_NAME="mlbint.shared.marathon.mesos:10050/${JOB_NAME}:${GIT_COMMIT}"
docker build -t $IMAGE_NAME .
docker push $IMAGE_NAME
```
Click on the **"Save"** button.

You should now be able to run the build job that will effectively build a Docker image out of the contents of the Dockerfile from the [mhausenblas/cicd-demo](https://github.com/mhausenblas/cicd-demo "mhausenblas/cicd-demo repository") github repository, then push it to our private docker registry. Be patient, as the first spin up of the new build slave will likely take a few minutes.



