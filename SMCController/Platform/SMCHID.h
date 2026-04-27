//
//  SMCHID.h
//  SMCController
//
//  HID-based sensor reading for Apple Silicon Macs
//

#ifndef SMCHID_h
#define SMCHID_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HIDConnection {
    void* system;  // IOHIDEventSystemClientRef
} HIDConnection;

typedef enum {
    HIDSensorTypeTemperature = 0,
    HIDSensorTypeCurrent = 1,
    HIDSensorTypeVoltage = 2
} HIDSensorType;

typedef struct {
    char name[128];
    char location[64];
    int primaryUsagePage;
    int primaryUsage;
    double value;
} HIDSensorInfo;

// Open HID connection
HIDConnection* hid_open(void);

// Close HID connection
void hid_close(HIDConnection* conn);

// Read temperature (pass NULL for sensorName to get first sensor)
double hid_read_temperature(HIDConnection* conn, const char* sensorName);

// Get sensor count by type
int hid_get_sensor_count(HIDConnection* conn, HIDSensorType type);

// Enumerate all sensors of a type
int hid_enumerate_sensors(HIDConnection* conn, HIDSensorType type, HIDSensorInfo* outSensors, int maxCount);

#ifdef __cplusplus
}
#endif

#endif /* SMCHID_h */
