#include <WiFi.h>
#include <SPIFFS.h>
#include <PubSubClient.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <ArduinoJson.h>

// Pins
#define RECV_PIN    23
#define IR_SEND_PIN 4

IRrecv irrecv(RECV_PIN);
IRsend irsend(IR_SEND_PIN);
decode_results results;

// WiFi credentials
const char* ssid = "Jio_Air_Fiber_4G";
const char* password = "Yath2605";

// MQTT settings
const char* mqtt_server = "192.168.29.142";
const int   mqtt_port   = 1883;
const char* mqtt_user   = "hema";
const char* mqtt_pass   = "@hema.";

WiFiClient espClient;
PubSubClient client(espClient);

// Path to store commands
const char* file_path = "/codes.json";

// Forward declarations
void setup_wifi();
DynamicJsonDocument loadFromFile();
void saveToFile(DynamicJsonDocument &doc);
void sendStatus(const char* msg);
void handleSend(const String &name);
void handleLearn(const String &name);
void handleList();
void handleDelete(const String &name);
void handleRename(const String &oldName, const String &newName);
void callback(char* topic, byte* payload, unsigned int length);
void reconnect();

void setup() {
  Serial.begin(9600);
  delay(100);

  // Initialize SPIFFS
  if (!SPIFFS.begin(true)) {
    Serial.println("❌ SPIFFS Mount Failed!");
  }
  // Ensure codes.json exists
  if (!SPIFFS.exists(file_path)) {
    File f = SPIFFS.open(file_path, FILE_WRITE);
    if (f) {
      f.print("{}");
      f.close();
      Serial.println("ℹ️ Created empty codes.json");
    }
  }

  // Connect to Wi-Fi
  setup_wifi();

  // Setup MQTT
  client.setServer(mqtt_server, mqtt_port);
  client.setBufferSize(2048);             // ← bump buffer to 2 KB
  client.setCallback(callback);

  // Initialize IR
  irrecv.enableIRIn();
  irsend.begin();

  // Initial status
  sendStatus("ESP32 Ready");
}

void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();
}

void setup_wifi() {
  Serial.print("Connecting to Wi‑Fi");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n✅ Connected! IP: %s\n", WiFi.localIP().toString().c_str());
}

DynamicJsonDocument loadFromFile() {
  DynamicJsonDocument doc(8192);
  File file = SPIFFS.open(file_path, FILE_READ);
  if (file) {
    auto err = deserializeJson(doc, file);
    file.close();
    if (err) {
      Serial.println("⚠️ Error parsing JSON, starting fresh");
      doc.clear();
    }
  }
  return doc;
}

void saveToFile(DynamicJsonDocument &doc) {
  File file = SPIFFS.open(file_path, FILE_WRITE);
  if (file) {
    serializeJson(doc, file);
    file.close();
    Serial.println("ℹ️ Saved codes.json");
  } else {
    Serial.println("❌ Failed to open codes.json for writing");
  }
}

void sendStatus(const char* msg) {
  client.publish("home/ac/status", msg);
  Serial.printf(">> Status published: %s\n", msg);
}

void handleSend(const String &name) {
  DynamicJsonDocument doc = loadFromFile();
  if (!doc.containsKey(name)) {
    sendStatus("Error: Command not found");
    return;
  }
  JsonArray arr = doc[name].as<JsonArray>();
  uint16_t raw[arr.size()];
  for (size_t i = 0; i < arr.size(); i++) raw[i] = arr[i];
  irsend.sendRaw(raw, arr.size(), 38);
  sendStatus((String("Sent ") + name).c_str());
}

void handleLearn(const String &name) {
  sendStatus("Waiting for IR...");
  Serial.printf(">> handleLearn(%s) start, waiting up to 20s...\n", name.c_str());

  // Flush any existing buffer
  while (irrecv.decode(&results)) {
    irrecv.resume();
  }

  unsigned long t0 = millis();
  bool got = false;
  while (millis() - t0 < 20000) {
    if (irrecv.decode(&results)) {
      got = true;
      break;
    }
    delay(20);
  }

  if (!got) {
    sendStatus("Error: No IR captured");
    Serial.println("!! Timeout: no IR data");
    return;
  }

  Serial.printf(">> Decoded type=%d, rawlen=%u\n",
                results.decode_type, results.rawlen);
  irrecv.resume();

  Serial.print("Raw ticks: ");
  for (size_t i = 1; i < min<size_t>(results.rawlen, 20); i++) {
    Serial.printf("%u ", results.rawbuf[i] * kRawTick);
  }
  Serial.println("…");

  DynamicJsonDocument doc = loadFromFile();
  Serial.print("Existing keys before store: ");
  for (auto kv : doc.as<JsonObject>()) {
    Serial.printf("%s ", kv.key().c_str());
  }
  Serial.println();

  JsonArray arr = doc.createNestedArray(name);
  for (size_t i = 1; i < results.rawlen; i++) {
    arr.add(results.rawbuf[i] * kRawTick);
  }
  saveToFile(doc);
  Serial.printf("ℹ️ Saved %u ticks under '%s'\n", arr.size(), name.c_str());

  sendStatus((String("Learned ") + name).c_str());
}

void handleList() {
  DynamicJsonDocument doc = loadFromFile();
  String result;
  serializeJson(doc, result);

  // Publish and print result length
  bool ok = client.publish("home/ac/available_cmds", result.c_str());
  Serial.printf("→ publish available_cmds %s (len=%u)\n",
                ok ? "succeeded" : "FAILED",
                result.length());
}

void handleDelete(const String &name) {
  DynamicJsonDocument doc = loadFromFile();
  if (doc.containsKey(name)) {
    doc.remove(name);
    saveToFile(doc);
    sendStatus((String("Deleted ") + name).c_str());
  } else {
    sendStatus("Error: Not found");
  }
}

void handleRename(const String &oldName, const String &newName) {
  DynamicJsonDocument doc = loadFromFile();
  if (!doc.containsKey(oldName)) {
    sendStatus("Error: Old name not found");
    return;
  }
  doc[newName] = doc[oldName];
  doc.remove(oldName);
  saveToFile(doc);
  sendStatus("Renamed successfully");
}

void callback(char* topic, byte* payload, unsigned int length) {
  payload[length] = '\0';
  String t = topic;
  String msg = String((char*)payload);
  Serial.printf(">> Received [%s]: %s\n", t.c_str(), msg.c_str());

  StaticJsonDocument<256> cmd;
  deserializeJson(cmd, msg);

  if      (t == "home/ac/send")   handleSend(cmd["name"].as<String>());
  else if (t == "home/ac/learn")  handleLearn(cmd["name"].as<String>());
  else if (t == "home/ac/delete") handleDelete(cmd["name"].as<String>());
  else if (t == "home/ac/rename") handleRename(cmd["old"].as<String>(), cmd["new"].as<String>());
  else if (t == "home/ac/list")   handleList();
}

void reconnect() {
  while (!client.connected()) {
    Serial.print("Attempting MQTT connection…");
    if (client.connect("esp32Client", mqtt_user, mqtt_pass)) {
      Serial.println("connected");
      client.subscribe("home/ac/#");
      sendStatus("ESP32 connected");
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" try again in 2s");
      delay(2000);
    }
  }
}
