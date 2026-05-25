FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY reasoner.py .

ENV PORT=8080
EXPOSE 8080

RUN addgroup --system app && adduser --system --ingroup app app
USER app

CMD ["python", "reasoner.py"]
