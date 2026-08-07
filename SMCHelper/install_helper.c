//
//  install_helper.c
//  SMCHelper
//
//  Root installer used by the application after authorization. Besides copying
//  the launchd helper it snapshots the validated app's designated requirement
//  into a root-owned, private configuration file for the XPC listener.
//

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#define HELPER_PATH "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
#define PLIST_PATH "/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"
#define HELPER_DIRECTORY "/Library/PrivilegedHelperTools"
#define CLIENT_CONFIG_PATH HELPER_DIRECTORY "/com.minepacu.SMCHelper.client-requirement.plist"
#define SOCKET_PATH "/tmp/com.minepacu.SMCHelper.socket"
#define SERVICE_LABEL "com.minepacu.SMCHelper"
#define CLIENT_IDENTIFIER "com.minepacu.SMCController"

static int run_command(const char *command, const char *failure_message, int ignore_missing) {
    int result = system(command);
    if (result == -1) {
        fprintf(stderr, "%s: %s\n", failure_message, strerror(errno));
        return -1;
    }
    if (!WIFEXITED(result)) {
        fprintf(stderr, "%s: command did not exit normally\n", failure_message);
        return -1;
    }
    int status = WEXITSTATUS(result);
    if (status != 0 && !ignore_missing) {
        fprintf(stderr, "%s with status %d\n", failure_message, status);
    }
    return status;
}

static int copy_file(const char *source, const char *destination) {
    FILE *input = fopen(source, "rb");
    if (input == NULL) {
        fprintf(stderr, "Cannot open source %s: %s\n", source, strerror(errno));
        return -1;
    }

    FILE *output = fopen(destination, "wb");
    if (output == NULL) {
        fprintf(stderr, "Cannot open destination %s: %s\n", destination, strerror(errno));
        fclose(input);
        return -1;
    }

    char buffer[4096];
    size_t count = 0;
    int status = 0;
    while ((count = fread(buffer, 1, sizeof(buffer), input)) > 0) {
        if (fwrite(buffer, 1, count, output) != count) {
            fprintf(stderr, "Unable to write %s\n", destination);
            status = -1;
            break;
        }
    }
    if (ferror(input)) {
        fprintf(stderr, "Unable to read %s\n", source);
        status = -1;
    }

    fclose(input);
    if (fclose(output) != 0) {
        status = -1;
    }
    return status;
}

static bool write_all(int fd, const UInt8 *bytes, CFIndex length) {
    while (length > 0) {
        ssize_t count = write(fd, bytes, (size_t)length);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        bytes += count;
        length -= count;
    }
    return true;
}

static bool ensure_privileged_helper_directory(void) {
    if (mkdir(HELPER_DIRECTORY, 0755) != 0 && errno != EEXIST) {
        return false;
    }

    struct stat status = {0};
    return lstat(HELPER_DIRECTORY, &status) == 0 && S_ISDIR(status.st_mode) &&
           status.st_uid == 0 && (status.st_mode & 0022) == 0;
}

static CFDataRef create_client_config_data(const char *app_bundle_path) {
    CFURLRef app_url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
                                                                 (const UInt8 *)app_bundle_path,
                                                                 (CFIndex)strlen(app_bundle_path),
                                                                 true);
    if (app_url == NULL) {
        return NULL;
    }

    SecStaticCodeRef code = NULL;
    OSStatus status = SecStaticCodeCreateWithPath(app_url, kSecCSDefaultFlags, &code);
    CFRelease(app_url);
    if (status != errSecSuccess) {
        return NULL;
    }

    status = SecStaticCodeCheckValidity(code, kSecCSCheckAllArchitectures, NULL);
    if (status != errSecSuccess) {
        CFRelease(code);
        return NULL;
    }

    CFDictionaryRef signing_info = NULL;
    status = SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &signing_info);
    CFTypeRef identifier = signing_info == NULL
                               ? NULL
                               : CFDictionaryGetValue(signing_info, kSecCodeInfoIdentifier);
    if (status != errSecSuccess || identifier == NULL ||
        CFGetTypeID(identifier) != CFStringGetTypeID() ||
        !CFEqual(identifier, CFSTR(CLIENT_IDENTIFIER))) {
        if (signing_info != NULL) {
            CFRelease(signing_info);
        }
        CFRelease(code);
        return NULL;
    }

    SecRequirementRef designated_requirement = NULL;
    CFStringRef requirement_string = NULL;
    status = SecCodeCopyDesignatedRequirement(code, kSecCSDefaultFlags, &designated_requirement);
    if (status == errSecSuccess) {
        status = SecRequirementCopyString(designated_requirement, kSecCSDefaultFlags, &requirement_string);
    }
    if (designated_requirement != NULL) {
        CFRelease(designated_requirement);
    }
    CFRelease(code);
    if (status != errSecSuccess || requirement_string == NULL || CFStringGetLength(requirement_string) == 0) {
        if (requirement_string != NULL) {
            CFRelease(requirement_string);
        }
        CFRelease(signing_info);
        return NULL;
    }

    int format_version = 2;
    CFNumberRef version = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &format_version);
    const void *keys[] = {CFSTR("FormatVersion"), CFSTR("Identifier"), CFSTR("Requirement")};
    const void *values[] = {version, identifier, requirement_string};
    CFDictionaryRef configuration = CFDictionaryCreate(kCFAllocatorDefault,
                                                        keys,
                                                        values,
                                                        3,
                                                        &kCFTypeDictionaryKeyCallBacks,
                                                        &kCFTypeDictionaryValueCallBacks);
    CFDataRef data = configuration == NULL
                         ? NULL
                         : CFPropertyListCreateData(kCFAllocatorDefault,
                                                    configuration,
                                                    kCFPropertyListBinaryFormat_v1_0,
                                                    0,
                                                    NULL);
    if (configuration != NULL) {
        CFRelease(configuration);
    }
    if (version != NULL) {
        CFRelease(version);
    }
    CFRelease(requirement_string);
    CFRelease(signing_info);
    return data;
}

