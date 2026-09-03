package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// EmitirTitulo registra la emisión del título y realiza la transición
// a TITULADO cuando existen las evidencias de certificado y servicio
// social liberado.
func (s *SmartContract) EmitirTitulo(
	ctx contractapi.TransactionContextInterface,
	id string,
	hash string,
) error {

	// Validar parámetros
	if id == "" {
		return ErrIDVacio
	}

	if hash == "" {
		return ErrHashVacio
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

	// La titulación solo puede registrarse una vez.
	if _, existe := expediente.Evidencias[EvTitulacionRegistrada]; existe {
		return ErrEstadoInvalido
	}

	// Requiere certificado emitido.
	if _, existe := expediente.Evidencias[EvCertificadoEmitido]; !existe {
		return ErrCertificadoPendiente
	}

	// Requiere servicio social liberado.
	if _, existe := expediente.Evidencias[EvServicioSocialLiberado]; !existe {
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
		EvTitulacionRegistrada,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Transición final:
	// CERTIFICADO / SS_LIBERADO → TITULADO.
	expediente.EstadoActual = EstadoTitulado

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
