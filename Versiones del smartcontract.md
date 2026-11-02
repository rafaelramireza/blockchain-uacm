# Evolución y Control de Versiones del Smart Contract (UACM-Blockchain)

Este documento registra el ciclo de vida y la evolución metodológica del contrato inteligente (`smartcontract.go`) desarrollado para la gestión inmutable de expedientes de egreso en la Universidad Autónoma de la Ciudad de México (UACM).

---

## Versión 1.0 — Prototipo Inicial (Concepto Single-Org)

* **Objetivo:** Validar la persistencia básica de datos en el Ledger distribuido de Hyperledger Fabric.
* **Características:**
  * Implementación de una estructura rudimentaria para almacenar datos de estudiantes directamente en el World State.
  * Funciones básicas de lectura y escritura (`PutState` y `GetState`) sin validación de estados ni control de acceso.
  * Almacenamiento directo de datos en texto plano (sin abstracción criptográfica de evidencias).
* **Limitaciones:** Carecía de lógica de negocio real. No reflejaba procesos de la UACM y cualquier identidad conectada a la red podía alterar los datos sin restricciones de gobernanza.


---

## Versión 2.0 — Introducción de la Máquina de Estados Finitos (FSM)

* **Objetivo:** Codificar el flujo administrativo de egreso y estructurar el expediente digital.
* **Características:**
  * **Estructura de Datos Tesis:** Se define formalmente el objeto `Expediente` con un `DocType`, `EstadoActual` y un mapa de `Evidencias` respaldado por la estructura `HashEvidencia` (Hash, Timestamp, Emisor).
  * **Validación de Transiciones:** Se programa una lógica secuencial estricta para impedir saltos en el ciclo de vida del estudiante.
  * **Nomenclatura Inicial:** Funciones nombradas con base en la acción técnica/operador (`RegistrarIngreso`, `ValidarDocumentacion`, `CertificarEstudio`, `TitularAlumno`).
* **Limitaciones:** El control de acceso por organización era estático e inverso al diseño definitivo de responsabilidades administrativas.

---

### Versión 3.0 — Gobierno de Consorcio y Auditoría Masiva
* **Objetivo:** Implementar la gobernanza multi-organización y dar soporte a pruebas de estrés (Ciper Benchmarks).
* **Características:**
  * **Control de Acceso basado en Atributos (ABAC):** Implementación del método interno `validarOrg(ctx, mspID)` utilizando la librería `pkg/cid` para restringir qué organización firma cada transacción.
  * **Lógica Especial para Benchmark:** Se inyectó un bypass condicional exclusivo para matrículas con prefijo `TEST-`. Esto permitió simular la creación masiva de expedientes con hitos falsificados (*hashes mock*) para evaluar el rendimiento de la red bajo entornos de alta concurrencia.
  * **Mecanismo de Interbloqueo:** Integración del método `verificarIntegridadHitosPrevios()`, el cual audita criptográficamente en el hito final que los 5 estados anteriores existan en el Ledger y no hayan sido alterados.

---

### Versión 3.1 & 3.2 — Reestructuración de Gobernanza Institucional

* **Objetivo:** Alinear el control de firmas del Chaincode con las competencias reales de las dependencias universitarias.
* **Cambio de Responsabilidades:**
  * Se transfirieron las funciones de **Servicio Social** a la gobernanza y firma exclusiva de **`Org1MSP`** (Registro Escolar + Servicio Social unificados en el mismo nodo/consorcio).
  * Se transfirió la función de **Certificación** a la firma de **`Org2MSP`** (Coordinación de Certificaciones y Titulación unificadas en el segundo nodo de red).
* **Resultado:** Validación exitosa mediante el benchmark masivo de Caliper (1,998 transacciones exitosas de punta a punta con un 99.8% de efectividad en entornos masivos de estrés).

---

