# Evolución y Control de Versiones del Smart Contract (UACM-Blockchain)

Este documento registra el ciclo de vida y la evolución metodológica del contrato inteligente (`smartcontract.go`) desarrollado para la gestión inmutable de expedientes de egreso en la Universidad Autónoma de la Ciudad de México (UACM).

---

## 📌 Versión 1.0 — Prototipo Inicial (Concepto Single-Org)
* **Objetivo:** Validar la persistencia básica de datos en el Ledger distribuido de Hyperledger Fabric.
* **Características:**
  * Implementación de una estructura rudimentaria para almacenar datos de estudiantes directamente en el World State.
  * Funciones básicas de lectura y escritura (`PutState` y `GetState`) sin validación de estados ni control de acceso.
  * Almacenamiento directo de datos en texto plano (sin abstracción criptográfica de evidencias).
* **Limitaciones:** Carecía de lógica de negocio real. No reflejaba procesos de la UACM y cualquier identidad conectada a la red podía alterar los datos sin restricciones de gobernanza.

---

## 📌 Versión 2.0 — Introducción de la Máquina de Estados Finitos (FSM)
* **Objetivo:** Codificar el flujo administrativo de egreso y estructurar el expediente digital.
* **Características:**
  * **Estructura de Datos Tesis:** Se define formalmente el objeto `Expediente` con un `DocType`, `EstadoActual` y un mapa de `Evidencias` respaldado por la estructura `HashEvidencia` (Hash, Timestamp, Emisor).
  * **Validación de Transiciones:** Se programa una lógica secuencial estricta para impedir saltos en el ciclo de vida del estudiante.
  * **Nomenclatura Inicial:** Funciones nombradas con base en la acción técnica/operador (`RegistrarIngreso`, `ValidarDocumentacion`, `CertificarEstudio`, `TitularAlumno`).
* **Limitaciones:** El control de acceso por organización era estático e inverso al diseño definitivo de responsabilidades administrativas.

---

## 📌 Versión 3.0 — Gobierno de Consorcio y Auditoría Masiva
* **Objetivo:** Implementar la gobernanza multi-organización y dar soporte a pruebas de estrés (Ciper Benchmarks).
* **Características:**
  * **Control de Acceso basado en Atributos (ABAC):** Implementación del método interno `validarOrg(ctx, mspID)` utilizando la librería `pkg/cid` para restringir qué organización firma cada transacción.
  * **Lógica Especial para Benchmark:** Se inyectó un bypass condicional exclusivo para matrículas con prefijo `TEST-`. Esto permitió simular la creación masiva de expedientes con hitos falsificados (*hashes mock*) para evaluar el rendimiento de la red bajo entornos de alta concurrencia.
  * **Mecanismo de Interbloqueo:** Integración del método `verificarIntegridadHitosPrevios()`, el cual audita criptográficamente en el hito final que los 5 estados anteriores existan en el Ledger y no hayan sido alterados.

---

## 📌 Versión 3.1 & 3.2 — Reestructuración de Gobernanza Institucional
* **Objetivo:** Alinear el control de firmas del Chaincode con las competencias reales de las dependencias universitarias.
* **Cambio de Responsabilidades:**
  * Se transfirieron las funciones de **Servicio Social** a la gobernanza y firma exclusiva de **`Org1MSP`** (Registro Escolar + Servicio Social unificados en el mismo nodo/consorcio).
  * Se transfirió la función de **Certificación** a la firma de **`Org2MSP`** (Coordinación de Certificaciones y Titulación unificadas en el segundo nodo de red).
* **Resultado:** Validación exitosa mediante el benchmark masivo de Caliper (1,998 transacciones exitosas de punta a punta con un 99.8% de efectividad en entornos masivos de estrés).

---

## 📌 Versión 3.3 — Refactor de Alineación Metodológica (Versión Definitiva)
* **Objetivo:** Unificar la implementación técnica con la especificación de diseño de la **Épica 4** de la tesis para garantizar la trazabilidad de ingeniería de software.
* **Características:**
  * **Refactor Semántico Completo:** Se eliminó la nomenclatura basada en acciones físicas y se renombraron los identificadores de los métodos para reflejar fielmente los nombres formales de la **Máquina de Estados Finitos (FSM)** y los diagramas UML del documento de investigación:
    1. `RegistrarIngreso()` $\rightarrow$ **`RegistrarInscripcion()`** *(Alineado con el estado `INSCRITO`)*
    2. `ValidarDocumentacion()` $\rightarrow$ **`ValidarDocumentos()`** *(Alineado con el estado `DOC_VALIDADO`)*
    3. `CertificarEstudio()` $\rightarrow$ **`GenerarCertificado()`** *(Alineado con el estado `CERTIFICADO`)*
    4. `TitularAlumno()` $\rightarrow$ **`RegistrarTitulacion()`** *(Alineado con el estado `TITULADO` y con el rol del Ledger como repositorio de evidencias)*
  * **Trazabilidad Impecable:** Se garantizó que el diseño conceptual plasmado en los diagramas de secuencia, actividades y clases de la tesis coincida exactamente línea por línea con el punto de entrada expuesto por el API de contratos de Hyperledger Fabric en Go (`contractapi.Contract`).

---

### Resumen de Trazabilidad de Métodos (Matriz Diseño ↔ Código)

| Proceso Metodológico (Diseño Tesis) | Función en Código (v3.3) | Estado Resultante en Ledger | Organización Emisora |
| :--- | :--- | :--- | :--- |
| Apertura de Expediente / Ingreso | `RegistrarInscripcion` | `INSCRITO` | Registro Escolar (`Org1MSP`) |
| Cotejo y Validación Física | `ValidarDocumentos` | `DOC_VALIDADO` | Registro Escolar (`Org1MSP`) |
| Apertura de Servicio Social | `IniciarServicioSocial` | `SS_EN_CURSO` | Servicio Social (`Org1MSP`) |
| Conclusión de Servicio Social | `LiberarServicioSocial` | `SS_LIBERADO` | Servicio Social (`Org1MSP`) |
| Auditoría de Créditos Egresado | `GenerarCertificado` | `CERTIFICADO` | Certificaciones (`Org2MSP`) |
| Registro de Acta de Examen | `RegistrarTitulacion` | `TITULADO` | Titulación (`Org2MSP`) |