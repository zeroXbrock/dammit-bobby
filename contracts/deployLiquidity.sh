#!/bin/bash

contractAddr=$(cat ../deployment.json | jq -r .v2Factory)
echo "The factory is at $contractAddr"

