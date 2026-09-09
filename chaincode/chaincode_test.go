package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"math/big"
	"testing"
	"time"

	"github.com/golang/protobuf/proto"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
	"github.com/hyperledger/fabric-protos-go/msp"
)

type testStub struct {
	shim.ChaincodeStubInterface

	state       map[string][]byte
	mspID       string
	txID        string
	txTimestamp *timestamp.Timestamp
}

func newTestStub(mspID string) *testStub {
	now := time.Now().UTC()

	return &testStub{
		state: make(map[string][]byte),
		mspID: mspID,
		txID:  "TEST-TX-ID",
		txTimestamp: &timestamp.Timestamp{
			Seconds: now.Unix(),
			Nanos:   int32(now.Nanosecond()),
		},
	}
}

func (s *testStub) CreateCompositeKey(
	objectType string,
	attributes []string,
) (string, error) {
	key := objectType

	for _, attribute := range attributes {
		key += "\x00" + attribute
	}

	return key, nil
}

func (s *testStub) GetState(key string) ([]byte, error) {
	value, ok := s.state[key]
	if !ok {
		return nil, nil
	}

	return value, nil
}

func (s *testStub) PutState(key string, value []byte) error {
	copied := append([]byte(nil), value...)
	s.state[key] = copied

	return nil
}

func (s *testStub) GetTxID() string {
	return s.txID
}

func (s *testStub) GetTxTimestamp() (*timestamp.Timestamp, error) {
	return s.txTimestamp, nil
}

func crearCertificadoPrueba() ([]byte, error) {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}

	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			CommonName: "test-user",
		},
		NotBefore: time.Now().Add(-time.Hour),
		NotAfter:  time.Now().Add(24 * time.Hour),
		KeyUsage:  x509.KeyUsageDigitalSignature,
	}

	certDER, err := x509.CreateCertificate(
		rand.Reader,
		template,
		template,
		&privKey.PublicKey,
		privKey,
	)
	if err != nil {
		return nil, err
	}

	return pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: certDER,
	}), nil
}

func (s *testStub) GetCreator() ([]byte, error) {
	certPEM, err := crearCertificadoPrueba()
	if err != nil {
		return nil, err
	}

	identity := &msp.SerializedIdentity{
		Mspid:   s.mspID,
		IdBytes: certPEM,
	}

	return proto.Marshal(identity)
}

func newTestContext(stub shim.ChaincodeStubInterface) *contractapi.TransactionContext {
	ctx := new(contractapi.TransactionContext)
	ctx.SetStub(stub)

	return ctx
}

func calcularHashEsperado(
	id string,
	estadoAnterior string,
	evento string,
	estadoNuevo string,
	emisor string,
	timestamp string,
) string {
	datos := id + "|" +
		estadoAnterior + "|" +
		evento + "|" +
		estadoNuevo + "|" +
		emisor + "|" +
		timestamp

	hash := sha256.Sum256([]byte(datos))

	return hex.EncodeToString(hash[:])
}

func crearExpedienteDePrueba(
	t *testing.T,
	contract *SmartContract,
	ctx contractapi.TransactionContextInterface,
) {
	t.Helper()

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}
}

func TestRutaCertificadoServicioSocialTitulacion(t *testing.T) {
	contract := new(SmartContract)

	stubRegistro := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stubRegistro)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stubCertificacion := stubRegistro
	stubCertificacion.mspID = OrgCertificacion

	ctxCertificacion := newTestContext(stubCertificacion)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stubServicio := stubRegistro
	stubServicio.mspID = OrgServicioSocial

	ctxServicio := newTestContext(stubServicio)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stubTitulacion := stubRegistro
	stubTitulacion.mspID = OrgTitulacion

	ctxTitulacion := newTestContext(stubTitulacion)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirTitulo() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctxTitulacion,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	if expediente.EstadoActual != EstadoTitulado {
		t.Fatalf(
			"estado final = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoTitulado,
		)
	}
}

