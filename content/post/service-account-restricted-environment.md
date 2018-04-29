+++
date = 2018-04-29T15:44:45-07:00
title = "DC/OS Service Accounts in Restricted Environments"
author = "Julian Neytchev"
draft = false
description = "DC/OS Service Accounts in Restricted Environments"
tags = ["dcos","service-account","restricted-environment","JWT","openssl"]
categories = ["automation","security"]
+++

We are so used to having handy little pieces of software that help us do our jobs better. If you too work in the DevOps world and write automation for infrastructure or software (or pretty much anything else) you would know what I mean. Take `jq` for an example: can you imagine writing any sort of shell script that interacts with any JSON producing API and _NOT_ use good ole trustworthy `jq`?

Now, imagine you are writing such automation script for BigCompany &trade; and your environment is air gapped and you can not install `jq` or `python` or `nifty-help-tool`.

_What do you do?_

Well you revert to basics.

Had to solve exactly that kind of problem for a client, so I though I should jot down my notes in hopes that might be helpful to someone else down the line.

<!--more-->

### The Problem

BigCompany &trade; would like to integrate their external CI/CD pipeline with their DC/OS cluster in such a way that they can automatically launch container instances on the cluster as soon as the pipeline finishes running and new Docker image is built and pushed to their repository.

Such integration is very common and fairly easy to set up if the CI/CD pipeline is running inside of DC/OS. You get to use the native service discovery mechanisms available to you and it is just a matter of configuring a plugin and clicking "Deploy".

In our case though, the pipeline location and its configuration are not negotiable.

Also, here is the kicker: I am not allowed to install any helpers such as `jq` or even `pyhton` on the machines that will run the integration jobs.

The main problem here is: when working with DC/OS service accounts one needs to programmatically interact with its security service. The process looks like so:

* Using your service account and its associated private key you create a claim that you post to said API
* DC/OS responds with a blob of JSON data you have to parse to get a token.
* Using that extracted token your service account can now interact with the rest of the DC/OS cluster (depending on a set of permissions)
* All tokens have a lifespan of about 5 days. Upon expiration, run through the first 3 steps to renew our expired token.

Now, if we were lucky enough to have `jq` or `python` available to us, we could have just relied on their magic to create, sign and parse JWT data. All of this would have been encapsulated in a few lines of code.

### The Solution

We will start with the set up part first. We will first create a service group in Marathon called `dev` that will hold all of our development environment services.

Next, we will create a service account that will be used to spin up and destroy container instances in our `dev` group (only!). Along with that, we will create a public and private key pair that can be used to sign token claims.

Finally, using the generated files, we will write a script that can be run as a job (plan step) on the external pipeline that will implement the workflow described in the "Problem" section.

#### Prerequisites

