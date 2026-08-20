# UACM Blockchain – Red de 4 Organizaciones

Este directorio contiene la configuración de la red Hyperledger Fabric utilizada por el prototipo **UACM Blockchain**, desarrollado como parte de la investigación de licenciatura en Ingeniería de Software de la **Universidad Autónoma de la Ciudad de México (UACM)**.

La red implementa una arquitectura blockchain permisionada para soportar el modelo **MED-EC (Modelo de Ejecución Determinista por Estados Convergentes)** utilizado en la gestión de expedientes administrativos de egreso y titulación.

## Arquitectura de la red

La configuración actual utiliza:

| Componente | Configuración |
|---|---|
| Organizaciones | 4 |
| Peers | 4, uno por organización |
| Orderers | 3 |
| Consenso | Raft |
| World State | CouchDB |
| Canal | `uacmchannel` |
| Identidades | MSP |
| Generación criptográfica | cryptogen |
| Plataforma | Hyperledger Fabric |

Cada organización dispone de su propio MSP y de un peer participante en el canal.

La red utiliza tres nodos orderer para proporcionar el servicio de ordenamiento mediante el mecanismo de consenso Raft.

## Organizaciones

La red está estructurada mediante cuatro organizaciones institucionales:

```text
                    ┌─────────────────────┐
                    │    UACM Blockchain  │
                    │     uacmchannel     │
                    └──────────┬──────────┘
                               │
       ┌───────────────┬───────┼───────┬───────────────┐
       │               │       │       │
       ▼               ▼       ▼       ▼
    Org1            Org2     Org3    Org4
     Peer            Peer     Peer    Peer
       │               │       │       │
       └───────────────┴───────┴───────┘
                       │
                ┌──────┴──────┐
                │  Orderers   │
                │  3 nodos    │
                │    Raft     │
                └─────────────┘