func TestRutaServicioSocialCertificadoTitulacion(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirTitulo() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctxTitulacion,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	if expediente.EstadoActual != EstadoTitulado {
		t.Fatalf(
			"estado final = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoTitulado,
		)
	}
}

func TestEmitirTituloSinCertificado(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	)

	if err != ErrCertificadoPendiente {
		t.Fatalf(
			"error = %v, se esperaba ErrCertificadoPendiente",
			err,
		)
	}
}

func TestEmitirTituloSinServicioSocial(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	)

	if err != ErrServicioSocialPendiente {
		t.Fatalf(
			"error = %v, se esperaba ErrServicioSocialPendiente",
			err,
		)
	}
}

func TestOperacionConMSPNoAutorizado(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	err := contract.EmitirCertificado(
		ctxTitulacion,
		"EXP-001",
	)

	if err != ErrMSPNoAutorizado {
		t.Fatalf(
			"error = %v, se esperaba ErrMSPNoAutorizado",
			err,
		)
	}
}

func TestNoPermitirOperacionDesdeTITULADO(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirTitulo() error = %v", err)
	}

	stub.mspID = OrgCertificacion
	ctxCertificacion = newTestContext(stub)

	err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	)

	if err != ErrEstadoInvalido {
		t.Fatalf(
			"error = %v, se esperaba ErrEstadoInvalido",
			err,
		)
	}
}

func TestActivoPuedeEmitirCertificado(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctxCertificacion,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	if expediente.EstadoActual != EstadoCertificado {
		t.Fatalf(
			"estado = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoCertificado,
		)
	}
}

func TestActivoPuedeIniciarServicioSocial(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctxServicio,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	if expediente.EstadoActual != EstadoSSCurso {
		t.Fatalf(
			"estado = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoSSCurso,
		)
	}
}

func TestEmitirTituloNoPuedeEjecutarseDosVeces(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("primer EmitirTitulo() error = %v", err)
	}

	err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	)

	if err != ErrEstadoInvalido {
		t.Fatalf(
			"segundo EmitirTitulo() error = %v, se esperaba ErrEstadoInvalido",
			err,
		)
	}
}

