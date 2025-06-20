
#include <WiFiManager.h>
#include <WebServer.h>
#include <IRremoteESP8266.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <Preferences.h>
#include <SPIFFS.h>
#include <ArduinoJson.h>

#define RECV_PIN 23
#define IR_SEND_PIN 4

IRrecv irrecv(RECV_PIN);
IRsend irsend(IR_SEND_PIN);
WebServer server(80);
Preferences prefs;

decode_results results;

void setup() {
  Serial.begin(9600);
  SPIFFS.begin(true);
  irrecv.enableIRIn();
  irsend.begin();

  prefs.begin("wifi", true);
  bool configured = prefs.getBool("configured", false);
  prefs.end();

  if (!configured) {
    WiFiManager wm;
    if (!wm.startConfigPortal("ESP32-Setup")) {
      ESP.restart();
    }
    prefs.begin("wifi", false);
    prefs.putString("ssid", WiFi.SSID());
    prefs.putString("pass", WiFi.psk());
    prefs.putBool("configured", true);
    prefs.end();
    ESP.restart();
  }

  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  WiFi.begin(ssid.c_str(), pass.c_str());
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nConnected: " + WiFi.localIP().toString());

  server.on("/", HTTP_GET, []() {
    server.send(200, "text/html", R"rawliteral(
      <h2>IR Remote Control</h2>
      <form action="/learn">
        <input name="name" placeholder="Enter Command Name">
        <input type="submit" value="Learn IR">
      </form><br>
      <form action="/send">
        <input name="name" placeholder="Command Name to Send">
        <input type="submit" value="Send IR">
      </form><br>
      <a href="/list">View Saved Commands</a>
    )rawliteral");
  });

  server.on("/learn", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing command name");
      return;
    }

    String name = server.arg("name");
    server.send(200, "text/plain", "Waiting for IR signal…");

    unsigned long start = millis();
    while (!irrecv.decode(&results)) {
      if (millis() - start > 10000) {
        Serial.println("⏰ Timeout");
        return;
      }
      delay(50);
    }

    DynamicJsonDocument doc(16384);
    if (SPIFFS.exists("/codes.json")) {
      File file = SPIFFS.open("/codes.json", "r");
      deserializeJson(doc, file);
      file.close();
    }

    JsonArray arr = doc.createNestedArray(name);
    for (int i = 1; i < results.rawlen; i++) {
      arr.add(results.rawbuf[i] * kRawTick); // Convert to microseconds
    }

    File file = SPIFFS.open("/codes.json", "w");
    serializeJsonPretty(doc, file);
    file.close();

    irrecv.resume();
    Serial.println("✅ Learned and saved as: " + name);
  });

  server.on("/send", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing command name");
      return;
    }
    String name = server.arg("name");
    if (!SPIFFS.exists("/codes.json")) {
      server.send(404, "text/plain", "No stored IR codes");
      return;
    }

    File file = SPIFFS.open("/codes.json", "r");
    DynamicJsonDocument doc(16384);
    deserializeJson(doc, file);
    file.close();

    if (!doc.containsKey(name)) {
      server.send(404, "text/plain", "Command not found");
      return;
    }

    JsonArray arr = doc[name];
    uint16_t raw[arr.size()];
    for (int i = 0; i < arr.size(); i++) raw[i] = arr[i];

    irsend.sendRaw(raw, arr.size(), 38);
    Serial.println("📤 Sent IR command: " + name);
    server.send(200, "text/plain", "Sent " + name);
  });

  server.on("/list", HTTP_GET, []() {
    if (!SPIFFS.exists("/codes.json")) {
      server.send(200, "application/json", "{}");
      return;
    }
    File f = SPIFFS.open("/codes.json", "r");
    String content = f.readString();
    f.close();
    server.send(200, "application/json", content);
  });

  server.on("/reset", HTTP_GET, []() {
    WiFiManager wm; wm.resetSettings();
    prefs.begin("wifi", false); prefs.clear(); prefs.end();
    if (SPIFFS.exists("/codes.json")) SPIFFS.remove("/codes.json");
    server.send(200, "text/html", "<h3>Factory reset—rebooting...</h3>");
    delay(1000);
    ESP.restart();
  });

  server.begin();
  Serial.println("HTTP server started.");
}

void loop() {
  server.handleClient();
}
