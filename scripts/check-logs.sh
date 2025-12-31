#!/bin/bash
# Quick script to check OVBuddy logs on the Pi

PI_HOST="${PI_HOST:-192.168.1.170}"
PI_USER="${PI_USER:-pi}"

echo "Checking OVBuddy service logs on ${PI_USER}@${PI_HOST}..."
echo "=========================================="
echo ""

ssh "${PI_USER}@${PI_HOST}" "sudo journalctl -u ovbuddy -n 50 --no-pager"

