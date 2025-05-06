#!/bin/bash
# Script to activate venv and run the Python application

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change to the script's directory (project root)
cd "$SCRIPT_DIR"

# Activate the virtual environment
source .venv/bin/activate

# Run the Python script
python main.py --gui

# Deactivate the virtual environment (optional, as the script will exit)
# deactivate 