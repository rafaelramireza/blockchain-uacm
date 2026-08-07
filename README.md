# UACM Blockchain – Prototipo MED-EC

[![UACM Blockchain Smart Contract CI](https://github.com/rafaelramireza/blockchain-uacm/actions/workflows/ci-blockchain.yml/badge.svg)](https://github.com/rafaelramireza/blockchain-uacm/actions/workflows/ci-blockchain.yml)

## Descripción

Este repositorio contiene el prototipo funcional desarrollado como parte de la investigación:

**"Desarrollo de un prototipo funcional basado en una arquitectura híbrida de blockchain para la gestión modular de expedientes de titulación en la Universidad Autónoma de la Ciudad de México."**

El proyecto implementa el **Modelo de Ejecución Determinista por Estados Convergentes (MED-EC)** utilizando **Hyperledger Fabric**, con el propósito de garantizar que la evolución de los expedientes administrativos se realice únicamente mediante transiciones compatibles con las reglas de negocio establecidas.

---

## Objetivos

El prototipo busca:

- garantizar la consistencia de los expedientes administrativos;
- impedir transiciones de estado no autorizadas;
- registrar evidencia criptográfica verificable de cada operación;
- distribuir responsabilidades entre las áreas participantes mediante control de identidad institucional (MSP);
- preservar la privacidad evitando almacenar información personal en la blockchain.

---

## Arquitectura

Tecnologías utilizadas:

- Hyperledger Fabric
- Go
- Docker
- WSL2 (Ubuntu)
- CouchDB (World State)
- Raft Consensus

---

## Modelo MED-EC

El modelo implementa una Máquina de Estados Finitos (FSM) para controlar la evolución del expediente administrativo.

```
INSCRITO
    │
    ▼
DOCUMENTACIÓN VALIDADA
    │
    ▼
EGRESADO
   ├──────────────► CERTIFICADO
   │
   └──────────────► SERVICIO SOCIAL EN CURSO
                          │
                          ▼
                 SERVICIO SOCIAL LIBERADO
                          │
                          ▼
                      TITULADO
```

---

## Estructura del proyecto

```
.
├── chaincode/              # Smart Contract
├── benchmarks/             # Resultados experimentales
├── docs/                   # Documentación técnica
├── config/                 # Configuración
├── scripts/                # Scripts auxiliares
├── simular_egreso.sh
├── simular_camino_B.sh
├── simular_camino_C.sh
├── simular_camino_D.sh
├── simular_camino_E.sh
├── simular_camino_F.sh
└── .github/workflows/      # Integración continua
```

---

## Casos de prueba

### Caso A
Trayectoria principal del MED-EC.

```
INSCRITO
↓
DOCUMENTACIÓN VALIDADA
↓
EGRESADO
↓
SERVICIO SOCIAL
↓
LIBERACIÓN
↓
CERTIFICADO
↓
TITULADO
```

---

### Caso B

Trayectoria alternativa permitida por el modelo.

```
INSCRITO
↓
DOCUMENTACIÓN VALIDADA
↓
EGRESADO
├────────► CERTIFICADO
│
└────────► SERVICIO SOCIAL
                ↓
        SERVICIO SOCIAL LIBERADO
                ↓
            TITULADO
```

---

### Casos negativos

El repositorio incluye escenarios de validación que verifican el rechazo de operaciones incompatibles con el MED-EC:

- Camino C – Titulación sin cumplir requisitos.
- Camino D – Inicio de Servicio Social antes del egreso.
- Camino E – Certificación antes del egreso.
- Camino F – Operación ejecutada por una organización no autorizada.

---

## Ejecución

Registrar una trayectoria principal:

```bash
./simular_egreso.sh 11-011-0654
```

Trayectoria alternativa:

```bash
./simular_camino_B.sh 11-011-0654
```

Caso negativo:

```bash
./simular_camino_C.sh 11-011-0654
```

---

## Integración continua

El repositorio utiliza **GitHub Actions** para verificar automáticamente:

- compilación del contrato inteligente;
- formato oficial del código (`gofmt`);
- ejecución de pruebas unitarias.

Cada modificación enviada al repositorio es validada automáticamente antes de incorporarse a la rama principal.

---

## Privacidad

El prototipo implementa una política de minimización de datos.

La blockchain únicamente almacena:

- identificador del expediente;
- estado administrativo;
- evidencias criptográficas (SHA-256);
- metadatos de auditoría.

Los documentos administrativos permanecen fuera de la cadena (Off-Chain).

---

## Estado del proyecto

Versión actual del prototipo:

**MED-EC v4.1**

Estado:

✅ Prototipo funcional

---

## Licencia

Este proyecto fue desarrollado con fines académicos como parte de una investigación de licenciatura en Ingeniería de Software de la Universidad Autónoma de la Ciudad de México.