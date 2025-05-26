import asyncio
import logging
import sys
import nest_asyncio
import requests
from typing import Dict, Optional

API_KEY = "a86ff919-bdc4-4759-b05e-ffb7e2b0bc4e"
COURSE_ID = "012141520658891108829"

url = f"https://www.golfapi.io/api/v2.3/coordinates/{COURSE_ID}"

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

response = requests.get(url, headers=headers)

def get_green_coordinates(data, hole_number):
    # poi = 1 means green; location 1 = front, 2 = middle, 3 = back
    green_coords = {
        1: None,  # front
        2: None,  # middle
        3: None   # back
    }

    for coord in data["coordinates"]:
        if coord["hole"] == hole_number and coord["poi"] == 1:
            loc = coord["location"]
            if loc in green_coords:
                green_coords[loc] = {
                    "latitude": coord["latitude"],
                    "longitude": coord["longitude"]
                }

    return {
        "front": green_coords[1],
        "middle": green_coords[2],
        "back": green_coords[3]
    }

if response.status_code == 200:
    data = response.json()
    print(get_green_coordinates(data, 1))  # Replace this with your logic to extract green coordinates
else:
    print(f"Error: {response.status_code} - {response.text}")
