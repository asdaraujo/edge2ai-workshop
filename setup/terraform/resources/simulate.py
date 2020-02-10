#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""a simple sensor data generator that sends to an MQTT broker via paho"""


import json
import time
import random
import paho.mqtt.client as mqtt


"""generate data and send it to an MQTT broker"""
mqttc = mqtt.Client()

mqttc.connect("localhost", 1883)

interval_secs = 500 / 1000.0

data = {
    "sensor_id": random.randint(1,100),
    "sensor_ts": int(time.time()*1000000)
}

inject_error = False
if random.randint(1,100) >= 85:
    inject_error = True

machines = {"sensor_0": [1, 5], "sensor_1": [1, 20], "sensor_2": [0, 5], "sensor_3": [20, 60], "sensor_4": [1, 60],
            "sensor_5": [50, 100], "sensor_6": [10, 100], "sensor_7": [80, 150], "sensor_8": [1, 50],
            "sensor_9": [1, 10], "sensor_10": [1, 10], "sensor_11": [1, 10]}

for key in range(0, 12):
    min_val, max_val = machines.get("sensor_" + str(key))
    data["sensor_" + str(key)] = random.randint(min_val, max_val)
    if inject_error and key < 2 and random.randint(1, 100) < 80:
        data["sensor_" + str(key)] += random.randint(500,1000)

payload = json.dumps(data)
print("%s" % payload)

mqttc.publish("iot", payload)
