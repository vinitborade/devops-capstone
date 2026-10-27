from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_create_and_list_orders():
    r = client.post("/orders", json={"item": "book", "qty": 2})
    assert r.status_code == 201
    assert any(o["item"] == "book" for o in client.get("/orders").json())


def test_metrics_exposed():
    client.get("/health")
    assert "http_requests_total" in client.get("/metrics").text
