#!/bin/bash

cd ~/hyperledger/fabric-samples/test-network || exit 1

echo "Apagando red..."

./network.sh down

echo "Eliminando volúmenes..."

docker volume prune -f

echo "Levantando red..."

./network.sh up createChannel -ca