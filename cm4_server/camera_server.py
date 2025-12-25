#!/usr/bin/env python3
"""
CM4 Triple Camera MJPEG Streaming Server for Third Eye App
Streams 3 simultaneous 1080p camera feeds at 10fps (adaptive down to 5fps)
"""

import io
import time
import threading
import logging
from flask import Flask, Response, jsonify
from picamera2 import Picamera2
from PIL import Image

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Configuration
RESOLUTION = (1920, 1080)  # 1080p
TARGET_FPS = 10
MIN_FPS = 5
JPEG_QUALITY = 80

# Camera configuration
CAMERAS = {
    'left': {'port': 8081, 'camera_index': 0},
    'right': {'port': 8082, 'camera_index': 1},
    'eye': {'port': 8083, 'camera_index': 2}
}

# Global state for each camera
camera_states = {}


class CameraStream:
    """Manages a single camera stream with adaptive FPS"""

    def __init__(self, camera_name, camera_index):
        self.camera_name = camera_name
        self.camera_index = camera_index
        self.frame = None
        self.lock = threading.Lock()
        self.picam = None
        self.running = False
        self.clients = 0
        self.fps = TARGET_FPS
        self.frame_count = 0
        self.start_time = time.time()
        self.last_frame_time = 0

    def initialize_camera(self):
        """Initialize the camera with error handling"""
        try:
            self.picam = Picamera2(self.camera_index)
            config = self.picam.create_still_configuration(
                main={"size": RESOLUTION, "format": "RGB888"}
            )
            self.picam.configure(config)
            self.picam.start()
            logger.info(f"Camera '{self.camera_name}' (index {self.camera_index}) initialized at {RESOLUTION}")
            return True
        except Exception as e:
            logger.error(f"Failed to initialize camera '{self.camera_name}': {e}")
            self.picam = None
            return False

    def capture_loop(self):
        """Continuously capture frames at adaptive FPS"""
        self.running = True

        if not self.initialize_camera():
            # Create placeholder frame if camera fails
            self._create_placeholder_frame()
            return

        try:
            while self.running:
                loop_start = time.time()

                # Capture frame
                try:
                    array = self.picam.capture_array()

                    # Convert to JPEG
                    img = Image.fromarray(array)
                    buffer = io.BytesIO()
                    img.save(buffer, format='JPEG', quality=JPEG_QUALITY)
                    jpeg_bytes = buffer.getvalue()

                    # Update frame
                    with self.lock:
                        self.frame = jpeg_bytes
                        self.frame_count += 1
                        self.last_frame_time = time.time()

                except Exception as e:
                    logger.error(f"Error capturing from '{self.camera_name}': {e}")
                    time.sleep(0.1)
                    continue

                # Adaptive FPS: calculate sleep time
                capture_time = time.time() - loop_start
                target_interval = 1.0 / self.fps
                sleep_time = max(0, target_interval - capture_time)

                if sleep_time > 0:
                    time.sleep(sleep_time)
                else:
                    # Running behind, reduce FPS
                    if self.fps > MIN_FPS:
                        self.fps = max(MIN_FPS, self.fps - 1)
                        logger.warning(f"'{self.camera_name}' reducing FPS to {self.fps}")

        finally:
            if self.picam:
                self.picam.stop()
                logger.info(f"Camera '{self.camera_name}' stopped")

    def _create_placeholder_frame(self):
        """Create a placeholder image when camera is unavailable"""
        img = Image.new('RGB', RESOLUTION, color=(50, 50, 50))
        buffer = io.BytesIO()
        img.save(buffer, format='JPEG', quality=50)
        with self.lock:
            self.frame = buffer.getvalue()
        logger.info(f"Using placeholder for '{self.camera_name}'")

    def get_frame(self):
        """Get the latest frame (thread-safe)"""
        with self.lock:
            return self.frame

    def get_stats(self):
        """Get streaming statistics"""
        elapsed = time.time() - self.start_time
        actual_fps = self.frame_count / elapsed if elapsed > 0 else 0
        return {
            'camera': self.camera_name,
            'clients': self.clients,
            'target_fps': self.fps,
            'actual_fps': round(actual_fps, 2),
            'frames_captured': self.frame_count,
            'running': self.running,
            'has_camera': self.picam is not None
        }

    def stop(self):
        """Stop the capture loop"""
        self.running = False


