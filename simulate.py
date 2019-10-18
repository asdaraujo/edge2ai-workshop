#!/usr/bin/env python
"""a simple sensor data generator that sends to an MQTT broker via paho"""
import sys
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
    "sensor_ts": long(time.time()*1000000)
}

inject_error = False
if random.randint(1,100) >= 85:
    inject_error = True

machines = {}
machines["sensor_0"] = [1, 5]
machines["sensor_1"] = [1, 20]
machines["sensor_2"] = [0, 5]
machines["sensor_3"] = [20, 60]
machines["sensor_4"] = [1, 60]
machines["sensor_5"] = [50, 100]
machines["sensor_6"] = [10, 100]
machines["sensor_7"] = [80, 150]
machines["sensor_8"] = [1, 50]
machines["sensor_9"] =[1, 10]
machines["sensor_10"] = [1, 10]
machines["sensor_11"] = [1, 10]

for key in range(0, 12):
    min_val, max_val = machines.get("sensor_" + str(key))
    data["sensor_" + str(key)] = random.randint(min_val, max_val)
    if inject_error and key < 2 and random.randint(1, 100) < 80:
        data["sensor_" + str(key)] += random.randint(500,1000)

payload = json.dumps(data)
print("%s" % (payload))

mqttc.publish("iot", payload)
