#!/usr/bin/env bash

# Mandatory component:              BASE
# Common components to CDH and CDP: CDSW, FLINK, HBASE HDFS, HIVE, HUE, IMPALA, KAFKA, KUDU,
#                                   NIFI, OOZIE, SCHEMAREGISTRY, SMM, SRM, SOLR, SPARK_ON_YARN, YARN,
#                                   ZOOKEEPER
# CDP-only components:              ATLAS, KNOX, LIVY, OZONE, RANGER, ZEPPELIN
CM_SERVICES=BASE,ZOOKEEPER,HDFS,YARN,HIVE,HUE,IMPALA,KAFKA,KUDU,OOZIE,OZONE,SCHEMAREGISTRY,SPARK_ON_YARN,SMM,SOLR,HBASE,ATLAS,LIVY,ZEPPELIN
ENABLE_KERBEROS=no
ENABLE_TLS=no

##### Cloudera repository credentials - only needed if using subscription-only URLs below; leave it blank otherwise
REMOTE_REPO_USR=
REMOTE_REPO_PWD=

#####  Java Package
JAVA_PACKAGE_NAME=java-11-openjdk-devel

##### Maven binary
MAVEN_BINARY_URL=https://downloads.apache.org/maven/maven-3/3.8.8/binaries/apache-maven-3.8.8-bin.tar.gz

#####  CM
CM_VERSION=7.4.4
CM_MAJOR_VERSION=${CM_VERSION%%.*}
CM_REPO_AS_TARBALL_URL=https://archive.cloudera.com/cm7/7.4.4/repo-as-tarball/cm7.4.4-redhat7.tar.gz
CM_BASE_URL=
CM_REPO_FILE_URL=

#####  CDH
CDH_VERSION=7.1.7
CDH_BUILD=7.1.7-1.cdh7.1.7.p0.15945976
CDH_MAJOR_VERSION=${CDH_VERSION%%.*}
CDH_PARCEL_REPO=https://archive.cloudera.com/cdh7/7.1.7.0/parcels/

#####  Anaconda
ANACONDA_PRODUCT=Anaconda3
ANACONDA_VERSION=2021.05
ANACONDA_PARCEL_REPO=https://repo.anaconda.com/pkgs/misc/parcels/

# Parcels to be pre-downloaded during install.
# Cloudera Manager will download any parcels that are not already downloaded previously.
PARCEL_URLS=(
  hadoop         "$CDH_BUILD"                         "$CDH_PARCEL_REPO"
  Anaconda       "$ANACONDA_VERSION"                  "$ANACONDA_PARCEL_REPO"
)

CSD_URLS=(
)
