"""Tests for image_generator (fal.ai is mocked — no network calls)."""
import base64
import io
from unittest.mock import patch
import numpy as np
import pytest
from PIL import Image

from kpeg.image_generator import (
    build_prompt,
    build_person_prompt,
    stub_generate,
    stage1_generate,
    stage2_refine,
    generate_image,
    _image_to_data_url,
    _extract_image_from_result,
)


# ═══ Test helpers ═══

def _tiny_image(color=(128, 128, 128), w=64, h=64) -> Image.Image:
    arr = np.full((h, w, 3), color, dtype=np.uint8)
    return Image.fromarray(arr)


def _fake_fal_result(img: Image.Image) -> dict:
    """Build a fal.ai-shaped response containing a data-URL image."""
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.standard_b64encode(buf.getvalue()).decode("ascii")
    return {"images": [{"url": f"data:image/png;base64,{b64}", "width": img.width, "height": img.height}]}


# ═══ Prompt assembly ═══

def test_build_prompt_minimal_scene():
    scene = {"s": {"d": "cozy living room"}}
    prompt = build_prompt(scene)
    assert "cozy living room" in prompt
    assert prompt.endswith(".")


def test_build_prompt_with_all_scene_fields():
    scene = {
        "s": {
            "d": "kitchen counter, morning",
            "mood": "calm",
            "light": {"dir": "side", "type": "natural", "warmth": "warm"},
            "depth": "fg counter, bg window",
            "style": "documentary photography",
        },
        "colors": ["#FFFFFF", "#8B4513"],
    }
    prompt = build_prompt(scene, colors=scene["colors"])
    assert "kitchen counter" in prompt
    assert "documentary" in prompt
    assert "calm mood" in prompt
    assert "side light" in prompt
    assert "warm tone" in prompt
    assert "#FFFFFF" in prompt


def test_build_prompt_shallow_dof_hint_from_aperture():
    scene = {"s": {"d": "portrait"}}
    prompt = build_prompt(scene, camera={"ap": 1.8})
    assert "shallow depth" in prompt.lower()
    assert "f/1.8" in prompt


def test_build_prompt_deep_focus_hint_from_aperture():
    scene = {"s": {"d": "landscape"}}
    prompt = build_prompt(scene, camera={"ap": 8.0})
    assert "deep focus" in prompt.lower()


def test_build_prompt_wide_angle_from_focal_length():
    scene = {"s": {"d": "room"}}
    prompt = build_prompt(scene, camera={"fl": 14.0})
    assert "wide angle" in prompt.lower()


def test_build_prompt_portrait_compression_from_focal_length():
    scene = {"s": {"d": "face"}}
    prompt = build_prompt(scene, camera={"fl": 85.0})
    assert "portrait compression" in prompt.lower()


def test_build_prompt_includes_people_and_object_descriptions():
    """People ARE included inline as Subjects so t2i tier sees them too."""
    scene = {
        "s": {"d": "scene"},
        "o": [
            {"n": "person", "d": "man smiling"},
            {"n": "desk", "d": "walnut desk"},
            {"n": "lamp", "d": "brass pendant"},
        ],
    }
    prompt = build_prompt(scene)
    assert "walnut desk" in prompt
    assert "brass pendant" in prompt
    assert "man smiling" in prompt
    assert "Subjects:" in prompt  # people get the Subjects: tag


def test_build_prompt_includes_text_literally():
    scene = {
        "s": {"d": "venue"},
        "t": [{"text": "PALAIS", "b": [0, 0, 1, 1], "type": "sign"}],
    }
    prompt = build_prompt(scene)
    assert 'text reads "PALAIS"' in prompt


def test_build_person_prompt_concatenates_descriptions():
    scene = {
        "o": [
            {"n": "person", "d": "woman mid-40s, ponytail"},
            {"n": "person", "d": "man early-30s, beard"},
            {"n": "desk", "d": "walnut"},
        ],
    }
    result = build_person_prompt(scene)
    assert "woman mid-40s" in result
    assert "man early-30s" in result
    assert "walnut" not in result


def test_build_person_prompt_empty_when_no_people():
    assert build_person_prompt({"o": []}) == ""
    assert build_person_prompt({}) == ""


# ═══ Data URL encoding ═══

def test_image_to_data_url_produces_valid_png():
    img = _tiny_image()
    url = _image_to_data_url(img, fmt="PNG")
    assert url.startswith("data:image/png;base64,")
    header, _, b64 = url.partition(",")
    decoded = base64.standard_b64decode(b64)
    assert decoded[:8] == b"\x89PNG\r\n\x1a\n"


def test_image_to_data_url_jpeg():
    img = _tiny_image()
    url = _image_to_data_url(img, fmt="JPEG")
    assert url.startswith("data:image/jpeg;base64,")


# ═══ fal.ai response parsing ═══

def test_extract_image_from_result_parses_data_url():
    img = _tiny_image(color=(255, 0, 0))
    result = _fake_fal_result(img)
    out = _extract_image_from_result(result)
    assert out.size == (64, 64)
    assert out.getpixel((0, 0)) == (255, 0, 0)


def test_extract_image_missing_images_raises():
    with pytest.raises(RuntimeError, match="missing images"):
        _extract_image_from_result({})


def test_extract_image_empty_url_raises():
    with pytest.raises(RuntimeError, match="no url"):
        _extract_image_from_result({"images": [{"url": ""}]})


# ═══ Stub fallback ═══

def test_stub_generate_returns_sized_image():
    guide = _tiny_image()
    out = stub_generate("any prompt", guide, width=512, height=384)
    assert out.size == (512, 384)
    assert out.mode == "RGB"


