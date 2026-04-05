"""Tests for scene_analyzer (Anthropic API is mocked — no network calls)."""
import json
from unittest.mock import patch, MagicMock
import numpy as np
import pytest
from PIL import Image

from kpeg.scene_analyzer import _image_to_base64, _build_system_prompt, analyze_scene


def _test_image(w=2000, h=1500):
    arr = np.random.randint(0, 256, size=(h, w, 3), dtype=np.uint8)
    return Image.fromarray(arr)


def test_image_to_base64_resizes_large():
    """Images larger than MAX_IMAGE_DIM are downscaled to fit."""
    img = _test_image(2000, 1500)
    b64, mt = _image_to_base64(img)
    assert mt == "image/jpeg"
    assert isinstance(b64, str)
    assert len(b64) > 100


def test_image_to_base64_small_unchanged():
    img = Image.fromarray(np.zeros((100, 100, 3), dtype=np.uint8))
    b64, mt = _image_to_base64(img)
    assert mt == "image/jpeg"


def test_image_to_base64_rgba_converts():
    """RGBA images convert to RGB before encoding."""
    arr = np.zeros((200, 200, 4), dtype=np.uint8)
    img = Image.fromarray(arr, mode="RGBA")
    b64, mt = _image_to_base64(img)
    assert mt == "image/jpeg"


def test_build_system_prompt_mentions_people_and_catalog():
    people = [{"ref": "usr_carlos_02", "bbox": [0.2, 0.1, 0.4, 0.9], "name": "Carlos"}]
    prompt = _build_system_prompt("obj_desk | Walnut desk | furniture", people)
    assert "usr_carlos_02" in prompt
    assert "Carlos" in prompt
    assert "obj_desk" in prompt
    assert "Walnut desk" in prompt


def test_build_system_prompt_flags_unknowns():
    people = [{"ref": "unknown1", "bbox": [0.0, 0.0, 0.5, 0.5]}]
    prompt = _build_system_prompt("(empty library)", people)
    assert "unknown1" in prompt
    assert "UNKNOWN" in prompt


def test_build_system_prompt_multiple_people():
    people = [
        {"ref": "usr_carlos_02", "bbox": [0.1, 0.1, 0.3, 0.9], "name": "Carlos"},
        {"ref": "unknown1", "bbox": [0.4, 0.1, 0.6, 0.9]},
        {"ref": "unknown2", "bbox": [0.7, 0.1, 0.9, 0.9]},
    ]
    prompt = _build_system_prompt("(empty library)", people)
    assert "usr_carlos_02" in prompt
    assert "unknown1" in prompt
    assert "unknown2" in prompt


def test_build_system_prompt_no_people():
    prompt = _build_system_prompt("obj | x | y", [])
    assert "(none)" in prompt


def test_build_system_prompt_contains_flux_instructions():
    """Prompt must tell Claude it's writing for FLUX, not humans."""
    prompt = _build_system_prompt("", [])
    assert "FLUX" in prompt
    assert "PROMPT" in prompt


def test_analyze_scene_parses_response():
    fake_json = {
        "s": {"d": "test scene", "mood": "casual"},
        "o": [{"n": "desk", "b": [0, 0, 1, 1]}],
        "t": [],
        "colors": ["#123456"],
    }
    fake_response = MagicMock()
    fake_response.content = [MagicMock(text=json.dumps(fake_json))]
    mock_client = MagicMock()
    mock_client.messages.create.return_value = fake_response

    with patch("kpeg.scene_analyzer.Anthropic", return_value=mock_client), \
         patch("kpeg.scene_analyzer.ANTHROPIC_API_KEY", "fake-key"):
        result = analyze_scene(_test_image(), known_people=[], objects_catalog=[])

    assert result["s"]["d"] == "test scene"
    assert result["o"][0]["n"] == "desk"


def test_analyze_scene_strips_markdown_fences():
    """Responses wrapped in ```json fences should parse correctly."""
    fake_response = MagicMock()
    fake_response.content = [MagicMock(
        text='```json\n{"s":{"d":"x"},"o":[],"t":[],"colors":[]}\n```'
    )]
    mock_client = MagicMock()
    mock_client.messages.create.return_value = fake_response

    with patch("kpeg.scene_analyzer.Anthropic", return_value=mock_client), \
         patch("kpeg.scene_analyzer.ANTHROPIC_API_KEY", "fake-key"):
        result = analyze_scene(_test_image(), known_people=[], objects_catalog=[])
    assert result["s"]["d"] == "x"


def test_analyze_scene_no_api_key():
    with patch("kpeg.scene_analyzer.ANTHROPIC_API_KEY", ""):
        with pytest.raises(RuntimeError, match="ANTHROPIC_API_KEY"):
            analyze_scene(_test_image(), [], [])


def test_analyze_scene_passes_catalog_to_prompt():
    """Verify the objects catalog reaches Claude's system prompt."""
    fake_response = MagicMock()
    fake_response.content = [MagicMock(text='{"s":{"d":"x"},"o":[],"t":[],"colors":[]}')]
    mock_client = MagicMock()
    mock_client.messages.create.return_value = fake_response

    catalog = [{"id": "obj_unique_xyz", "name": "Thing", "category": "test"}]
    with patch("kpeg.scene_analyzer.Anthropic", return_value=mock_client), \
         patch("kpeg.scene_analyzer.ANTHROPIC_API_KEY", "fake-key"):
        analyze_scene(_test_image(), known_people=[], objects_catalog=catalog)

    call_kwargs = mock_client.messages.create.call_args.kwargs
    assert "obj_unique_xyz" in call_kwargs["system"]


def test_build_system_prompt_includes_place_context():
    """App-confirmed venue should appear in the system prompt as LOCATION CONTEXT."""
    prompt = _build_system_prompt(
        "(empty library)", [],
        place_context="ETHGlobal Hall - near exit, wide view",
    )
    assert "LOCATION CONTEXT" in prompt
    assert "ETHGlobal Hall" in prompt
    assert "near exit, wide view" in prompt


def test_build_system_prompt_place_context_optional():
    """Without place_context, the LOCATION CONTEXT section should be absent."""
    prompt = _build_system_prompt("(empty library)", [])
    assert "LOCATION CONTEXT" not in prompt


def test_analyze_scene_passes_place_context_to_prompt():
    """Verify place_context reaches Claude's system prompt verbatim."""
    fake_response = MagicMock()
    fake_response.content = [MagicMock(text='{"s":{"d":"x"},"o":[],"t":[],"colors":[]}')]
    mock_client = MagicMock()
    mock_client.messages.create.return_value = fake_response

    with patch("kpeg.scene_analyzer.Anthropic", return_value=mock_client), \
         patch("kpeg.scene_analyzer.ANTHROPIC_API_KEY", "fake-key"):
        analyze_scene(
            _test_image(), known_people=[], objects_catalog=[],
            place_context="WeWork Cannes - 2nd floor meeting room",
        )

    call_kwargs = mock_client.messages.create.call_args.kwargs
    assert "WeWork Cannes" in call_kwargs["system"]
    assert "2nd floor meeting room" in call_kwargs["system"]
