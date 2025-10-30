#include "esp_camera.h"
#include "BluetoothSerial.h"

// Camera model: AI Thinker
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

BluetoothSerial SerialBT;
bool streaming = false;
unsigned long lastFrameTime = 0;
const unsigned long FRAME_INTERVAL = 1000; // 1 second = 1 FPS

void setup() {
  Serial.begin(115200);
  Serial.println("ESP32-CAM Bluetooth Image Stream");

  // Initialize camera
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;

  // Init with high specs to pre-allocate larger buffers
  if(psramFound()){
    config.frame_size = FRAMESIZE_VGA;  // 640x480
    config.jpeg_quality = 10;
    config.fb_count = 2;
  } else {
    config.frame_size = FRAMESIZE_QVGA; // 320x240
    config.jpeg_quality = 12;
    config.fb_count = 1;
  }

  // Camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", err);
    return;
  }

  // Initialize Bluetooth
  SerialBT.begin("ESP32_CAM"); // Bluetooth device name
  Serial.println("Bluetooth started. Device name: ESP32_CAM");
  Serial.println("Waiting for connection...");
}

void loop() {
  // Check for incoming commands
  if (SerialBT.available()) {
    String command = SerialBT.readStringUntil('\n');
    command.trim();

    Serial.println("Received command: " + command);

    if (command == "START") {
      streaming = true;
      Serial.println("Streaming started");
    }
    else if (command == "STOP") {
      streaming = false;
      Serial.println("Streaming stopped");
    }
    else if (command == "SNAPSHOT") {
      sendFrame();
    }
  }

  // Stream frames if enabled
  if (streaming) {
    unsigned long currentTime = millis();
    if (currentTime - lastFrameTime >= FRAME_INTERVAL) {
      sendFrame();
      lastFrameTime = currentTime;
    }
  }
}

void sendFrame() {
  // Capture a frame
  camera_fb_t * fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("Camera capture failed");
    return;
  }

  // Send the frame via Bluetooth
  Serial.printf("Sending frame: %d bytes\n", fb->len);
  SerialBT.write(fb->buf, fb->len);

  // Return the frame buffer back to the driver for reuse
  esp_camera_fb_return(fb);
}
