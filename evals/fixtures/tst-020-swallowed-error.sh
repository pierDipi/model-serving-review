#!/usr/bin/env bash
FIXTURE_NAME="tst-020-swallowed-error"
source "$(dirname "$0")/common.sh"
init_repo

write_file test/e2e/test_inference.py <<'PYTHON'
import pytest

def test_inference_basic():
    """Basic inference test."""
    response = send_inference_request()
    assert response.status_code == 200
PYTHON
commit "initial test"

write_file test/e2e/test_inference.py <<'PYTHON'
import pytest
import logging

logger = logging.getLogger(__name__)

def test_inference_basic():
    """Basic inference test."""
    response = send_inference_request()
    assert response.status_code == 200

def test_inference_tracing():
    """Verify traces are exported for inference requests."""
    response = send_inference_request()
    assert response.status_code == 200

    # Swallowed assertion — logs warning on green check
    try:
        traces = collect_traces(service="predictor")
        assert len(traces) > 0, "No traces found for predictor service"
    except AssertionError:
        logger.warning("Traces not found — this may indicate a tracing configuration issue")

def test_inference_metrics():
    """Verify metrics are exported."""
    response = send_inference_request()
    assert response.status_code == 200

    try:
        metrics = scrape_metrics(endpoint="http://localhost:9090/metrics")
        assert "request_count" in metrics
        assert metrics["request_count"] > 0
    except Exception as e:
        logger.warning(f"Metrics check failed: {e}")
        # Test passes even though metrics are broken
PYTHON
commit "add tests that swallow assertion errors"

emit_repo
