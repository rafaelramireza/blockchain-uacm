package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// IniciarServicioSocial registra el inicio del servicio social
// y realiza la transición de ACTIVO o CERTIFICADO a SS_EN_CURSO.
func (s *SmartContract) IniciarServicioSocial(
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

	// El servicio social puede iniciarse desde ACTIVO
	// o desde CERTIFICADO.
	if expediente.EstadoActual != EstadoActivo &&
		expediente.EstadoActual != EstadoCertificado {
		return ErrEstadoInvalido
	}

	// El inicio solo puede estar vigente una vez.
	// Si una operación anterior fue rectificada, puede volver a iniciarse.
	if existeTransicionVigente(expediente, EvServicioSocialIniciado) {
		return ErrEstadoInvalido
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgServicioSocial {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Registrar evidencia del inicio del servicio social.
	agregarEvidencia(
		expediente,
		expediente.EstadoActual,
		EvServicioSocialIniciado,
		EstadoSSCurso,
		msp,
		timestamp,
		txID,
	)

	// Transición ACTIVO/CERTIFICADO → SS_EN_CURSO.
	expediente.EstadoActual = EstadoSSCurso

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}

// LiberarServicioSocial registra la liberación del servicio social
// y realiza la transición de SS_EN_CURSO a SS_LIBERADO.
func (s *SmartContract) LiberarServicioSocial(
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

	// La liberación solo puede realizarse cuando
	// el expediente está en SS_EN_CURSO.
	if expediente.EstadoActual != EstadoSSCurso {
		return ErrEstadoInvalido
	}

	// La liberación requiere que exista una evidencia
	// vigente de inicio del servicio social.
	if !existeTransicionVigente(expediente, EvServicioSocialIniciado) {
		return ErrEstadoInvalido
	}

	// La liberación solo puede estar vigente una vez.
	// Si una liberación anterior fue rectificada, puede volver a realizarse.
	if existeTransicionVigente(expediente, EvServicioSocialLiberado) {
		return ErrEstadoInvalido
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgServicioSocial {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Registrar evidencia de liberación del servicio social.
	agregarEvidencia(
		expediente,
		EstadoSSCurso,
		EvServicioSocialLiberado,
		EstadoSSLiberado,
		msp,
		timestamp,
		txID,
	)

	// Transición SS_EN_CURSO → SS_LIBERADO.
	expediente.EstadoActual = EstadoSSLiberado

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
