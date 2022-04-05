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
MAVEN_BINARY_URL=https://downloads.apache.org/maven/maven-3/3.8.5/binaries/apache-maven-3.8.5-bin.tar.gz

#####  CM
CM_VERSION=7.6.1
CM_MAJOR_VERSION=${CM_VERSION%%.*}
CM_REPO_AS_TARBALL_URL=https://archive.cloudera.com/p/cm7/7.6.1/repo-as-tarball/cm7.6.1-redhat7.tar.gz
CM_BASE_URL=
CM_REPO_FILE_URL=

#####  CDH
CDH_VERSION=7.1.7
CDH_BUILD=7.1.7-1.cdh7.1.7.p1000.24102687
CDH_MAJOR_VERSION=${CDH_VERSION%%.*}
CDH_PARCEL_REPO=https://archive.cloudera.com/p/cdh7/7.1.7.1000/parcels/

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
ANACONDA_VERSION=2021.04
ANACONDA_PARCEL_REPO=https://repo.anaconda.com/pkgs/misc/parcels/

#####  CDSW
# If version is set, install will be attempted
CDSW_VERSION=1.10.0
CDSW_BUILD=1.10.0.p1.19362179
CDSW_PARCEL_REPO=https://archive.cloudera.com/p/cdsw1/1.10.0/parcels/
CDSW_CSD_URL=https://archive.cloudera.com/p/cdsw1/1.10.0/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDPDC-1.10.0.jar

#####  CEM
CEM_VERSION=1.2.2.0
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
CSA_VERSION=1.6.2.0
FLINK_VERSION=1.14.0
FLINK_BUILD=1.14.0-csa1.6.2.0-cdh7.1.7.0-551-23013538
CSA_PARCEL_REPO=https://archive.cloudera.com/p/csa/1.6.2.0/parcels/
FLINK_CSD_URL=https://archive.cloudera.com/p/csa/1.6.2.0/csd/FLINK-1.14.0-csa1.6.2.0-cdh7.1.7.0-551-23013538.jar
SSB_CSD_URL=https://archive.cloudera.com/p/csa/1.6.2.0/csd/SQL_STREAM_BUILDER-1.14.0-csa1.6.2.0-cdh7.1.7.0-551-23013538.jar

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