func TestEmitirTituloRegistraEvidenciaCompleta(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctxRegistro := newTestContext(stub)

	crearExpedienteDePrueba(t, contract, ctxRegistro)

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
	); err != nil {
		t.Fatalf("EmitirTitulo() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctxTitulacion,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	var evidencia *HashEvidencia

	for _, e := range expediente.HistorialTransiciones {
		if e.Evento == EvTitulacionRegistrada {
			evidencia = e
			break
		}
	}

	if evidencia == nil {
		t.Fatal("no se encontró la evidencia de titulación")
	}

	hashEsperado := calcularHashEsperado("EXP-001", evidencia.EstadoAnterior, evidencia.Evento, evidencia.EstadoNuevo, evidencia.Emisor, evidencia.Timestamp)
	if evidencia.Hash != hashEsperado {
		t.Fatalf(
			"Hash = %s, se esperaba %s",
			evidencia.Hash,
			hashEsperado,
		)
	}

	if evidencia.TxID != "TEST-TX-ID" {
		t.Fatalf(
			"TxID = %s, se esperaba TEST-TX-ID",
			evidencia.TxID,
		)
	}

	if evidencia.Timestamp == "" {
		t.Fatal("Timestamp de la evidencia está vacío")
	}

	if evidencia.Emisor != OrgTitulacion {
		t.Fatalf(
			"Emisor = %s, se esperaba %s",
			evidencia.Emisor,
			OrgTitulacion,
		)
	}
}

func TestRegistrarInscripcionIniciaEnINSCRITO(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	if expediente.EstadoActual != EstadoInscrito {
		t.Fatalf(
			"estado inicial = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoInscrito,
		)
	}
}

func TestConfirmarActivoAntesDeValidarDocumentos(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	err := contract.ConfirmarActivo(
		ctx,
		"EXP-001",
	)

	if err != ErrEstadoInvalido {
		t.Fatalf(
			"error = %v, se esperaba ErrEstadoInvalido",
			err,
		)
	}
}

func TestTransicionRegistraUnaEvidencia(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	var evidencia *HashEvidencia

	for _, e := range expediente.HistorialTransiciones {
		if e.Evento == EvInscripcion {
			evidencia = e
			break
		}
	}

	if evidencia == nil {
		t.Fatal("no se encontró la evidencia de inscripción")
	}

	hashEsperado := calcularHashEsperado("EXP-001", evidencia.EstadoAnterior, evidencia.Evento, evidencia.EstadoNuevo, evidencia.Emisor, evidencia.Timestamp)
	if evidencia.Hash != hashEsperado {
		t.Fatalf(
			"Hash = %s, se esperaba %s",
			evidencia.Hash,
			hashEsperado,
		)
	}

	if evidencia.TxID != "TEST-TX-ID" {
		t.Fatalf(
			"TxID = %s, se esperaba TEST-TX-ID",
			evidencia.TxID,
		)
	}

	if evidencia.Timestamp == "" {
		t.Fatal("Timestamp de la evidencia está vacío")
	}

	if evidencia.Emisor != OrgRegistro {
		t.Fatalf(
			"Emisor = %s, se esperaba %s",
			evidencia.Emisor,
			OrgRegistro,
		)
	}

	if len(expediente.HistorialTransiciones) != 1 {
		t.Fatalf(
			"número de evidencias = %d, se esperaba 1",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestEvidenciaPersistidaEnWorldState(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	clave, err := contract.crearClaveExpediente(
		ctx,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("crearClaveExpediente() error = %v", err)
	}

	datos, err := stub.GetState(clave)
	if err != nil {
		t.Fatalf("GetState() error = %v", err)
	}

	if datos == nil {
		t.Fatal("el expediente no fue persistido en el World State")
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf("ConsultarExpediente() error = %v", err)
	}

	var evidencia *HashEvidencia

	for _, e := range expediente.HistorialTransiciones {
		if e.Evento == EvInscripcion {
			evidencia = e
			break
		}
	}

	if evidencia == nil {
		t.Fatal("la evidencia no fue persistida en el World State")
	}

	hashEsperado := calcularHashEsperado("EXP-001", evidencia.EstadoAnterior, evidencia.Evento, evidencia.EstadoNuevo, evidencia.Emisor, evidencia.Timestamp)
	if evidencia.Hash != hashEsperado {
		t.Fatalf(
			"Hash persistido = %s, se esperaba %s",
			evidencia.Hash,
			hashEsperado,
		)
	}
}

func TestRectificarTransicionBasica(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	// Registrar inscripción.
	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	// Validar documentos.
	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-001",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	// Rectificar la transición de validación.
	stub.txID = "TX-RECTIFICACION"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-001",
		"TX-VALIDACION",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-001",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	// El estado debe regresar al estado anterior.
	if expediente.EstadoActual != EstadoInscrito {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoInscrito,
		)
	}

	// Deben conservarse las dos transiciones originales
	// y registrarse la nueva rectificación.
	if len(expediente.HistorialTransiciones) != 3 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 3",
			len(expediente.HistorialTransiciones),
		)
	}

	// La transición original debe permanecer en el historial.
	var transicion *HashEvidencia

	for _, evidencia := range expediente.HistorialTransiciones {
		if evidencia.Tipo == "TRANSICION" &&
			evidencia.TxID == "TX-VALIDACION" {
			transicion = evidencia
			break
		}
	}

	if transicion == nil {
		t.Fatal(
			"no se encontró la transición original TX-VALIDACION",
		)
	}

	if transicion.EstadoAnterior != EstadoInscrito {
		t.Fatalf(
			"EstadoAnterior de transición = %s, se esperaba %s",
			transicion.EstadoAnterior,
			EstadoInscrito,
		)
	}

	if transicion.EstadoNuevo != EstadoDocValidado {
		t.Fatalf(
			"EstadoNuevo de transición = %s, se esperaba %s",
			transicion.EstadoNuevo,
			EstadoDocValidado,
		)
	}

	// Buscar la rectificación.
	var rectificacion *HashEvidencia

	for _, evidencia := range expediente.HistorialTransiciones {
		if evidencia.Tipo == "RECTIFICACION" {
			rectificacion = evidencia
			break
		}
	}

	if rectificacion == nil {
		t.Fatal(
			"no se encontró la rectificación",
		)
	}

	if rectificacion.TxID != "TX-RECTIFICACION" {
		t.Fatalf(
			"TxID de rectificación = %s, se esperaba TX-RECTIFICACION",
			rectificacion.TxID,
		)
	}

	if rectificacion.TxIDTransicionOrigen != "TX-VALIDACION" {
		t.Fatalf(
			"TxIDTransicionOrigen = %s, se esperaba TX-VALIDACION",
			rectificacion.TxIDTransicionOrigen,
		)
	}

	if rectificacion.EstadoAnterior != EstadoDocValidado {
		t.Fatalf(
			"EstadoAnterior de rectificación = %s, se esperaba %s",
			rectificacion.EstadoAnterior,
			EstadoDocValidado,
		)
	}

	if rectificacion.EstadoNuevo != EstadoInscrito {
		t.Fatalf(
			"EstadoNuevo de rectificación = %s, se esperaba %s",
			rectificacion.EstadoNuevo,
			EstadoInscrito,
		)
	}

	if rectificacion.Evento != "RECTIFICACION" {
		t.Fatalf(
			"Evento = %s, se esperaba RECTIFICACION",
			rectificacion.Evento,
		)
	}

	if rectificacion.Emisor != OrgRegistro {
		t.Fatalf(
			"Emisor = %s, se esperaba %s",
			rectificacion.Emisor,
			OrgRegistro,
		)
	}
}

func TestRectificarTransicionDosVeces(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-002",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-002",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	// Primera rectificación.
	stub.txID = "TX-RECTIFICACION-1"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-002",
		"TX-VALIDACION",
	); err != nil {
		t.Fatalf(
			"primera RectificarTransicion() error = %v",
			err,
		)
	}

	// Segunda rectificación de la misma transición.
	stub.txID = "TX-RECTIFICACION-2"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-002",
		"TX-VALIDACION",
	)

	if err != ErrTransicionYaRectificada {
		t.Fatalf(
			"error = %v, se esperaba ErrTransicionYaRectificada",
			err,
		)
	}
}

