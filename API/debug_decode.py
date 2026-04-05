"""
Debug script: simula el decode de un .kpeg sin llamar a la IA.
Guarda en debug/ el prompt, bitmap, scene JSON, y todas las imágenes
de referencia que se enviarían a FLUX para cada tier (balanced, high).

Uso:
  cd API
  python3 debug_decode.py debug/<id>.kpeg

  O sin argumento (usa el último .kpeg de debug/):
  python3 debug_decode.py
"""
import base64
import io
import json
import os
import sys
from pathlib import Path

# Configurar imports del Tooling
_TOOLING_DIR = Path(__file__).resolve().parent.parent / 'Tooling'
sys.path.insert(0, str(_TOOLING_DIR))

from kpeg.format import unpack_kpeg
from kpeg.compression import decompress_json
from kpeg.bitmap import unpack_bitmap, render_bitmap
from kpeg.image_generator import build_prompt
from kpeg.library_reader import (
    get_person_photos,
    get_object_photos,
    get_object_info,
    select_best_place_refs,
    get_place_name,
    get_person_name,
)
from kpeg.decoder import _collect_reference_urls, _collect_categorized_refs, _compute_output_size

DEBUG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'debug')


def find_latest_kpeg():
    """Buscar el .kpeg más reciente en debug/."""
    kpegs = sorted(Path(DEBUG_DIR).glob('*.kpeg'), key=lambda p: p.stat().st_mtime, reverse=True)
    if not kpegs:
        print('No .kpeg files found in debug/')
        sys.exit(1)
    return str(kpegs[0])


def save_data_url(data_url: str, path: str):
    """Decodificar un data URL y guardarlo como archivo."""
    _, _, b64_part = data_url.partition(',')
    data = base64.standard_b64decode(b64_part)
    with open(path, 'wb') as f:
        f.write(data)