### Versión 3.3 — Refactor de Alineación Metodológica (Versión Definitiva)
* **Objetivo:** Unificar la implementación técnica con la especificación de diseño de la **Épica 4** de la tesis para garantizar la trazabilidad de ingeniería de software.
* **Características:**
  * **Refactor Semántico Completo:** Se eliminó la nomenclatura basada en acciones físicas y se renombraron los identificadores de los métodos para reflejar fielmente los nombres formales de la **Máquina de Estados Finitos (FSM)** y los diagramas UML del documento de investigación:

    1. `RegistrarIngreso()` $\rightarrow$ **`RegistrarInscripcion()`** *(Alineado con el estado `INSCRITO`)*
    2. `ValidarDocumentacion()` $\rightarrow$ **`ValidarDocumentos()`** *(Alineado con el estado `DOC_VALIDADO`)*
    3. `CertificarEstudio()` $\rightarrow$ **`GenerarCertificado()`** *(Alineado con el estado `CERTIFICADO`)*
    4. `TitularAlumno()` $\rightarrow$ **`RegistrarTitulacion()`** *(Alineado con el estado `TITULADO` y con el rol del Ledger como repositorio de evidencias)*
  * **Trazabilidad Impecable:** Se garantizó que el diseño conceptual plasmado en los diagramas de secuencia, actividades y clases de la tesis coincida exactamente línea por línea con el punto de entrada expuesto por el API de contratos de Hyperledger Fabric en Go (`contractapi.Contract`).

---

### Versión 3.4 — Determinismo Criptográfico y Versión de Producción (Actual)

Objetivo: Solucionar fallas de consenso multi-nodo mediante marcas de tiempo nativas de canal y depurar la lógica del contrato de cara al despliegue definitivo.

Características:

Determinismo Temporal Absoluto: Se erradicó el uso de time.Now() en todas las funciones de escritura de la FSM. En su lugar, se implementó el método ctx.GetStub().GetTxTimestamp() acoplado al formato RFC3339 UTC, obligando a todos los Peers validadores a evaluar exactamente el mismo milisegundo firmado por la propuesta del cliente, soportando transiciones distribuidas a lo largo de 7 años.

Purgado de Código de Pruebas (Código Limpio): Se eliminó por completo el bloque condicional del prefijo TEST- y los estados ficticios (mocks) en RegistrarTitulacion. La función se simplificó a un flujo lineal y seguro que exige rigurosamente la existencia del expediente y la acreditación previa del estado CERTIFICADO.

Gobernanza de Estilo de Código: Formateo integral del archivo bajo el estándar oficial de Go (go fmt) y comentarios semánticos basados en Godoc, asegurando que el código sea auto-documentado y limpio para su inclusión en los anexos de investigación.

---

### Versión 3.5

El desarrollo evolutivo del componente on-chain culminó con la liberación de la versión 3.5 del contrato inteligente, la cual consolida las directrices de seguridad digital y robustez arquitectónica del sistema distribuido. Esta revisión no solo unifica la nomenclatura técnica bajo el identificador único de matrícula, sino que introduce mecanismos avanzados de mitigación de riesgos mediante constructores de consultas estructuradas en CouchDB, validaciones de integridad transversales en los hitos intermedios de certificación y titulación, y restricciones de auditoría basadas en la identidad criptográfica del llamador. Asimismo, la versión 3.5 añade resiliencia institucional al incorporar formalmente la capacidad de revocación de títulos, completando el ciclo de vida del expediente digital dentro de un entorno de red totalmente permisionado y auditable.

---

### Resumen de Trazabilidad de Métodos (Matriz Diseño ↔ Código)

