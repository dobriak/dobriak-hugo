+++
date = 2018-01-27T12:34:45-07:00
title = "Secure Kafka Install on DC/OS"
author = "Julian Neytchev"
draft = false
description = "Secure Kafka Install on DC/OS"
tags = ["dcos","kafka","security","service-account"]
categories = ["services"]
+++

[Apache Kafka](https://kafka.apache.org/) is a distributed high-throughput publish-subscribe messaging system with strong ordering guarantees. Kafka clusters are highly available, fault tolerant, and very durable. DC/OS offers a [single click install](https://github.com/dcos/examples/tree/master/kafka/1.10) of Kafka as a framework which is great for trying out. When it comes to actually using it in a Dev/Test/Production environment, you should definitely consider securing your Kafka installation. You will be required to do so if you are running your DC/OS EE cluster in ```strict``` mode.

<!--more-->
Luckily, the Enterprise version of DC/OS comes with tooling that simplifies secure installation and usage of Kafka.

There are many possible configuration combinations, so here I will present the one that I encounter the most and is by design an excellent starting point for new users. It also represents service usage best practices of compartmentalization and security.

### Planning

Let's assume we have a team in our organization (let's call it **coolteam**) that would like to use Kafka for their applications and that they would like their own instance.

The following steps will be taken to achieve our goal:

* Provision a service account that can only interact with Kafka.
* Create namespace for our team and establish an easy way of adding team members to it.
* Grant appropriate permissions to that namespace.
* Make use of external ZooKeeper for increased capacity (default installation uses the system ZooKeeper instance).

### Prerequisites

