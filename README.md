# UACM Blockchain – Prototipo MED-EC

[![UACM Blockchain Smart Contract CI](https://github.com/rafaelramireza/blockchain-uacm/actions/workflows/ci-blockchain.yml/badge.svg)](https://github.com/rafaelramireza/blockchain-uacm/actions/workflows/ci-blockchain.yml)

## Descripción

Este repositorio contiene el código fuente del prototipo desarrollado como parte de la investigación de licenciatura en Ingeniería de Software de la **Universidad Autónoma de la Ciudad de México (UACM)**.

El prototipo implementa el **Modelo de Ejecución Determinista por Estados Convergentes (MED-EC)** sobre una red **Hyperledger Fabric**, con el propósito de gestionar la evolución de expedientes administrativos mediante reglas de negocio deterministas, control de acceso institucional y registro de evidencias criptográficas.

El proyecto demuestra la viabilidad de utilizar tecnología blockchain para fortalecer la consistencia, integridad y verificabilidad del proceso administrativo de egreso y titulación.

---

## Objetivos

El prototipo tiene como objetivos principales:

* Implementar el modelo MED-EC mediante un contrato inteligente.
* Garantizar que cada expediente evolucione únicamente mediante transiciones autorizadas.
* Impedir operaciones incompatibles con las reglas de negocio.
* Registrar evidencia criptográfica para cada operación administrativa.
* Distribuir responsabilidades entre las distintas áreas institucionales.
* Preservar la privacidad evitando almacenar datos personales dentro de la blockchain.

---

## Tecnologías utilizadas

| Tecnología         | Uso                                     |
| ------------------ | --------------------------------------- |
| Hyperledger Fabric | Plataforma blockchain permisionada      |
| Go                 | Implementación del contrato inteligente |
| Docker             | Infraestructura de la red               |
| CouchDB            | World State                             |
| Raft               | Consenso                                |
| GitHub Actions     | Integración continua                    |

---

## Arquitectura de la red

La red blockchain está conformada por cuatro organizaciones institucionales. Cada organización dispone de un peer y una identidad MSP propia.

| Componente               | Configuración           |
| ------------------------ | ----------------------- |
| Organizaciones           | 4                       |
| Peers                    | 4, uno por organización |
| Orderer                  | 1                       |
| Consenso                 | Raft                    |
| World State              | CouchDB                 |
| Canal                    | `uacmchannel`           |
| Chaincode                | `uacm`                  |
| Identidades              | MSP                     |
| Generación criptográfica | cryptogen               |
| Plataforma               | Hyperledger Fabric      |

### Organizaciones

| Organización     | MSP                  | Peer                                     |
| ---------------- | -------------------- | ---------------------------------------- |
| Registro Escolar | `RegistroEscolarMSP` | `peer0.registroescolar.uacm.edu.mx:7051` |
| Servicio Social  | `ServicioSocialMSP`  | `peer0.serviciosocial.uacm.edu.mx:8051`  |
| Certificación    | `CertificacionMSP`   | `peer0.certificacion.uacm.edu.mx:9051`   |
| Titulación       | `TitulacionMSP`      | `peer0.titulacion.uacm.edu.mx:10051`     |

### Orderer

El servicio de ordenamiento utiliza el nodo:

```text
orderer.example.com:7050
```

El ordenamiento de las transacciones se realiza mediante **Raft**.

---

## Arquitectura híbrida

El prototipo utiliza un esquema híbrido de almacenamiento.

Los documentos administrativos originales permanecen **Off-Chain**. La blockchain almacena la información necesaria para representar el estado del expediente y las evidencias criptográficas asociadas a las operaciones.

La información registrada en el World State comprende el identificador del expediente y su estado administrativo actual. Para cada evidencia asociada al expediente se registran su hash criptográfico, timestamp, organización emisora e identificador de la transacción.

Los documentos originales no se almacenan dentro de la blockchain.

---

## Modelo MED-EC

El expediente administrativo evoluciona mediante una **Máquina de Estados Finitos (FSM)**. Las transiciones son ejecutadas por el contrato inteligente de acuerdo con las reglas de negocio definidas por el modelo MED-EC.

```text
RegistrarInscripcion()
        ↓
     INSCRITO
        │
        │ ValidarDocumentos()
        ▼
   DOC_VALIDADO
        │
        │ ConfirmarActivo()
        ▼
      ACTIVO
        │
        ├──────────────────────────────┐
        │                              │
        │ EmitirCertificado()          │ IniciarServicioSocial()
        ▼                              ▼
   CERTIFICADO                    SS_EN_CURSO
        │                              │
        │ IniciarServicioSocial()     │ LiberarServicioSocial()
        ▼                              ▼
   SS_EN_CURSO                    SS_LIBERADO
        │                              │
        │ LiberarServicioSocial()     │ EmitirCertificado()
        ▼                              ▼
   SS_LIBERADO                    CERTIFICADO
        │                              │
        └──────────────┬───────────────┘
                       │
              CERTIFICADO + SS_LIBERADO
                       │
                  EmitirTitulo()
                       ↓
                    TITULADO
```

Después de alcanzar el estado `ACTIVO`, las operaciones de Certificación y Servicio Social pueden ejecutarse en distinto orden.

La titulación constituye el punto de convergencia de ambas ramas y requiere la existencia de las evidencias correspondientes al certificado emitido y al servicio social liberado.

Los estados utilizados por el contrato inteligente son:

```text
INSCRITO
DOC_VALIDADO
ACTIVO
CERTIFICADO
SS_EN_CURSO
SS_LIBERADO
TITULADO
```

---

## Operaciones por organización

Cada organización está autorizada para ejecutar determinadas operaciones del contrato inteligente.

| Operación               | Organización autorizada |
| ----------------------- | ----------------------- |
| `RegistrarInscripcion`  | Registro Escolar        |
| `ValidarDocumentos`     | Registro Escolar        |
| `ConfirmarActivo`       | Registro Escolar        |
| `IniciarServicioSocial` | Servicio Social         |
| `LiberarServicioSocial` | Servicio Social         |
| `EmitirCertificado`     | Certificación           |
| `EmitirTitulo`          | Titulación              |

El contrato inteligente verifica la identidad MSP de la organización solicitante antes de ejecutar las operaciones correspondientes.

---

## Contrato inteligente

El chaincode `uacm` implementa las reglas de negocio del modelo MED-EC.

Entre sus principales mecanismos se encuentran:

* validación del identificador del expediente;
* validación del hash de evidencia;
* validación del estado actual;
* autorización mediante MSP;
* prevención de operaciones duplicadas;
* registro de evidencias criptográficas;
* actualización controlada del estado del expediente;
* consulta individual de expedientes;
* consulta de expedientes por estado.

Las transiciones de estado se ejecutan dentro de las transacciones del contrato inteligente y son persistidas en el World State.

---

## Scripts de operación

El flujo operativo se encuentra dividido en scripts independientes:

```text
01_registrar_inscripcion.sh
02_validar_documentos.sh
03_confirmar_activo.sh
04_emitir_certificado.sh
05_iniciar_servicio_social.sh
06_liberar_servicio_social.sh
07_emitir_titulo.sh
```

Cada script ejecuta una operación específica del contrato inteligente.

También se incluyen scripts de consulta:

```text
consultar_expediente.sh
consultar_expedientes_estado.sh
```

El primero permite consultar un expediente mediante su identificador. El segundo permite consultar los expedientes que se encuentran en un estado determinado.

### Ejemplo de ejecución

Registro de una inscripción:

```bash
./01_registrar_inscripcion.sh 11-011-0658
```

Validación documental:

```bash
./02_validar_documentos.sh 11-011-0658
```

Confirmación del estado `ACTIVO`:

```bash
./03_confirmar_activo.sh 11-011-0658
```

Emisión del certificado:

```bash
./04_emitir_certificado.sh 11-011-0658
```

Inicio del Servicio Social:

```bash
./05_iniciar_servicio_social.sh 11-011-0658
```

Liberación del Servicio Social:

```bash
./06_liberar_servicio_social.sh 11-011-0658
```

Emisión del título:

```bash
./07_emitir_titulo.sh 11-011-0658
```

Consulta de un expediente:

```bash
./consultar_expediente.sh 11-011-0658
```

Consulta de expedientes por estado:

```bash
./consultar_expedientes_estado.sh TITULADO
```

---

## Pruebas

El repositorio incluye una suite de pruebas unitarias en:

```text
chaincode/chaincode_test.go
```

Las pruebas cubren diferentes condiciones del modelo MED-EC, incluyendo:

### Rutas válidas

* `TestRutaCertificadoServicioSocialTitulacion`
* `TestRutaServicioSocialCertificadoTitulacion`
* `TestActivoPuedeEmitirCertificado`
* `TestActivoPuedeIniciarServicioSocial`

Estas pruebas verifican que Certificación y Servicio Social puedan ejecutarse desde `ACTIVO` y que ambas rutas puedan converger posteriormente en `TITULADO`.

### Reglas de rechazo

* `TestEmitirTituloSinCertificado`
* `TestEmitirTituloSinServicioSocial`
* `TestOperacionConMSPNoAutorizado`
* `TestNoPermitirOperacionDesdeTITULADO`
* `TestConfirmarActivoAntesDeValidarDocumentos`

Estas pruebas verifican el rechazo de operaciones que incumplen las reglas de negocio o las restricciones de autorización.

### Integridad y persistencia

* `TestEmitirTituloNoPuedeEjecutarseDosVeces`
* `TestEmitirTituloRegistraEvidenciaCompleta`
* `TestRegistrarInscripcionIniciaEnINSCRITO`
* `TestTransicionRegistraUnaEvidencia`
* `TestEvidenciaPersistidaEnWorldState`

Estas pruebas verifican la persistencia de las evidencias, la actualización de estados y la prevención de operaciones duplicadas.

---

## Integración continua

El repositorio utiliza **GitHub Actions** para ejecutar verificaciones automáticas sobre el contrato inteligente.

El flujo de integración continua incluye:

* compilación;
* descarga de dependencias;
* verificación del formato del código Go mediante `gofmt`;
* ejecución de pruebas unitarias.

El workflow utilizado se encuentra en:

```text
.github/workflows/ci-blockchain.yml
```

---

## Alcance del prototipo

Este trabajo constituye un prototipo funcional desarrollado con fines académicos y de investigación.

Su propósito es implementar y evaluar el modelo MED-EC sobre una red Hyperledger Fabric, demostrando la ejecución determinista de las reglas de negocio, el control de acceso institucional y el registro de evidencias criptográficas.

El prototipo no pretende sustituir los sistemas institucionales actualmente utilizados por la UACM.

---

## Autor

**Rafael Ramírez Ángeles**

Licenciatura en Ingeniería de Software

Universidad Autónoma de la Ciudad de México

---

## Licencia

Este proyecto fue desarrollado exclusivamente con fines académicos y de investigación.
