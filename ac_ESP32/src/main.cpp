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

  // Optional: mount SPIFFS (only for reset endpoint)
  if (!SPIFFS.begin(/*formatOnFail=*/false)) {
    Serial.println("[WARN] SPIFFS mount failed");
  }

  // IR hardware init
  irrecv.enableIRIn();
  irsend.begin();

  // Check if Wi-Fi creds are stored
  prefs.begin("wifi", true);
  bool configured = prefs.getBool("configured", false);
  prefs.end();

  // If not, launch captive portal
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

  // Load saved Wi-Fi creds
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  // Connect to Wi-Fi
  WiFi.begin(ssid.c_str(), pass.c_str());
  Serial.print("[INFO] Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.printf("[INFO] Connected, IP: %s\n", WiFi.localIP().toString().c_str());

  // ── REST PROXY ENDPOINTS ───────────────────────────────────────

  // LEARN: capture IR, then POST to remote /learn
  server.on("/learn", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing name");
      return;
    }
    String name = server.arg("name");

    // capture IR
    unsigned long t0 = millis();
    while (!irrecv.decode(&results) && millis() - t0 < 10000) {
      delay(20);
    }
    if (results.decode_type == UNKNOWN) {
      server.send(422, "text/plain", "No IR signal");
      return;
    }
    irrecv.resume();

    // build JSON payload
    DynamicJsonDocument payload(8192);
    payload["name"] = name;
    JsonArray arr = payload.createNestedArray("raw");
    for (size_t i = 1; i < results.rawlen; i++) {
      arr.add(results.rawbuf[i] * kRawTick);
    }
    String body;
    serializeJson(payload, body);

    // HTTP POST to backend
    HTTPClient http;
    http.begin(String(serverBase) + "/learn");
    http.addHeader("Content-Type", "application/json");
    int code = http.POST(body);
    String resp = http.getString();
    http.end();

    server.send(code, "text/plain", resp);
  });

  // SEND: GET raw from backend, then transmit
  server.on("/send", HTTP_GET, []() {
    if (!server.hasArg("name")) {
      server.send(400, "text/plain", "Missing name");
      return;
    }
    String name = urlencode("name");

    // HTTP GET from backend
    HTTPClient http;
    http.begin(String(serverBase) + "/send?name=" + name);
    int code = http.GET();
    String resp = http.getString();
    http.end();

    if (code != 200) {
      server.send(code, "text/plain", resp);
      return;
    }

    // parse JSON
    DynamicJsonDocument doc(8192);
    if (deserializeJson(doc, resp)) {
      server.send(500, "text/plain", "Invalid JSON");
      return;
    }
    JsonArray arr = doc["raw"].as<JsonArray>();

    // build raw array
    size_t n = arr.size();
    uint16_t raw[n];
    for (size_t i = 0; i < n; i++) raw[i] = arr[i].as<uint16_t>();

    // send IR
    irsend.sendRaw(raw, n, 38);
    server.send(200, "text/plain", "Sent " + name);
  });

  // LIST: proxy to backend
  server.on("/list", HTTP_GET, []() {
    HTTPClient http;
    http.begin(String(serverBase) + "/list");
    int code = http.GET();
    String resp = http.getString();
    http.end();
    server.send(code, "application/json", resp);
  });
  // RFC-3986 percent-encoder for query components



// DELETE: proxy to backend (percent-encode the name!)
server.on("/delete", HTTP_GET, []() {
  if (!server.hasArg("name")) {
    server.send(400, "text/plain", "Missing name");
    return;
  }
  String name = server.arg("name");

  // percent-encode spaces and special chars
  String encoded = urlencode(name);
  String url = String(serverBase) + "/delete?name=" + encoded;

  Serial.printf("[DEBUG] Forwarding DELETE to: %s\n", url.c_str());

  HTTPClient http;
  http.begin(url);
  int code = http.sendRequest("DELETE", (uint8_t*)"", 0);
  String resp = http.getString();
  http.end();

  server.send(code, "text/plain", resp);
});



  // RENAME: proxy to backend
  server.on("/rename", HTTP_GET, []() {
    if (!server.hasArg("old") || !server.hasArg("new")) {
      server.send(400, "text/plain", "Missing old or new");
      return;
    }
    String oldName = server.arg("old");
    String newName = server.arg("new");
    String url = String(serverBase)
                 + "/rename?old=" + urlencode(oldName)
                 + "&new=" + urlencode(newName);
    HTTPClient http;
    http.begin(url);
    // Send an empty-body PUT
    int code = http.sendRequest("PUT", String());
    String resp = http.getString();
    http.end();
    server.send(code, "text/plain", resp);
  });
  

  // RESET: clear Wi-Fi creds & factory reset
  server.on("/reset", HTTP_GET, []() {
    WiFiManager wm; wm.resetSettings();
    prefs.begin("wifi", false);
    prefs.clear();
    prefs.end();
    server.send(200, "text/html",
                "<h3>Factory reset… rebooting</h3>");
    delay(1000);
    ESP.restart();
  });


  // start server
  server.begin();
  Serial.println("[INFO] HTTP server started");
}

// ─── LOOP ──────────────────────────────────────────────────────────────────

void loop() {
  server.handleClient();
}