# ═══ Stage 1 (mocked fal) ═══

def test_stage1_generate_t2i_skips_guide():
    """Text-to-image models ignore the guide image."""
    guide = _tiny_image()
    expected = _tiny_image(color=(10, 20, 30), w=128, h=128)
    calls = []

    def fake_submit(model, arguments):
        calls.append((model, arguments))
        return _fake_fal_result(expected)

    out = stage1_generate(
        "a prompt", guide,
        model="fal-ai/flux/schnell",
        model_type="t2i",
        width=128, height=128,
        submit=fake_submit,
    )
    assert out.size == (128, 128)
    model, args = calls[0]
    assert model == "fal-ai/flux/schnell"
    assert args["prompt"] == "a prompt"
    assert args["image_size"] == {"width": 128, "height": 128}
    assert "image_url" not in args
    assert "strength" not in args


def test_stage1_generate_i2i_passes_guide():
    """Image-to-image models receive the guide + strength."""
    guide = _tiny_image()
    expected = _tiny_image(w=128, h=128)
    calls = []

    def fake_submit(model, arguments):
        calls.append((model, arguments))
        return _fake_fal_result(expected)

    stage1_generate(
        "p", guide,
        model="fal-ai/flux/dev/image-to-image",
        model_type="i2i",
        width=128, height=128,
        submit=fake_submit,
    )
    model, args = calls[0]
    assert model == "fal-ai/flux/dev/image-to-image"
    assert args["image_url"].startswith("data:image/png;base64,")
    assert "strength" in args


# ═══ Stage 2 (mocked fal) ═══

def test_stage2_refine_passes_reference_urls():
    base = _tiny_image()
    expected = _tiny_image(color=(50, 60, 70))
    refs = ["https://example.com/face1.jpg", "https://example.com/face2.jpg"]
    calls = []

    def fake_submit(model, arguments):
        calls.append((model, arguments))
        return _fake_fal_result(expected)

    out = stage2_refine(base, "refine prompt", refs, submit=fake_submit)
    assert out.size == expected.size
    assert len(calls) == 1
    model, args = calls[0]
    assert "kontext" in model
    assert args["reference_image_urls"] == refs
    assert args["prompt"] == "refine prompt"


# ═══ Full pipeline ═══

def test_generate_image_fast_tier_stage1_only():
    guide = _tiny_image()
    expected = _tiny_image(color=(200, 100, 50), w=256, h=256)
    calls = []

    def fake_submit(model, arguments):
        calls.append(model)
        return _fake_fal_result(expected)

    scene = {"s": {"d": "test scene"}, "o": []}
    out = generate_image(
        scene, guide,
        reference_urls=["https://x/ref.jpg"],  # ignored on fast
        quality="fast",
        width=256, height=256,
        submit=fake_submit,
    )
    assert out.size == (256, 256)
    assert len(calls) == 1  # stage 1 only, no stage 2 on fast
    assert "schnell" in calls[0]


def test_generate_image_balanced_tier_runs_stage2_when_refs_present():
    guide = _tiny_image()
    stage1_out = _tiny_image(color=(1, 1, 1))
    stage2_out = _tiny_image(color=(2, 2, 2))
    call_log = []

    def fake_submit(model, arguments):
        call_log.append(model)
        if "kontext" in model:
            return _fake_fal_result(stage2_out)
        return _fake_fal_result(stage1_out)

    scene = {"s": {"d": "s"}, "o": [{"n": "person", "d": "woman smiling"}]}
    out = generate_image(
        scene, guide,
        reference_urls=["https://x/ref.jpg"],
        quality="balanced",
        submit=fake_submit,
    )
    assert out.getpixel((0, 0)) == (2, 2, 2)  # stage 2 result
    assert any("flux/dev/image-to-image" in m for m in call_log)
    assert any("kontext" in m for m in call_log)


def test_generate_image_balanced_skips_stage2_without_refs():
    guide = _tiny_image()
    stage1_out = _tiny_image(color=(9, 9, 9))
    calls = []

    def fake_submit(model, arguments):
        calls.append(model)
        return _fake_fal_result(stage1_out)

    scene = {"s": {"d": "scene"}}
    out = generate_image(
        scene, guide,
        reference_urls=[],
        quality="balanced",
        submit=fake_submit,
    )
    assert len(calls) == 1
    assert all("kontext" not in m for m in calls)
    assert out.getpixel((0, 0)) == (9, 9, 9)


def test_generate_image_high_tier_invokes_upscale():
    guide = _tiny_image()
    call_log = []

    def fake_submit(model, arguments):
        call_log.append(model)
        return _fake_fal_result(_tiny_image())

    scene = {"s": {"d": "scene"}}
    generate_image(
        scene, guide,
        reference_urls=["https://x/ref.jpg"],
        quality="high",
        submit=fake_submit,
    )
    assert any("flux-pro/v1.1" in m for m in call_log)
    assert any("upscaler" in m for m in call_log)


def test_generate_image_invalid_quality_raises():
    with pytest.raises(ValueError, match="quality"):
        generate_image({"s": {"d": "x"}}, _tiny_image(), quality="bogus")


def test_generate_image_uses_stub_when_no_fal_key_and_no_submit():
    """When FAL_KEY is empty and no submit callback is given, falls back to stub."""
    with patch("kpeg.image_generator.FAL_KEY", ""):
        out = generate_image(
            {"s": {"d": "scene"}}, _tiny_image(),
            reference_urls=None,
            quality="fast",
            width=128, height=128,
        )
    assert out.size == (128, 128)
    assert out.mode == "RGB"
