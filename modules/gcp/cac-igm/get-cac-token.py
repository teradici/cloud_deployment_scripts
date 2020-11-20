#!/usr/bin/env python3

# Copyright (c) 2020 Teradici Corporation
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import argparse
import datetime
import json
import requests


def create_connector_name():
    """A function to create a custom connector name
    
    Uses metadata server to access instance data, which is used to create the connector name.
    
    Returns:
        string: a string for the connector name
    """

    metadata_url = "http://metadata.google.internal/computeMetadata/v1/instance/"
    headers      = {"Metadata-Flavor": "Google"}
    iso_time     = datetime.datetime.utcnow().isoformat(timespec='seconds').replace(':','').replace('-','') + 'Z'

    response_zone = requests.get(metadata_url + "zone", headers = headers)
    response_name = requests.get(metadata_url + "name", headers = headers)

    zone = response_zone.text.rpartition('/')[2]
    name = response_name.text

    connector_name = f"{zone}-{name}-{iso_time}"

    return connector_name


def load_service_account_key(path):
    print(f"Loading CAM deployment service account key from {path}...")

    with open(path) as f:
        dsa_key = json.load(f)

    return dsa_key


def cam_login(key):
    print(f"Signing in to CAM with key {key['keyName']}...")

    payload = {
        'username': key['username'], 
        'password': key['apiKey'],
    }
    resp = session.post(
        f"{cam_api_url}/auth/signin",
        json=payload, 
    )
    resp.raise_for_status()

    token = resp.json()['data']['token']
    session.headers.update({"Authorization": token})


def get_cac_token(key, connector_name):
    print(f"Creating a CAC token in deployment {key['deploymentId']}...")

    payload = {
        'deploymentId': key['deploymentId'], 
        'connectorName': connector_name,
    }
    resp = session.post(
        f"{cam_api_url}/auth/tokens/connector",
        json=payload, 
    )
    resp.raise_for_status()

    return resp.json()['data']['token']


def token_write(token, path):
    print(f"Writing CAC token to {path}...")
    with open(path, 'w') as f:
        f.write(token)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="This script uses CAM Deployment Service Account JSON file to create a new CAC token.")

    parser.add_argument("cam", help="specify the path to CAM Deployment Service Account JSON file")
    parser.add_argument("--out", required=True, help="File to write the CAC token")
    parser.add_argument("--url", default="https://cam.teradici.com", help="specify the api url")
    parser.add_argument("--insecure", default=False, help="Allow unverified HTTPS connection to CAM")

    args = parser.parse_args()

    cam_api_url = f"{args.url}/api/v1"

    # Set up session to be used for all subsequent calls to CAM
    session = requests.Session()
    if args.insecure:
        session.verify = False

    dsa_key = load_service_account_key(args.cam)
    cam_login(dsa_key)
    connector_name = create_connector_name()
    cac_token = get_cac_token(dsa_key, connector_name)
    token_write(cac_token, args.out)