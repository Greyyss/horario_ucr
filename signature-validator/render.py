import io
import json
import os
import subprocess

from pyhanko.pdf_utils.generic import DictionaryObject, NumberObject, pdf_string
from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
from pyhanko.sign.fields import SigFieldSpec, append_signature_field


def render_declaration(data, declaration_id):
    executable = os.environ.get("PDF_RENDERER_PATH", "/app/render-pdf")

    result = subprocess.run(
        [executable],
        input=json.dumps(
            {"declaration": data},
            ensure_ascii=False,
        ).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=60,
    )

    if not result.stdout.startswith(b"%PDF-"):
        raise ValueError("El generador no devolvió un PDF válido.")

    writer = IncrementalPdfFileWriter(
        io.BytesIO(result.stdout)
    )

    writer.set_info(DictionaryObject({
        "/Title": pdf_string(
            "Declaración jurada de horario y jornada de trabajo"
        ),
        "/DeclaraDeclarationId": pdf_string(
            str(declaration_id)
        ),
        "/DeclaraVersion": NumberObject(
            int(data["version"])
        ),
    }))

    append_signature_field(
        writer,
        SigFieldSpec("Declarante"),
    )

    append_signature_field(
        writer,
        SigFieldSpec("Superior"),
    )

    writer.root["/AcroForm"]["/SigFlags"] = NumberObject(3)
    writer.update_container(writer.root["/AcroForm"])

    output = io.BytesIO()
    writer.write(output)

    return output.getvalue()