* DC/OS Enterprise Edition version 1.11.x or newer
* Machine (let's call it laptop) that has the DC/OS CLI installed and configured with a super user account

#### Preparation - on your laptop

Using the DC/OS CLI create a `dev` Marathon group
```bash
echo '{"id":"/dev"}' > dev-group.json
dcos marathon group add < dev-group.json
```

Create service account, keys
```bash
SERVICE_PRINCIPAL="bamboo"
NAMESPACE="dev"

# Installing EE cli
dcos package install --cli dcos-enterprise-cli --yes

# Get root CA
curl -k -v $(dcos config show core.dcos_url)/ca/dcos-ca.crt -o dcos-ca.crt

# Create pub / priv keys
dcos security org service-accounts keypair ${SERVICE_PRINCIPAL}-priv.pem ${SERVICE_PRINCIPAL}-pub.pem
chmod 400 ${SERVICE_PRINCIPAL}-pub.pem

# Create service account
dcos security org service-accounts create -p ${SERVICE_PRINCIPAL}-pub.pem -d "DCOS service account for external integration" ${SERVICE_PRINCIPAL}
dcos security org service-accounts show ${SERVICE_PRINCIPAL}

# Create secret if you will be using it from inside of DC/OS, so you won't need to distribute the private keys.
dcos security secrets create-sa-secret ${SERVICE_PRINCIPAL}-priv.pem ${SERVICE_PRINCIPAL} as_secret_${SERVICE_PRINCIPAL}

# Grant permissions
dcos security org users grant ${SERVICE_PRINCIPAL} dcos:adminrouter:ops:mesos full
dcos security org users grant ${SERVICE_PRINCIPAL} dcos:adminrouter:ops:slave full
# Assign appropriate permissions depending on the purpose of the service account
# In our case, I want my service account SERVICE_PRINCIPAL to have full
# control over apps running in the Marathon NAMESPACE service group
dcos security org users grant ${SERVICE_PRINCIPAL} dcos:adminrouter:service:marathon full
dcos security org users grant ${SERVICE_PRINCIPAL} dcos:service:marathon:marathon:services:/${NAMESPACE} full

```
#### Script to run in your restricted environment

Now with the service account created and assigned appropriate permissions, let's create a BASH script that will create a JWT claim and use it to request an authentication token.

The script is going to use the private key associated with the service account to sign the claim, and it has no external dependencies other than the (linux standard) `openssl`.

Make sure to enter your master node IP (or URL if behind a load balancer) and the name of your service account. You can also pass the account name and the contents of the private key as environment variables (`SA_NAME` and `SA_SECRET`)

```
#!/bin/bash
set -o pipefail
# get_sa_token.sh - run inside your restricted environment
# Create RS256 JWT claim for a service account
# and get an auth token based on it.
# Not using any external binaries (jq,python).

# Inspired by https://stackoverflow.com/questions/46657001/how-do-you-create-an-rs256-jwt-assertion-with-bash-shell-scripting/46672439#46672439
MASTER_URL="<Master.IP.or.URL>"
svc_account=${SA_NAME:-"bamboo"}
private_key="${svc_account}-priv.pem"
secret=${SA_SECRET:-"$(cat ${private_key})"}

b64enc() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
rs_sign() { openssl dgst -binary -sha256 -sign <(printf '%s\n' "$1"); }

# Claim header and payload
header='{"typ":"JWT","alg":"RS256"}'
payload='{"uid":"'${svc_account}'"}'

signed_content="$(printf %s "$header" | b64enc).$(printf %s "$payload" | b64enc)"
sig=$(printf %s "$signed_content" | rs_sign "$secret" | b64enc)
claim=$(printf '%s.%s' "${signed_content}" "${sig}")

echo '{"uid":"'${svc_account}'","token":"'${claim}'"}' > login_token.json
# Request auth token based on the claim
curl --cacert dcos-ca.crt -X POST -H "content-type:application/json" -d @login_token.json  ${MASTER_URL}/acs/api/v1/auth/login > authorization_token.json
# Get just the token part from the json response (no jq)
token=$(cat authorization_token.json | grep "token" | cut -d':' -f2 | tr -d '"' | tr -d [:space:])
echo "${token}" > token

# Cleanup
rm login_token.json authorization_token.json
echo "Done."
```

Please note that all authentication tokens have a lifespan of 5 days. When the token expires API calls will return a `401 Unauthorized` error, and you can programmatically catch it and deal with it, for example you can just re-run the script to get a fresh token.

Now, using the auth token stored in `token` you can interact with DC/OS services and APIs as allowed by the service account permissions. In our case we assigned permissions that should let us spin up apps in Marathon's `/dev` service group, so to test our set up we can do something like:

```bash
echo '{
  "id": "/dev/testapp",
  "instances": 1,
  "portDefinitions": [],
  "container": {
    "type": "DOCKER",
    "volumes": [],
    "docker": {
      "image": "nginx"
    }
  },
  "cpus": 0.1,
  "mem": 128,
  "requirePorts": false,
  "networks": [],
  "healthChecks": [],
  "fetch": [],
  "constraints": []
}' > testapp.json

curl --cacert dcos-ca.crt -H "Content-type: application/json" -H "Authorization: token=$(cat token)" -X POST ${MASTER_URL}/service/marathon/v2/apps -d @testapp.json
```

That's it! You should now be able to use DC/OS service accounts to interact with services and APIs even in completely locked down environments.
