#include <WiFiManager.h>       // WiFi Manager for captive portal
#include <WebServer.h>         // Web server for HTTP requests
#include <IRremoteESP8266.h>
#include <IRsend.h>
#include <Preferences.h>
#include <Arduino.h>

const uint16_t kIrLedPin = 4; // IR LED pin
IRsend irsend(kIrLedPin);     // IR sender object

Preferences prefs;
WebServer server(80);         // Web server

// IR raw codes
uint16_t raw_pause[] = {2678, 886,  420, 478,  448, 450,  448, 900,  420, 928,  1310, 936,  420, 478,  452, 446,  456, 442,  454, 444,  454, 444,  450, 448,  420, 478,  866, 930,  866, 930,  420, 478,  866, 930,  420, 478,  452, 444,  902, 894,  420, 478,  864, 482,  456, 892,  420, 478,  864, 482,  452, 896,  864, 482,  420, 478,  454, 892,  422};
uint16_t raw_play[] = {2672, 890,  446, 450,  420, 478,  420, 926,  452, 896,  1310, 936,  446, 452,  444, 452,  420, 478,  452, 446,  446, 450,  420, 478,  450, 448,  896, 900,  864, 932,  446, 452,  864, 932,  896, 902,  862, 932,  420, 478,  864, 482,  418, 928,  450, 448,  864, 484,  446, 900,  896, 450,  420, 478,  448, 900,  450};
uint16_t raw_fwd[] = {2674, 888,  418, 480,  418, 478,  452, 894,  420, 926,  1310, 934,  422, 476,  420, 478,  420, 476,  424, 474,  454, 442,  450, 448,  456, 444,  900, 894,  864, 932,  420, 478,  900, 894,  420, 478,  450, 446,  866, 932,  420, 478,  900, 448,  454, 892,  448, 450,  456, 442,  454, 444,  454, 444,  454, 444,  454, 444,  418, 478,  864};
uint16_t raw_prev[] = {2652, 912,  424, 474,  420, 478,  420, 928,  454, 892,  1314, 934,  430, 466,  420, 478,  418, 478,  420, 478,  420, 478,  420, 478,  420, 478,  866, 932,  874, 920,  426, 470,  870, 928,  866, 930,  876, 920,  426, 470,  872, 474,  420, 928,  428, 468,  868, 928,  872, 474,  428, 922,  446, 450,  866};

const size_t len_play = sizeof(raw_play) / sizeof(raw_play[0]);
const size_t len_pause = sizeof(raw_pause) / sizeof(raw_pause[0]);
const size_t len_fwd = sizeof(raw_fwd) / sizeof(raw_fwd[0]);
const size_t len_prev = sizeof(raw_prev) / sizeof(raw_prev[0]);

void serveConfigForm();
void handleSave();
void handleSend();

void setup() {
  Serial.begin(9600);
  irsend.begin();

  prefs.begin("wifi", true);
  bool configured = prefs.getBool("configured", false);
  prefs.end();

  if (!configured) {
    WiFiManager wm;
    if (!wm.startConfigPortal("ESP32-Setup")) {
      Serial.println("Config portal failed or timed out");
      ESP.restart();
    }

    // ✅ Save SSID/PASS to Preferences
    prefs.begin("wifi", false);
    prefs.putString("ssid", WiFi.SSID());
    prefs.putString("pass", WiFi.psk());
    prefs.putBool("configured", true);
    prefs.end();

    Serial.println("✔ Wi‑Fi configured and saved");
    ESP.restart();
  }

  // Load saved credentials
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  Serial.printf("Connecting to %s …\n", ssid.c_str());
  WiFi.begin(ssid.c_str(), pass.c_str());

  unsigned long startAttempt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < 20000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\n❌ Failed to connect. Restarting...");
    ESP.restart();
  }

  Serial.println("\n✔ Connected. IP: " + WiFi.localIP().toString());

  // Define HTTP routes
  server.on("/", HTTP_GET, serveConfigForm);
  server.on("/config", HTTP_GET, serveConfigForm);
  server.on("/save", HTTP_GET, handleSave);
  server.on("/send", HTTP_GET, handleSend);
  server.on("/reset", HTTP_GET, []() {
    WiFiManager wm;
    wm.resetSettings();
  
    prefs.begin("wifi", false);
    prefs.clear();     // wipe ssid/pass/configured
    prefs.end();
  
    server.send(200, "text/html",
                "<h3>Wi‑Fi credentials erased.<br>Rebooting to setup portal...</h3>");
    delay(1000);       // give the TCP stack time to flush the response
    ESP.restart();
  });

  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  server.handleClient();
}

void serveConfigForm() {
  server.send(200, "text/html", R"rawliteral(
    <html><body>
      <h2>Send IR Command</h2>
      <form action="/send">
        Command: 
        <select name="cmd">
          <option value="play">Play</option>
          <option value="pause">Pause</option>
          <option value="prev">Previous</option>
          <option value="fwd">Forward</option>
        </select>
        <input type="submit" value="Send">
      </form>
      <br><a href="/reset"><button>Reset Wi-Fi Settings</button></a>
    </body></html>
  )rawliteral");
}

void handleSave() {
  if (!server.hasArg("ssid") || !server.hasArg("pass")) {
    server.send(400, "text/plain", "Missing ssid or pass");
    return;
  }

  prefs.begin("wifi", false);
  prefs.putString("ssid",  server.arg("ssid"));
  prefs.putString("pass",  server.arg("pass"));
  prefs.putBool("configured", true);
  prefs.end();

  server.send(200, "text/html", "<h3>Saved—rebooting...</h3>");
  delay(1000);
  ESP.restart();
}

void handleSend() {
  if (!server.hasArg("cmd")) {
    server.send(400, "text/plain", "Missing cmd");
    return;
  }

  String cmd = server.arg("cmd");
  Serial.println("Sending IR: " + cmd);

  if (cmd == "play")        irsend.sendRaw(raw_play, len_play, 38);
  else if (cmd == "pause")  irsend.sendRaw(raw_pause, len_pause, 38);
  else if (cmd == "prev")   irsend.sendRaw(raw_prev, len_prev, 38);
  else if (cmd == "fwd")    irsend.sendRaw(raw_fwd, len_fwd, 38);
  else {
    server.send(400, "text/plain", "Invalid cmd");
    return;
  }

  server.send(200, "text/plain", "OK");
}












