import os
import sys
from pathlib import Path

from asn1crypto import crl
from pyhanko_certvalidator import ValidationContext as RealValidationContext


ROOT = Path(__file__).resolve().parents[2]
PKI = ROOT / ".firma-test" / "pki"

executable = ROOT / ".firma-test" / "render-pdf.exe"

if not executable.is_file():
    raise RuntimeError("Falta compilar el generador local de PDF.")

if not (PKI / "trust" / "raiz.pem").is_file():
    raise RuntimeError("Primero generá los certificados de prueba.")

os.environ["PDF_RENDERER_PATH"] = str(executable)
os.environ["PDF_LOGO_PATH"] = str(
    ROOT / "assets" / "images" / "logo_ucr.png"
)

sys.path.insert(0, str(ROOT / "signature-validator"))

import main as validator


def local_context(**kwargs):
    kwargs["allow_fetching"] = False
    kwargs["crls"] = [
        crl.CertificateList.load(
            (PKI / "lista.crl").read_bytes()
        )
    ]

    return RealValidationContext(**kwargs)


validator.TRUST_DIR = PKI / "trust"
validator.ValidationContext = local_context


if __name__ == "__main__":
    print("VERIFICADOR LOCAL: CERTIFICADOS SIN VALIDEZ OFICIAL")

    validator.app.run(
        host="127.0.0.1",
        port=8088,
        debug=False,
        use_reloader=False,
    )