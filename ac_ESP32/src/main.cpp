#define MQTT_MAX_PACKET_SIZE 4096  // Must be above PubSubClient include

#include <WiFi.h>
#include <SPIFFS.h>
#include <PubSubClient.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <WiFiManager.h>
#include <map>

#ifndef kRawTick
#define kRawTick 50  // microseconds per raw tick
#endif

Preferences prefs;

#define RECV_PIN    23
#define IR_SEND_PIN 4
#define LED_PIN     21

#define BTN_ON      18
#define LED_ON      2
#define BTN_PLAY    19
#define LED_PLAY    22

const int buttonPins[2] = { BTN_ON, BTN_PLAY };
const int ledPins[2]    = { LED_ON, LED_PLAY };

const char* mqtt_server = "192.168.29.142";
const int   mqtt_port   = 1883;
const char* mqtt_user   = "hema";
const char* mqtt_pass   = "@hema.";

WiFiClient espClient;
PubSubClient client(espClient);
IRrecv irrecv(RECV_PIN);
IRsend irsend(IR_SEND_PIN);
decode_results results;

unsigned long pressStart[2] = {0, 0};
bool firstConnect = true;
std::map<String, std::vector<uint16_t>> commandMap;

void setup_wifi();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void sendStatus(const String &msg);
void requestCommandList();
void handleAvailableCommands(const String &msg);
void sendIR(const String &name);
void learnIR(int index, const String &name);
void handleButtons();
void blinkFeedback(int times, int ms);
void resetWiFi();

void setup() {
  Serial.begin(9600);
  Serial.println("[SETUP] Starting up...");

  pinMode(LED_PIN, OUTPUT);
  pinMode(BTN_ON, INPUT_PULLUP);
  pinMode(LED_ON, OUTPUT);
  pinMode(BTN_PLAY, INPUT_PULLUP);
  pinMode(LED_PLAY, OUTPUT);

  irrecv.enableIRIn();
  irsend.begin();

  setup_wifi();

  client.setServer(mqtt_server, mqtt_port);
  client.setBufferSize(2048);  // Set dynamically

  client.setCallback(mqttCallback);

  Serial.printf("[MQTT] Connecting to %s:%d… ", mqtt_server, mqtt_port);
  if (client.connect("esp32Client", mqtt_user, mqtt_pass)) {
    Serial.println("OK");
    client.subscribe("home/ac/send");
    client.subscribe("home/ac/available_cmds");
    client.subscribe("home/ac/erase_all");
    client.subscribe("home/ac/reset_wifi");

    sendStatus("ESP32 Ready");
    requestCommandList();
  } else {
    Serial.printf("FAILED, rc=%d\n", client.state());
  }
}

void loop() {
  if (!client.connected()) {
    Serial.println("[MQTT] Disconnected! Reconnecting…");
    if (client.connect("esp32Client", mqtt_user, mqtt_pass)) {
      Serial.println("[MQTT] Reconnected");
      client.subscribe("home/ac/send");
      client.subscribe("home/ac/available_cmds");
      client.subscribe("home/ac/erase_all");
      client.subscribe("home/ac/reset_wifi");
      sendStatus("Reconnected");
      if (firstConnect) {
        requestCommandList();
        firstConnect = false;
      }
    } else {
      Serial.printf("[MQTT] Reconnect failed, rc=%d\n", client.state());
      delay(2000);
    }
  }

  client.loop();
  handleButtons();
}

void setup_wifi() {
  Serial.println("[WIFI] Checking stored credentials…");
  prefs.begin("wifi", true);
  bool configured = prefs.getBool("configured", false);
  prefs.end();

  if (!configured) {
    Serial.println("[WIFI] Starting config portal");
    WiFiManager wm;
    if (!wm.startConfigPortal("ESP32-Setup")) {
      Serial.println("[WIFI] Config portal failed, rebooting");
      ESP.restart();
    }
    prefs.begin("wifi", false);
    prefs.putString("ssid", WiFi.SSID());
    prefs.putString("pass", WiFi.psk());
    prefs.putBool("configured", true);
    prefs.end();
    Serial.println("[WIFI] Credentials saved, rebooting");
    ESP.restart();
  }

  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  Serial.printf("[WIFI] Connecting to SSID: %s\n", ssid.c_str());
  WiFi.begin(ssid.c_str(), pass.c_str());

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > 20000) {
      Serial.println("[ERROR] WiFi Disconnected during publish!");
      Serial.println("[WIFI] Timeout, rebooting");
      ESP.restart();
    }
    Serial.print(".");
    delay(500);
  }
  Serial.printf("\n[WIFI] Connected! IP: %s\n", WiFi.localIP().toString().c_str());
}

