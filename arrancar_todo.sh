#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain: Script de Inicializacion y Benchmarking Automatizado
# Hostname: DESKTOP-9LHUF5R | Prototipo Funcional de Egreso (MED-EC v4.1)
# ================================================================================

# Salir inmediatamente si algun comando falla
set -e

echo "=== [1/5] Limpiando contenedores, volumenes y estados previos ==="
cd ~/hyperledger/fabric-samples/test-network
./network.sh down

echo "=== [2/5] Levantando topologia de consorcio con CouchDB y CAs ==="
./network.sh up createChannel -c canal-uacm -s couchdb -ca

echo "=== [3/5] Desplegando Smart Contract unificado (Go v4.1 - Secuencia 3) ==="
./network.sh deployCC -ccn uacm-contract -ccp /home/rafa/hyperledger/uacm-egreso -ccv 4.1 -ccs 1 -ccl go -c canal-uacm

echo "=== [4/5] Extrayendo llaves privadas dinamicas (_sk) de los Administradores ==="
KEY_ORG1=$(ls ~/hyperledger/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/)
KEY_ORG2=$(ls ~/hyperledger/fabric-samples/test-network/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/keystore/)

# Sincronizar llaves de forma segura borrando cualquier residuo previo en la configuracion de Caliper
echo "-> Sincronizando hashes en network-config.yaml para Caliper..."
sed -i "s|org1.example.com/users/Admin@org1.example.com/msp/keystore/[^']*_sk|org1.example.com/users/Admin@org1.example.com/msp/keystore/${KEY_ORG1}|g" ~/hyperledger/benchmarks/networks/network-config.yaml
sed -i "s|org2.example.com/users/Admin@org2.example.com/msp/keystore/[^']*_sk|org2.example.com/users/Admin@org2.example.com/msp/keystore/${KEY_ORG2}|g" ~/hyperledger/benchmarks/networks/network-config.yaml

echo "=== [5/5] Entorno listo y llaves criptograficas sincronizadas exitosamente ==="