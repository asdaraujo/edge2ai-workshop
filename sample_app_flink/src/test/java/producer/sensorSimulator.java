package producer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import commons.Commons;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.ByteArraySerializer;
import org.apache.kafka.common.serialization.StringSerializer;

import java.time.Instant;
import java.util.Properties;
import java.util.Random;
import java.util.UUID;


public class sensorSimulator {
    private static final String BOOTSTRAP_SERVERS = Commons.EXAMPLE_KAFKA_SERVER;
    private static final String TOPIC = Commons.EXAMPLE_KAFKA_TOPIC;
    private static final ObjectMapper objectMapper = new ObjectMapper();
    private static final Random random = new Random();

    public static long sleeptime;


    public static void main(String[] args) throws Exception {


        if( args.length > 0 ) {
            setsleeptime(Long.parseLong(args[0]));
            System.out.println("sleeptime (ms): " + sleeptime);
        } else {
            System.out.println("no sleeptime defined - use default");
            setsleeptime(1000);
            System.out.println("default sleeptime (ms): " + sleeptime);
        }

        Producer<String, byte[]> producer = createProducer();
        try {
            for (int i = 0; i < 1000000; i++) {
                publishMessage(producer);
                Thread.sleep(sleeptime);
            }
        } finally {
            producer.close();
        }
    }

    private static Producer<String, byte[]> createProducer() {
        Properties config = new Properties();
        config.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
        config.put(ProducerConfig.CLIENT_ID_CONFIG, "md");
        config.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        config.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
        return new KafkaProducer<>(config);
    }

    private static void publishMessage(Producer<String, byte[]> producer) throws Exception {
        String key = UUID.randomUUID().toString();

        ObjectNode messageJsonObject = JsonOnject();
        byte[] valueJson = objectMapper.writeValueAsBytes(messageJsonObject);

        ProducerRecord<String, byte[]> record = new ProducerRecord<>(TOPIC, key, valueJson);

        RecordMetadata md = producer.send(record).get();
        System.out.println("Published " + md.topic() + "/" + md.partition() + "/" + md.offset()
                + " (key=" + key + ") : " + messageJsonObject);
    }

    // build random json object
    private static ObjectNode JsonOnject() {

        int i= random.nextInt(5);

        ObjectNode report = objectMapper.createObjectNode();
        report.put("sensor_ts", Instant.now().toEpochMilli());
        report.put("sensor_id", (random.nextInt(11)));
        report.put("sensor_0", (random.nextInt(99)));
        report.put("sensor_1", (random.nextInt(99)));
        report.put("sensor_2", (random.nextInt(99)));
        report.put("sensor_3", (random.nextInt(99)));
        report.put("sensor_4", (random.nextInt(99)));
        report.put("sensor_5", (random.nextInt(99)));
        report.put("sensor_6", (random.nextInt(99)));
        report.put("sensor_7", (random.nextInt(99)));
        report.put("sensor_8", (random.nextInt(99)));
        report.put("sensor_9", (random.nextInt(99)));
        report.put("sensor_10", (random.nextInt(99)));
        report.put("sensor_11", (random.nextInt(99)));

        return report;
    }

    public static void setsleeptime(long sleeptime) {
        sensorSimulator.sleeptime = sleeptime;
    }

}
