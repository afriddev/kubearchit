from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator
import logging
from pythonjsonlogger import jsonlogger
import socket

app = FastAPI()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logstash_handler = logging.StreamHandler(socket.socket(socket.AF_INET, socket.SOCK_STREAM))
logstash_handler.socket.connect(('logstash', 5044))
formatter = jsonlogger.JsonFormatter('%(asctime)s %(levelname)s %(message)s')
logstash_handler.setFormatter(formatter)
logger.addHandler(logstash_handler)
Instrumentator().instrument(app).expose(app)

@app.get("/")
async def root():
    logger.info("Received request at /")
    return {"message": "Hello from FastAPI"}