static bool write_client_config_atomically(CFDataRef data) {
    if (data == NULL || !ensure_privileged_helper_directory()) {
        return false;
    }

    int directory_fd = open(HELPER_DIRECTORY, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (directory_fd < 0) {
        return false;
    }

    char temporary_path[PATH_MAX] = {0};
    int length = snprintf(temporary_path,
                          sizeof(temporary_path),
                          "%s/.com.minepacu.SMCHelper.client-requirement.XXXXXX",
                          HELPER_DIRECTORY);
    if (length < 0 || (size_t)length >= sizeof(temporary_path)) {
        close(directory_fd);
        return false;
    }

    int temporary_fd = mkstemp(temporary_path);
    bool succeeded = false;
    if (temporary_fd >= 0 && fchmod(temporary_fd, 0600) == 0 &&
        fchown(temporary_fd, 0, 0) == 0 &&
        write_all(temporary_fd, CFDataGetBytePtr(data), CFDataGetLength(data)) &&
        fsync(temporary_fd) == 0) {
        if (close(temporary_fd) == 0) {
            temporary_fd = -1;
            succeeded = rename(temporary_path, CLIENT_CONFIG_PATH) == 0 && fsync(directory_fd) == 0;
        } else {
            temporary_fd = -1;
        }
    }
    if (temporary_fd >= 0) {
        close(temporary_fd);
    }
    if (!succeeded) {
        unlink(temporary_path);
    }
    close(directory_fd);
    return succeeded;
}

int main(int argc, char *argv[]) {
    if (geteuid() != 0) {
        fprintf(stderr, "Must run as root\n");
        return 1;
    }
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <helper_binary> <plist_file> <app_bundle_path>\n", argv[0]);
        return 1;
    }

    const char *helper_source = argv[1];
    const char *plist_source = argv[2];
    const char *app_bundle_path = argv[3];
    CFDataRef config_data = create_client_config_data(app_bundle_path);
    if (config_data == NULL) {
        fprintf(stderr, "The app bundle is unsigned, invalid, or has an unexpected identifier\n");
        return 1;
    }

    if (!ensure_privileged_helper_directory()) {
        fprintf(stderr, "Unable to create privileged helper directory: %s\n", strerror(errno));
        CFRelease(config_data);
        return 1;
    }
    if (copy_file(helper_source, HELPER_PATH) != 0 || chmod(HELPER_PATH, 0755) != 0 ||
        chown(HELPER_PATH, 0, 0) != 0) {
        fprintf(stderr, "Unable to install helper binary: %s\n", strerror(errno));
        CFRelease(config_data);
        return 1;
    }
    if (copy_file(plist_source, PLIST_PATH) != 0 || chmod(PLIST_PATH, 0644) != 0 ||
        chown(PLIST_PATH, 0, 0) != 0) {
        fprintf(stderr, "Unable to install launchd plist: %s\n", strerror(errno));
        CFRelease(config_data);
        return 1;
    }
    if (!write_client_config_atomically(config_data)) {
        fprintf(stderr, "Unable to persist client signing requirement\n");
        CFRelease(config_data);
        return 1;
    }
    CFRelease(config_data);

    // Legacy socket cleanup only. The daemon itself exposes no filesystem socket.
    unlink(SOCKET_PATH);
    run_command("/bin/launchctl bootout system " PLIST_PATH " 2>/dev/null",
                "launchctl bootout system failed", 1);
    if (run_command("/bin/launchctl bootstrap system " PLIST_PATH,
                    "launchctl bootstrap system failed", 0) != 0 ||
        run_command("/bin/launchctl kickstart -k system/" SERVICE_LABEL,
                    "launchctl kickstart system service failed", 0) != 0) {
        return 1;
    }

    printf("SMCHelper installation complete\n");
    return 0;
}
