import argparse
import io
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko.sign import signers


ROOT = Path(__file__).resolve().parents[2]
PKI = ROOT / ".firma-test" / "pki"
TRUST = PKI / "trust"


def name(common_name, identification=None):
    attributes = [
        x509.NameAttribute(NameOID.COUNTRY_NAME, "CR"),
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
    ]

    if identification:
        attributes.append(
            x509.NameAttribute(
                NameOID.SERIAL_NUMBER,
                identification,
            )
        )

    return x509.Name(attributes)


def save_key(path, key):
    path.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )


def generate():
    if (TRUST / "raiz.pem").exists():
        print("Los certificados de prueba ya existen.")
        return

    TRUST.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)

    root_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )

    root_name = name(
        "CA DECLARAUCR SOLO PRUEBAS SIN VALIDEZ REAL"
    )

    root_cert = (
        x509.CertificateBuilder()
        .subject_name(root_name)
        .issuer_name(root_name)
        .public_key(root_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=365))
        .add_extension(
            x509.BasicConstraints(ca=True, path_length=0),
            critical=True,
        )
        .add_extension(
            x509.KeyUsage(
                digital_signature=False,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .sign(root_key, hashes.SHA256())
    )

    (TRUST / "raiz.pem").write_bytes(
        root_cert.public_bytes(serialization.Encoding.PEM)
    )

    save_key(PKI / "raiz-key.pem", root_key)

    people = [
        (
            "declarante",
            "DECLARANTE DE PRUEBAS (FIRMA)",
            "CPF-01-0000-0001",
        ),
        (
            "superior",
            "SUPERIOR DE PRUEBAS (FIRMA)",
            "CPF-02-0000-0002",
        ),
    ]

    for role, common_name, identification in people:
        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

        certificate = (
            x509.CertificateBuilder()
            .subject_name(name(common_name, identification))
            .issuer_name(root_name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1))
            .not_valid_after(now + timedelta(days=30))
            .add_extension(
                x509.BasicConstraints(ca=False, path_length=None),
                critical=True,
            )
            .add_extension(
                x509.KeyUsage(
                    digital_signature=True,
                    content_commitment=True,
                    key_encipherment=False,
                    data_encipherment=False,
                    key_agreement=False,
                    key_cert_sign=False,
                    crl_sign=False,
                    encipher_only=False,
                    decipher_only=False,
                ),
                critical=True,
            )
            .add_extension(
                x509.CRLDistributionPoints([
                    x509.DistributionPoint(
                        full_name=[
                            x509.UniformResourceIdentifier(
                                "http://127.0.0.1:8088/test.crl"
                            )
                        ],
                        relative_name=None,
                        reasons=None,
                        crl_issuer=None,
                    )
                ]),
                critical=False,
            )
            .sign(root_key, hashes.SHA256())
        )

        save_key(PKI / f"{role}-key.pem", key)

        (PKI / f"{role}-cert.pem").write_bytes(
            certificate.public_bytes(serialization.Encoding.PEM)
        )

    crl = (
        x509.CertificateRevocationListBuilder()
        .issuer_name(root_name)
        .last_update(now - timedelta(minutes=1))
        .next_update(now + timedelta(days=30))
        .sign(root_key, hashes.SHA256())
    )

    (PKI / "lista.crl").write_bytes(
        crl.public_bytes(serialization.Encoding.DER)
    )

    print("Certificados de prueba creados.")
    print("NO tienen validez oficial y NO deben copiarse a producción.")


def sign(role, source):
    source = Path(source).resolve()

    if not source.is_file():
        raise ValueError("No existe el PDF seleccionado.")

    signer = signers.SimpleSigner.load(
        key_file=str(PKI / f"{role}-key.pem"),
        cert_file=str(PKI / f"{role}-cert.pem"),
        ca_chain_files=[str(TRUST / "raiz.pem")],
    )

    if signer is None:
        raise ValueError("No se pudieron cargar los certificados de prueba.")

    field = "Declarante" if role == "declarante" else "Superior"

    output = io.BytesIO()

    with source.open("rb") as input_file:
        signers.sign_pdf(
            IncrementalPdfFileWriter(input_file),
            signers.PdfSignatureMetadata(
                field_name=field,
                reason="PRUEBA LOCAL SIN VALIDEZ OFICIAL",
            ),
            signer=signer,
            output=output,
        )

    directory = ROOT / ".firma-test" / "firmados"
    directory.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")

    destination = directory / (
        f"{source.stem}-{role}-{stamp}.pdf"
    )

    destination.write_bytes(output.getvalue())

    print("PDF firmado para pruebas:")
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["crear", "firmar"])
    parser.add_argument("--rol", choices=["declarante", "superior"])
    parser.add_argument("--archivo")

    args = parser.parse_args()

    if args.action == "crear":
        generate()
    else:
        if not args.rol or not args.archivo:
            parser.error("Para firmar se requiere --rol y --archivo.")

        sign(args.rol, args.archivo)