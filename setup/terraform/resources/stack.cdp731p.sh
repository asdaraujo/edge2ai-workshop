#!/usr/bin/env bash

# Mandatory component:              BASE
# Common components to CDH and CDP: CDSW, FLINK, HBASE HDFS, HIVE, HUE, IMPALA, KAFKA, KUDU,
#                                   NIFI, OOZIE, SCHEMAREGISTRY, SMM, SRM, SOLR, SPARK_ON_YARN, YARN,
#                                   ZOOKEEPER
# CDP-only components:              ATLAS, KNOX, LIVY, OZONE, RANGER, ZEPPELIN
CM_SERVICES=BASE,ZOOKEEPER,HDFS,YARN,HIVE,HUE,IMPALA,KAFKA,KUDU,NIFI,OOZIE,OZONE,SCHEMAREGISTRY,SPARK_ON_YARN,SMM,FLINK,SOLR,HBASE,ATLAS,LIVY,ZEPPELIN
ENABLE_KERBEROS=no
ENABLE_TLS=no

#####  Java Package
JAVA_PACKAGE_NAME=java-11-openjdk-devel
OPENJDK_VERSION=17.0.2

##### Maven binary
MAVEN_BINARY_URL=https://dlcdn.apache.org/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz

#####  CM
CM_VERSION=7.13.1.0
_CM_BUILD_PATH=${CM_VERSION}
CM_MAJOR_VERSION=${CM_VERSION%%.*}
CM_REPO_AS_TARBALL_URL=https://archive.cloudera.com/p/cm${CM_MAJOR_VERSION}/${_CM_BUILD_PATH}/repo-as-tarball/cm${CM_VERSION}-redhat${MAJOR_OS_VERSION}.tar.gz
CM_BASE_URL=
CM_REPO_FILE_URL=

#####  CDH
CDH_VERSION=7.3.1
CDH_BUILD=${CDH_VERSION}-1.cdh${CDH_VERSION}.p0.60371244
_CDH_BUILD_PATH=${CDH_VERSION}
CDH_MAJOR_VERSION=${CDH_VERSION%%.*}
CDH_PARCEL_REPO=https://archive.cloudera.com/p/cdh${CDH_MAJOR_VERSION}/${_CDH_BUILD_PATH}/parcels/

#####  CFM
CFM_VERSION=2.1.7.1000
CFM_BUILD=${CFM_VERSION}-46
CFM_MAJOR_VERSION=${CFM_VERSION%%.*}
NIFI_VERSION=1.26.0
NIFI_REGISTRY_VERSION=${NIFI_VERSION}
CFM_PARCEL_REPO=https://archive.cloudera.com/p/cfm${CFM_MAJOR_VERSION}/${CFM_VERSION}/redhat${MAJOR_OS_VERSION}/yum/tars/parcel/
CFM_NIFI_CSD_URL=https://archive.cloudera.com/p/cfm${CFM_MAJOR_VERSION}/${CFM_VERSION}/redhat${MAJOR_OS_VERSION}/yum/tars/parcel/NIFI-${NIFI_VERSION}.${CFM_BUILD}.jar
CFM_NIFIREG_CSD_URL=https://archive.cloudera.com/p/cfm${CFM_MAJOR_VERSION}/${CFM_VERSION}/redhat${MAJOR_OS_VERSION}/yum/tars/parcel/NIFIREGISTRY-${NIFI_REGISTRY_VERSION}.${CFM_BUILD}.jar

#####  Anaconda3
ANACONDA_PRODUCT=Anaconda3
ANACONDA_VERSION=2021.05
ANACONDA_PARCEL_REPO=https://repo.anaconda.com/pkgs/misc/parcels/

#####  CDSW
# CDSW is not longer supported on CDP 7.3.1
CDSW_VERSION=
CDSW_BUILD=
CDSW_PARCEL_REPO=
CDSW_CSD_URL=

#####  CEM
CEM_VERSION=2.0.0.0
CEM_BUILD=${CEM_VERSION}-53
CEM_MAJOR_VERSION=${CEM_VERSION%%.*}
EFM_TARBALL_URL=https://archive.cloudera.com/p/CEM/ubuntu20/${CEM_MAJOR_VERSION}.x/updates/${CEM_VERSION}/tars/efm/efm-${CEM_BUILD}-bin.tar.gz

#####  CEM AGENTS
MINIFI_VERSION=1.24.01
MINIFI_BUILD=${MINIFI_VERSION}-b21
MINIFI_TARBALL_URL=https://archive.cloudera.com/p/cem-agents/${MINIFI_VERSION}/ubuntu22/apt/tars/nifi-minifi-cpp/nifi-minifi-cpp-${MINIFI_BUILD}-bin-linux.tar.gz
MINIFITK_TARBALL_URL=https://archive.cloudera.com/p/cem-agents/${MINIFI_VERSION}/ubuntu22/apt/tars/nifi-minifi-cpp/nifi-minifi-cpp-${MINIFI_BUILD}-extra-extensions-linux.tar.gz

#####  CSA
CSA_VERSION=1.14.0.0
FLINK_VERSION=1.19.1
FLINK_BUILD=${FLINK_VERSION}-csa${CSA_VERSION}-60467927
CSA_PARCEL_REPO=https://archive.cloudera.com/p/csa/${CSA_VERSION}/parcels/
FLINK_CSD_URL=https://archive.cloudera.com/p/csa/${CSA_VERSION}/csd/FLINK-${FLINK_BUILD}.jar
SSB_CSD_URL=https://archive.cloudera.com/p/csa/${CSA_VERSION}/csd/SQL_STREAM_BUILDER-${FLINK_BUILD}.jar
