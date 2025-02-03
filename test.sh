#!/bin/bash

# Start backend server
python3 -m http.server 8888 &
BACKEND_PID=$!

# Start proxy
nasm -f elf64 -o main.out asm/main.asm && ld main.out -o main && ./main 8080 127.0.0.1 8888 &
PROXY_PID=$!

# Give time to start
sleep 2

# Test connectivity
curl http://localhost:8080

# Cleanup
kill $BACKEND_PID
kill $PROXY_PID