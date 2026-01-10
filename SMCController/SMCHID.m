//
//  SMCHID.m
//  SMCController
//
//  HID-based sensor reading for Apple Silicon Macs
//

#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import "SMCHID.h"

typedef struct __IOHIDEvent         *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef double                      IOHIDFloat;

#define IOHIDEventFieldBase(type) (type << 16)
#define kIOHIDEventTypeTemperature  15
#define kIOHIDEventTypePower        25

// Private IOHIDEventSystemClient functions - declarations without 'extern'
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
#define kIOHIDEventTypePower        25

static NSDictionary* createMatching(int page, int usage) {
    return @{
        @"PrimaryUsagePage" : @(page),
        @"PrimaryUsage" : @(usage),
    };
}

HIDConnection* hid_open(void) {
    HIDConnection* conn = (HIDConnection*)calloc(1, sizeof(HIDConnection));
    if (!conn) return NULL;
    
    conn->system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!conn->system) {
        free(conn);
        return NULL;
    }
    
    return conn;
}

void hid_close(HIDConnection* conn) {
    if (!conn) return;
    if (conn->system) {
        CFRelease(conn->system);
    }
    free(conn);
}

double hid_read_temperature(HIDConnection* conn, const char* sensorName) {
    if (!conn || !conn->system) return NAN;
    
    // Thermal sensors: page 0xff00, usage 5
    NSDictionary* matching = createMatching(0xff00, 5);
    IOHIDEventSystemClientSetMatching(conn->system, (__bridge CFDictionaryRef)matching);
    
    NSArray* services = (__bridge_transfer NSArray*)IOHIDEventSystemClientCopyServices(conn->system);
    if (!services) return NAN;
    
    for (id serviceObj in services) {
        IOHIDServiceClientRef service = (__bridge IOHIDServiceClientRef)serviceObj;
        
        CFTypeRef propertyRef = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        NSString* productName = (__bridge_transfer NSString*)propertyRef;
        
        // If sensorName is NULL, return first available temperature
        if (!sensorName || (productName && [productName containsString:@(sensorName)])) {
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
            if (event) {
                double temp = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
                CFRelease(event);
                return temp;
            }
        }
    }
    
    return NAN;
}

int hid_get_sensor_count(HIDConnection* conn, HIDSensorType type) {
    if (!conn || !conn->system) return -1;
    
    NSDictionary* matching = nil;
    switch (type) {
        case HIDSensorTypeTemperature:
            matching = createMatching(0xff00, 5);
            break;
        case HIDSensorTypeCurrent:
            matching = createMatching(0xff08, 2);
            break;
        case HIDSensorTypeVoltage:
            matching = createMatching(0xff08, 3);
            break;
        default:
            return -1;
    }
    
    IOHIDEventSystemClientSetMatching(conn->system, (__bridge CFDictionaryRef)matching);
    NSArray* services = (__bridge_transfer NSArray*)IOHIDEventSystemClientCopyServices(conn->system);
    
    return services ? (int)[services count] : 0;
}

int hid_enumerate_sensors(HIDConnection* conn, HIDSensorType type, HIDSensorInfo* outSensors, int maxCount) {
    if (!conn || !conn->system || !outSensors) return -1;
    
    NSDictionary* matching = nil;
    int eventType = 0;
    
    switch (type) {
        case HIDSensorTypeTemperature:
            matching = createMatching(0xff00, 5);
            eventType = kIOHIDEventTypeTemperature;
            break;
        case HIDSensorTypeCurrent:
            matching = createMatching(0xff08, 2);
            eventType = kIOHIDEventTypePower;
            break;
        case HIDSensorTypeVoltage:
            matching = createMatching(0xff08, 3);
            eventType = kIOHIDEventTypePower;
            break;
        default:
            return -1;
    }
    
    IOHIDEventSystemClientSetMatching(conn->system, (__bridge CFDictionaryRef)matching);
    NSArray* services = (__bridge_transfer NSArray*)IOHIDEventSystemClientCopyServices(conn->system);
    
    if (!services) return 0;
    
    int count = 0;
    for (id serviceObj in services) {
        if (count >= maxCount) break;
        
        IOHIDServiceClientRef service = (__bridge IOHIDServiceClientRef)serviceObj;
        
        // Get Product name
        CFTypeRef propertyRef = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        NSString* productName = (__bridge_transfer NSString*)propertyRef;
        
        if (productName) {
            strncpy(outSensors[count].name, [productName UTF8String], sizeof(outSensors[count].name) - 1);
            outSensors[count].name[sizeof(outSensors[count].name) - 1] = '\0';
        } else {
            snprintf(outSensors[count].name, sizeof(outSensors[count].name), "Sensor %d", count);
        }
        
        // Get LocationID for additional identification
        CFTypeRef locationRef = IOHIDServiceClientCopyProperty(service, CFSTR("LocationID"));
        NSString* location = locationRef ? [NSString stringWithFormat:@"%@", (__bridge_transfer NSString*)locationRef] : @"";
        strncpy(outSensors[count].location, [location UTF8String], sizeof(outSensors[count].location) - 1);
        outSensors[count].location[sizeof(outSensors[count].location) - 1] = '\0';
        
        // Get PrimaryUsagePage and PrimaryUsage
        CFTypeRef usagePageRef = IOHIDServiceClientCopyProperty(service, CFSTR("PrimaryUsagePage"));
        CFTypeRef usageRef = IOHIDServiceClientCopyProperty(service, CFSTR("PrimaryUsage"));
        outSensors[count].primaryUsagePage = usagePageRef ? [(__bridge NSNumber*)usagePageRef intValue] : 0;
        outSensors[count].primaryUsage = usageRef ? [(__bridge NSNumber*)usageRef intValue] : 0;
        if (usagePageRef) CFRelease(usagePageRef);
        if (usageRef) CFRelease(usageRef);
        
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, eventType, 0, 0);
        if (event) {
            double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(eventType));
            if (type == HIDSensorTypeCurrent || type == HIDSensorTypeVoltage) {
                value /= 1000.0;  // Convert to A or V
            }
            outSensors[count].value = value;
            CFRelease(event);
        } else {
            outSensors[count].value = 0.0;
        }
        
        count++;
    }
    
    return count;
}
