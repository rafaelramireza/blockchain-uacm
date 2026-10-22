# Evolución y control de versiones del smart contract (UACM-Blockchain)

Este documento resume la evolución del contrato inteligente del prototipo UACM-Blockchain y distingue las versiones conceptuales de los cambios de implementación usados en la evaluación experimental.

---

## Versión 1.0 — Prototipo inicial

**Objetivo:** validar escritura y consulta de información con Hyperledger Fabric.

**Cambios principales:**
- Primer contrato inteligente funcional.
- Uso básico de `PutState()` y `GetState()`.
- Persistencia directa en el World State.
- Sin reglas de negocio ni control de acceso.

**Resultado:** se comprobó la viabilidad técnica de usar Hyperledger Fabric para el prototipo.

---

## Versión 2.0 — Modelo de estados

**Objetivo:** representar el proceso administrativo mediante una máquina de estados finitos.

**Cambios principales:**
- Definición de la estructura `Expediente`.
- Incorporación de estados administrativos y validación de transiciones.
- Registro de evidencias criptográficas asociadas a operaciones.

**Resultado:** el contrato evolucionó de almacenamiento simple a un modelo de reglas de negocio.

---

## Versión 3.0 — Gobernanza institucional

**Objetivo:** distribuir responsabilidades administrativas entre las organizaciones de la red.

**Cambios principales:**
- Control de acceso mediante Membership Service Providers (MSP).
- Separación de responsabilidades por organización.
- Refactorización modular del contrato.

**Resultado:** las operaciones quedaron restringidas a las organizaciones autorizadas.

---

## Versión 4.0 — Consolidación del prototipo

**Objetivo:** alinear la implementación con el modelo MED-EC.

**Cambios principales:**
- Reestructuración de la máquina de estados.
- Separación de los procesos de Certificación y Servicio Social.
- Validaciones de parámetros, existencia del expediente, estado y organización autorizada.
- Eliminación de componentes temporales.

---

## Versión 4.1 — Convergencia de trayectorias

**Objetivo:** implementar las trayectorias alternativas del MED-EC.

**Cambios principales:**
- Incorporación de trayectorias administrativas alternativas.
- Verificación de transiciones de estado.
- Rechazo de operaciones incompatibles con el modelo.
- Formato de código Go mediante `gofmt` e integración continua.

---

## Versión 4.2 — MED-EC basado en ACTIVO y validación experimental

**Objetivo:** consolidar el flujo administrativo basado en el estado `ACTIVO` y preparar el prototipo para la evaluación experimental.

**Cambios principales documentados en la línea de desarrollo:**
- Uso de `ACTIVO` como punto desde el que pueden desarrollarse las ramas de Certificación y Servicio Social.
- Operaciones de contrato separadas en scripts secuenciales: inscripción, validación documental, confirmación de activo, certificado, servicio social y título.
- Pruebas funcionales mediante identidades institucionales, con verificaciones del estado resultante.
- Ajustes a la configuración y a los scripts de invocación de peers para evitar conflictos con los nombres TLS.
- Organización de artefactos temporales en `.gitignore`, conservando el código fuente y los resultados experimentales que deban documentarse.

**Nota de trazabilidad:** esta versión identifica la línea de desarrollo de la rama MED-EC basada en `ACTIVO`. Antes de etiquetar una versión de despliegue, debe verificarse la correspondencia entre el código local, los scripts de despliegue y los resultados de las pruebas.

---

## Resumen de funcionalidades

| Funcionalidad | Estado en la línea MED-EC |
| --- | --- |
| Registro de inscripción | Implementado |
| Validación documental | Implementado |
| Confirmación del estado ACTIVO | Implementado |
| Emisión del certificado | Implementado |
| Inicio del Servicio Social | Implementado |
| Liberación del Servicio Social | Implementado |
| Emisión del título | Implementado |
| Consulta del expediente | Implementado |
| Control de acceso mediante MSP | Implementado |
| Evidencias criptográficas | Implementado |
| Pruebas y scripts de validación | Incorporados en la rama de desarrollo |

## Correspondencia de operaciones

| Proceso | Función del contrato |
| --- | --- |
| Registro de inscripción | `RegistrarInscripcion()` |
| Validación documental | `ValidarDocumentos()` |
| Confirmación de activo | `ConfirmarActivo()` |
| Emisión del certificado | `EmitirCertificado()` |
| Inicio del Servicio Social | `IniciarServicioSocial()` |
| Liberación del Servicio Social | `LiberarServicioSocial()` |
| Emisión del título | `EmitirTitulo()` |

## Estado documentado

**Versión de la línea de desarrollo: MED-EC v4.2.**

El número de versión debe mantenerse sincronizado con el código, los scripts de despliegue, la documentación y los registros de pruebas. Esta bitácora no sustituye la validación del artefacto desplegado en la red.