def generate_mjpeg(camera_stream):
    """Generator for MJPEG multipart stream"""
    camera_stream.clients += 1
    logger.info(f"Client connected to '{camera_stream.camera_name}' (total: {camera_stream.clients})")

    try:
        while True:
            frame = camera_stream.get_frame()
            if frame is None:
                time.sleep(0.01)
                continue

            # Yield frame in multipart format
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

            # Adaptive delay based on FPS
            time.sleep(1.0 / camera_stream.fps)

    finally:
        camera_stream.clients -= 1
        logger.info(f"Client disconnected from '{camera_stream.camera_name}' (remaining: {camera_stream.clients})")


def create_camera_app(camera_name, camera_stream):
    """Create a Flask app for a specific camera"""
    app = Flask(f"{camera_name}_cam")

    @app.route('/stream')
    def stream():
        return Response(
            generate_mjpeg(camera_stream),
            mimetype='multipart/x-mixed-replace; boundary=frame'
        )

    @app.route('/stats')
    def stats():
        return jsonify(camera_stream.get_stats())

    @app.route('/health')
    def health():
        return jsonify({'status': 'ok', 'camera': camera_name})

    return app


def start_camera_server(camera_name, camera_index, port):
    """Start a camera server on a specific port"""
    camera_stream = CameraStream(camera_name, camera_index)
    camera_states[camera_name] = camera_stream

    # Start capture thread
    capture_thread = threading.Thread(target=camera_stream.capture_loop, daemon=True)
    capture_thread.start()

    # Give camera time to initialize
    time.sleep(2)

    # Start Flask server
    app = create_camera_app(camera_name, camera_stream)
    logger.info(f"Starting {camera_name} camera server on port {port}")
    app.run(host='0.0.0.0', port=port, threaded=True, debug=False)


def main():
    """Start all camera servers"""
    logger.info("=" * 60)
    logger.info("CM4 Triple Camera MJPEG Streaming Server")
    logger.info(f"Resolution: {RESOLUTION[0]}x{RESOLUTION[1]}")
    logger.info(f"Target FPS: {TARGET_FPS} (adaptive down to {MIN_FPS})")
    logger.info(f"JPEG Quality: {JPEG_QUALITY}")
    logger.info("=" * 60)

    threads = []

    for camera_name, config in CAMERAS.items():
        thread = threading.Thread(
            target=start_camera_server,
            args=(camera_name, config['camera_index'], config['port']),
            daemon=True
        )
        thread.start()
        threads.append(thread)
        logger.info(f"Camera '{camera_name}' starting on port {config['port']}")

    # Keep main thread alive
    logger.info("\nAll camera servers started. Press Ctrl+C to stop.\n")
    logger.info("Stream URLs:")
    logger.info("  Left:  http://192.168.50.1:8081/stream")
    logger.info("  Right: http://192.168.50.1:8082/stream")
    logger.info("  Eye:   http://192.168.50.1:8083/stream")
    logger.info("\nStats URLs:")
    logger.info("  http://192.168.50.1:8081/stats")
    logger.info("  http://192.168.50.1:8082/stats")
    logger.info("  http://192.168.50.1:8083/stats")
    logger.info("=" * 60 + "\n")

    try:
        for thread in threads:
            thread.join()
    except KeyboardInterrupt:
        logger.info("\nShutting down camera servers...")
        for camera_stream in camera_states.values():
            camera_stream.stop()
        logger.info("Shutdown complete")


if __name__ == '__main__':
    main()