| Proceso Metodológico (Diseño Tesis) | Función en Código (v3.4) | Estado Resultante en Ledger | Organización Emisora |
| --- | --- | --- | --- |
| Apertura de Expediente / Ingreso | RegistrarInscripcion | INSCRITO | Registro Escolar (Org1MSP) |
| Cotejo y Validación Física | ValidarDocumentos | DOC_VALIDADO | Registro Escolar (Org1MSP) |
| Apertura de Servicio Social | IniciarServicioSocial | SS_EN_CURSO | Servicio Social (Org1MSP) |
| Conclusión de Servicio Social | LiberarServicioSocial | SS_LIBERADO | Servicio Social (Org1MSP) |
| Auditoría de Créditos Egresado | GenerarCertificado | CERTIFICADO | Certificaciones (Org2MSP) |
| Registro de Acta de Examen | RegistrarTitulacion | TITULADO | Titulación (Org2MSP) |

MED-EC v5.0 — Contrato inteligente vigente

Descripción general

La versión 5.0 del contrato inteligente implementa el Modelo de Ejecución Determinista por Estados Convergentes (MED-EC) para la gestión de expedientes administrativos de titulación de la Universidad Autónoma de la Ciudad de México (UACM).

El contrato administra las transiciones del expediente mediante una máquina de estados finitos. Cada operación valida el estado actual y las condiciones de ejecución antes de registrar una nueva transición. De esta manera, el flujo administrativo se mantiene sujeto a reglas deterministas y verificables por las organizaciones participantes.

La implementación utiliza Hyperledger Fabric y distribuye la validación y el registro de las operaciones entre cuatro organizaciones: Registro Escolar, Servicio Social, Certificación y Titulación.

Modelo de estados

La versión 5.0 contempla los siguientes estados:

Estado

Descripción

INSCRITO

El expediente cuenta con el registro de inscripción.

DOC_VALIDADO

La documentación requerida fue validada.

ACTIVO

Se confirmó la condición de activo del estudiante.

SS_EN_CURSO

El trámite de servicio social se encuentra en curso.

SS_LIBERADO

El servicio social fue liberado.

CERTIFICADO

Se registró la emisión del certificado.

TITULADO

Se registró la emisión del título.

El flujo contempla dos rutas a partir del estado ACTIVO: la emisión del certificado o el inicio del servicio social. Para alcanzar el estado TITULADO, el expediente debe contar con el certificado y la liberación del servicio social.

Operaciones principales

Operación

Función

RegistrarInscripcion()

Registra la inscripción y establece el estado inicial INSCRITO.

ValidarDocumentos()

Valida la documentación y permite avanzar a DOC_VALIDADO.

ConfirmarActivo()

Confirma la condición de activo y establece el estado ACTIVO.

EmitirCertificado()

Registra la emisión del certificado.

IniciarServicioSocial()

Inicia el proceso de servicio social.

LiberarServicioSocial()

Registra la liberación del servicio social.

EmitirTitulo()

Registra la emisión del título cuando se cumplen las condiciones del flujo.

RectificarTransicion()

Permite rectificar una transición conforme a las reglas de autorización y trazabilidad del contrato.

ConsultarExpediente()

Consulta la información registrada para un expediente.

ConsultarExpedientesPorEstado()

Consulta expedientes de acuerdo con su estado.

Rectificación de transiciones

La versión 5.0 incorpora un mecanismo de rectificación que permite corregir una transición previamente registrada sin eliminar la evidencia original del libro mayor.

La operación RectificarTransicion() identifica la transición que se desea rectificar mediante su identificador de transacción. La solicitud está sujeta a las reglas de autorización del contrato: únicamente la organización que emitió la transición original puede solicitar su rectificación, y la operación debe cumplir las condiciones establecidas para evitar rectificaciones de transiciones que ya no sean la última transición efectiva o que hayan sido rectificadas previamente.

La rectificación se registra como una nueva evidencia vinculada con la transición de origen. El registro conserva la trazabilidad de la operación y permite identificar la transición rectificada, el estado anterior y el estado resultante.

Este mecanismo no elimina ni modifica retroactivamente la evidencia original. La corrección se representa mediante un nuevo registro en el historial del expediente.

Evidencia registrada

Las transiciones del expediente generan evidencia que permite identificar el cambio de estado y la operación que lo produjo. La estructura de evidencia contempla los siguientes elementos:

Campo

Descripción

