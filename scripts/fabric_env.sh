#!/bin/bash

export FABRIC_CFG_PATH=$HOME/hyperledger/fabric-samples/config

cd ~/hyperledger/fabric-samples/test-network || exit 1

source scripts/envVar.sh

if [ "$1" == "1" ]; then
    setGlobals 1
elif [ "$1" == "2" ]; then
    setGlobals 2
else
    echo "Uso:"
    echo "./fabric_env.sh 1"
    echo "./fabric_env.sh 2"
fi