def debug_decode(kpeg_path: str):
    print(f'\n{"="*60}')
    print(f'DEBUG DECODE: {kpeg_path}')
    print(f'{"="*60}\n')

    # Leer .kpeg
    with open(kpeg_path, 'rb') as f:
        kpeg_bytes = f.read()

    kpeg_id = Path(kpeg_path).stem

    # 1. Unpack
    kpeg = unpack_kpeg(kpeg_bytes)
    scene = decompress_json(kpeg.compressed_json)
    metadata = scene.get('m') or {}

    # 2. Bitmap
    custom_palette, grid, keypoints = unpack_bitmap(kpeg.bitmap_data)
    out_w, out_h = _compute_output_size(kpeg.aspect_w, kpeg.aspect_h, 1024)
    guide_size = min(512, max(out_w, out_h))
    guide = render_bitmap(custom_palette, grid, keypoints, width=guide_size, height=guide_size)

    # Guardar bitmap
    bitmap_path = os.path.join(DEBUG_DIR, f'{kpeg_id}_decode_bitmap.png')
    guide.save(bitmap_path)
    print(f'  Bitmap: {bitmap_path} ({guide_size}x{guide_size})')

    # Guardar scene JSON
    scene_path = os.path.join(DEBUG_DIR, f'{kpeg_id}_decode_scene.json')
    with open(scene_path, 'w') as f:
        json.dump(scene, f, indent=2)
    print(f'  Scene:  {scene_path}')

    # 3. Prompt
    camera = scene.get('c') or {}
    colors = scene.get('colors') or []
    prompt = build_prompt(scene, camera=camera, colors=colors)

    prompt_path = os.path.join(DEBUG_DIR, f'{kpeg_id}_decode_prompt.txt')
    with open(prompt_path, 'w') as f:
        f.write(prompt)
    print(f'  Prompt: {prompt_path}')
    print(f'  Prompt text:\n    {prompt[:200]}...\n')

    # 4. Analizar referencias detalladamente (ANTES de collect)
    print(f'  --- REFERENCE ANALYSIS ---')

    # People
    people_refs = []
    for obj in scene.get('o') or []:
        ref = obj.get('ref', '')
        if ref.startswith('usr_'):
            name = get_person_name(ref)
            photos = get_person_photos(ref)
            found = [p for p in photos if Path(p).exists()]
            missing = [p for p in photos if not Path(p).exists()]
            print(f'  PERSON: {ref} ({name or "??"})')
            print(f'    DB selfies: {len(photos)}')
            print(f'    Found on disk: {len(found)}')
            if missing:
                print(f'    MISSING: {missing}')
            for p in found:
                print(f'      OK: {p}')
            people_refs.append((ref, name, found))

    # Place
    place_info = (scene.get('p') or {})
    place_id = place_info.get('place')
    if place_id:
        place_name = get_place_name(place_id)
        compass = metadata.get('compass')
        tilt = metadata.get('tilt')
        print(f'  PLACE: {place_id} ({place_name or "??"})')
        print(f'    Target compass: {compass}, tilt: {tilt}')
        place_refs = select_best_place_refs(place_id, target_compass=compass, target_tilt=tilt, max_refs=3)
        for pr in place_refs:
            exists = Path(pr['file_path']).exists()
            print(f'    Selected: {pr["id"]} ({pr["hint"]}) -> {pr["file_path"]} [{"OK" if exists else "MISSING"}]')
    else:
        print(f'  PLACE: (none in scene)')

    # Objects
    seen_obj = set()
    for obj in scene.get('o') or []:
        ref = obj.get('ref', '')
        if ref.startswith('obj_') and ref not in seen_obj:
            seen_obj.add(ref)
            info = get_object_info(ref)
            photos = get_object_photos(ref)
            found = [p for p in photos if Path(p).exists()]
            print(f'  OBJECT: {ref} ({info["name"] if info else "??"}) [{info["category"] if info else "??"}]')
            print(f'    Photos: {len(photos)}, found: {len(found)}')
            for p in found:
                print(f'      OK: {p}')

    print()

    # 5. Collect categorized references (multi-pass Stage 2)
    cat_refs = _collect_categorized_refs(scene, metadata, guide_image=guide)

    print(f'  --- CATEGORIZED REFERENCES ---')
    print(f'  Faces:   {len(cat_refs["face_urls"])} URLs ({len(cat_refs["face_people"])} people)')
    print(f'  Bitmap:  {"YES" if cat_refs["bitmap_url"] else "NO"}')
    print(f'  Places:  {len(cat_refs["place_urls"])} URLs')
    print(f'  Objects: {len(cat_refs["object_urls"])} URLs')
    print()

    # 6. Simular multi-pass para balanced y high
    for tier in ['balanced', 'high']:
        print(f'  --- TIER: {tier.upper()} (multi-pass) ---')
        tier_dir = os.path.join(DEBUG_DIR, f'{kpeg_id}_decode_{tier}')
        os.makedirs(tier_dir, exist_ok=True)

        # Guardar scene
        with open(os.path.join(tier_dir, 'scene.json'), 'w') as f:
            json.dump(scene, f, indent=2)

        # Guardar bitmap
        guide.save(os.path.join(tier_dir, 'bitmap.png'))

        # ── Stage 1 ──
        with open(os.path.join(tier_dir, 'stage1_prompt.txt'), 'w') as f:
            f.write(prompt)
        print(f'    Stage 1: {prompt[:100]}...')

        # ── Stage 2A: Faces ──
        face_dir = os.path.join(tier_dir, 'stage2a_faces')
        os.makedirs(face_dir, exist_ok=True)

        face_descriptions = [fp["description"] for fp in cat_refs["face_people"]]
        face_prompt = (
            "Apply the EXACT face, identity, and facial features from the reference photos. "
            "The reference images are face photos of: " +
            "; ".join(face_descriptions) +
            ". Preserve their exact likeness — eyes, nose, mouth, skin tone, facial structure. "
            "Keep the rest of the image unchanged."
        ) if face_descriptions else "(no faces)"

        with open(os.path.join(face_dir, 'prompt.txt'), 'w') as f:
            f.write(face_prompt)

        for i, url in enumerate(cat_refs["face_urls"]):
            save_data_url(url, os.path.join(face_dir, f'face{i:02d}.jpg'))

        print(f'    Stage 2A FACES: {len(cat_refs["face_urls"])} selfies')
        print(f'      Prompt: {face_prompt[:120]}...')
        for fp in cat_refs["face_people"]:
            print(f'      Person: {fp["ref"]} — {fp["url_count"]} selfies — "{fp["description"][:60]}..."')

        # ── Stage 2B: Scene + Objects ──
        scene_dir = os.path.join(tier_dir, 'stage2b_scene')
        os.makedirs(scene_dir, exist_ok=True)

        idx = 0
        if cat_refs["bitmap_url"]:
            save_data_url(cat_refs["bitmap_url"], os.path.join(scene_dir, f'ref{idx:02d}_bitmap.png'))
            idx += 1
        for j, url in enumerate(cat_refs["place_urls"]):
            save_data_url(url, os.path.join(scene_dir, f'ref{idx:02d}_place{j}.jpg'))
            idx += 1
        for j, url in enumerate(cat_refs["object_urls"]):
            obj_desc = cat_refs["object_descriptions"][j] if j < len(cat_refs["object_descriptions"]) else "object"
            safe_name = obj_desc[:20].replace(' ', '_').replace(',', '')
            save_data_url(url, os.path.join(scene_dir, f'ref{idx:02d}_obj_{safe_name}.jpg'))
            idx += 1

        obj_descs = cat_refs["object_descriptions"]
        scene_prompt = (
            "Refine the background and objects to match the reference images. "
            "The first reference is the color/composition guide. "
        )
        if cat_refs["place_urls"]:
            scene_prompt += "The venue/background photos show the exact location — match the architecture, furniture layout, and atmosphere. "
        if obj_descs:
            scene_prompt += "These specific objects must appear: " + ", ".join(obj_descs) + ". "
        scene_prompt += "Keep the people and their faces exactly as they are."

        with open(os.path.join(scene_dir, 'prompt.txt'), 'w') as f:
            f.write(scene_prompt)

        print(f'    Stage 2B SCENE: {idx} references (1 bitmap + {len(cat_refs["place_urls"])} places + {len(cat_refs["object_urls"])} objects)')
        print(f'      Prompt: {scene_prompt[:120]}...')

        print(f'    Saved to: {tier_dir}/')

    print(f'\n{"="*60}')
    print(f'Done. Check debug/ folder.')
    print(f'{"="*60}\n')


if __name__ == '__main__':
    if len(sys.argv) > 1:
        kpeg_file = sys.argv[1]
    else:
        kpeg_file = find_latest_kpeg()

    if not os.path.exists(kpeg_file):
        print(f'File not found: {kpeg_file}')
        sys.exit(1)

    debug_decode(kpeg_file)
