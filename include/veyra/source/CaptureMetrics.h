#pragma once
#include <cstdint>
namespace veyra::source {
// Frame-arrival counters the engine reports for a live source (screen capture).
struct CaptureMetrics {
    uint64_t received=0, delivered=0, dropped=0;
    double callbackFps=0, readAgeMs=0, frameAgeMs=0;
    bool sampledBlack=false; // Sparse source pixels, not input signal detection.
};
}