func TestRectificarTransicionMSPDiferente(t *testing.T) {
	contract := new(SmartContract)

	// RegistroEscolarMSP ejecuta la transición original.
	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-003",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-003",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	// Otro MSP intenta rectificar la transición.
	stub.mspID = OrgCertificacion
	stub.txID = "TX-RECTIFICACION-NO-AUTORIZADA"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-003",
		"TX-VALIDACION",
	)

	if err != ErrRectificacionNoAutorizada {
		t.Fatalf(
			"error = %v, se esperaba ErrRectificacionNoAutorizada",
			err,
		)
	}

	// El expediente no debe haber sido modificado.
	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-003",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoDocValidado {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoDocValidado,
		)
	}

	if len(expediente.HistorialTransiciones) != 2 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 2",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestRectificarTransicionConOperacionPosterior(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-004",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-004",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-004",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// Intentar rectificar una transición que ya tiene
	// una operación posterior.
	stub.txID = "TX-RECTIFICACION"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-004",
		"TX-VALIDACION",
	)

	if err != ErrTransicionNoRectificable {
		t.Fatalf(
			"error = %v, se esperaba ErrTransicionNoRectificable",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-004",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoActivo {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoActivo,
		)
	}

	if len(expediente.HistorialTransiciones) != 3 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 3",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestRectificarTransicionInexistente(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-005",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-RECTIFICACION"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-005",
		"TX-NO-EXISTE",
	)

	if err != ErrTransicionNoExiste {
		t.Fatalf(
			"error = %v, se esperaba ErrTransicionNoExiste",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-005",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoInscrito {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoInscrito,
		)
	}

	if len(expediente.HistorialTransiciones) != 1 {
		t.Fatalf(
			"número de entradas = %d, se esperaba 1",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestRectificarTransicionConRamaCompleta(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	// INSCRITO
	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-006",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	// INSCRITO → DOC_VALIDADO
	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-006",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	// DOC_VALIDADO → ACTIVO
	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-006",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// ACTIVO → CERTIFICADO
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-006",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	// CERTIFICADO → SS_EN_CURSO
	stub.mspID = OrgServicioSocial
	stub.txID = "TX-SS-INICIO"

	if err := contract.IniciarServicioSocial(
		ctx,
		"EXP-006",
	); err != nil {
		t.Fatalf(
			"IniciarServicioSocial() error = %v",
			err,
		)
	}

	// SS_EN_CURSO → SS_LIBERADO
	stub.txID = "TX-SS-LIBERADO"

	if err := contract.LiberarServicioSocial(
		ctx,
		"EXP-006",
	); err != nil {
		t.Fatalf(
			"LiberarServicioSocial() error = %v",
			err,
		)
	}

	// Intentar rectificar ACTIVO → CERTIFICADO.
	// La transición tiene operaciones posteriores, por lo que
	// debe ser rechazada.
	stub.mspID = OrgCertificacion
	stub.txID = "TX-RECTIFICACION"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-006",
		"TX-CERTIFICADO",
	)

	if err != ErrTransicionNoRectificable {
		t.Fatalf(
			"error = %v, se esperaba ErrTransicionNoRectificable",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-006",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	// El estado debe permanecer en SS_LIBERADO.
	if expediente.EstadoActual != EstadoSSLiberado {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoSSLiberado,
		)
	}

	// No debe haberse agregado una rectificación.
	if len(expediente.HistorialTransiciones) != 6 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 6",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestRectificarUltimaTransicionRama(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-007",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-007",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-007",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-007",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	stub.txID = "TX-SS-INICIO"

	if err := contract.IniciarServicioSocial(
		ctx,
		"EXP-007",
	); err != nil {
		t.Fatalf(
			"IniciarServicioSocial() error = %v",
			err,
		)
	}

	stub.txID = "TX-SS-LIBERADO"

	if err := contract.LiberarServicioSocial(
		ctx,
		"EXP-007",
	); err != nil {
		t.Fatalf(
			"LiberarServicioSocial() error = %v",
			err,
		)
	}

	// Rectificar la última transición efectiva.
	stub.txID = "TX-RECTIFICACION"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-007",
		"TX-SS-LIBERADO",
	)

	if err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-007",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoSSCurso {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoSSCurso,
		)
	}

	// Se esperan las seis transiciones originales más
	// la nueva rectificación.
	if len(expediente.HistorialTransiciones) != 7 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 7",
			len(expediente.HistorialTransiciones),
		)
	}

	var rectificacion *HashEvidencia

	for _, evidencia := range expediente.HistorialTransiciones {
		if evidencia.Tipo == "RECTIFICACION" &&
			evidencia.TxID == "TX-RECTIFICACION" {
			rectificacion = evidencia
			break
		}
	}

	if rectificacion == nil {
		t.Fatal(
			"no se encontró la rectificación",
		)
	}

	if rectificacion.TxIDTransicionOrigen != "TX-SS-LIBERADO" {
		t.Fatalf(
			"TxIDTransicionOrigen = %s, se esperaba TX-SS-LIBERADO",
			rectificacion.TxIDTransicionOrigen,
		)
	}

	if rectificacion.EstadoAnterior != EstadoSSLiberado {
		t.Fatalf(
			"EstadoAnterior = %s, se esperaba %s",
			rectificacion.EstadoAnterior,
			EstadoSSLiberado,
		)
	}

	if rectificacion.EstadoNuevo != EstadoSSCurso {
		t.Fatalf(
			"EstadoNuevo = %s, se esperaba %s",
			rectificacion.EstadoNuevo,
			EstadoSSCurso,
		)
	}
}

