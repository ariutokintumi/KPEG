"""FLUX image generator for KPEG decode (fal.ai integration).

Two-stage pipeline:
  Stage 1: color guide bitmap + text prompt → FLUX (i2i OR t2i) → base photo
  Stage 2: base photo + library refs + bitmap → FLUX Kontext Pro → refined photo

Quality tiers (matches App's fast/balanced/high):
  fast      → Stage 1 only (FLUX Schnell t2i, bitmap IGNORED for speed), ~1-2s
  balanced  → Stage 1 (FLUX Dev i2i, bitmap used as structural guide)
              + Stage 2 Kontext (bitmap + library refs), ~7-14s
  high      → Stage 1 (FLUX Pro 1.1 t2i)
              + Stage 2 Kontext (bitmap + library refs as anchor)
              + Clarity upscaler, ~10-20s

The bitmap is always injected into Stage 2's reference_image_urls (see
decoder._collect_reference_urls), so even t2i tiers like 'high' get a
color/composition anchor. Only 'fast' intentionally skips the bitmap.

This module wraps fal.ai and accepts a `_submit` override so tests can run
entirely offline without hitting the network.
"""
import base64
import io
from typing import Callable, Optional
from urllib.request import urlopen
from PIL import Image, ImageDraw

from .config import FAL_KEY, IMAGE_MODEL

# Model routing per quality tier.
# `type` decides whether the bitmap is used as structural guide (i2i) or just text (t2i).
_STAGE1_MODELS = {
    "fast":     {"model": "fal-ai/flux/schnell",              "type": "t2i"},
    "balanced": {"model": "fal-ai/flux/dev/image-to-image",   "type": "i2i"},
    "high":     {"model": "fal-ai/flux-pro/v1.1",             "type": "t2i"},
}
_STAGE2_MODEL = "fal-ai/flux-pro/kontext"
_UPSCALE_MODEL = "fal-ai/clarity-upscaler"

# Stage 1 strength: how far FLUX is allowed to drift from the color guide.
# Higher = more creative, lower = sticks closer to the 512px bitmap.
_IMG2IMG_STRENGTH = 0.80


def _image_to_data_url(img: Image.Image, fmt: str = "PNG") -> str:
    """Encode a PIL image to a base64 data URL for fal.ai inline uploads."""
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format=fmt)
    b64 = base64.standard_b64encode(buf.getvalue()).decode("ascii")
    mime = "image/png" if fmt.upper() == "PNG" else "image/jpeg"
    return f"data:{mime};base64,{b64}"


def _fetch_image_from_url(url: str) -> Image.Image:
    """Download an image URL and return it as a PIL image."""
    if url.startswith("data:"):
        header, _, b64 = url.partition(",")
        return Image.open(io.BytesIO(base64.standard_b64decode(b64)))
    with urlopen(url, timeout=30) as resp:
        return Image.open(io.BytesIO(resp.read()))


def _extract_image_from_result(result: dict) -> Image.Image:
    """Pull the first image out of a fal.ai response dict."""
    images = result.get("images") or []
    if not images:
        raise RuntimeError(f"fal.ai response missing images: {result!r}")
    first = images[0]
    url = first.get("url") if isinstance(first, dict) else first
    if not url:
        raise RuntimeError(f"fal.ai image entry has no url: {first!r}")
    return _fetch_image_from_url(url)


