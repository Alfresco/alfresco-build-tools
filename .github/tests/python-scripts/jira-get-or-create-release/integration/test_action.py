import pytest

pytestmark = pytest.mark.integration


@pytest.mark.integration_pollution
def test_integration_pollution():
    print("Hello from integration pollution!")


def test_integration():
    print("Hello from integration!")
