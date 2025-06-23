#include <WiFiManager.h>       // Captive portal for Wi-Fi config
#include <WebServer.h>         // HTTP server
#include <HTTPClient.h>        // HTTP client for REST proxy
#include <IRremoteESP8266.h>   // IR constants (kRawTick, etc.)
#include <IRrecv.h>            // IR receiver
#include <IRsend.h>            // IR transmitter
#include <Preferences.h>       // NVS storage for Wi-Fi creds
#include <SPIFFS.h>            // For reset wiping SPIFFS if desired
#include <ArduinoJson.h>       // JSON serialization/parsing

// ─── CONFIG ────────────────────────────────────────────────────────────────

// IR hardware pins
#define RECV_PIN    23
#define IR_SEND_PIN 4

// Your FastAPI + PostgreSQL server base URL
const char *serverBase = "http://192.168.29.142:8000";

IRrecv irrecv(RECV_PIN);
IRsend irsend(IR_SEND_PIN);
WebServer server(80);
Preferences prefs;

// Temporary decode result
decode_results results;

// ─── SETUP ─────────────────────────────────────────────────────────────────
String urlencode(const String &s) {
  String enc = "";
  char c;
  for (size_t i = 0; i < s.length(); i++) {
    c = s[i];
    if ( (c >= '0' && c <= '9')
      || (c >= 'A' && c <= 'Z')
      || (c >= 'a' && c <= 'z')
      || c=='-' || c=='_' || c=='.' || c=='~') {
      enc += c;
    } else {
      char buf[4];
      sprintf(buf, "%%%02X", (uint8_t)c);
      enc += buf;
    }
  }
  return enc;
}
void setup() {
  Serial.begin(9600);
  Serial.println("[BOOT] Starting ESP32 setup");

  irrecv.enableIRIn();
  irsend.begin();
  Serial.println("[INFO] IR Receiver and Transmitter initialized");

  // Check if Wi-Fi creds are stored
  prefs.begin("wifi", true);
  bool configured = prefs.getBool("configured", false);
  prefs.end();

  if (!configured) {
    Serial.println("[INFO] No Wi-Fi config found. Launching AP mode...");
    WiFiManager wm;
    if (!wm.startConfigPortal("ESP32-Setup")) {
      Serial.println("[ERROR] Config portal failed");
      ESP.restart();
    }
    prefs.begin("wifi", false);
    prefs.putString("ssid", WiFi.SSID());
    prefs.putString("pass", WiFi.psk());
    prefs.putBool("configured", true);
    prefs.end();
    Serial.println("[INFO] Wi-Fi credentials saved. Restarting...");
    ESP.restart();
  }

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
  Serial.printf("[INFO] Connected! IP Address: %s\n", WiFi.localIP().toString().c_str());

  // LEARN
  server.on("/learn", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing name");
      Serial.println("[WARN] /learn called without 'name'");
      return;
    }
    String name = server.arg("name");
    Serial.printf("[INFO] Capturing IR for: %s\n", name.c_str());

    unsigned long t0 = millis();
    while (!irrecv.decode(&results) && millis() - t0 < 10000) {
      delay(20);
    }
    if (results.decode_type == UNKNOWN) {
      server.send(422, "text/plain", "No IR signal");
      Serial.println("[WARN] No IR signal captured");
      return;
    }
    irrecv.resume();

    DynamicJsonDocument payload(8192);
    payload["name"] = name;
    JsonArray arr = payload.createNestedArray("raw");
    for (size_t i = 1; i < results.rawlen; i++) {
      arr.add(results.rawbuf[i] * kRawTick);
    }
    String body;
    serializeJson(payload, body);

    Serial.println("[DEBUG] Sending IR data to backend...");
    HTTPClient http;
    http.begin(String(serverBase) + "/learn");
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(body);
    String resp = http.getString();
    http.end();

    Serial.printf("[INFO] Response from backend: %d\n", code);
    server.send(code, "text/plain", resp);
  });

  // SEND
  server.on("/send", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing name");
      Serial.println("[WARN] /send called without 'name'");
      return;
    }
    String name = urlencode(server.arg("name"));
    Serial.printf("[INFO] Sending command: %s\n", name.c_str());

    HTTPClient http;
    http.begin(String(serverBase) + "/send?name=" + name);
    int code = http.GET();
    String resp = http.getString();
    http.end();

    if (code != 200) {
      Serial.printf("[ERROR] Backend send failed: %d %s\n", code, resp.c_str());
      server.send(code, "text/plain", resp);
      return;
    }

    DynamicJsonDocument doc(8192);
    if (deserializeJson(doc, resp)) {
      Serial.println("[ERROR] Invalid JSON from backend");
      server.send(500, "text/plain", "Invalid JSON");
      return;
    }
    JsonArray arr = doc["raw"].as<JsonArray>();

    size_t n = arr.size();
    uint16_t raw[n];
    for (size_t i = 0; i < n; i++) raw[i] = arr[i].as<uint16_t>();

    Serial.println("[INFO] Transmitting IR signal...");
    irsend.sendRaw(raw, n, 38);
    server.send(200, "text/plain", "Sent " + name);
  });

  // LIST
  server.on("/list", HTTP_GET, []() {
    Serial.println("[INFO] Fetching command list...");
    HTTPClient http;
    http.begin(String(serverBase) + "/list");
    int code = http.GET();
    String resp = http.getString();
    http.end();
    Serial.printf("[INFO] Response from /list: %d\n", code);
    server.send(code, "application/json", resp);
  });

  // DELETE
  server.on("/delete", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing name");
      Serial.println("[WARN] /delete called without 'name'");
      return;
    }
    String name = server.arg("name");
    String encoded = urlencode(name);
    String url = String(serverBase) + "/delete?name=" + encoded;

    Serial.printf("[INFO] Deleting command: %s → URL: %s\n", name.c_str(), url.c_str());

    HTTPClient http;
    http.begin(url);
    int code = http.sendRequest("DELETE", (uint8_t*)"", 0);
    String resp = http.getString();
    http.end();
    server.send(code, "text/plain", resp);
  });

  // RENAME
  server.on("/rename", HTTP_GET, []() {
    if (!server.hasArg("old") || !server.hasArg("new")) {
      server.send(400, "text/plain", "Missing old or new");
      Serial.println("[WARN] /rename missing 'old' or 'new'");
      return;
    }
    String oldName = server.arg("old");
    String newName = server.arg("new");
    String url = String(serverBase)
                 + "/rename?old=" + urlencode(oldName)
                 + "&new=" + urlencode(newName);

    Serial.printf("[INFO] Renaming: '%s' to '%s'\n", oldName.c_str(), newName.c_str());

    HTTPClient http;
    http.begin(url);
    int code = http.sendRequest("PUT", String());
    String resp = http.getString();
    http.end();

    Serial.printf("[INFO] Rename result: %d\n", code);
    server.send(code, "text/plain", resp);
  });

  // RESET
  server.on("/reset", HTTP_GET, []() {
    Serial.println("[WARN] Factory reset requested");
    WiFiManager wm; wm.resetSettings();
    prefs.begin("wifi", false);
    prefs.clear();
    prefs.end();
    server.send(200, "text/html",
                "<h3>Factory reset… rebooting</h3>");
    delay(1000);
    ESP.restart();
  });

  // Start server
  server.begin();
  Serial.println("[BOOT] HTTP server started and ready");
}

void loop() {
  server.handleClient();
}