EstadoAnterior

Estado del expediente antes de la operación.

EstadoNuevo

Estado resultante de la operación.

Evento

Operación que produjo la transición.

Timestamp

Marca temporal asociada con el registro.

Emisor

Identidad de la organización que emitió la operación.

TxID

Identificador de la transacción en Fabric.

La información registrada permite reconstruir la trayectoria de estados y verificar la correspondencia entre las operaciones administrativas y las evidencias almacenadas.

Organizaciones participantes

La red contempla cuatro organizaciones con responsabilidades diferenciadas:

Organización

Responsabilidad principal

RegistroEscolarMSP

Registro de inscripción, validación documental y confirmación de activo.

ServicioSocialMSP

Inicio y liberación del servicio social.

CertificacionMSP

Emisión del certificado.

TitulacionMSP

Emisión del título.

El control de acceso se realiza mediante la identidad del cliente y las reglas de autorización implementadas en el contrato inteligente.

Consideraciones de integridad y trazabilidad

La versión 5.0 mantiene el uso de evidencia criptográfica para respaldar las transiciones del expediente. La rectificación se registra como una operación adicional y conserva la referencia a la evidencia original, lo que permite mantener el historial de las modificaciones realizadas.

La implementación no debe interpretarse como un mecanismo que elimina errores administrativos de origen. Su propósito es establecer reglas de transición, autorización y registro que permitan detectar y rastrear las operaciones efectuadas sobre cada expediente.

Identificación de la versión

La versión funcional vigente del contrato inteligente se identifica como MED-EC v5.0.

La numeración funcional del contrato es independiente de los campos Version y Sequence de Hyperledger Fabric. Estos últimos corresponden a la definición del chaincode comprometida en el canal y deben consultarse mediante:

peer lifecycle chaincode querycommitted \
  -C uacmchannel \
  -n uacm

Las versiones anteriores se conservan en este documento como antecedentes de la evolución del contrato. La versión 5.0 representa la implementación vigente del MED-EC documentada en este apartado.


## Evidencia experimental asociada con MED-EC v5.0

La evaluación del prototipo se documenta por separado de la numeración funcional del contrato. Los archivos de respaldo de las pruebas se conservan en el directorio `resultados/` del repositorio, junto con los scripts que permiten reproducir las ejecuciones.

La evidencia disponible comprende las siguientes categorías:

| Categoría de prueba | Evidencia asociada |
| --- | --- |
| Latencia | Registros de ejecución y archivos CSV con mediciones temporales. |
| Rendimiento secuencial | Registros de transacciones procesadas y archivos de resultados de throughput. |
| Rendimiento concurrente | Resultados de la prueba de throughput concurrente y sus registros de ejecución. |
| Consistencia distribuida | Evidencias de consulta del estado entre los cuatro peers. |
| Integridad criptográfica | Registros de comprobación de hashes y evidencias asociadas. |
| Resiliencia | Resultados de la prueba de resiliencia bajo la política de endoso `MAJORITY`. |
| Pruebas funcionales | Resultados de escenarios positivos y negativos, incluidos los rechazos de operaciones no permitidas. |
| Carga controlada | Registros de las ejecuciones piloto y de la ejecución definitiva documentada. |

Los archivos originales son la fuente para consultar los valores medidos, identificadores de transacción, marcas de tiempo y resultados individuales. Este documento no sustituye esos respaldos ni incorpora cifras agregadas que deban calcularse a partir de ellos.

Al redactar los resultados de la tesis, deben distinguirse las ejecuciones piloto de las ejecuciones definitivas seleccionadas para el análisis. La inclusión de un archivo en el repositorio conserva la trazabilidad del trabajo, pero no implica por sí misma que sus datos se utilicen como resultados finales de la evaluación.

La evidencia experimental permite evaluar el comportamiento observado del prototipo bajo las condiciones de ejecución documentadas. No debe interpretarse como una garantía de rendimiento o disponibilidad en un despliegue institucional de producción.
