package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
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

func crearExpedienteDePrueba(
	t *testing.T,
	contract *SmartContract,
	ctx contractapi.TransactionContextInterface,
) {
	t.Helper()

	if err := contract.RegistrarInscripcion(
		ctx,
		"EXP-001",
		"hash-inscripcion",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	if err := contract.ValidarDocumentos(
		ctx,
		"EXP-001",
		"hash-validacion",
	); err != nil {
		t.Fatalf("ValidarDocumentos() error = %v", err)
	}

	if err := contract.ConfirmarActivo(
		ctx,
		"EXP-001",
		"hash-activo",
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
		"hash-certificado",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stubServicio := stubRegistro
	stubServicio.mspID = OrgServicioSocial

	ctxServicio := newTestContext(stubServicio)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-inicio",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-liberado",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stubTitulacion := stubRegistro
	stubTitulacion.mspID = OrgTitulacion

	ctxTitulacion := newTestContext(stubTitulacion)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
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
		"hash-ss-inicio",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-liberado",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgCertificacion
	ctxCertificacion := newTestContext(stub)

	if err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
		"hash-certificado",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
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
		"hash-ss-inicio",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-liberado",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
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
		"hash-certificado",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
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
		"hash-certificado",
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
		"hash-certificado",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-inicio",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-liberado",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
	); err != nil {
		t.Fatalf("EmitirTitulo() error = %v", err)
	}

	stub.mspID = OrgCertificacion
	ctxCertificacion = newTestContext(stub)

	err := contract.EmitirCertificado(
		ctxCertificacion,
		"EXP-001",
		"hash-certificado-2",
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
		"hash-certificado",
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
		"hash-ss-inicio",
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
		"hash-certificado",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-inicio",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-liberado",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
	); err != nil {
		t.Fatalf("primer EmitirTitulo() error = %v", err)
	}

	err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo-2",
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
		"hash-certificado",
	); err != nil {
		t.Fatalf("EmitirCertificado() error = %v", err)
	}

	stub.mspID = OrgServicioSocial
	ctxServicio := newTestContext(stub)

	if err := contract.IniciarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-inicio",
	); err != nil {
		t.Fatalf("IniciarServicioSocial() error = %v", err)
	}

	if err := contract.LiberarServicioSocial(
		ctxServicio,
		"EXP-001",
		"hash-ss-liberado",
	); err != nil {
		t.Fatalf("LiberarServicioSocial() error = %v", err)
	}

	stub.mspID = OrgTitulacion
	ctxTitulacion := newTestContext(stub)

	if err := contract.EmitirTitulo(
		ctxTitulacion,
		"EXP-001",
		"hash-titulo",
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

	evidencia, existe := expediente.Evidencias[EvTitulacionRegistrada]
	if !existe {
		t.Fatal("no se encontró la evidencia de titulación")
	}

	if evidencia.Hash != "hash-titulo" {
		t.Fatalf(
			"Hash = %s, se esperaba hash-titulo",
			evidencia.Hash,
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
		"hash-inscripcion",
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
		"hash-inscripcion",
	); err != nil {
		t.Fatalf("RegistrarInscripcion() error = %v", err)
	}

	err := contract.ConfirmarActivo(
		ctx,
		"EXP-001",
		"hash-activo",
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
		"hash-inscripcion",
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

	evidencia, existe := expediente.Evidencias[EvInscripcion]
	if !existe {
		t.Fatal("no se encontró la evidencia de inscripción")
	}

	if evidencia.Hash != "hash-inscripcion" {
		t.Fatalf(
			"Hash = %s, se esperaba hash-inscripcion",
			evidencia.Hash,
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

	if len(expediente.Evidencias) != 1 {
		t.Fatalf(
			"número de evidencias = %d, se esperaba 1",
			len(expediente.Evidencias),
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
		"hash-inscripcion",
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

	evidencia, existe := expediente.Evidencias[EvInscripcion]
	if !existe {
		t.Fatal("la evidencia no fue persistida en el World State")
	}

	if evidencia.Hash != "hash-inscripcion" {
		t.Fatalf(
			"Hash persistido = %s, se esperaba hash-inscripcion",
			evidencia.Hash,
		)
	}
}