def build_prompt(scene: dict, camera: Optional[dict] = None, colors: Optional[list] = None) -> str:
    """Assemble a FLUX-ready positive prompt from the scene JSON.

    Ordering strategy (what matters most for FLUX attention):
      1. Photograph framing + main scene description (subject + action + setting)
      2. People descriptions inline (each person's appearance + action + interaction)
      3. Style / mood / light / depth modifiers
      4. Camera depth-of-field + perspective hints
      5. Object descriptions (bbox-anchored sub-phrases)
      6. Literal text signs
      7. Color palette constraint
    """
    parts = []
    s = scene.get("s") or {}

    # Lead with "Photograph:" framing so FLUX locks into photo-caption mode
    main = s.get("d")
    if main:
        parts.append(f"Photograph: {main.strip()}")

    # People inline — with spatial position from bounding box
    person_phrases = []
    for o in scene.get("o") or []:
        if o.get("n") == "person":
            d = o.get("d")
            if not d:
                continue
            b = o.get("b")
            if b and len(b) == 4:
                cx = (b[0] + b[2]) / 2
                if cx < 0.33:
                    pos = "left side"
                elif cx > 0.67:
                    pos = "right side"
                else:
                    pos = "center"
                person_phrases.append(f"{d.strip()} (positioned {pos} of frame)")
            else:
                person_phrases.append(d.strip())
    if person_phrases:
        parts.append("Subjects: " + "; ".join(person_phrases))

    style = s.get("style")
    if style:
        parts.append(style)

    mood = s.get("mood")
    if mood:
        parts.append(f"{mood} mood")

    light = s.get("light") or {}
    light_bits = []
    if light.get("dir"):
        light_bits.append(f"{light['dir']} light")
    if light.get("type"):
        light_bits.append(light["type"])
    if light.get("warmth"):
        light_bits.append(f"{light['warmth']} tone")
    if light_bits:
        parts.append(", ".join(light_bits))

    depth = s.get("depth")
    if depth:
        parts.append(depth)

    # Camera → depth of field / perspective hints
    cam = camera or {}
    cam_bits = []
    if cam.get("ap") is not None:
        ap = cam["ap"]
        if ap <= 2.0:
            cam_bits.append(f"shallow depth of field f/{ap}, creamy bokeh")
        elif ap >= 5.6:
            cam_bits.append(f"deep focus f/{ap}")
    if cam.get("fl") is not None:
        fl = cam["fl"]
        if fl <= 18:
            cam_bits.append("wide angle perspective")
        elif fl >= 70:
            cam_bits.append("portrait compression")
    if cam_bits:
        parts.append(", ".join(cam_bits))

    # Non-person object sub-prompts with spatial positioning
    obj_phrases = []
    for o in scene.get("o") or []:
        if o.get("n") == "person":
            continue
        d = o.get("d")
        if not d:
            continue
        # Añadir posición espacial del bounding box para guiar a FLUX
        b = o.get("b")
        if b and len(b) == 4:
            cx = (b[0] + b[2]) / 2
            if cx < 0.33:
                pos = "on the left"
            elif cx > 0.67:
                pos = "on the right"
            else:
                pos = "in the center"
            cy = (b[1] + b[3]) / 2
            if cy < 0.33:
                pos += " top"
            elif cy > 0.67:
                pos += " bottom"
            obj_phrases.append(f"{d.strip()} ({pos})")
        else:
            obj_phrases.append(d.strip())
    if obj_phrases:
        parts.append(", ".join(obj_phrases))

    # Literal text rendering
    texts = scene.get("t") or []
    for t in texts:
        txt = t.get("text")
        if txt:
            parts.append(f'text reads "{txt}"')

    # Color constraint hint
    if colors:
        parts.append("color palette " + " ".join(colors[:5]))

    return ". ".join(p for p in parts if p) + "."


def build_person_prompt(scene: dict) -> str:
    """Sub-prompt listing every person's description (used for Stage 2 refinement)."""
    phrases = []
    for o in scene.get("o") or []:
        if o.get("n") != "person":
            continue
        d = o.get("d")
        if d:
            phrases.append(d.strip())
    return ". ".join(phrases)