void mqttCallback(char* topic, byte* payload, unsigned int len) {
  String msg;
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  Serial.printf("[MQTT] ← %s : %s\n", topic, msg.c_str());

  if (strcmp(topic, "home/ac/send") == 0) {
    DynamicJsonDocument req(2048);
    if (deserializeJson(req, msg) == DeserializationError::Ok) {
      sendIR(req["name"].as<String>());
    }
  } else if (strcmp(topic, "home/ac/available_cmds") == 0) {
    handleAvailableCommands(msg);
  } else if (strcmp(topic, "home/ac/erase_all") == 0) {
    commandMap.clear();
    sendStatus("Erase all requested");
  } else if (strcmp(topic, "home/ac/reset_wifi") == 0) {
    resetWiFi();
  }
}

void sendStatus(const String &msg) {
  Serial.printf("[STATUS] %s\n", msg.c_str());
  client.publish("home/ac/status", msg.c_str());
}

void requestCommandList() {
  Serial.println("[REQUEST] Asking for available_cmds");
  client.publish("home/ac/list", "");
}

void handleAvailableCommands(const String &msg) {
  Serial.println("[MQTT] ← available_cmds : " + msg);
  DynamicJsonDocument doc(8192);
  DeserializationError err = deserializeJson(doc, msg);
  if (err) {
    Serial.println("[ERROR] Invalid available_cmds JSON");
    return;
  }
  commandMap.clear();
  for (auto kv : doc.as<JsonObject>()) {
    String name = kv.key().c_str();
    JsonArray arr = kv.value().as<JsonArray>();
    std::vector<uint16_t> timings;
    for (auto v : arr) timings.push_back((uint16_t)v.as<uint32_t>());
    commandMap[name] = timings;
  }
}

void sendIR(const String &name) {
  Serial.printf("[IR SEND] %s\n", name.c_str());
  auto it = commandMap.find(name);
  if (it == commandMap.end()) {
    Serial.println("[ERROR] Command not found: " + name);
    return;
  }
  irsend.sendRaw(it->second.data(), it->second.size(), kRawTick);
  sendStatus("Sent " + name);
}

void learnIR(int index, const String &name) {
  Serial.printf("[LEARN] Button %d → %s\n", index, name.c_str());
  while (irrecv.decode(&results)) irrecv.resume();
  blinkFeedback(5, 75);
  sendStatus("Learning " + name);

  unsigned long start = millis();
  while (millis() - start < 20000) {
    if (irrecv.decode(&results)) {
      Serial.printf("[LEARN] Captured rawlen=%u\n", results.rawlen);

      DynamicJsonDocument doc(8192);
      doc["name"] = name;
      JsonArray timings = doc.createNestedArray("timings");
      for (size_t i = 0; i < results.rawlen; i++) {
        uint16_t d = results.rawbuf[i] * kRawTick;
        if (d > 50 && d < 20000) timings.add(d);
      }

      char buffer[4096];
      size_t len = serializeJson(doc, buffer, sizeof(buffer));
      Serial.printf("[DEBUG] Final payload size: %u bytes\n", len);
      Serial.printf("[MEM] Free heap before publish: %u\n", ESP.getFreeHeap());

      bool ok = client.publish("home/ac/save", (uint8_t*)buffer, len, false);
      Serial.printf("[DEBUG] publish() returned: %d\n", ok);
      if (!ok) Serial.println("[ERROR] MQTT publish failed!");

      client.loop();
      sendStatus("Learned " + name);
      irrecv.resume();
      return;
    }
  }

  sendStatus("Error: Timeout");
}

void handleButtons() {
  const String names[2] = { "on", "play" };
  for (int i = 0; i < 2; i++) {
    int raw = digitalRead(buttonPins[i]);
    bool pressed = (raw == LOW);
    unsigned long now = millis();

    if (pressed && pressStart[i] == 0) {
      pressStart[i] = now;
      Serial.printf("[DEBUG] Btn %d DOWN at %lums\n", i, now);
    } else if (!pressed && pressStart[i] != 0) {
      unsigned long dt = now - pressStart[i];
      Serial.printf("[DEBUG] Btn %d UP after %lums\n", i, dt);
      pressStart[i] = 0;

      if (dt > 2000) {
        learnIR(i, names[i]);
      } else {
        digitalWrite(ledPins[i], HIGH);
        sendIR(names[i]);
        delay(200);
        digitalWrite(ledPins[i], LOW);
      }
    }
  }
}

void blinkFeedback(int times, int ms) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(ms);
    digitalWrite(LED_PIN, LOW);
    delay(ms);
  }
}

void resetWiFi() {
  prefs.begin("wifi", false);
  prefs.clear();
  prefs.end();
  sendStatus("Wi-Fi reset, restarting");
  delay(500);
  ESP.restart();
}
