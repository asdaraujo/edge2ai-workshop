Setup
Create Kafka Topic -- highTemp
Upload NiFi Template to NiFi and run - https://gist.githubusercontent.com/vvagias/3836c11680133691e5b69293d67253f7/raw/0644611bbb962ae21899d20e5e1aa6ba181500b8/Load-IoT-to-Kafka.xml
Examine Flink App Code:
https://gist.github.com/vvagias/c46d23af91d0daff17f9d1916e7a2bbc

Run Job:
Load Flink JAR -
Run Flink JAR -  flink run -m yarn-cluster vv2-1.0-SNAPSHOT.jar
