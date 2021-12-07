#!/usr/bin/env bash

# Mandatory component:              BASE
# Common components to CDH and CDP: CDSW, FLINK, HBASE HDFS, HIVE, HUE, IMPALA, KAFKA, KUDU,
#                                   NIFI, OOZIE, SCHEMAREGISTRY, SMM, SRM, SOLR, SPARK_ON_YARN, YARN,
#                                   ZOOKEEPER
# CDP-only components:              ATLAS, KNOX, LIVY, OZONE, RANGER, ZEPPELIN
CM_SERVICES=BASE,ZOOKEEPER,HDFS,YARN,HIVE,HUE,IMPALA,KAFKA,KUDU,NIFI,OOZIE,OZONE,SCHEMAREGISTRY,SPARK_ON_YARN,SMM,CDSW,FLINK,SOLR,HBASE,ATLAS,LIVY,ZEPPELIN
ENABLE_KERBEROS=no
ENABLE_TLS=no

##### Cloudera repository credentials - only needed if using subscription-only URLs below; leave it blank otherwise
REMOTE_REPO_USR=<YOUR_USERNAME_HERE>
REMOTE_REPO_PWD=<YOUR_PASSWORD_HERE>

#####  Java Package
JAVA_PACKAGE_NAME=java-1.8.0-openjdk-devel

##### Maven binary
MAVEN_BINARY_URL=https://downloads.apache.org/maven/maven-3/3.8.4/binaries/apache-maven-3.8.4-bin.tar.gz

#####  CM
CM_VERSION=7.4.4
CM_MAJOR_VERSION=${CM_VERSION%%.*}
CM_REPO_AS_TARBALL_URL=https://archive.cloudera.com/p/cm7/7.4.4/repo-as-tarball/cm7.4.4-redhat7.tar.gz
CM_BASE_URL=
CM_REPO_FILE_URL=

#####  CDH
CDH_VERSION=7.1.7
CDH_BUILD=7.1.7-1.cdh7.1.7.p0.15945976
CDH_MAJOR_VERSION=${CDH_VERSION%%.*}
CDH_PARCEL_REPO=https://archive.cloudera.com/p/cdh7/7.1.7.0/parcels/

#####  CFM
CFM_VERSION=2.0.4.0
CFM_BUILD=2.0.4.0-80
CFM_MAJOR_VERSION=${CFM_VERSION%%.*}
NIFI_VERSION=1.11.4
NIFI_REGISTRY_VERSION=0.6.0
CFM_PARCEL_REPO=https://archive.cloudera.com/p/CFM/2.x/redhat7/yum/tars/parcel/
CFM_NIFI_CSD_URL=https://archive.cloudera.com/p/CFM/2.x/redhat7/yum/tars/parcel/NIFI-1.11.4.2.0.4.0-80.jar
CFM_NIFIREG_CSD_URL=https://archive.cloudera.com/p/CFM/2.x/redhat7/yum/tars/parcel/NIFIREGISTRY-0.6.0.2.0.4.0-80.jar

#####  Anaconda
ANACONDA_VERSION=2021.04
ANACONDA_PARCEL_REPO=https://repo.anaconda.com/pkgs/misc/parcels/

#####  CDSW
# If version is set, install will be attempted
CDSW_VERSION=1.9.2
CDSW_BUILD=1.9.2.p1.14556745
CDSW_PARCEL_REPO=https://archive.cloudera.com/p/cdsw1/1.9.2/parcels/
CDSW_CSD_URL=https://archive.cloudera.com/p/cdsw1/1.9.2/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDPDC-1.9.2.jar

#####  CEM
CEM_VERSION=1.2.1.0
CEM_MAJOR_VERSION=${CEM_VERSION%%.*}
EFM_VERSION=1.0.0
MINIFI_VERSION=0.6.0
# PUBLIC TARBALL
CEM_URL=
# INDIVIDUAL TARBALLS
EFM_TARBALL_URL=https://archive.cloudera.com/p/CEM/centos7/1.x/updates/1.2.2.0/tars/efm/efm-1.0.0.1.2.2.0-14-bin.tar.gz
MINIFI_TARBALL_URL=https://archive.cloudera.com/p/CEM/centos7/1.x/updates/1.2.2.0/tars/minifi/minifi-0.6.0.1.2.2.0-14-bin.tar.gz
MINIFITK_TARBALL_URL=https://archive.cloudera.com/p/CEM/centos7/1.x/updates/1.2.2.0/tars/minifi/minifi-toolkit-0.6.0.1.2.2.0-14-bin.tar.gz

#####   CSA
CSA_VERSION=1.5.0.1
FLINK_VERSION=1.13.2
FLINK_BUILD=1.13.2-csa1.5.0.1-cdh7.1.7.0-551-17559653
CSA_PARCEL_REPO=https://archive.cloudera.com/p/csa/1.5.0.1/parcels/
FLINK_CSD_URL=https://archive.cloudera.com/p/csa/1.5.0.1/csd/FLINK-1.13.2-csa1.5.0.1-cdh7.1.7.0-551-17559653.jar
SSB_CSD_URL=https://archive.cloudera.com/p/csa/1.5.0.1/csd/SQL_STREAM_BUILDER-1.13.2-csa1.5.0.1-cdh7.1.7.0-551-17559653.jar

# Parcels to be pre-downloaded during install.
# Cloudera Manager will download any parcels that are not already downloaded previously.
PARCEL_URLS=(
  hadoop         "$CDH_BUILD"                         "$CDH_PARCEL_REPO"
  nifi           "$CFM_BUILD"                         "$CFM_PARCEL_REPO"
  cdsw           "$CDSW_BUILD"                        "$CDSW_PARCEL_REPO"
  Anaconda       "$ANACONDA_VERSION"                  "$ANACONDA_PARCEL_REPO"
  flink          "$FLINK_BUILD"                       "$CSA_PARCEL_REPO"
)

CSD_URLS=(
  $CFM_NIFI_CSD_URL
  $CFM_NIFIREG_CSD_URL
  $CDSW_CSD_URL
  $FLINK_CSD_URL
  $SSB_CSD_URL
)