def stub_generate(
    prompt: str,
    guide_image: Image.Image,
    width: int = 1024,
    height: int = 1024,
) -> Image.Image:
    """Offline fallback: upscale the guide image with a watermark.

    Used when FAL_KEY is unset or tests run without network. Produces a valid
    PIL image so the decoder pipeline can be exercised end-to-end.
    """
    img = guide_image.convert("RGB").resize((width, height), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(img)
    marker = "KPEG stub"
    draw.rectangle([10, 10, 160, 40], fill=(0, 0, 0))
    draw.text((18, 16), marker, fill=(255, 255, 255))
    return img


def _default_submit(model: str, arguments: dict) -> dict:
    """Real fal.ai call. Imported lazily so tests don't need the package."""
    import fal_client
    if FAL_KEY:
        import os
        os.environ["FAL_KEY"] = FAL_KEY
    return fal_client.subscribe(model, arguments=arguments, with_logs=False)


def stage1_generate(
    prompt: str,
    guide_image: Image.Image,
    model: str,
    model_type: str = "t2i",
    width: int = 1024,
    height: int = 1024,
    submit: Optional[Callable[[str, dict], dict]] = None,
) -> Image.Image:
    """Stage 1: prompt (+ optional color guide for i2i) → FLUX → base photo.

    model_type: "t2i" (text-to-image, guide is ignored) or "i2i" (img2img, guide conditions).
    """
    submit = submit or _default_submit
    args = {
        "prompt": prompt,
        "num_images": 1,
        "image_size": {"width": width, "height": height},
    }
    if model_type == "i2i":
        args["image_url"] = _image_to_data_url(guide_image, fmt="PNG")
        args["strength"] = _IMG2IMG_STRENGTH
    result = submit(model, args)
    return _extract_image_from_result(result)


def stage2_refine(
    base_image: Image.Image,
    prompt: str,
    reference_urls: list[str],
    submit: Optional[Callable[[str, dict], dict]] = None,
) -> Image.Image:
    """Stage 2: base photo + library refs → FLUX Kontext Pro → refined photo.

    Kontext accepts one primary image + an array of reference images.
    References should be hosted URLs or data URLs (faces/places/objects).
    """
    submit = submit or _default_submit
    args = {
        "prompt": prompt,
        "image_url": _image_to_data_url(base_image, fmt="PNG"),
        "reference_image_urls": reference_urls,
        "num_images": 1,
    }
    result = submit(_STAGE2_MODEL, args)
    return _extract_image_from_result(result)


_PULID_MODEL = "fal-ai/flux-pulid"


def pulid_generate(
    prompt: str,
    face_url: str,
    width: int = 1024,
    height: int = 1024,
    id_weight: float = 1.0,
    num_steps: int = 28,
    submit: Optional[Callable[[str, dict], dict]] = None,
) -> Image.Image:
    """Generate image with embedded face identity via PuLID FLUX.

    PuLID inyecta la identidad facial DENTRO de la generación, no como
    post-proceso. Mucho más fiable que face-swap para preservar identidad.

    num_steps: 12 para fast (rápido), 28 para balanced/high (calidad).
    """
    submit = submit or _default_submit
    args = {
        "prompt": prompt,
        "reference_image_url": face_url,
        "image_size": {"width": width, "height": height},
        "id_weight": id_weight,
        "num_inference_steps": num_steps,
        "guidance_scale": 4,
        "enable_safety_checker": False,
        "max_sequence_length": "256",
    }
    try:
        result = submit(_PULID_MODEL, args)
        return _extract_image_from_result(result)
    except Exception as e:
        print(f"  ⚠️ PuLID face generation failed: {e}")
        # Fallback: generar sin identidad facial
        return stub_generate(prompt, Image.new("RGB", (width, height)), width, height)


def upscale(
    image: Image.Image,
    scale: int = 2,
    submit: Optional[Callable[[str, dict], dict]] = None,
) -> Image.Image:
    """Apply clarity upscaler (high quality tier)."""
    submit = submit or _default_submit
    args = {
        "image_url": _image_to_data_url(image, fmt="PNG"),
        "scale": scale,
    }
    result = submit(_UPSCALE_MODEL, args)
    return _extract_image_from_result(result)


def generate_image(
    scene: dict,
    guide_image: Image.Image,
    categorized_refs: Optional[dict] = None,
    reference_urls: Optional[list[str]] = None,
    quality: str = "balanced",
    width: int = 1024,
    height: int = 1024,
    camera: Optional[dict] = None,
    colors: Optional[list] = None,
    submit: Optional[Callable[[str, dict], dict]] = None,
) -> Image.Image:
    """Full decoder image pipeline: scene JSON + guide → reconstructed photo.

    Multi-pass Stage 2 (when categorized_refs provided):
      Stage 2A: Face identity — selfies only + face-focused prompt
      Stage 2B: Scene refinement — bitmap + places + objects + scene prompt

    Falls back to single-pass if only flat reference_urls provided.

    Args:
        scene: parsed KPEG scene dict (s, o, t, ...).
        guide_image: rendered color guide from bitmap (PIL image).
        categorized_refs: dict with face_urls, bitmap_url, place_urls, object_urls, etc.
        reference_urls: legacy flat list (used if categorized_refs is None).
        quality: "fast" | "balanced" | "high".
        width, height: output dimensions.
        camera: KPEG c section (aperture, focal length, zoom, flash).
        colors: KPEG colors array.
        submit: injectable fal.ai call (for tests / offline mode).

    Returns:
        PIL.Image of the reconstructed photo.
    """
    if quality not in _STAGE1_MODELS:
        raise ValueError(f"Unknown quality tier: {quality!r}")

    prompt = build_prompt(scene, camera=camera, colors=colors)

    # Offline fallback when no key and no injected submit
    if submit is None and not FAL_KEY:
        return stub_generate(prompt, guide_image, width=width, height=height)

    # Extraer refs categorizadas
    face_urls = []
    face_people = []
    if categorized_refs:
        face_urls = categorized_refs.get("face_urls", [])
        face_people = categorized_refs.get("face_people", [])

    # ════════════════════════════════════════
    # STAGE 1: Generación base con identidad facial (PuLID) o sin ella
    # ════════════════════════════════════════
    tier = _STAGE1_MODELS[quality]
    if face_urls and face_people:
        # PuLID FLUX: genera con la cara del sujeto principal embebida
        person_desc = face_people[0].get("description", "")
        pulid_prompt = f"{prompt} The main subject is {person_desc}."
        # Fast usa menos pasos para ser rápido pero SÍ aplica la cara
        steps = 12 if quality == "fast" else 28
        weight = 0.85 if quality == "fast" else 0.95
        print(f"  Stage 1: PuLID ({face_people[0]['ref']}, steps={steps}, id={weight}) + prompt")
        base = pulid_generate(
            pulid_prompt, face_urls[0],
            width=width, height=height,
            id_weight=weight,
            num_steps=steps,
            submit=submit,
        )
    else:
        # FLUX estándar (sin caras detectadas)
        base = stage1_generate(
            prompt, guide_image,
            model=tier["model"],
            model_type=tier["type"],
            width=width, height=height,
            submit=submit,
        )

    # Fast: no hace Stage 2 (la cara ya está aplicada por PuLID)
    if quality == "fast":
        return base

    # ════════════════════════════════════════
    # STAGE 2: Refinamiento de escena + objetos (Kontext) — balanced/high
    # ════════════════════════════════════════
    if categorized_refs is not None:
        scene_urls = []
        bitmap_url = categorized_refs.get("bitmap_url")
        if bitmap_url:
            scene_urls.append(bitmap_url)
        scene_urls.extend(categorized_refs.get("place_urls", []))
        scene_urls.extend(categorized_refs.get("object_urls", []))

        if scene_urls:
            obj_descriptions = categorized_refs.get("object_descriptions", [])

            # Prompt detallado para que Kontext sea fiel a la escena y objetos
            scene_prompt = (
                "Refine this image to be MORE FAITHFUL to the reference photos. "
            )
            if bitmap_url:
                scene_prompt += "The first reference is the spatial color/edge guide — match the overall composition and color layout. "
            if categorized_refs.get("place_urls"):
                scene_prompt += (
                    "The venue reference photos show the EXACT real location where this photo was taken. "
                    "Match the architecture, walls, ceiling, floor, lighting fixtures, and general atmosphere PRECISELY from these venue photos. "
                )
            if obj_descriptions:
                scene_prompt += (
                    "The following objects appear in the original photo and MUST be faithfully reproduced "
                    "using the reference photos provided for each: " +
                    "; ".join(obj_descriptions) + ". "
                    "Each object reference photo shows the REAL object — match its exact appearance, color, shape, and texture. "
                )
            scene_prompt += (
                "CRITICAL: Do NOT modify, change, or alter any person's face, expression, or identity. "
                "Keep all people EXACTLY as they are."
            )
            print(f"  Stage 2: Kontext ({len(scene_urls)} refs: "
                  f"{1 if bitmap_url else 0} bitmap + "
                  f"{len(categorized_refs.get('place_urls', []))} places + "
                  f"{len(categorized_refs.get('object_urls', []))} objects)")
            base = stage2_refine(base, scene_prompt, scene_urls, submit=submit)

    elif reference_urls:
        # Legacy single-pass (backward compat)
        person_prompt = build_person_prompt(scene)
        refine_prompt = prompt
        if person_prompt:
            refine_prompt = f"{prompt} People: {person_prompt}"
        base = stage2_refine(base, refine_prompt, reference_urls, submit=submit)

    # ════════════════════════════════════════
    # STAGE 3: Upscale (high tier only)
    # ════════════════════════════════════════
    if quality == "high":
        try:
            base = upscale(base, scale=2, submit=submit)
        except Exception:
            pass  # upscale is best-effort

    return base
