/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package clodera.dim.streaming

import java.util.{Properties, StringTokenizer}
import org.apache.flink.api.common.functions.{FlatMapFunction, MapFunction}
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.core.JsonParseException
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.node.ObjectNode
import org.apache.flink.streaming.api.scala.{StreamExecutionEnvironment, _}
import org.apache.flink.streaming.connectors.kafka.{FlinkKafkaConsumer, FlinkKafkaProducer, FlinkKafkaProducer011}
import org.apache.flink.streaming.util.serialization.JSONKeyValueDeserializationSchema

/**
 * Skeleton for a Flink Streaming Job.
 *
 * For a tutorial how to write a Flink streaming application, check the
 * tutorials and examples on the <a href="https://flink.apache.org/docs/stable/">Flink Website</a>.
 *
 * To package your application into a JAR file for execution, run
 * 'mvn clean package' on the command line.
 *
 * If you change the name of the main class (with the public static void main(String[] args))
 * method, change the respective entry in the POM.xml file (simply search for 'mainClass').
 */
object StreamingJob {
  def main(args: Array[String]) {
    // set up the streaming execution environment
    val env = StreamExecutionEnvironment.getExecutionEnvironment
    // get input data
    val properties = new Properties()
    properties.setProperty("bootstrap.servers", "edge2ai-1.dim.local:9092")
    // only required for Kafka 0.8
    //properties.setProperty("zookeeper.connect", "localhost:2181")
    properties.setProperty("group.id", "FlinkTemp")
    val myConsumer = new FlinkKafkaConsumer[ObjectNode]("highTemp", new JSONKeyValueDeserializationSchema(false), properties)
    val stream = env.addSource(myConsumer)
    // make parameters available in the web interface
    // get input data
    //example data

    // Workshop Data Ex
    //[{"sensor_ts":1579006137039000000,"sensor_id":90,"sensor_9":681,"sensor_3":764,"sensor_2":25,"sensor_1":557,"sensor_0":672,"sensor_7":989,"sensor_6":635,"sensor_5":967,"sensor_8":876,"sensor_4":799,"sensor_11":893,"sensor_10":812}]

    try {

      stream.map(new MapFunction[ObjectNode, (String, Double)]() {
        @throws[Exception]
        override def map(node: ObjectNode): (String, Double) = (node.findValue("sensor_id").asText(), node.findValue("sensor_9").asDouble())
      })
        .keyBy(0)
        .countWindow(3)
        .sum(1).print()

      //Print max value temperature in the window...
      stream.map(new MapFunction[ObjectNode, (String, Double)]() {
        @throws[Exception]
        override def map(node: ObjectNode): (String, Double) = (node.findValue("sensor_id").asText(), node.findValue("sensor_9").asDouble())
      })
        .keyBy(0)
        .countWindow(3)
        .maxBy(1).print()

      val result = stream.map(new MapFunction[ObjectNode, (String, Double)]() {
        @throws[Exception]
        override def map(node: ObjectNode): (String, Double) = (node.findValue("sensor_id").asText(), node.findValue("sensor_9").asDouble())
      })
        .keyBy(0)
        .countWindow(3)
        .sum(1)

      stream.print( stream.map(new MapFunction[ObjectNode, (String, Double)]() {
        @throws[Exception]
        override def map(node: ObjectNode): (String, Double) = (node.findValue("sensor_id").asText(), node.findValue("sensor_9").asDouble())
      })
        .keyBy(0)
        .countWindow(3)
        .sum(1).toString)

    }
    catch {
      case x: JsonParseException =>
      {

        // Display this if exception is found
        println("Exception: data does not contain valid value field... Try again.")
      }
    }

    // execute program
    env.execute("Kafka Streaming Example")
  }


}