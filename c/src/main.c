#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define BUFFER_SIZE 4096

int main(int argc, char *argv[]) {
  if (argc != 4) {
    fprintf(stderr, "Usage: %s <listen_port> <backend_host> <backend_port>\n",
            argv[0]);
    return 1;
  }

  int listen_port = atoi(argv[1]);
  char *backend_host = argv[2];
  int backend_port = atoi(argv[3]);

  // server
  int server_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd < 0) {
    perror("socket");
    return 1;
  }

  struct sockaddr_in server_addr = {
      .sin_family = AF_INET, .sin_addr.s_addr = INADDR_ANY,
      .sin_port = htons(listen_port)};

  if (bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) <
      0) {
    perror("bind");
    close(server_fd);
    return 1;
  }

  if (listen(server_fd, 10) < 0) {
    perror("listen");
    close(server_fd);
    return 1;
  }

  printf("reverse proxy listening on port %d...\n", listen_port);

  while (1) {
    struct sockaddr_in client_addr;
    socklen_t client_addr_len = sizeof(client_addr);
    int client_fd =
        accept(server_fd, (struct sockaddr *)&client_addr, &client_addr_len);
    if (client_fd < 0) {
      perror("accept");
      continue;
    }

    // reading the request
    char buffer[BUFFER_SIZE];
    ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer), 0);
    if (bytes_read <= 0) {
      close(client_fd);
      continue;
    }

    // connect to the backend
    struct hostent *he = gethostbyname(backend_host);
    if (!he) {
      close(client_fd);
      continue;
    }

    // connect to the backend
    struct sockaddr_in backend_addr = {
        .sin_family = AF_INET,
        .sin_port = htons(backend_port),
    };

    memcpy(&backend_addr.sin_addr, he->h_addr_list[0], he->h_length);

    int backend_fd = socket(AF_INET, SOCK_STREAM, 0);

    if (connect(backend_fd, (struct sockaddr *)&backend_addr,
                sizeof(backend_addr)) < 0) {
      close(backend_fd);
      close(client_fd);
      continue;
    }

    // forward request to backend
    send(backend_fd, buffer, bytes_read, 0);

    // relay backend response to client
    char backend_buffer[BUFFER_SIZE];
    ssize_t backend_bytes;
    while ((backend_bytes = recv(backend_fd, backend_buffer,
                                 sizeof(backend_buffer), 0)) > 0) {
      send(client_fd, backend_buffer, backend_bytes, 0);
    }

    close(backend_fd);
    close(client_fd);
  }
}