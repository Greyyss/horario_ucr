import base64
import hashlib
import io
import re
from pathlib import Path

from flask import Flask, jsonify, request

from pyhanko.keys import load_certs_from_pemder
from pyhanko.pdf_utils.reader import PdfFileReader

from pyhanko.sign.diff_analysis import (
    DEFAULT_DIFF_POLICY,
    ModificationLevel,
    SuspiciousModification,
)

from pyhanko.sign.validation import validate_pdf_signature
from pyhanko.sign.validation.settings import KeyUsageConstraints
from pyhanko.sign.validation.status import SignatureCoverageLevel

from pyhanko_certvalidator import ValidationContext

from render import render_declaration


app = Flask(__name__)

app.config["MAX_CONTENT_LENGTH"] = 15 * 1024 * 1024

TRUST_DIR = Path(__file__).parent / "trust"

LIMIT = 5 * 1024 * 1024


def reject(message):
    raise ValueError(message)


def pdf_bytes(value):
    if (
        not isinstance(value, str)
        or len(value) > 7 * 1024 * 1024
    ):
        reject("Archivo inválido o demasiado grande.")

    raw = base64.b64decode(value, validate=True)

    if (
        not raw.startswith(b"%PDF-")
        or len(raw) > LIMIT
    ):
        reject("Se requiere un PDF de hasta 5 MiB.")

    return raw


def certificate_identity(subject):
    serial = str(subject.get("serial_number", ""))

    match = re.fullmatch(
        r"CPF-(0[1-9])-(\d{4})-(\d{4})",
        serial,
    )

    if (
        not match
        or subject.get("country_name") != "CR"
    ):
        reject(
            "El certificado no contiene una "
            "cédula nacional compatible."
        )

    common_name = str(
        subject.get("common_name", "")
    ).upper()

    if not common_name.endswith("(FIRMA)"):
        reject(
            "Se requiere el certificado de firma, "
            "no el de autenticación."
        )

    return (
        str(int(match[1]))
        + match[2]
        + match[3]
    )


@app.get("/health")
def health():
    return jsonify(
        ok=True,
        trustConfigured=any(
            TRUST_DIR.glob("*.pem")
        ),
    )


@app.post("/render")
def render():
    data = request.get_json(silent=True) or {}

    declaration = data.get("declaration")
    identifier = data.get("declarationId")

    if (
        not isinstance(declaration, dict)
        or not isinstance(identifier, str)
    ):
        return jsonify(
            error="Declaración inválida."
        ), 400

    if not isinstance(
        declaration.get("version"),
        int,
    ):
        return jsonify(
            error="Versión inválida."
        ), 400

    raw = render_declaration(
        declaration,
        identifier,
    )

    return jsonify(
        pdfBase64=base64.b64encode(raw).decode(),
        sha256=hashlib.sha256(raw).hexdigest(),
    )


@app.post("/validate")
def validate():
    try:
        data = request.get_json(silent=True) or {}

        raw = pdf_bytes(
            data.get("pdfBase64")
        )

        base = pdf_bytes(
            data.get("basePdfBase64")
        )

        identities = data.get(
            "expectedIdentifications"
        )

        if (
            not isinstance(identities, list)
            or len(identities) not in (1, 2)
        ):
            reject("Etapa de firma inválida.")

        if any(
            not isinstance(identity, str)
            or not re.fullmatch(
                r"[1-9]\d{8}",
                identity,
            )
            for identity in identities
        ):
            reject(
                "Falta la cédula válida "
                "de un firmante."
            )

        if len(set(identities)) != len(identities):
            reject(
                "El declarante y el superior "
                "deben ser personas distintas."
            )

        if (
            len(raw) <= len(base)
            or not raw.startswith(base)
        ):
            reject(
                "El PDF debe conservar el archivo "
                "descargado mediante firma incremental."
            )

        original = PdfFileReader(
            io.BytesIO(base),
            strict=True,
        )

        reader = PdfFileReader(
            io.BytesIO(raw),
            strict=True,
        )

        if original.encrypted or reader.encrypted:
            reject(
                "No se admiten PDF cifrados."
            )

        signatures = (
            reader.embedded_regular_signatures
        )

        previous = (
            original.embedded_regular_signatures
        )

        if (
            len(signatures) != len(identities)
            or len(previous) != len(identities) - 1
        ):
            reject(
                "La cantidad de firmas no "
                "corresponde a esta etapa."
            )

        for old, new in zip(
            previous,
            signatures,
        ):
            old_contents = bytes(
                old.sig_object["/Contents"]
            )

            new_contents = bytes(
                new.sig_object["/Contents"]
            )

            if old_contents != new_contents:
                reject(
                    "La firma anterior fue reemplazada."
                )

        last = signatures[-1]

        diff = DEFAULT_DIFF_POLICY.review_file(
            reader,
            original.xrefs.total_revisions - 1,
        )

        if (
            isinstance(diff, SuspiciousModification)
            or diff.modification_level
            > ModificationLevel.FORM_FILLING
        ):
            reject(
                "Se detectaron cambios de "
                "contenido en el documento."
            )

        if (
            diff.changed_form_fields
            - {last.field_name}
        ):
            reject(
                "Se modificaron campos ajenos "
                "a la nueva firma."
            )

        if (
            last.signed_revision
            != reader.xrefs.total_revisions - 1
        ):
            reject(
                "Existen revisiones posteriores "
                "a la última firma."
            )

        roots = list(
            TRUST_DIR.glob("*.pem")
        )

        if not roots:
            return jsonify(
                valid=False,
                error=(
                    "Falta configurar "
                    "la raíz de confianza."
                ),
            ), 503

        context = ValidationContext(
            trust_roots=list(
                load_certs_from_pemder(
                    [str(path) for path in roots]
                )
            ),
            allow_fetching=True,
            revocation_mode="require",
        )

        results = []

        for index, signature in enumerate(
            signatures
        ):
            status = validate_pdf_signature(
                signature,
                signer_validation_context=context,
                key_usage_settings=KeyUsageConstraints(
                    key_usage={"non_repudiation"}
                ),
            )

            allowed_coverage = (
                SignatureCoverageLevel.ENTIRE_FILE,
                SignatureCoverageLevel.ENTIRE_REVISION,
            )

            if (
                not status.bottom_line
                or status.coverage
                not in allowed_coverage
            ):
                reject(
                    "No se pudo comprobar integridad, "
                    "confianza o revocación "
                    "de una firma."
                )

            identification = certificate_identity(
                status.signing_cert.subject.native
            )

            if identification != identities[index]:
                reject(
                    "La cédula del certificado "
                    "no corresponde al "
                    "firmante esperado."
                )

            fingerprint = hashlib.sha256(
                status.signing_cert.dump()
            ).hexdigest()

            results.append({
                "identification": identification,
                "certificateSha256": fingerprint,
                "fieldName": signature.field_name,
            })

        return jsonify(
            valid=True,
            sha256=hashlib.sha256(raw).hexdigest(),
            signers=results,
        )

    except ValueError as error:
        return jsonify(
            valid=False,
            error=str(error),
        ), 422

    except Exception:
        app.logger.warning(
            "PDF rechazado: análisis o "
            "validación no completados."
        )

        return jsonify(
            valid=False,
            error=(
                "No se pudo verificar "
                "el PDF firmado."
            ),
        ), 422