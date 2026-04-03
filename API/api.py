from flask import Flask, request, jsonify
import os
from datetime import datetime

app = Flask(__name__)

CARPETA_FOTOS = "fotos"
os.makedirs(CARPETA_FOTOS, exist_ok=True)

@app.route("/upload", methods=["POST"])
def recibir_foto():
    if "foto" not in request.files:
        return jsonify({"error": "No se recibió ninguna foto"}), 400

    foto = request.files["foto"]

    if foto.filename == "":
        return jsonify({"error": "Nombre de archivo vacío"}), 400

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    extension = os.path.splitext(foto.filename)[1] or ".jpg"
    nombre_archivo = f"foto_{timestamp}{extension}"

    ruta = os.path.join(CARPETA_FOTOS, nombre_archivo)
    foto.save(ruta)

    print(f"✅ Foto guardada: {ruta}")
    return jsonify({"ok": True, "archivo": nombre_archivo}), 200

@app.route("/", methods=["GET"])
def inicio():
    fotos = os.listdir(CARPETA_FOTOS)
    return jsonify({
        "status": "API funcionando 🟢",
        "fotos_recibidas": len(fotos),
        "fotos": fotos
    })

if __name__ == "__main__":
    print("🚀 API iniciada en http://0.0.0.0:8000")
    print(f"📁 Fotos en: {os.path.abspath(CARPETA_FOTOS)}/")
    app.run(host="0.0.0.0", port=8000, debug=True)
