# UACM Blockchain – Prototipo MED-EC

[![UACM Blockchain Smart Contract CI](https://github.com/rafaelramireza/blockchain-uacm/actions/workflows/ci-blockchain.yml/badge.svg)](https://github.com/rafaelramireza/blockchain-uacm/actions/workflows/ci-blockchain.yml)

## Descripción

Este repositorio contiene el código fuente del prototipo desarrollado como parte de la investigación de licenciatura en Ingeniería de Software de la **Universidad Autónoma de la Ciudad de México (UACM)**.

El prototipo implementa el **Modelo de Ejecución Determinista por Estados Convergentes (MED-EC)** sobre una red **Hyperledger Fabric**, con el propósito de gestionar la evolución de expedientes administrativos mediante reglas de negocio deterministas, control de acceso institucional y registro de evidencias criptográficas.

El proyecto demuestra la viabilidad de utilizar tecnología blockchain para fortalecer la consistencia, integridad y verificabilidad del proceso administrativo de egreso y titulación.

---

# Objetivos

El prototipo tiene como objetivos principales:

* Implementar el modelo MED-EC mediante un contrato inteligente.
* Garantizar que cada expediente evolucione únicamente mediante transiciones autorizadas.
* Impedir operaciones incompatibles con las reglas de negocio.
* Registrar evidencia criptográfica verificable para cada operación administrativa.
* Distribuir responsabilidades entre las distintas áreas institucionales.
* Preservar la privacidad evitando almacenar datos personales dentro de la blockchain.

---

# Tecnologías utilizadas

| Tecnología         | Uso                                     |
| ------------------ | --------------------------------------- |
| Hyperledger Fabric | Plataforma blockchain permissionada     |
| Go                 | Implementación del contrato inteligente |
| Docker             | Infraestructura de la red               |
| CouchDB            | World State                             |
| Raft               | Consenso                                |
| GitHub Actions     | Integración continua                    |

---

# Arquitectura del prototipo

El sistema implementa una arquitectura híbrida donde:

* Los documentos administrativos permanecen **Off-Chain**.
* La blockchain almacena únicamente:

  * identificador del expediente;
  * estado administrativo;
  * evidencias criptográficas (SHA-256);
  * metadatos de auditoría.

Este enfoque permite minimizar la información almacenada en la red sin perder capacidad de verificación.

---

# Modelo MED-EC

El expediente administrativo evoluciona mediante una Máquina de Estados Finitos (FSM).

```text
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

El contrato inteligente verifica que cada transición cumpla las reglas del modelo antes de modificar el expediente.

---

# Estructura del repositorio

```text
.
├── .github/
│   └── workflows/
│       └── ci-blockchain.yml
├── benchmarks/
├── chaincode/
├── config/
├── docs/
├── fabric-samples/
├── scripts/
├── simular_egreso.sh
├── simular_camino_B.sh
├── simular_camino_C.sh
├── simular_camino_D.sh
├── simular_camino_E.sh
├── simular_camino_F.sh
├── arrancar_todo.sh
└── README.md
```

---

# Casos de prueba implementados

## Casos positivos

**Camino A**

* Trayectoria administrativa principal del MED-EC.

**Camino B**

* Trayectoria alternativa permitida por el modelo, donde las actividades de Certificación y Servicio Social pueden desarrollarse de forma independiente antes de converger en la titulación.

## Casos negativos

El repositorio incorpora escenarios para verificar el rechazo de operaciones incompatibles con las reglas del modelo:

| Script              | Escenario evaluado                                                  |
| ------------------- | ------------------------------------------------------------------- |
| simular_camino_C.sh | Intento de registrar la titulación sin cumplir todos los requisitos |
| simular_camino_D.sh | Inicio del Servicio Social desde un estado no permitido             |
| simular_camino_E.sh | Emisión del certificado antes de confirmar el egreso                |
| simular_camino_F.sh | Operación ejecutada por una organización no autorizada              |

Estos casos permiten comprobar que el contrato inteligente preserva la consistencia del expediente rechazando operaciones inválidas.

---

# Ejecución

## Trayectoria principal

```bash
./simular_egreso.sh 11-011-0654
```

## Trayectoria alternativa

```bash
./simular_camino_B.sh 11-011-0654
```

## Casos negativos

```bash
./simular_camino_C.sh 11-011-0654
./simular_camino_D.sh 11-011-0654
./simular_camino_E.sh 11-011-0654
./simular_camino_F.sh 11-011-0654
```

---

# Integración continua

El repositorio utiliza **GitHub Actions** para validar automáticamente cada cambio enviado a la rama principal.

Las verificaciones incluyen:

* compilación del contrato inteligente;
* descarga de dependencias;
* verificación del formato oficial de Go (`gofmt`);
* ejecución de pruebas unitarias.

---

# Alcance del prototipo

Este trabajo constituye un prototipo funcional de investigación.

Su propósito es validar el modelo MED-EC y demostrar la viabilidad técnica del uso de blockchain en la gestión de expedientes administrativos. No pretende sustituir los sistemas institucionales actualmente utilizados por la UACM.

---

# Autor

**Rafael Ramírez Ángeles**

Licenciatura en Ingeniería de Software

Universidad Autónoma de la Ciudad de México

---

# Licencia

Este proyecto fue desarrollado exclusivamente con fines académicos y de investigación.
