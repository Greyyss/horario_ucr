FROM dart:stable AS pdf_builder

WORKDIR /renderer

COPY pdf-renderer/pubspec.yaml ./
RUN dart pub get

COPY pdf-renderer/lib/ lib/
COPY pdf-renderer/bin/ bin/

RUN mkdir -p /out && dart compile exe bin/render.dart -o /out/render-pdf

FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=pdf_builder /out/render-pdf /app/render-pdf

COPY main.py render.py ./
COPY trust/ trust/
COPY assets/ assets/

ENV PORT=8080

CMD ["sh", "-c", "exec gunicorn --bind :$PORT --timeout 110 --workers 1 --threads 1 main:app"]
