//
//  main_daemon.c
//  SMCHelper
//
//  Privileged helper daemon for SMC operations
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <errno.h>
#include "../SMCController/SMCBridge.h"

#define SOCKET_PATH "/tmp/com.minepacu.SMCHelper.socket"

static SMCConnection* g_conn = NULL;

static void cleanup(void) {
    if (g_conn) {
        smc_close(g_conn);
        g_conn = NULL;
    }
    unlink(SOCKET_PATH);
}

static void handle_client(int client_fd) {
    char buffer[1024];
    ssize_t n = read(client_fd, buffer, sizeof(buffer) - 1);
    if (n <= 0) {
        close(client_fd);
        return;
    }
    buffer[n] = '\0';
    
    char response[1024] = "ERROR: Unknown command\n";
    
    // Parse command: "set-fan <index> <rpm>"
    char cmd[64], arg1[64], arg2[64];
    int argc = sscanf(buffer, "%63s %63s %63s", cmd, arg1, arg2);
    
    if (strcmp(cmd, "check") == 0) {
        snprintf(response, sizeof(response), "OK: Helper daemon running (euid=%d)\n", geteuid());
        
    } else if (strcmp(cmd, "set-fan") == 0 && argc >= 3) {
        int fan_index = atoi(arg1);
        int rpm = atoi(arg2);
        
        int ret = smc_write_fan_target_rpm(g_conn, fan_index, rpm);
        if (ret == 0) {
            snprintf(response, sizeof(response), "OK: Set fan %d to %d RPM\n", fan_index, rpm);
        } else {
            snprintf(response, sizeof(response), "ERROR: Failed to set fan speed (error=%d)\n", ret);
        }
        
    } else if (strcmp(cmd, "set-mode") == 0 && argc >= 2) {
        bool enabled = atoi(arg1) != 0;
        
        int ret = smc_set_fan_manual(g_conn, enabled);
        if (ret == 0) {
            snprintf(response, sizeof(response), "OK: Set manual mode to %s\n", enabled ? "ON" : "OFF");
        } else {
            snprintf(response, sizeof(response), "ERROR: Failed to set manual mode (error=%d)\n", ret);
        }
    }
    
    write(client_fd, response, strlen(response));
    close(client_fd);
}

static void run_daemon(void) {
    int server_fd;
    struct sockaddr_un addr;
    
    // Open SMC connection once
    g_conn = smc_open();
    if (!g_conn) {
        fprintf(stderr, "ERROR: Failed to open SMC connection\n");
        exit(2);
    }
    
    // Create socket
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        exit(3);
    }
    
    // Remove existing socket
    unlink(SOCKET_PATH);
    
    // Bind socket
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        exit(4);
    }
    
    // Make socket accessible to all users
    chmod(SOCKET_PATH, 0666);
    
    // Listen
    if (listen(server_fd, 5) < 0) {
        perror("listen");
        exit(5);
    }
    
    fprintf(stderr, "Daemon started, listening on %s\n", SOCKET_PATH);
    
    // Accept connections
    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            break;
        }
        
        handle_client(client_fd);
    }
    
    close(server_fd);
}

int main(int argc, char* argv[]) {
    // Helper must run as root
    if (geteuid() != 0) {
        fprintf(stderr, "ERROR: Helper must run as root\n");
        return 1;
    }
    
    atexit(cleanup);
    run_daemon();
    
    return 0;
}
