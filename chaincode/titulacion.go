package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// RegistrarTitulacion registra la titulación del expediente
// y cambia su estado a TITULADO.
func (s *SmartContract) RegistrarTitulacion(
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

	// Validar estado actual
	if expediente.EstadoActual != EstadoEgresado {
		return ErrEstadoInvalido
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgCertificacion {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Verificar que exista la evidencia del certificado.
	if _, ok := expediente.Evidencias[EvCertificadoEmitido]; !ok {
		return ErrCertificadoPendiente
	}

	if _, ok := expediente.Evidencias[EvServicioSocialLiberado]; !ok {
		return ErrServicioSocialPendiente
	}

	// Registrar evidencia
	agregarEvidencia(
		expediente,
		EvTitulacionRegistrada,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Cambiar estado
	cambiarEstado(
		expediente,
		EstadoTitulado,
	)

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
