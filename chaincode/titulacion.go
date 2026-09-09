package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// EmitirTitulo registra la emisión del título y realiza la transición
// a TITULADO cuando existen las evidencias de certificado y servicio
// social liberado.
func (s *SmartContract) EmitirTitulo(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {

	// Validar parámetros
	if id == "" {
		return ErrIDVacio
	}

	// Obtener expediente
	expediente, err := s.obtenerExpediente(ctx, id)
	if err != nil {
		return err
	}

	// La titulación solo puede ejecutarse desde una de las
	// dos ramas finales del modelo: CERTIFICADO o SS_LIBERADO.
	if expediente.EstadoActual != EstadoCertificado &&
		expediente.EstadoActual != EstadoSSLiberado {
		return ErrEstadoInvalido
	}

	// La titulación solo puede estar vigente una vez.
	// Si una titulación anterior fue rectificada, puede volver a realizarse.
	if existeTransicionVigente(expediente, EvTitulacionRegistrada) {
		return ErrEstadoInvalido
	}

	// Requiere certificado emitido y vigente.
	if !existeTransicionVigente(expediente, EvCertificadoEmitido) {
		return ErrCertificadoPendiente
	}

	// Requiere servicio social liberado y vigente.
	if !existeTransicionVigente(expediente, EvServicioSocialLiberado) {
		return ErrServicioSocialPendiente
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgTitulacion {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Registrar evidencia de titulación.
	agregarEvidencia(
		expediente,
		expediente.EstadoActual,
		EvTitulacionRegistrada,
		EstadoTitulado,
		msp,
		timestamp,
		txID,
	)

	// Transición final:
	// CERTIFICADO / SS_LIBERADO → TITULADO.
	expediente.EstadoActual = EstadoTitulado

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
