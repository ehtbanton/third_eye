# Third Eye: End-to-End Navigation Architecture Plan

## Goal
Transform the current collection of services into a cohesive "Blind Navigation System" that provides:
1.  **Macro-Navigation:** Route planning and checkpoint guidance.
2.  **Micro-Guidance:** Real-time heading correction ("Turn slightly right").
3.  **Safety Layer:** Immediate obstacle warnings (Depth + Object Detection).
4.  **Scene Understanding:** High-level path analysis using Vision LLMs.

---

## 1. Architecture Overview

We will introduce a central coordinator, the **`NavigationSessionManager`**, which acts as the brain. It fuses data from three subsystems.

### Subsystems:
1.  **Positioning & Heading (The "Compass"):** 
    *   *Inputs:* GPS (`geolocator`), Magnetometer (`flutter_compass` - **NEW**).
    *   *Responsibility:* Knows where the user is and which way they are facing.
2.  **Reflex Vision (The "eyes"):**
    *   *Inputs:* Camera Feed, YOLO (`ObjectDetectionService`), MiDaS (`DepthMapService`).
    *   *Responsibility:* Fast, local detection of immediate physical threats (poles, people, cars).
3.  **Cognitive Vision (The "Cortex"):**
    *   *Inputs:* Camera Feed, Gemini 2.0 Flash (`CellularGeminiService`).
    *   *Responsibility:* Complex scene understanding ("The sidewalk ends ahead," "There is a puddle").

---

## 2. Detailed Implementation Steps

### Phase 1: Orientation & Precise Guidance (The Foundation)
*Current Problem:* `NavigationGuidanceService` only checks distance. It doesn't know if the user is facing the wrong way.
*   **Action:** Add `flutter_compass` dependency.
*   **Action:** Update `NavigationGuidanceService` to calculate:
    *   `Target Bearing`: Angle from User to Next Checkpoint.
    *   `Heading Delta`: Difference between `Device Heading` and `Target Bearing`.
*   **Output:** Voice commands change from "Go to point" to "Turn left 30 degrees", then "Walk forward".

### Phase 2: The Safety "Reflex" Loop (Obstacle Avoidance)
*Current Problem:* YOLO and Depth run but don't warn.
*   **Action:** Create `ObstacleFusionService`.
*   **Logic:**
    1.  Receive YOLO Bounding Boxes.
    2.  Receive Depth Map.
    3.  **Map Box to Depth:** Calculate the average depth *inside* the YOLO box.
    4.  **Zonal Safety Check:**
        *   Define zones: *Left, Center, Right*.
        *   If an object in *Center* is < 2.0 meters: **CRITICAL WARNING** ("Stop! Pole ahead").
        *   If an object in *Side* is < 1.0 meters: **Caution** ("Person on your right").

### Phase 3: The "Ideal World" Pathing (Vision LLM)
*Current Problem:* Hard-coded CV misses context (e.g., a path that curves but has no objects).
*   **Action:** Integrate `CellularGeminiService` (Gemini 2.0 Flash) into the loop.
*   **Logic:**
    *   Trigger: Periodic (every 10s) OR on user request (Double tap screen/button).
    *   Prompt: *"I am a blind user. Analyze this image. Is the path ahead safe and walkable? If not, briefly say why. Be concise."*
    *   Output: TTS of the response.

---

## 3. Data Flow Diagram

```
[Camera Feed] --> [StreamSplitter]
      |                 |
      v                 v
[Reflex Loop]     [Cognitive Loop (10s)]
(YOLO + Depth)    (Gemini Flash API)
      |                 |
      |                 v
      |          "Sidewalk curves left"
      v
"Stop! Tree 1m"
      |
      v
[NavigationSessionManager] <--- [Location/Compass]
      |                                |
      | (Prioritize Safety)            | "Turn Right 20 deg"
      v                                v
[Text-to-Speech Engine] ("Stop! Tree ahead. Then turn right.")
```

## 4. Technical Requirements

1.  **New Dependencies:**
    *   `flutter_compass`: For stationary heading.
    *   `sensors_plus`: (Optional backup).

2.  **Refactoring:**
    *   Extract the "loop" logic from `ImagePickerScreen` into `NavigationSessionManager`.
    *   Ensure `flutter_vision` and `tflite_flutter` don't block the UI thread (isolate usage if possible, though currently likely on main thread).

## 5. Execution Plan (Todo List)

1.  **Dependencies:** Add `flutter_compass`.
2.  **Service:** Upgrade `NavigationGuidanceService` with bearing calculations.
3.  **Service:** Implement `ObstacleFusionService` (YOLO+Depth logic).
4.  **UI:** Create a `BlindNavigationScreen` that starts these services automatically without complex toggles.
5.  **LLM:** Hook up the "Describe Path" feature.
