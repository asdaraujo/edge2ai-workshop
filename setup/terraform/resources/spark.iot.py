#!/usr/bin/env python
"""Structured Streaming example
"""

import json
import requests
import socket
import sys
import time

from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, TimestampType, IntegerType
from pyspark.sql.functions import window, from_json, decode
from pyspark.sql.types import *

KAFKA_BROKERS = "%s:9092" % (socket.gethostname(),)
KUDU_MASTER = "%s:7051" % (socket.gethostname(),)
KUDU_TABLE = "default.sensors"
KAFKA_TOPIC = "iot"
OUTPUT_MODE = "complete"
PUBLIC_IP = requests.get('http://ifconfig.me').text

SCHEMA = StructType([
    StructField("sensor_id", IntegerType(), True),
    StructField("sensor_ts", LongType(), True),
    StructField("sensor_0", DoubleType(), True),
    StructField("sensor_1", DoubleType(), True),
    StructField("sensor_2", DoubleType(), True),
    StructField("sensor_3", DoubleType(), True),
    StructField("sensor_4", DoubleType(), True),
    StructField("sensor_5", DoubleType(), True),
    StructField("sensor_6", DoubleType(), True),
    StructField("sensor_7", DoubleType(), True),
    StructField("sensor_8", DoubleType(), True),
    StructField("sensor_9", DoubleType(), True),
    StructField("sensor_10", DoubleType(), True),
    StructField("sensor_11", DoubleType(), True),
    StructField("is_healthy", IntegerType(), True),
])


def model_lookup(data):
    global ACCESS_KEY
    p = json.loads(data)
    feature = "%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s" % (p['sensor_1'], p['sensor_0'], p['sensor_2'],
                                                                  p['sensor_3'], p['sensor_4'], p['sensor_5'],
                                                                  p['sensor_6'], p['sensor_7'], p['sensor_8'],
                                                                  p['sensor_9'], p['sensor_10'], p['sensor_11'])

    url = 'http://cdsw.' + PUBLIC_IP + '.nip.io/api/altus-ds-1/models/call-model'
    data = '{"accessKey":"' + ACCESS_KEY + '", "request":{"feature":"' + feature + '"}}'
    while True:
        resp = requests.post(url, data=data, headers={'Content-Type': 'application/json'})
        j = resp.json()
        if 'response' in j and 'result' in j['response']:
            return resp.json()['response']['result']
        print(">>>>>>>>>>>>>>>>>>>>>" + resp.text)
        time.sleep(.1)


def main():
    """Main"""
    spark = SparkSession \
        .builder \
        .appName("KafkaStructuredStreamingExample") \
        .getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    events = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_BROKERS) \
        .option("startingoffsets", "latest") \
        .option("subscribe", KAFKA_TOPIC) \
        .load()

    spark.udf.register("model_lookup", model_lookup)
    data = events \
        .select(decode("value", "UTF-8").alias("decoded")) \
        .select(from_json("decoded", SCHEMA).alias("data"), "decoded") \
        .selectExpr("data.*", 'cast(model_lookup(decoded) as int) as is_healthy')
    kudu = data \
        .writeStream \
        .format("kudu") \
        .option("kudu.master", KUDU_MASTER) \
        .option("kudu.table", KUDU_TABLE) \
        .option("kudu.operation", "upsert") \
        .option("checkpointLocation", "file:///tmp/checkpoints") \
        .start()
    console = data \
        .writeStream \
        .format("console") \
        .start()

    kudu.awaitTermination()
    console.awaitTermination()


if __name__ == '__main__':
    ACCESS_KEY = sys.argv[1]
    main()
