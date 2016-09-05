#!/bin/sh

set -e

curl https://www.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz -o apache-maven-3.3.9-bin.tar.gz
tar xvzf apache-maven-3.3.9-bin.tar.gz
sudo mv apache-maven-3.3.9 /opt/maven

export PATH=/opt/maven/bin:$PATH

mvn dependency:get -DremoteRepositories=http://repo1.maven.org/maven2/ -DgroupId=stax -DartifactId=stax -Dversion=1.2.0 -Dtransitive=false
mvn dependency:get -DremoteRepositories=http://repo1.maven.org/maven2/ -DgroupId=ch.qos.logback -DartifactId=logback-core -Dversion=1.1.3 -Dtransitive=false
mvn dependency:get -DremoteRepositories=http://repo1.maven.org/maven2/ -DgroupId=ch.qos.logback -DartifactId=logback-classic -Dversion=1.1.3 -Dtransitive=false
