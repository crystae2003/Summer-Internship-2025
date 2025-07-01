#include <WiFi.h>
#include <SPIFFS.h>
#include <PubSubClient.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <WiFiManager.h>  // Include this for captive portal

Preferences prefs;

// IR pins
#define RECV_PIN    23
#define IR_SEND_PIN 4
#define LED_PIN     21

// Buttons + LEDs
#define BTN_ON    18
#define LED_ON    2
#define BTN_PLAY  19
#define LED_PLAY  22

const int buttonPins[2] = { BTN_ON, BTN_PLAY };
const int ledPins[2]   = { LED_ON, LED_PLAY };

// MQTT broker
const char* mqtt_server = "192.168.29.142";
const int   mqtt_port   = 1883;
const char* mqtt_user   = "hema";
const char* mqtt_pass   = "@hema.";

WiFiClient    espClient;
PubSubClient  client(espClient);
IRrecv        irrecv(RECV_PIN);
IRsend        irsend(IR_SEND_PIN);
decode_results results;

unsigned long pressStart[2] = {0, 0};

// --- Function Prototypes ---
void setup_wifi();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void loadCommands(JsonDocument &doc);
void saveCommands(JsonDocument &doc);
void sendStatus(const String &msg);
void publishCommandList();
void sendIR(const String &name);
void learnIR(int index, const String &name);
void handleButtons();
void blinkFeedback(int times, int ms);
void resetWiFi();

void setup() {
  Serial.begin(9600);
  SPIFFS.begin(true);

  pinMode(LED_PIN, OUTPUT);
  pinMode(BTN_ON, INPUT_PULLUP);
  pinMode(LED_ON, OUTPUT);
  pinMode(BTN_PLAY, INPUT_PULLUP);
  pinMode(LED_PLAY, OUTPUT);

  // IR init
  irrecv.enableIRIn();
  irsend.begin();

  // WiFi setup with dynamic portal if first time
  prefs.begin("wifi", true);
  bool configured = prefs.getBool("configured", false);
  prefs.end();

  if (!configured) {
    WiFiManager wm;
    if (!wm.startConfigPortal("ESP32-Setup")) {
      Serial.println("[ERROR] Config portal failed");
      ESP.restart();
    }

    // Save credentials
    prefs.begin("wifi", false);
    prefs.putString("ssid", WiFi.SSID());
    prefs.putString("pass", WiFi.psk());
    prefs.putBool("configured", true);
    prefs.end();
    ESP.restart();
  }

  // Load stored credentials
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  WiFi.begin(ssid.c_str(), pass.c_str());
  Serial.print("[INFO] Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.printf("[INFO] Connected, IP: %s\n", WiFi.localIP().toString().c_str());

  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(mqttCallback);

  sendStatus("ESP32 Ready");
}

void loop() {
  if (!client.connected()) {
    while (!client.connect("esp32Client", mqtt_user, mqtt_pass)) {
      delay(2000);
    }
    client.subscribe("home/ac/#");
    sendStatus("Connected");
    publishCommandList();
  }

  client.loop();
  handleButtons();
}

// MQTT Callback
void mqttCallback(char* topic, byte* payload, unsigned int len) {
  String msg;
  for (unsigned int i = 0; i < len; i++) msg += char(payload[i]);
  Serial.printf("MQTT ← %s: %s\n", topic, msg.c_str());

  if (String(topic) == "home/ac/send") {
    DynamicJsonDocument req(256);
    if (deserializeJson(req, msg) == DeserializationError::Ok) {
      sendIR(req["name"].as<String>());
    }
  } else if (String(topic) == "home/ac/list") {
    publishCommandList();
  } else if (String(topic) == "home/ac/erase_all") {
    SPIFFS.remove("/codes.json");
    sendStatus("All commands erased");
    publishCommandList();
  } else if (String(topic) == "home/ac/reset_wifi") {
    resetWiFi();
  }
}

// Wi-Fi Reset Logic
void resetWiFi() {
  prefs.begin("wifi", false);
  prefs.clear();  // Clear all saved creds
  prefs.end();
  sendStatus("Wi-Fi credentials cleared, restarting...");
  delay(1000);
  ESP.restart();
}

// Load commands
void loadCommands(JsonDocument &doc) {
  File f = SPIFFS.open("/codes.json", FILE_READ);
  if (!f) return;
  deserializeJson(doc, f);
  f.close();
}

// Save commands
void saveCommands(JsonDocument &doc) {
  File f = SPIFFS.open("/codes.json", FILE_WRITE);
  serializeJson(doc, f);
  f.close();
  publishCommandList();
}

void sendStatus(const String &msg) {
  client.publish("home/ac/status", msg.c_str());
  Serial.println(">> Status: " + msg);
}

void publishCommandList() {
  DynamicJsonDocument doc(10 * 1024);
  loadCommands(doc);
  String payload;
  serializeJson(doc, payload);
  client.publish("home/ac/available_cmds", payload.c_str());
  Serial.println(">> Cmds: " + payload);
}

// Send learned IR
void sendIR(const String &name) {
  DynamicJsonDocument doc(10 * 1024);
  loadCommands(doc);
  if (!doc.containsKey(name)) {
    sendStatus("Error: Cmd not found");
    return;
  }
  JsonArray arr = doc[name];
  size_t n = arr.size();
  uint16_t *raw = new uint16_t[n];
  for (size_t i = 0; i < n; i++) raw[i] = arr[i].as<uint16_t>();
  irsend.sendRaw(raw, n, 38);
  delete[] raw;
  sendStatus("Sent " + name);
}

// Learn and save new IR
void learnIR(int index, const String &name) {
  while (irrecv.decode(&results)) irrecv.resume();
  blinkFeedback(5, 75);
  sendStatus("Learning " + name);

  unsigned long start = millis();
  while (millis() - start < 20000) {
    if (irrecv.decode(&results)) {
      Serial.printf(" → rawlen=%u; filtering...\n", results.rawlen);
      DynamicJsonDocument doc(10 * 1024);
      loadCommands(doc);
      doc.remove(name);
      JsonArray arr = doc.createNestedArray(name);
      for (size_t i = 0; i < results.rawlen; i++) {
        uint16_t d = results.rawbuf[i] * kRawTick;
        if (d > 50 && d < 20000) arr.add(d);
      }
      Serial.printf(" → kept %u values\n", arr.size());
      saveCommands(doc);
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
    bool pressed = digitalRead(buttonPins[i]) == LOW;
    if (pressed && pressStart[i] == 0) {
      pressStart[i] = millis();
    } else if (!pressed && pressStart[i] != 0) {
      unsigned long dt = millis() - pressStart[i];
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
