#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain: Simulador Automatizado Concurrente (MED-EC v4.1)
# Hostname: DESKTOP-9LHUF5R | Prototipo Funcional de Egreso (Fork-Join)
# ================================================================================
set -e

# 1. Control de Matrícula Dinámica y Nombre
MATRICULA=${1:-"22-001-7777"}
NOMBRE_ESTUDIANTE=${2:-"Estudiante Concurrente UACM"}

echo "================================================================================"
echo "Iniciando ciclo automatizado MED-EC v4.1 para: $NOMBRE_ESTUDIANTE ($MATRICULA)"
echo "================================================================================"

# 2. SIMULACIÓN OFF-CHAIN: Generación de evidencias SHA-256 reales para las compuertas
HASH_DOCS=$(echo -n "${MATRICULA}_FOL-2026-DOCS-UACM" | sha256sum | awk '{print $1}')
HASH_CERT=$(echo -n "${MATRICULA}_FOL-2026-CERTIFICA" | sha256sum | awk '{print $1}')
HASH_SS_INI=$(echo -n "${MATRICULA}_FOL-2026-SS-INICIO" | sha256sum | awk '{print $1}')
HASH_SS_LIB=$(echo -n "${MATRICULA}_FOL-2026-SS-LIBERA" | sha256sum | awk '{print $1}')
HASH_ACTA=$(echo -n "${MATRICULA}_FOL-2026-ACTA-EXAMEN" | sha256sum | awk '{print $1}')

# Configuración de variables base de la red
NETWORK_DIR="/home/rafa/hyperledger/fabric-samples/test-network"
export PATH="/home/rafa/hyperledger/fabric-samples/bin":$PATH
export FABRIC_CFG_PATH="/home/rafa/hyperledger/fabric-samples/config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_ARGS="-o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt"
CHANNEL_ARGS="-C canal-uacm -n uacm-contract"
PEERS_ARGS="--peerAddresses localhost:7051 --tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem --peerAddresses localhost:9051 --tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

function cargar_org1() {
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
    export CORE_PEER_ADDRESS=localhost:7051
}

function cargar_org2() {
    export CORE_PEER_LOCALMSPID="Org2MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    export CORE_PEER_ADDRESS=localhost:9051
}

# --- EJECUCIÓN DEL FLUJO CONCURRENTE (CAMINO B) ---
cd $NETWORK_DIR

echo "=== [Etapa 1] Fase Inicial en Org1MSP ==="
cargar_org1

echo "-> CU-01: Ejecutando inscripción inicial..."
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarInscripcion\",\"$MATRICULA\",\"$NOMBRE_ESTUDIANTE\"]}"
echo "Esperando confirmacion en el ledger..."
sleep 3

echo "-> CU-02: Validando documentación base (Apertura del Fork)..."
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"ValidarDocumentos\",\"$MATRICULA\",\"$HASH_DOCS\"]}"
echo "Esperando confirmacion en el ledger..."
sleep 3


echo "=== [Etapa 2] Bifurcación Asíncrona: Certificación Anticipada en Org2MSP ==="
cargar_org2

echo "-> CU-03: Registrando Certificación Académica (Sin requerir Servicio Social)..."
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarCertificacion\",\"$MATRICULA\",\"$HASH_CERT\"]}"
echo "Esperando confirmacion en el ledger..."
sleep 3


echo "=== [Etapa 3] Paralelismo: Procesando Servicio Social en Org1MSP ==="
cargar_org1

echo "-> CU-04: Iniciando Servicio Social del estudiante..."
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"IniciarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_INI\"]}"
echo "Esperando confirmacion en el ledger..."
sleep 3

echo "-> CU-05: Liberando Servicio Social del estudiante..."
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"LiberarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_LIB\"]}"
echo "Esperando confirmacion en el ledger..."
sleep 3


echo "=== [Etapa 4] Confluencia (Join) y Cierre Terminal en Org2MSP ==="
cargar_org2

echo "-> CU-06: Evaluando compuertas lógicas y registrando Titulación..."
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarTitulacion\",\"$MATRICULA\",\"$HASH_ACTA\"]}"
echo "Esperando asentamiento final..."
sleep 3


echo "=== [Etapa 5] Auditoría Completa del Expediente Generado ==="
peer chaincode query $CHANNEL_ARGS -c "{\"Args\":[\"ConsultarExpediente\",\"$MATRICULA\"]}" | jq '.'