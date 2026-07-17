#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain: Simulador Concurrente - Camino C (Flujo Intercalado)
# Hostname: DESKTOP-9LHUF5R | MED-EC v4.1 | Cero Datos Personales (PII)
# ================================================================================
set -e

MATRICULA=${1:-"22-001-3333"}

echo "================================================================================"
echo "Iniciando CAMINO C (Flujo Intercalado Cruzado) para la matrícula: $MATRICULA"
echo "================================================================================"

# SIMULACIÓN OFF-CHAIN: Generación local de evidencias hash
HASH_INSCR=$(echo -n "${MATRICULA}_FOL-2026-INSCRIPCION" | sha256sum | awk '{print $1}')
HASH_DOCS=$(echo -n "${MATRICULA}_FOL-2026-DOCS-UACM" | sha256sum | awk '{print $1}')
HASH_CERT=$(echo -n "${MATRICULA}_FOL-2026-CERTIFICA" | sha256sum | awk '{print $1}')
HASH_SS_INI=$(echo -n "${MATRICULA}_FOL-2026-SS-INICIO" | sha256sum | awk '{print $1}')
HASH_SS_LIB=$(echo -n "${MATRICULA}_FOL-2026-SS-LIBERA" | sha256sum | awk '{print $1}')
HASH_ACTA=$(echo -n "${MATRICULA}_FOL-2026-ACTA-EXAMEN" | sha256sum | awk '{print $1}')

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
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/rock/fabric-samples/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    # Corrección dinámica para resolver la ruta absoluta local mapeada de Org2
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    export CORE_PEER_ADDRESS=localhost:9051
}

cd $NETWORK_DIR

echo "=== [Etapa 1] Fase Inicial en Org1MSP ==="
cargar_org1
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarInscripcion\",\"$MATRICULA\",\"$HASH_INSCR\"]}"
sleep 3
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"ValidarDocumentos\",\"$MATRICULA\",\"$HASH_DOCS\"]}"
sleep 3

echo "=== [Etapa 2] Intercalado: Inicio del Servicio Social (Org1MSP) ==="
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"IniciarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_INI\"]}"
sleep 3

echo "=== [Etapa 3] Intercalado: Certificación Académica Cruzada (Org2MSP) ==="
cargar_org2
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarCertificacion\",\"$MATRICULA\",\"$HASH_CERT\"]}"
sleep 3

echo "=== [Etapa 4] Intercalado: Cierre y Liberación de Servicio (Org1MSP) ==="
cargar_org1
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"LiberarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_LIB\"]}"
sleep 3

echo "=== [Etapa 5] Confluencia (Join) Terminal ==="
cargar_org2
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarTitulacion\",\"$MATRICULA\",\"$HASH_ACTA\"]}"
sleep 3

echo "=== [Etapa 6] Auditoría del Expediente Convergido ==="
peer chaincode query $CHANNEL_ARGS -c "{\"Args\":[\"ConsultarExpediente\",\"$MATRICULA\"]}" | jq '.'
chmod +x ~/hyperledger/uacm-egreso/simular_camino_C.sh