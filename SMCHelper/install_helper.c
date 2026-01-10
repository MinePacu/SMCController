//
//  install_helper.c
//  Simple installer for SMCHelper daemon
//
//  Designed to be run with AuthorizationExecuteWithPrivileges
//  Takes precompiled SMCHelper binary and installs it

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

#define HELPER_PATH "/Library/PrivilegedHelperTools/com.minepacu.SMCHelper"
#define PLIST_PATH "/Library/LaunchDaemons/com.minepacu.SMCHelper.plist"

static int copy_file(const char* src, const char* dst) {
    FILE* in = fopen(src, "rb");
    if (!in) {
        fprintf(stderr, "❌ Cannot open source: %s\n", src);
        return -1;
    }
    
    FILE* out = fopen(dst, "wb");
    if (!out) {
        fprintf(stderr, "❌ Cannot open destination: %s\n", dst);
        fclose(in);
        return -1;
    }
    
    char buffer[4096];
    size_t n;
    while ((n = fread(buffer, 1, sizeof(buffer), in)) > 0) {
        if (fwrite(buffer, 1, n, out) != n) {
            fprintf(stderr, "❌ Write failed\n");
            fclose(in);
            fclose(out);
            return -1;
        }
    }
    
    fclose(in);
    fclose(out);
    return 0;
}

int main(int argc, char* argv[]) {
    printf("🔧 SMCHelper Installer\n");
    printf("Running as euid=%d\n", geteuid());
    
    if (geteuid() != 0) {
        fprintf(stderr, "❌ Must run as root\n");
        return 1;
    }
    
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <helper_binary> <plist_file>\n", argv[0]);
        return 1;
    }
    
    const char* helper_src = argv[1];
    const char* plist_src = argv[2];
    
    printf("�� Installing helper daemon...\n");
    printf("Source binary: %s\n", helper_src);
    printf("Source plist: %s\n", plist_src);
    
    // Create directory if needed
    mkdir("/Library/PrivilegedHelperTools", 0755);
    
    // Copy helper binary
    printf("Copying helper binary...\n");
    if (copy_file(helper_src, HELPER_PATH) != 0) {
        fprintf(stderr, "❌ Failed to copy helper binary\n");
        return 1;
    }
    
    // Set permissions
    printf("Setting permissions...\n");
    if (chmod(HELPER_PATH, 0755) != 0) {
        fprintf(stderr, "❌ Failed to chmod: %s\n", strerror(errno));
        return 1;
    }
    
    if (chown(HELPER_PATH, 0, 0) != 0) {
        fprintf(stderr, "❌ Failed to chown: %s\n", strerror(errno));
        return 1;
    }
    
    printf("✅ Helper binary installed\n");
    
    // Copy plist
    printf("📦 Installing LaunchDaemon plist...\n");
    if (copy_file(plist_src, PLIST_PATH) != 0) {
        fprintf(stderr, "❌ Failed to copy plist\n");
        return 1;
    }
    
    if (chmod(PLIST_PATH, 0644) != 0) {
        fprintf(stderr, "❌ Failed to chmod plist: %s\n", strerror(errno));
        return 1;
    }
    
    if (chown(PLIST_PATH, 0, 0) != 0) {
        fprintf(stderr, "❌ Failed to chown plist: %s\n", strerror(errno));
        return 1;
    }
    
    printf("✅ LaunchDaemon plist installed\n");
    
    // Start daemon using system()
    printf("🔄 Starting daemon...\n");
    system("launchctl unload " PLIST_PATH " 2>/dev/null");
    
    int ret = system("launchctl load " PLIST_PATH);
    if (ret != 0) {
        fprintf(stderr, "⚠️ launchctl load returned %d\n", ret);
    } else {
        printf("✅ Daemon loaded\n");
    }
    
    printf("✅ Installation complete!\n");
    return 0;
}
