"""
orders-api: a small service for the DevOps/SRE capstone.

The app is deliberately simple. The DevOps work around it is the point.

Endpoints
  GET  /health        liveness: process is up
  GET  /ready         readiness: database reachable (if configured)
  GET  /orders        list orders
  POST /orders        create an order  {"item": "book", "qty": 2}
  GET  /metrics       Prometheus metrics
  POST /chaos/leak    allocate ~50 MB and keep it (to trigger OOMKilled)

Config (environment variables)
  DATABASE_URL        postgresql://user:pass@host:5432/db  (if unset: in-memory store)
  FAIL_RATE           0.0-1.0  fraction of /orders requests that return 500   (chaos)
  EXTRA_LATENCY_MS    add this much delay to /orders                          (chaos)
  APP_VERSION         shown in /health, set it to the image tag in your pipeline
"""
import os
import random
import time

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel

DATABASE_URL = os.getenv("DATABASE_URL")
FAIL_RATE = float(os.getenv("FAIL_RATE", "0"))
EXTRA_LATENCY_MS = int(os.getenv("EXTRA_LATENCY_MS", "0"))
APP_VERSION = os.getenv("APP_VERSION", "dev")

app = FastAPI(title="orders-api")

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "path", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Request latency", ["method", "path"])

_memory_store: list[dict] = []
_leak: list[bytearray] = []


class OrderIn(BaseModel):
    item: str
    qty: int = 1


def db_conn():
    import psycopg  # imported lazily so the app runs without Postgres
    return psycopg.connect(DATABASE_URL, connect_timeout=3)


def init_db():
    if not DATABASE_URL:
        return
    with db_conn() as conn:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS orders (id SERIAL PRIMARY KEY, item TEXT NOT NULL, qty INT NOT NULL)"
        )


@app.on_event("startup")
def startup():
    try:
        init_db()
    except Exception as exc:  # keep running; /ready will report the problem
        print(f"WARN: database init failed: {exc}", flush=True)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    path = request.url.path
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        status = 500
        raise
    finally:
        if path != "/metrics":
            LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
            REQUESTS.labels(request.method, path, str(status)).inc()
    return response


def chaos():
    if EXTRA_LATENCY_MS:
        time.sleep(EXTRA_LATENCY_MS / 1000)
    if FAIL_RATE and random.random() < FAIL_RATE:
        raise HTTPException(status_code=500, detail="injected failure (FAIL_RATE)")


@app.get("/health")
def health():
    return {"status": "ok", "version": APP_VERSION}


@app.get("/ready")
def ready():
    if not DATABASE_URL:
        return {"status": "ready", "db": "in-memory"}
    try:
        with db_conn() as conn:
            conn.execute("SELECT 1")
        return {"status": "ready", "db": "ok"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"database unavailable: {exc}")


@app.get("/orders")
def list_orders():
    chaos()
    if not DATABASE_URL:
        return _memory_store
    with db_conn() as conn:
        rows = conn.execute("SELECT id, item, qty FROM orders ORDER BY id").fetchall()
    return [{"id": r[0], "item": r[1], "qty": r[2]} for r in rows]


@app.post("/orders", status_code=201)
def create_order(order: OrderIn):
    chaos()
    if not DATABASE_URL:
        rec = {"id": len(_memory_store) + 1, **order.model_dump()}
        _memory_store.append(rec)
        return rec
    with db_conn() as conn:
        new_id = conn.execute(
            "INSERT INTO orders (item, qty) VALUES (%s, %s) RETURNING id", (order.item, order.qty)
        ).fetchone()[0]
    return {"id": new_id, **order.model_dump()}


@app.post("/chaos/leak")
def leak():
    _leak.append(bytearray(50 * 1024 * 1024))
    return {"leaked_mb": 50 * len(_leak)}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
