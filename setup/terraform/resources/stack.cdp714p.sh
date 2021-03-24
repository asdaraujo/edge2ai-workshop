#!/usr/bin/env bash

# Mandatory component:              BASE
# Common components to CDH and CDP: CDSW, HBASE HDFS, HIVE, HUE, IMPALA, KAFKA, KUDU,
#                                   NIFI, OOZIE, SCHEMAREGISTRY, SMM, SRM, SOLR, SPARK_ON_YARN, YARN,
#                                   ZOOKEEPER
# CDP-only components:              ATLAS, LIVY, RANGER, ZEPPELIN, KNOX
CM_SERVICES=BASE,ZOOKEEPER,HDFS,YARN,HIVE,HUE,IMPALA,KAFKA,KUDU,NIFI,OOZIE,SCHEMAREGISTRY,SPARK_ON_YARN,SMM,CDSW,SOLR,HBASE,ATLAS,LIVY,ZEPPELIN
ENABLE_KERBEROS=no
ENABLE_TLS=no

##### Cloudera repository credentials - only needed if using subscription-only URLs below; leave it blank otherwise
REMOTE_REPO_USR="<YOUR_USERNAME_HERE>"
REMOTE_REPO_PWD="<YOUR_PASSWORD_HERE>"

#####  Java Package
JAVA_PACKAGE_NAME=java-1.8.0-openjdk-devel

##### Maven binary
MAVEN_BINARY_URL=https://www.strategylions.com.au/mirror/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz

#####  CM
CM_VERSION=7.1.4
CM_MAJOR_VERSION=${CM_VERSION%%.*}
CM_REPO_AS_TARBALL_URL=
CM_BASE_URL=https://archive.cloudera.com/cm7/7.1.4/redhat7/yum/
CM_REPO_FILE_URL=https://archive.cloudera.com/cm7/7.1.4/redhat7/yum/cloudera-manager-trial.repo

#####  CDH
CDH_VERSION=7.1.4
CDH_BUILD=7.1.4-1.cdh7.1.4.p0.6300266
CDH_MAJOR_VERSION=${CDH_VERSION%%.*}
CDH_PARCEL_REPO=https://archive.cloudera.com/cdh7/7.1.4.0/parcels/

#####  CFM
CFM_VERSION=1.0.1.0
CFM_BUILD=1.0.1.0-12
CFM_MAJOR_VERSION=${CFM_VERSION%%.*}
NIFI_VERSION=1.9.0
NIFI_REGISTRY_VERSION=0.3.0
CFM_PARCEL_REPO=https://archive.cloudera.com/CFM/parcels/1.0.1.0/
CFM_NIFI_CSD_URL=https://archive.cloudera.com/CFM/csd/1.0.1.0/NIFI-1.9.0.1.0.1.0-12.jar
CFM_NIFIREG_CSD_URL=https://archive.cloudera.com/CFM/csd/1.0.1.0/NIFIREGISTRY-0.3.0.1.0.1.0-12.jar

#####  Anaconda
ANACONDA_VERSION=2019.10
ANACONDA_PARCEL_REPO=https://repo.anaconda.com/pkgs/misc/parcels/

#####  CDSW
# If version is set, install will be attempted
CDSW_VERSION=1.7.2
CDSW_BUILD=1.7.2.p1.2066404
CDSW_PARCEL_REPO=https://archive.cloudera.com/cdsw1/1.7.2/parcels/
CDSW_CSD_URL=https://archive.cloudera.com/cdsw1/1.7.2/csd/CLOUDERA_DATA_SCIENCE_WORKBENCH-CDPDC-1.7.2.jar

#####  CEM
CEM_VERSION=1.0.0.0
CEM_MAJOR_VERSION=${CEM_VERSION%%.*}
EFM_VERSION=1.0.0
MINIFI_VERSION=0.6.0
# PUBLIC TARBALL
CEM_URL=
# INDIVIDUAL TARBALLS
EFM_TARBALL_URL=https://archive.cloudera.com/CEM/centos7/1.x/updates/1.0.0.0/tars/efm/efm-1.0.0.1.0.0.0-54-bin.tar.gz
MINIFI_TARBALL_URL=https://archive.cloudera.com/CEM/centos7/1.x/updates/1.0.0.0/tars/minifi/minifi-0.6.0.1.0.0.0-54-bin.tar.gz
MINIFITK_TARBALL_URL=https://archive.cloudera.com/CEM/centos7/1.x/updates/1.0.0.0/tars/minifi/minifi-toolkit-0.6.0.1.0.0.0-54-bin.tar.gz

# Parcels to be pre-downloaded during install.
# Cloudera Manager will download any parcels that are not already downloaded previously.
PARCEL_URLS=(
  hadoop         "$CDH_BUILD"                         "$CDH_PARCEL_REPO"
  nifi           "$CFM_BUILD"                         "$CFM_PARCEL_REPO"
  cdsw           "$CDSW_BUILD"                        "$CDSW_PARCEL_REPO"
  Anaconda       "$ANACONDA_VERSION"                  "$ANACONDA_PARCEL_REPO"
)

CSD_URLS=(
  $CFM_NIFI_CSD_URL
  $CFM_NIFIREG_CSD_URL
  $CDSW_CSD_URL
)
