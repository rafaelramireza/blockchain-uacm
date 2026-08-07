#!/bin/bash

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Uso:"
    echo "./deploy.sh 2.0"
    exit 1
fi

cd ~/hyperledger/fabric-samples/test-network || exit 1

export FABRIC_CFG_PATH=$HOME/hyperledger/fabric-samples/config

echo "Desplegando versión $VERSION..."

./network.sh deployCC \
    -ccn uacm-egreso \
    -ccp ../../uacm-egreso-v5/chaincode \
    -ccl go \
    -ccv $VERSION

echo
echo "Versión desplegada."

source scripts/envVar.sh
setGlobals 1

peer lifecycle chaincode querycommitted \
    --channelID mychannel \
    --name uacm-egreso