func TestContinuarFlujoDespuesDeRectificacion(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-008",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-008",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-008",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// ACTIVO → CERTIFICADO
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-008",
	); err != nil {
		t.Fatalf(
			"EmitirCertificado() error = %v",
			err,
		)
	}

	// CERTIFICADO → ACTIVO mediante rectificación.
	stub.txID = "TX-RECTIFICACION"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-008",
		"TX-CERTIFICADO",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	// Después de la rectificación, el expediente debe
	// encontrarse nuevamente en ACTIVO.
	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-008",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoActivo {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoActivo,
		)
	}

	// El flujo debe poder continuar por la otra rama.
	stub.mspID = OrgServicioSocial
	stub.txID = "TX-SS-INICIO"

	if err := contract.IniciarServicioSocial(
		ctx,
		"EXP-008",
	); err != nil {
		t.Fatalf(
			"IniciarServicioSocial() después de rectificación error = %v",
			err,
		)
	}

	expediente, err = contract.ConsultarExpediente(
		ctx,
		"EXP-008",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() después de continuar error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoSSCurso {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoSSCurso,
		)
	}
}

func TestReejecutarTransicionDespuesDeRectificacion(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-009",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-009",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-009",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// Primera ejecución: ACTIVO → CERTIFICADO.
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO-1"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-009",
	); err != nil {
		t.Fatalf(
			"primera EmitirCertificado() error = %v",
			err,
		)
	}

	// Rectificar la primera ejecución.
	stub.txID = "TX-RECTIFICACION"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-009",
		"TX-CERTIFICADO-1",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	// El expediente debe regresar a ACTIVO.
	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-009",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoActivo {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoActivo,
		)
	}

	// Segunda ejecución de la misma operación.
	// Debe ser permitida porque la primera transición
	// ya fue rectificada.
	stub.txID = "TX-CERTIFICADO-2"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-009",
	); err != nil {
		t.Fatalf(
			"segunda EmitirCertificado() después de rectificación error = %v",
			err,
		)
	}

	expediente, err = contract.ConsultarExpediente(
		ctx,
		"EXP-009",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() final error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoCertificado {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoCertificado,
		)
	}

	// Deben existir:
	// 3 transiciones iniciales
	// + certificado 1
	// + rectificación
	// + certificado 2
	if len(expediente.HistorialTransiciones) != 6 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 6",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestNoPuedeRectificarseUnaRectificacion(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-010",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-010",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	// Rectificar la transición de validación.
	stub.txID = "TX-RECTIFICACION"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-010",
		"TX-VALIDACION",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	// Intentar rectificar la propia rectificación.
	stub.txID = "TX-RECTIFICACION-2"

	err := contract.RectificarTransicion(
		ctx,
		"EXP-010",
		"TX-RECTIFICACION",
	)

	if err != ErrTransicionNoExiste {
		t.Fatalf(
			"error = %v, se esperaba ErrTransicionNoExiste",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-010",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoInscrito {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoInscrito,
		)
	}

	if len(expediente.HistorialTransiciones) != 3 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 3",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestRectificarTitulacionDesdeCertificado(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// ACTIVO → CERTIFICADO
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	// CERTIFICADO → SS_EN_CURSO
	stub.mspID = OrgServicioSocial
	stub.txID = "TX-SS-INICIO"

	if err := contract.IniciarServicioSocial(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf(
			"IniciarServicioSocial() error = %v",
			err,
		)
	}

	// SS_EN_CURSO → SS_LIBERADO
	stub.txID = "TX-SS-LIBERADO"

	if err := contract.LiberarServicioSocial(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf(
			"LiberarServicioSocial() error = %v",
			err,
		)
	}

	// SS_LIBERADO → TITULADO
	stub.mspID = OrgTitulacion
	stub.txID = "TX-TITULO"

	if err := contract.EmitirTitulo(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf(
			"EmitirTitulo() error = %v",
			err,
		)
	}

	// TITULADO → SS_LIBERADO mediante rectificación.
	stub.txID = "TX-RECTIFICACION-TITULO"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-011",
		"TX-TITULO",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-011",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoSSLiberado {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoSSLiberado,
		)
	}

	if len(expediente.HistorialTransiciones) != 8 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 8",
			len(expediente.HistorialTransiciones),
		)
	}

	var rectificacion *HashEvidencia

	for _, evidencia := range expediente.HistorialTransiciones {
		if evidencia.Tipo == "RECTIFICACION" &&
			evidencia.TxID == "TX-RECTIFICACION-TITULO" {
			rectificacion = evidencia
			break
		}
	}

	if rectificacion == nil {
		t.Fatal("no se encontró la rectificación de titulación")
	}

	if rectificacion.TxIDTransicionOrigen != "TX-TITULO" {
		t.Fatalf(
			"TxIDTransicionOrigen = %s, se esperaba TX-TITULO",
			rectificacion.TxIDTransicionOrigen,
		)
	}

	if rectificacion.EstadoAnterior != EstadoTitulado {
		t.Fatalf(
			"EstadoAnterior = %s, se esperaba %s",
			rectificacion.EstadoAnterior,
			EstadoTitulado,
		)
	}

	if rectificacion.EstadoNuevo != EstadoSSLiberado {
		t.Fatalf(
			"EstadoNuevo = %s, se esperaba %s",
			rectificacion.EstadoNuevo,
			EstadoSSLiberado,
		)
	}
}

