#!/usr/bin/env bash

# Mandatory component:              BASE
# Common components to CDH and CDP: CDSW, FLINK, HBASE HDFS, HIVE, HUE, IMPALA, KAFKA, KUDU,
#                                   NIFI, OOZIE, SCHEMAREGISTRY, SMM, SRM, SOLR, SPARK_ON_YARN, YARN,
#                                   ZOOKEEPER
# CDP-only components:              ATLAS, KNOX, LIVY, OZONE, RANGER, ZEPPELIN
CM_SERVICES=BASE,ZOOKEEPER,HDFS,YARN,HIVE,HUE,IMPALA,KAFKA,KUDU,NIFI,OOZIE,OZONE,SCHEMAREGISTRY,SPARK_ON_YARN,SMM,CDSW,FLINK,SOLR,HBASE,ATLAS,LIVY,ZEPPELIN
ENABLE_KERBEROS=no
ENABLE_TLS=no

#####  Java Package
JAVA_PACKAGE_NAME=java-11-openjdk-devel

##### Maven binary
MAVEN_BINARY_URL=https://downloads.apache.org/maven/maven-3/3.9.6/binaries/apache-maven-3.9.6-bin.tar.gz

#####  CM
CM_VERSION=7.6.1
_CM_BUILD_PATH=${CM_VERSION}
CM_MAJOR_VERSION=${CM_VERSION%%.*}
CM_REPO_AS_TARBALL_URL=https://archive.cloudera.com/p/cm${CM_MAJOR_VERSION}/${_CM_BUILD_PATH}/repo-as-tarball/cm${CM_VERSION}-redhat7.tar.gz
CM_BASE_URL=
CM_REPO_FILE_URL=

#####  CDH
CDH_VERSION=7.1.7
CDH_BUILD=${CDH_VERSION}-1.cdh${CDH_VERSION}.p1000.24102687
_CDH_BUILD_PATH=${CDH_VERSION}.1000
CDH_MAJOR_VERSION=${CDH_VERSION%%.*}
CDH_PARCEL_REPO=https://archive.cloudera.com/p/cdh${CDH_MAJOR_VERSION}/${_CDH_BUILD_PATH}/parcels/

#####  CFM
CFM_VERSION=2.1.3.0
CFM_BUILD=2.1.3.0-125
CFM_MAJOR_VERSION=${CFM_VERSION%%.*}
NIFI_VERSION=1.15.2
NIFI_REGISTRY_VERSION=1.15.2
CFM_PARCEL_REPO=https://archive.cloudera.com/p/cfm2/2.1.3.0/redhat7/yum/tars/parcel/
CFM_NIFI_CSD_URL=https://archive.cloudera.com/p/cfm2/2.1.3.0/redhat7/yum/tars/parcel/NIFI-1.15.2.2.1.3.0-125.jar
CFM_NIFIREG_CSD_URL=https://archive.cloudera.com/p/cfm2/2.1.3.0/redhat7/yum/tars/parcel/NIFIREGISTRY-1.15.2.2.1.3.0-125.jar

#####  Anaconda
ANACONDA_PRODUCT=Anaconda3
ANACONDA_VERSION=2021.05
ANACONDA_PARCEL_REPO=https://repo.anaconda.com/pkgs/misc/parcels/

#####  CDSW
# If version is set, install will be attempted
CDSW_VERSION=1.10.0
CDSW_BUILD=1.10.0.p1.19362179
CDSW_PARCEL_REPO=https://archive.cloudera.com/p/cdsw1/${CDSW_VERSION}/parcels/
CDSW_CSD_URL=https://archive.cloudera.com/p/cdsw1/${CDSW_VERSION}/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDPDC-${CDSW_VERSION}.jar

#####  CEM
CEM_VERSION=1.5.1.0
CEM_BUILD=${CEM_VERSION}-25
CEM_MAJOR_VERSION=${CEM_VERSION%%.*}
EFM_TARBALL_URL=https://archive.cloudera.com/p/CEM/ubuntu20/${CEM_MAJOR_VERSION}.x/updates/${CEM_VERSION}/tars/efm/efm-${CEM_BUILD}-bin.tar.gz

#####  CEM AGENTS
MINIFI_VERSION=1.23.04
MINIFI_BUILD=${MINIFI_VERSION}-b23
MINIFI_TARBALL_URL=https://archive.cloudera.com/p/cem-agents/${MINIFI_VERSION}/ubuntu18/apt/tars/nifi-minifi-cpp/nifi-minifi-cpp-${MINIFI_BUILD}-bin-centos.tar.gz
MINIFITK_TARBALL_URL=https://archive.cloudera.com/p/cem-agents/${MINIFI_VERSION}/ubuntu18/apt/tars/nifi-minifi-cpp/nifi-minifi-cpp-${MINIFI_BUILD}-extra-extensions-centos.tar.gz

#####  CSA
CSA_VERSION=1.10.0.0
FLINK_VERSION=1.16.1
FLINK_BUILD=1.16.1-csa1.10.0.0-cdh7.1.8.0-801-41959971
CSA_PARCEL_REPO=https://archive.cloudera.com/p/csa/1.10.0.0/parcels/
FLINK_CSD_URL=https://archive.cloudera.com/p/csa/1.10.0.1/csd/FLINK-1.16.1-csa1.10.0.1-cdh7.1.8.0-801-50506469.jar
SSB_CSD_URL=https://archive.cloudera.com/p/csa/1.10.0.1/csd/SQL_STREAM_BUILDER-1.16.1-csa1.10.0.1-cdh7.1.8.0-801-50506469.jar
