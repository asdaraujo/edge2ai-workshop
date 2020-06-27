package commons;

public class Commons {
    public final static String EXAMPLE_KAFKA_TOPIC = System.getenv("EXAMPLE_KAFKA_TOPIC") != null ?
            System.getenv("EXAMPLE_KAFKA_TOPIC") : "iot";
    public final static String EXAMPLE_KAFKA_SERVER = System.getenv("EXAMPLE_KAFKA_SERVER") != null ?
            System.getenv("EXAMPLE_KAFKA_SERVER") : "edge2ai-1.dim.local:9092";
      //      System.getenv("EXAMPLE_KAFKA_SERVER") : "localhost:9092";
    public final static String GROUP_ID_CONFIG = System.getenv("GROUP_ID_CONFIG") != null ?
            System.getenv("GROUP_ID_CONFIG") : "iot-sensor-consumer-flink";
}