func TestRectificarTitulacionDesdeServicioSocial(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// ACTIVO → SS_EN_CURSO
	stub.mspID = OrgServicioSocial
	stub.txID = "TX-SS-INICIO"

	if err := contract.IniciarServicioSocial(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf(
			"IniciarServicioSocial() error = %v",
			err,
		)
	}

	// SS_EN_CURSO → SS_LIBERADO
	stub.txID = "TX-SS-LIBERADO"

	if err := contract.LiberarServicioSocial(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf(
			"LiberarServicioSocial() error = %v",
			err,
		)
	}

	// SS_LIBERADO → CERTIFICADO
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf(
			"EmitirCertificado() error = %v",
			err,
		)
	}

	// CERTIFICADO → TITULADO
	stub.mspID = OrgTitulacion
	stub.txID = "TX-TITULO"

	if err := contract.EmitirTitulo(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf(
			"EmitirTitulo() error = %v",
			err,
		)
	}

	// TITULADO → CERTIFICADO mediante rectificación.
	stub.txID = "TX-RECTIFICACION-TITULO"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-012",
		"TX-TITULO",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() error = %v",
			err,
		)
	}

	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-012",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoCertificado {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoCertificado,
		)
	}

	// Cinco transiciones previas + titulación + rectificación.
	if len(expediente.HistorialTransiciones) != 8 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 8",
			len(expediente.HistorialTransiciones),
		)
	}

	var rectificacion *HashEvidencia

	for _, evidencia := range expediente.HistorialTransiciones {
		if evidencia.Tipo == "RECTIFICACION" &&
			evidencia.TxID == "TX-RECTIFICACION-TITULO" {
			rectificacion = evidencia
			break
		}
	}

	if rectificacion == nil {
		t.Fatal("no se encontró la rectificación de titulación")
	}

	if rectificacion.TxIDTransicionOrigen != "TX-TITULO" {
		t.Fatalf(
			"TxIDTransicionOrigen = %s, se esperaba TX-TITULO",
			rectificacion.TxIDTransicionOrigen,
		)
	}

	if rectificacion.EstadoAnterior != EstadoTitulado {
		t.Fatalf(
			"EstadoAnterior = %s, se esperaba %s",
			rectificacion.EstadoAnterior,
			EstadoTitulado,
		)
	}

	if rectificacion.EstadoNuevo != EstadoCertificado {
		t.Fatalf(
			"EstadoNuevo = %s, se esperaba %s",
			rectificacion.EstadoNuevo,
			EstadoCertificado,
		)
	}
}