* DC/OS Enterprise Edition cluster version 1.10 and up. At least 4 private nodes with sufficient resources (at least: 2 vCPUs, 4GB memory, 10GB disk).
* DC/OS Enterprise Edition CLI installed and configured.
* Superuser access to create service accounts and configure access permissions.
* Ability to SSH into master nodes to perform initial validation.
* Ability to run python scripts or use [jq](https://stedolan.github.io/jq/) processor.

### Installation

Create a ```coolteam``` namespace for our team. Also, create a default user and assign it to said group:

```bash
TEAM="coolteam"
KROLE=${TEAM}'__kafka-role'
TKN=$(dcos config show core.dcos_acs_token)
URL=$(dcos config show core.dcos_url)

dcos package install --cli dcos-enterprise-cli --yes
dcos security org groups create ${TEAM}
dcos security org users create -d "Default ${TEAM} user" -p "sup3rs3cr3T" ctuser
dcos security org groups add_user ${TEAM} ctuser

dcos security org groups grant ${TEAM} dcos:adminrouter:service:marathon full
dcos security org groups grant ${TEAM} dcos:service:marathon:marathon:services:/${TEAM} full
dcos security org groups grant ${TEAM} dcos:adminrouter:ops:mesos full
dcos security org groups grant ${TEAM} dcos:adminrouter:ops:slave full
```

Adding any other members would follow the same pattern:

```bash
dcos security org groups add_user ${TEAM} <another-user-id>
```

Now, once we have the ability to associate users to the coolteam group, let's work on creating a service account and a secret using our Enterprise Edition DC/OS CLI:

```bash
# Get our certificate authority
curl -k ${URL}/ca/dcos-ca.crt -o dcos-ca.crt

# Create service account
dcos security org service-accounts keypair ${TEAM}-priv.pem ${TEAM}-pub.pem
chmod 400 ${TEAM}-pub.pem
dcos security org service-accounts create -p ${TEAM}-pub.pem -d "CoolTeam Kafka service account" ${TEAM}
dcos security org service-accounts show ${TEAM}

dcos security secrets create-sa-secret ${TEAM}-priv.pem ${TEAM} ${TEAM}/kafka
# Use --strict if running in strict security mode
#dcos security secrets create-sa-secret --strict ${TEAM}-priv.pem ${TEAM} ${TEAM}/kafka
dcos security secrets list ${TEAM}

# Create
# Next line not needed if running in strict mode
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:task:user:nobody -d '{"description":"Allows Linux user nobody to execute tasks"}' -H 'Content-Type: application/json'
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:framework:role:${KROLE} -d '{"description":"Controls the ability of '${KROLE}' to register as a framework with the Mesos master"}' -H 'Content-Type: application/json'
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:reservation:role:${KROLE} -d '{"description":"Controls the ability of '${KROLE}' to reserve resources"}' -H 'Content-Type: application/json'
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:volume:role:${KROLE} -d '{"description":"Controls the ability of '${KROLE}' to access volumes"}' -H 'Content-Type: application/json'
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:reservation:principal:${TEAM} -d '{"description":"Controls the ability of '${TEAM}' to reserve resources"}' -H 'Content-Type: application/json'
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:volume:principal:${TEAM} -d '{"description":"Controls the ability of '${TEAM}' to access volumes"}' -H 'Content-Type: application/json'

# Grant
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:framework:role:${KROLE}/users/${TEAM}/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:reservation:role:${KROLE}/users/${TEAM}/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:volume:role:${KROLE}/users/${TEAM}/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:task:user:nobody/users/${TEAM}/create
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:reservation:principal:${TEAM}/users/${TEAM}/delete
curl -X PUT --cacert dcos-ca.crt -H "Authorization: token=${TKN}" ${URL}/acs/api/v1/acls/dcos:mesos:master:volume:principal:${TEAM}/users/${TEAM}/delete

# Currently, this is required for TLS to work
dcos security org users grant coolteam dcos:superuser full

```

Now, let's enable SSL encryption.

```bash
# Using our CA, generate a signed certificate
openssl genrsa -out auth_priv.key 2048
openssl req -new -sha256 -key auth_priv.key -out auth_request.csr -subj "/C=US/ST=WA/L=Seattle/O=coolteam/OU=dev/CN=nuc5.lan"
encoded=$(awk '{printf "%s\\n", $0}' auth_request.csr)
cat > auth_request.csr.json << EOF
{
  "certificate_request":"${encoded}"
}
EOF
curl -X POST --cacert dcos-ca.crt -H "Content-Type: application/json" -H "Authorization: token=${TKN}" ${URL}/ca/api/v2/sign -d @auth_request.csr.json > auth_request.csr.result
# Parse with Python
#cat auth_request.csr.result | python -c 'import  sys,json;j=sys.stdin.read();print(json.loads(j))["result"]["certificate"]' > auth_request.crt
# Or parse with jq
cat auth_request.csr.result | jq -r .result.certificate | sed -E 's/\\n/\n/g' > auth_request.crt
```
Create custom options file for our kafka installation:

```bash
cat > coolteam-kafka.json << EOF
{
  "service": {
    "name": "${TEAM}/kafka",
    "placement_strategy": "NODE",
    "service_account": "${TEAM}",
    "service_account_secret": "${TEAM}/kafka",
    "security": {
      "transport_encryption": {
        "enabled": true
      },
      "ssl_authentication": {
        "enabled": true
      }
    }
  },
  "kafka": {
    "delete_topic_enable": true,
    "log_retention_hours": 128,
    "kafka_zookeeper_uri": "zookeeper-0-server.kafka-zookeeper.autoip.dcos.thisdcos.directory:1140,zookeeper-1-server.kafka-zookeeper.autoip.dcos.thisdcos.directory:1140,zookeeper-2-server.kafka-zookeeper.autoip.dcos.thisdcos.directory:1140"
  }
}
EOF
```

Start the installation of Kafka and wait until all brokers finish installing:

```bash
dcos package install beta-kafka-zookeeper --yes
```

Monitor the UI, wait until all ZooKeeper nodes are in a healthy state at ```Services > kafka-zookeeper```

```bash
dcos package install --options=coolteam-kafka.json beta-kafka --yes
```

Monitor the UI, wait until all kafka brokers are in a healthy state at ```Services > coolteam > kafka```

### Verification

To verify the new local user access, please log out of your superuser account and log in as ```ctuser \ sup3rs3cr3T```. As ctuser, you should only be allowed to interact with services running in the ```/coolteam``` namespace. When done verifying, please switch back to the superuser account.

Query the DC/OS CLI about our TLS secured Kafka VIP address:

```bash
[laptop]$ dcos beta-kafka --name=/coolteam/kafka endpoints broker-tls
{
  "address": [
    "10.0.1.85:1026",
    "10.0.2.194:1026",
    "10.0.1.27:1025"
  ],
  "dns": [
    "kafka-0-broker.coolteamkafka.autoip.dcos.thisdcos.directory:1026",
    "kafka-1-broker.coolteamkafka.autoip.dcos.thisdcos.directory:1026",
    "kafka-2-broker.coolteamkafka.autoip.dcos.thisdcos.directory:1025"
  ],
  "vip": "broker-tls.coolteamkafka.l4lb.thisdcos.directory:9093"
}
```

Find the IP address of your leading master node and scp some files to it:

```bash
[laptop]$ scp -i /path/to/key  auth_priv.key auth_request.crt <user>@<master IP address>:
[laptop]$ ssh -i /path/to/key <user>@<master IP address>

[master]$ cp /run/dcos/pki/CA/ca-bundle.crt .
# Enter "export" when prompted for password
[master]$ openssl pkcs12 -export -in auth_request.crt -inkey auth_priv.key -out keypair.p12 -name keypair -CAfile ca-bundle.crt -caname root
[master]$ docker run --rm -ti -v /home/core:/tmp -w /opt/kafka/bin wurstmeister/kafka bash

[kafka]$ keytool -importkeystore -deststorepass changeit -destkeypass changeit -destkeystore /tmp/keystore.jks -srckeystore /tmp/keypair.p12 -srcstoretype PKCS12 -srcstorepass export -alias keypair
# Answer "yes" to "Trust this certificate?"
[kafka]$ keytool -import -trustcacerts -alias root -file /tmp/ca-bundle.crt -storepass changeit  -keystore /tmp/truststore.jks
[kafka]$ cat >/tmp/client.properties << EOL
security.protocol = SSL
ssl.truststore.location = /tmp/truststore.jks
ssl.truststore.password = changeit
ssl.keystore.location = /tmp/keystore.jks
ssl.keystore.password = changeit
EOL
```

Open another terminal window and SSH into the same master node. Start another bash environment with the same ```wurstmeister/kafka``` docker image (kafka2 below). Start a producer service in the first session and a consumer in the other:

```bash
# Producer
[kafka]$ ./kafka-console-producer.sh --broker-list broker-tls.coolteamkafka.l4lb.thisdcos.directory:9093   --topic test --producer.config /tmp/client.properties

# Consumer
[kafka2]$ ./kafka-console-consumer.sh --bootstrap-server broker-tls.coolteamkafka.l4lb.thisdcos.directory:9093  --topic test --consumer.config /tmp/client.properties
```

It will take couple of minutes before a topic leader is elected and the consumer may complain about LEADER_NOT_AVAILABLE, just wait a bit before sending any messages from the producer.

Done! You have successfully configured TLS encrypted communications in your DC/OS Kafka cluster and you have done that following best practices, using a service account and creating a separate namespace (folder) for your team! Way to go!

For a good description on how to connect various clients (golang, c++, python, .Net, java), please visit the [documentation website](https://docs.mesosphere.com/services/beta-kafka/2.1.1-1.0.0-beta/connecting-clients/).
