"""Claude Vision scene analyzer for KPEG.

CRITICAL: The output JSON is a PROMPT BLUEPRINT for FLUX reconstruction, not
generic image description. Every field maps to a decoder stage:
  - s.d              → FLUX Pro positive prompt
  - o[].d + o[].b    → bbox-anchored object sub-prompts
  - person "d" for unknowns → the ONLY face info FLUX has to reconstruct that face
  - person "d" for knowns   → expression/pose on top of library reference photo
  - t[].text         → literal text rendering
  - colors           → color constraint hint

People are pre-tagged by the App (usr_xxx or unknownN numbered left-to-right by x).
This analyzer describes them + smart-matches objects against the library catalog.
"""
import base64
import io
import json as json_lib
from typing import Optional
from PIL import Image
from anthropic import Anthropic

from .config import ANTHROPIC_API_KEY, VISION_MODEL

MAX_IMAGE_DIM = 1024  # Resize before sending to keep API payload small


def _image_to_base64(image: Image.Image) -> tuple[str, str]:
    """Resize image (max 1024px) and encode to base64 JPEG."""
    img = image.convert("RGB")
    w, h = img.size
    if max(w, h) > MAX_IMAGE_DIM:
        if w >= h:
            new_w, new_h = MAX_IMAGE_DIM, int(h * MAX_IMAGE_DIM / w)
        else:
            new_w, new_h = int(w * MAX_IMAGE_DIM / h), MAX_IMAGE_DIM
        img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return base64.standard_b64encode(buf.getvalue()).decode("ascii"), "image/jpeg"


def _build_system_prompt(objects_catalog: str, known_people: list[dict]) -> str:
    """Build the prompt that tells Claude to output FLUX-ready scene JSON."""
    people_lines = []
    for p in known_people:
        ref = p["ref"]
        bbox = p.get("bbox", [0, 0, 1, 1])
        if ref.startswith("usr_"):
            name = p.get("name", "known person")
            people_lines.append(f"- {ref} ({name}), bbox {bbox}")
        else:
            people_lines.append(f"- {ref} UNKNOWN (no library match), bbox {bbox}")
    people_text = "\n".join(people_lines) if people_lines else "(none)"

    return f"""You analyze photos and emit scene JSON TO BE CONSUMED BY FLUX for reconstruction.

You are NOT describing for a human. You are writing a PROMPT BLUEPRINT.
Every field you write is concatenated directly into the FLUX text prompt.
Write prompt-ready phrases, not prose.

GOOD: "man mid-30s, short beard, blue polo, wide smile, looking left"
BAD:  "This appears to be a gentleman in his mid-thirties who is smiling"

=== PEOPLE (pre-tagged by the App, include all of them in "o") ===
{people_text}

Rules for people:
- Emit one entry per person above in "o" with n:"person", b:given_bbox, ref:given_ref.
- For UNKNOWN persons, your "d" is ALL THE INFO FLUX HAS to reconstruct the face.
  Pack every detail: age range, gender, hair, beard, glasses, skin marks, expression,
  head pose, clothing, accessories, visible emotions.
- For KNOWN persons (usr_xxx), the Library has the face photo. Describe expression,
  pose, clothing only. Do NOT redescribe facial features (comes from the reference).

=== OBJECTS LIBRARY (smart match against catalog) ===
Format: obj_id | name | category
{objects_catalog}

Rules for objects:
- Scan the photo and match confidently against the catalog above.
- Emit matches as o entries: n:name, b:bbox, d:brief, ref:obj_id.
- For detected objects NOT in catalog, emit them WITHOUT the ref field.
- Skip trivial items (walls, plain floor) unless distinctive.

=== TEXT & SIGNS ===
Extract visible text/signs/logos. Will be rendered LITERALLY.
Format: {{"text":"EXACT","b":[x0,y0,x1,y1],"type":"sign|logo|label"}}

=== OUTPUT SCHEMA (ultra-short keys, return ONLY this JSON, no other text) ===
{{
  "s": {{
    "d": "scene description, prompt-ready, 1-2 sentences",
    "mood": "single word: casual|formal|professional|festive|calm|...",
    "light": {{"dir":"above|side|front|back|above-left|...", "type":"natural|artificial|mixed", "warmth":"warm|neutral|cool"}},
    "depth": "fg/mg/bg layout, 1 phrase",
    "style": "natural photography|portrait|documentary|..."
  }},
  "o": [
    {{"n":"person","b":[x0,y0,x1,y1],"d":"...","ref":"usr_xxx|unknownN"}},
    {{"n":"desk","b":[x0,y0,x1,y1],"d":"...","ref":"obj_xxx"}}
  ],
  "t": [{{"text":"...","b":[x0,y0,x1,y1],"type":"sign"}}],
  "colors": ["#RRGGBB", ...up to 5 dominant hex colors]
}}

bbox = [x0,y0,x1,y1] normalized 0-1, top-left origin.
Keep it TIGHT. Max ~1500 raw JSON bytes."""


def analyze_scene(
    image: Image.Image,
    known_people: list[dict],
    objects_catalog: Optional[list[dict]] = None,
    max_tokens: int = 2000,
) -> dict:
    """Call Claude Vision with the photo + catalog, return parsed scene JSON.

    Args:
        image: PIL image of the source photo.
        known_people: from App metadata: [{"ref":"usr_xxx|unknownN","bbox":[...],"name":"..."}]
        objects_catalog: list of {"id","name","category"} from library.
        max_tokens: cap on Claude's response.

    Returns:
        dict with keys s, o, t, colors (the raw scene JSON before compression).
    """
    from .library_reader import format_objects_catalog_for_prompt

    if not ANTHROPIC_API_KEY:
        raise RuntimeError("ANTHROPIC_API_KEY not set — check .env")

    client = Anthropic(api_key=ANTHROPIC_API_KEY)
    catalog_text = format_objects_catalog_for_prompt(objects_catalog or [])
    system = _build_system_prompt(catalog_text, known_people)
    img_b64, media_type = _image_to_base64(image)

    response = client.messages.create(
        model=VISION_MODEL,
        max_tokens=max_tokens,
        system=system,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": img_b64,
                        },
                    },
                    {"type": "text", "text": "Analyze this photo. Return ONLY the JSON."},
                ],
            }
        ],
    )

    text = response.content[0].text.strip()
    # Strip markdown fences if present
    if text.startswith("```"):
        lines = text.split("\n")
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()

    return json_lib.loads(text)
