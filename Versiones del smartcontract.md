# Evolución y Control de Versiones del Smart Contract (UACM-Blockchain)

Este documento resume la evolución del contrato inteligente desarrollado para el prototipo **UACM-Blockchain**. Su propósito es registrar los principales cambios funcionales y arquitectónicos incorporados durante el desarrollo del proyecto, desde el prototipo inicial hasta la versión final implementada para la investigación.

---

# Versión 1.0 — Prototipo inicial

**Objetivo**

Validar la escritura y consulta de información utilizando Hyperledger Fabric.

**Principales características**

* Primer contrato inteligente funcional.
* Uso básico de `PutState()` y `GetState()`.
* Persistencia directa de información en el World State.
* Sin reglas de negocio ni control de acceso.

**Resultado**

Se comprobó la viabilidad técnica de utilizar Hyperledger Fabric como plataforma para el desarrollo del prototipo.

---

# Versión 2.0 — Incorporación del modelo de estados

**Objetivo**

Modelar el proceso administrativo mediante una Máquina de Estados Finitos (FSM).

**Principales cambios**

* Definición de la estructura `Expediente`.
* Incorporación de estados administrativos.
* Validación de transiciones entre estados.
* Registro de evidencias criptográficas asociadas a cada operación.

**Resultado**

El contrato inteligente evolucionó de un simple almacenamiento de información a un modelo basado en reglas de negocio.

---

# Versión 3.0 — Gobernanza institucional

**Objetivo**

Distribuir las responsabilidades administrativas entre las organizaciones participantes de la red blockchain.

**Principales cambios**

* Implementación del control de acceso mediante Membership Service Providers (MSP).
* Separación de responsabilidades entre las organizaciones participantes.
* Refactorización de la estructura interna del contrato inteligente.
* Alineación de la nomenclatura utilizada en el código con la documentación de la tesis.

**Resultado**

Cada operación administrativa quedó restringida a la organización institucional responsable de su ejecución.

---

# Versión 4.0 — Consolidación del prototipo

**Objetivo**

Adecuar la implementación del contrato inteligente al modelo definitivo propuesto en la investigación.

**Principales cambios**

* Reestructuración de la Máquina de Estados Finitos.
* Incorporación del estado **EGRESADO** como punto de bifurcación del proceso administrativo.
* Separación de los procesos de Certificación y Servicio Social.
* Validaciones adicionales de parámetros, existencia del expediente, estado administrativo y organización autorizada.
* Refactorización del código en módulos especializados.
* Eliminación de componentes temporales utilizados durante las etapas iniciales de desarrollo.

**Resultado**

El contrato inteligente alcanzó una estructura modular, alineada con la arquitectura propuesta en la tesis.

---

# Versión 4.1 — Implementación definitiva del MED-EC

**Objetivo**

Implementar la versión definitiva del Modelo de Ejecución Determinista por Estados Convergentes (MED-EC).

**Principales cambios**

* Consolidación del flujo administrativo definitivo.
* Incorporación de trayectorias administrativas alternativas compatibles con las reglas del MED-EC.
* Verificación determinista de las transiciones de estado.
* Integración de mecanismos de rechazo para operaciones incompatibles con el modelo.
* Optimización del código y adopción del estándar oficial de formato de Go (`gofmt`).
* Integración de GitHub Actions para la compilación, verificación estática y ejecución automática de pruebas.

**Resultado**

La versión 4.1 constituye la implementación final utilizada para el desarrollo experimental y la evaluación presentada en la tesis.

---

# Resumen de funcionalidades implementadas

| Funcionalidad                  | Estado       |
| ------------------------------ | ------------ |
| Registro de inscripción        | Implementado |
| Validación documental          | Implementado |
| Confirmación del egreso        | Implementado |
| Emisión del certificado        | Implementado |
| Inicio del Servicio Social     | Implementado |
| Liberación del Servicio Social | Implementado |
| Registro de titulación         | Implementado |
| Consulta del expediente        | Implementado |

---

# Correspondencia entre procesos administrativos y funciones del contrato inteligente

| Proceso administrativo         | Función implementada      |
| ------------------------------ | ------------------------- |
| Registro de inscripción        | `RegistrarInscripcion()`  |
| Validación documental          | `ValidarDocumentos()`     |
| Confirmación del egreso        | `ConfirmarEgreso()`       |
| Emisión del certificado        | `EmitirCertificado()`     |
| Inicio del Servicio Social     | `IniciarServicioSocial()` |
| Liberación del Servicio Social | `LiberarServicioSocial()` |
| Registro de titulación         | `RegistrarTitulacion()`   |
| Consulta del expediente        | `ConsultarExpediente()`   |

---

# Estado actual del proyecto

Versión del contrato inteligente:

**MED-EC v4.1**

Estado del desarrollo:

* Contrato inteligente implementado.
* Máquina de estados completamente funcional.
* Control de acceso institucional mediante MSP.
* Registro de evidencias criptográficas.
* Casos de prueba positivos y negativos implementados.
* Integración continua mediante GitHub Actions.
* Validación experimental concluida.

Esta versión corresponde al código fuente utilizado como base para el desarrollo y evaluación del prototipo presentado en la investigación.