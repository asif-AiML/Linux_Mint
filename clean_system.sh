#!/bin/bash
echo "--- Starting Weekly Grooming ---"

echo "[1] Removing orphaned packages..."
sudo apt autoremove -y

echo "[2] Cleaning Apt cache..."
sudo apt clean

echo "[3] Vacuuming system logs..."
sudo journalctl --vacuum-time=2weeks

echo "[4] Clearing thumbnail cache..."
rm -rf ~/.cache/thumbnails/*

echo "[5] Cleaning unused Flatpaks..."
flatpak uninstall --unused -y

echo "--- System is Clean and Happy! ---"
