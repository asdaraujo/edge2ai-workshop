#!/usr/bin/env python
"""a simple sensor data generator that sends to an MQTT broker via paho"""
import sys
import json
import time
import random

import paho.mqtt.client as mqtt

def generate(host, port, username, password, topic, machines, interval_ms, verbose):
    """generate data and send it to an MQTT broker"""
    mqttc = mqtt.Client()

    if username:
        mqttc.username_pw_set(username, password)

    mqttc.connect(host, port)

    interval_secs = interval_ms / 1000.0

    while True:
        data = {
            "sensor_id": random.randint(1,100),
            "sensor_ts": long(time.time()*1000000)
        }

        for key in range(0, 12):
            min_val, max_val = machines.get("sensor_" + str(key))
            data["sensor_" + str(key)] = random.randint(min_val, max_val)

        payload = json.dumps(data)

        if verbose:
            print("%s: %s" % (topic, payload))

        mqttc.publish(topic, payload)
        time.sleep(interval_secs)


def main(config_path):
    """main entry point, load and validate config and call generate"""
    try:
        with open(config_path) as handle:
            config = json.load(handle)
            mqtt_config = config.get("mqtt", {})
            misc_config = config.get("misc", {})
            machines = config.get("machines")

            interval_ms = misc_config.get("interval_ms", 500)
            verbose = misc_config.get("verbose", False)

            host = mqtt_config.get("host", "localhost")
            port = mqtt_config.get("port", 1883)
            username = mqtt_config.get("username")
            password = mqtt_config.get("password")
            topic = mqtt_config.get("topic", "mqttgen")

            generate(host, port, username, password, topic, machines, interval_ms, verbose)
    except IOError as error:
        print("Error opening config file '%s'" % config_path, error)

if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(sys.argv[1])
    else:
        print("usage %s config.json" % sys.argv[0])