func TestRectificarTransicionReejecutada(t *testing.T) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// Primera ejecución: ACTIVO → CERTIFICADO.
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO-1"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf("primera EmitirCertificado() error = %v", err)
	}

	// Rectificar la primera transición.
	stub.txID = "TX-RECTIFICACION-1"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-011",
		"TX-CERTIFICADO-1",
	); err != nil {
		t.Fatalf("primera RectificarTransicion() error = %v", err)
	}

	// Segunda ejecución: ACTIVO → CERTIFICADO.
	stub.txID = "TX-CERTIFICADO-2"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-011",
	); err != nil {
		t.Fatalf(
			"segunda EmitirCertificado() después de rectificación error = %v",
			err,
		)
	}

	// Rectificar la segunda transición.
	stub.txID = "TX-RECTIFICACION-2"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-011",
		"TX-CERTIFICADO-2",
	); err != nil {
		t.Fatalf(
			"segunda RectificarTransicion() error = %v",
			err,
		)
	}

	// El expediente debe regresar nuevamente a ACTIVO.
	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-011",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoActivo {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoActivo,
		)
	}

	// Deben existir:
	// 3 transiciones iniciales
	// + certificado 1
	// + rectificación 1
	// + certificado 2
	// + rectificación 2
	if len(expediente.HistorialTransiciones) != 7 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 7",
			len(expediente.HistorialTransiciones),
		)
	}
}

