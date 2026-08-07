# Hito v1.1 - Núcleo MED-ec funcional

Fecha: 31 de julio de 2026

## Funcionalidades implementadas

- Registro de inscripción
- Validación documental
- Confirmación de egreso
- Emisión de certificado
- Inicio de servicio social
- Liberación de servicio social
- Registro de titulación
- Consulta de expediente

## Control de acceso

Org1MSP
- RegistrarInscripcion
- ValidarDocumentos
- IniciarServicioSocial
- LiberarServicioSocial

Org2MSP
- ConfirmarEgreso
- EmitirCertificado
- RegistrarTitulacion

## Validaciones realizadas

Casos positivos:
- Flujo principal completo
- Camino A (Certificado → Servicio Social)
- Camino B (Servicio Social → Certificado)

Casos negativos:
- Estado inválido
- MSP incorrecto
- Expediente inexistente
- ID vacío
- Hash vacío

## Estado del proyecto

El núcleo del chaincode se considera funcional y validado.
Las siguientes etapas corresponden al desarrollo del backend, frontend y automatización de pruebas.