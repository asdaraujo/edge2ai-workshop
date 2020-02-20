
### Concept:  
Collected iot events and pushing into Apache Kafka. The App reads the Kafka events, do some filtering and summarizing over a  10 sec. window based on the "sensor_id".  
The result which is reported end of the window period returns the value sensor_ts, sensor_id, sensor_0, sensor_1 of the first event plus a counter.

Job-log:  
```
input message: :3> {"sensor_ts":1569497509282,"sensor_id":5,"sensor_0":62,"sensor_1":7,"sensor_2":39,"sensor_3":69,"sensor_4":35,"sensor_5":65,"sensor_6":8,"sensor_7":84,"sensor_8":48,"sensor_9":41,"sensor_10":41,"sensor_11":56}
input message: :3> {"sensor_ts":1569497509384,"sensor_id":10,"sensor_0":66,"sensor_1":50,"sensor_2":26,"sensor_3":26,"sensor_4":57,"sensor_5":22,"sensor_6":38,"sensor_7":69,"sensor_8":87,"sensor_9":63,"sensor_10":4,"sensor_11":71}
input message: :3> {"sensor_ts":1569497509486,"sensor_id":2,"sensor_0":62,"sensor_1":13,"sensor_2":32,"sensor_3":11,"sensor_4":33,"sensor_5":65,"sensor_6":92,"sensor_7":64,"sensor_8":39,"sensor_9":56,"sensor_10":72,"sensor_11":84}
input message: :3> {"sensor_ts":1569497509591,"sensor_id":3,"sensor_0":74,"sensor_1":55,"sensor_2":5,"sensor_3":17,"sensor_4":60,"sensor_5":92,"sensor_6":94,"sensor_7":17,"sensor_8":15,"sensor_9":23,"sensor_10":4,"sensor_11":94}
input message: :3> {"sensor_ts":1569497509694,"sensor_id":2,"sensor_0":19,"sensor_1":1,"sensor_2":80,"sensor_3":98,"sensor_4":9,"sensor_5":91,"sensor_6":23,"sensor_7":73,"sensor_8":33,"sensor_9":51,"sensor_10":94,"sensor_11":80}
input message: :3> {"sensor_ts":1569497509796,"sensor_id":2,"sensor_0":27,"sensor_1":0,"sensor_2":90,"sensor_3":26,"sensor_4":40,"sensor_5":39,"sensor_6":44,"sensor_7":57,"sensor_8":6,"sensor_9":7,"sensor_10":56,"sensor_11":12}
input message: :3> {"sensor_ts":1569497509899,"sensor_id":3,"sensor_0":1,"sensor_1":31,"sensor_2":3,"sensor_3":68,"sensor_4":55,"sensor_5":45,"sensor_6":15,"sensor_7":27,"sensor_8":14,"sensor_9":94,"sensor_10":1,"sensor_11":91}
8> (1569497501845,5,21,45,6)
4> (1569497500908,3,94,95,11)
1> (1569497500283,4,33,89,12)
10> (1569497501323,9,88,52,8)
2> (1569497501219,6,86,11,7)
6> (1569497501639,10,33,54,10)
```

Kafka output:  
```
{"type":"Sum over 10 sec window","sensor_ts_start":1569598190568,"sensor_id":6,"sensor_0":55,"window_count":12}
{"type":"Sum over 10 sec window","sensor_ts_start":1569598190773,"sensor_id":10,"sensor_0":70,"window_count":6}
{"type":"Sum over 10 sec window","sensor_ts_start":1569598194047,"sensor_id":2,"sensor_0":10,"window_count":6}
```

### Setup:

The project generated a fat-jar which can executed with **iot.sh** - the & symbol, switches the program to run in the background. 

install:
```
wget https://github.com/zBrainiac/edge2ailab/releases/download/0.1.2/edge2ai-lab-0.1.2-SNAPSHOT-jar-with-dependencies.jar
```

for headless/background execution                                                       
```
#!/bin/sh
nohup java -jar target/edge2ai-lab-0.1.2-SNAPSHOT-jar-with-dependencies &
```