func TestNoPuedeRectificarTransicionAnterior(
	t *testing.T,
) {
	contract := new(SmartContract)

	stub := newTestStub(OrgRegistro)
	ctx := newTestContext(stub)

	stub.txID = "TX-INSCRIPCION"

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	stub.txID = "TX-VALIDACION"

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	stub.txID = "TX-ACTIVO"

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("ConfirmarActivo() error = %v", err)
	}

	// T1: ACTIVO → CERTIFICADO.
	stub.mspID = OrgCertificacion
	stub.txID = "TX-CERTIFICADO"

	if err := contract.EmitirCertificado(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	// T2: CERTIFICADO → SS_EN_CURSO.
	stub.mspID = OrgServicioSocial
	stub.txID = "TX-SS-INICIO"

	if err := contract.IniciarServicioSocial(
		ctx,
		"EXP-012",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	// Rectificar T2.
	stub.txID = "TX-RECTIFICACION-SS"

	if err := contract.RectificarTransicion(
		ctx,
		"EXP-012",
		"TX-SS-INICIO",
	); err != nil {
		t.Fatalf(
			"RectificarTransicion() de T2 error = %v",
			err,
		)
	}

	// El expediente debe regresar a CERTIFICADO.
	expediente, err := contract.ConsultarExpediente(
		ctx,
		"EXP-012",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoCertificado {
		t.Fatalf(
			"EstadoActual = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoCertificado,
		)
	}

	// Intentar rectificar T1, que ya no es la última
	// transición efectiva.
	stub.mspID = OrgCertificacion
	stub.txID = "TX-RECTIFICACION-CERTIFICADO"

	err = contract.RectificarTransicion(
		ctx,
		"EXP-012",
		"TX-CERTIFICADO",
	)

	if err != ErrTransicionNoRectificable {
		t.Fatalf(
			"RectificarTransicion() error = %v, se esperaba %v",
			err,
			ErrTransicionNoRectificable,
		)
	}

	// El estado no debe modificarse.
	expediente, err = contract.ConsultarExpediente(
		ctx,
		"EXP-012",
	)
	if err != nil {
		t.Fatalf(
			"ConsultarExpediente() final error = %v",
			err,
		)
	}

	if expediente.EstadoActual != EstadoCertificado {
		t.Fatalf(
			"EstadoActual final = %s, se esperaba %s",
			expediente.EstadoActual,
			EstadoCertificado,
		)
	}

	// Deben existir únicamente:
	// 3 transiciones iniciales
	// + certificado
	// + servicio social
	// + rectificación del servicio social
	if len(expediente.HistorialTransiciones) != 6 {
		t.Fatalf(
			"número de entradas = %d, se esperaban 6",
			len(expediente.HistorialTransiciones),
		)
	}
}
